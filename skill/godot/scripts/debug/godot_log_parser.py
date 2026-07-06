#!/usr/bin/env python3
"""Parse Godot 4.7 stdout/stderr into structured diagnostics.

The parser turns the raw text the Godot debugger prints when a project runs
(runtime script errors, engine errors, ``push_error``/``push_warning`` output,
and GDScript parse errors) into a list of structured diagnostics that a skill
can act on: fix the referenced ``file:line``, then re-run to confirm.

It is intentionally free of any Godot dependency so it can run anywhere and be
unit tested against captured logs. It can be imported (``parse_log``) or used as
a CLI that reads a log file or stdin and prints JSON.

Recognised Godot 4.7 output shapes (captured from ``godot 4.7.stable``)::

    SCRIPT ERROR: Invalid access to property or key 'position' on a base object of type 'null instance'.
              at: _ready (res://scripts/main.gd:4)
              GDScript backtrace (most recent call first):
                  [0] _ready (res://scripts/main.gd:4)

    ERROR: custom boom happened                 # from push_error()
       at: push_error (core/variant/variant_utility.cpp:1023)
       GDScript backtrace (most recent call first):
           [0] _ready (res://scripts/main.gd:3)

    WARNING: this is a warning                  # from push_warning()
         at: push_warning (core/variant/variant_utility.cpp:1033)

    SCRIPT ERROR: Parse Error: Identifier "foo" not declared in the current scope.
              at: GDScript::reload (res://scripts/main.gd:3)

Best-effort support is also included for the interactive ``-d`` debugger format
(``Debugger Break, Reason: '...'`` / ``*Frame N - res://file:line``) and the
timestamped ``E 0:00:...`` / ``<Stack Trace>`` format, so logs a user pastes by
hand also parse. The bundled runner (``run_project.py``) never uses ``-d``
because it blocks on stdin.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Optional


# --- Header patterns -------------------------------------------------------
# Order matters: the most specific prefix must be tried first. Each entry maps a
# regex (matched against the left-stripped line) to a severity. Group 1 is the
# human-readable message.
_HEADER_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^(?:USER )?SCRIPT ERROR:\s*Parse Error:\s*(.*)$"), "parse_error"),
    (re.compile(r"^(?:USER )?SCRIPT ERROR:\s*(.*)$"), "script_error"),
    (re.compile(r"^(?:USER )?SHADER ERROR:\s*(.*)$"), "shader_error"),
    (re.compile(r"^(?:USER )?ERROR:\s*(.*)$"), "error"),
    (re.compile(r"^(?:USER )?WARNING:\s*(.*)$"), "warning"),
    # Interactive -d debugger break line (best effort).
    (re.compile(r"^Debugger Break, Reason:\s*'(.*)'\s*$"), "script_error"),
    # Timestamped print_error format: "E 0:00:01:0456   file.gd:10 @ _ready(): msg"
    (re.compile(r"^E\s+\d[\d:]*\s+.*?:\d+\s+@\s+.*?:\s*(.*)$"), "script_error"),
    (re.compile(r"^W\s+\d[\d:]*\s+.*?:\d+\s+@\s+.*?:\s*(.*)$"), "warning"),
]

# res:// location, e.g. "res://scripts/main.gd:4". res:// paths contain no ':'
# other than the line-number separator, so stopping at the first ':' is safe.
_RES_LOC = re.compile(r"(res://[^:\s()]+):(\d+)")

# "at: <func> (<loc>)" continuation line.
_AT_LINE = re.compile(r"^at:\s*(?P<func>.*?)\s*\((?P<loc>[^()]*)\)\s*$")

# GDScript backtrace frame: "[0] _ready (res://scripts/main.gd:4)".
_FRAME_LINE = re.compile(r"^\[\d+\]\s*(?P<func>.*?)\s*\((?P<loc>[^()]*)\)\s*$")

# Interactive -d frame: "*Frame 0 - res://scripts/main.gd:6 in function 'foo'".
_D_FRAME = re.compile(
    r"^\*Frame\s+\d+\s*-\s*(?P<loc>res://[^\s]+)\s+in function\s+'(?P<func>[^']*)'"
)

# Timestamped-format location, e.g. "file.gd:10 @ _ready()".
_TS_LOC = re.compile(r"(?P<file>[^\s:@]+\.\w+):(?P<line>\d+)\s+@\s+(?P<func>.*?)\(\)")

# Continuation markers that belong to the current diagnostic even when a line's
# indentation was stripped by some capture pipeline.
_CONT_PREFIXES = (
    "at:",
    "GDScript backtrace",
    "<C++ Error>",
    "<C++ Source>",
    "<Stack Trace>",
    "<GDScript>",
    "*Frame ",
)


# --- Category / suggested-fix heuristics -----------------------------------
# Each rule is (needle_lowercased, category, suggested_fix). First match wins.
_CATEGORY_RULES: list[tuple[str, str, str]] = [
    (
        "null instance",
        "null_reference",
        "A node or object is null. Check the NodePath / get_node() target exists and is spelled correctly, "
        "use get_node_or_null() with a guard, or access it only after the node is in the tree (in _ready, "
        "or via @onready).",
    ),
    (
        "on a null value",
        "null_reference",
        "Calling a method on null. Guard the reference (if node: ...) or fix the assignment that left it null.",
    ),
    (
        "nonexistent function",
        "missing_method",
        "The method does not exist on that type. Check for a typo, the correct node class, or an API renamed "
        "between Godot versions (see the 4.x migration notes).",
    ),
    (
        "not found in base",
        "missing_method",
        "The function/member is not found on the base type. Fix the name, cast to the right type, or declare it.",
    ),
    (
        "nonexistent signal",
        "signal",
        "The signal is not declared on the emitter. Declare it with `signal name(...)`, fix the signal name, "
        "or connect to the correct node.",
    ),
    (
        "not declared in the current scope",
        "undeclared_identifier",
        "Identifier is undeclared. Declare the variable/const, fix the typo, or add the missing preload/import.",
    ),
    (
        "invalid get index",
        "invalid_index",
        "Indexing failed. The key/index is missing or the base is the wrong type (often a null or empty "
        "collection). Verify the property name and that the object is initialised.",
    ),
    (
        "invalid set index",
        "invalid_index",
        "Assignment target index is invalid. Verify the property/key name and the object type.",
    ),
    (
        "invalid access to property or key",
        "invalid_member",
        "Property or key does not exist on that object (or the object is null). Verify the member name and the "
        "object's type.",
    ),
    (
        "invalid call",
        "invalid_call",
        "The call target is invalid. Check the callee type and arguments.",
    ),
    (
        "node not found",
        "node_path",
        "get_node() could not resolve the path. Fix the NodePath, ensure the node exists at that path, or use "
        "get_node_or_null() plus a null check.",
    ),
    (
        "trying to assign value of type",
        "type_mismatch",
        "A typed variable received an incompatible type. Convert the value or relax/fix the declared type.",
    ),
    (
        "cannot convert",
        "type_mismatch",
        "A value cannot be converted to the expected type. Fix the value or the type annotation.",
    ),
    (
        "failed to load script",
        "resource_load",
        "A script failed to load, usually because of a parse error above it. Fix the parse error first.",
    ),
    (
        "failed to load resource",
        "resource_load",
        "A resource failed to load. Confirm the res:// path exists and the .uid metadata is intact "
        "(get_uid / resave_resources can repair missing UID sidecars).",
    ),
    (
        "resource file not found",
        "resource_load",
        "Referenced resource path does not exist. Fix the path or restore the file; repair UIDs if a move "
        "broke the reference (get_uid / resave_resources).",
    ),
    (
        "cannot open file",
        "resource_load",
        "A file path could not be opened. Confirm the res:// path and that the file was exported/committed.",
    ),
    (
        "parse error",
        "parse_error",
        "GDScript failed to compile. Fix the syntax/identifier at the reported line; the script will not run "
        "until it parses.",
    ),
    (
        "shader",
        "shader",
        "A shader failed to compile. Fix the reported shader line; uniforms and varyings must match their use.",
    ),
    (
        "condition \"",
        "engine_assertion",
        "An engine precondition failed. Usually a call made in the wrong state/order (e.g. before the node is "
        "in the tree). Move the call or satisfy the precondition.",
    ),
]

_SEVERITY_ORDER = {
    "parse_error": 0,
    "script_error": 1,
    "shader_error": 1,
    "error": 2,
    "warning": 3,
}


class _Diagnostic:
    __slots__ = (
        "severity",
        "message",
        "file",
        "line",
        "function",
        "stack",
        "raw_lines",
    )

    def __init__(self, severity: str, message: str) -> None:
        self.severity = severity
        self.message = message.strip()
        self.file: Optional[str] = None
        self.line: Optional[int] = None
        self.function: Optional[str] = None
        self.stack: list[dict] = []
        self.raw_lines: list[str] = []

    def set_location(self, file: str, line: int, function: Optional[str]) -> None:
        # First concrete res:// location wins (the crash site), except we never
        # overwrite it with a later, less-specific frame.
        if self.file is None:
            self.file = file
            self.line = line
            if function and function not in ("", "GDScript::reload"):
                self.function = function

    def to_dict(self) -> dict:
        category, suggested_fix = _classify(self.message)
        return {
            "severity": self.severity,
            "category": category,
            "message": self.message,
            "file": self.file,
            "line": self.line,
            "function": self.function,
            "stack": self.stack,
            "suggested_fix": suggested_fix,
            "raw": "\n".join(self.raw_lines).rstrip(),
        }


def _classify(message: str) -> tuple[str, str]:
    lowered = message.lower()
    for needle, category, fix in _CATEGORY_RULES:
        if needle in lowered:
            return category, fix
    return "unknown", (
        "Open the referenced file:line, read the message, and fix the offending statement. "
        "Re-run to confirm the diagnostic clears."
    )


def _match_header(stripped: str) -> Optional[tuple[str, str]]:
    for pattern, severity in _HEADER_PATTERNS:
        match = pattern.match(stripped)
        if match:
            return severity, match.group(1).strip()
    return None


def _is_continuation(stripped: str) -> bool:
    return stripped.startswith(_CONT_PREFIXES)


def _apply_continuation(diag: _Diagnostic, stripped: str) -> None:
    """Pull file/line/function and stack frames out of a continuation line."""
    at_match = _AT_LINE.match(stripped)
    if at_match:
        loc = at_match.group("loc")
        res = _RES_LOC.search(loc)
        if res:
            diag.set_location(res.group(1), int(res.group(2)), at_match.group("func"))
        return

    frame_match = _FRAME_LINE.match(stripped)
    if frame_match:
        loc = frame_match.group("loc")
        res = _RES_LOC.search(loc)
        if res:
            func = frame_match.group("func")
            frame = {"function": func, "file": res.group(1), "line": int(res.group(2))}
            diag.stack.append(frame)
            diag.set_location(frame["file"], frame["line"], func)
        return

    d_frame = _D_FRAME.match(stripped)
    if d_frame:
        res = _RES_LOC.search(d_frame.group("loc"))
        if res:
            func = d_frame.group("func")
            frame = {"function": func, "file": res.group(1), "line": int(res.group(2))}
            diag.stack.append(frame)
            diag.set_location(frame["file"], frame["line"], func)
        return

    # Fallback: any res:// location on a continuation line.
    res = _RES_LOC.search(stripped)
    if res:
        diag.set_location(res.group(1), int(res.group(2)), None)


def parse_log(text: str, include_warnings: bool = True) -> dict:
    """Parse Godot output text into a structured diagnostics report.

    Returns a dict with ``diagnostics`` (deduplicated, most-severe first) and a
    ``counts`` summary. Set ``include_warnings=False`` to drop warnings.
    """
    diagnostics: list[_Diagnostic] = []
    current: Optional[_Diagnostic] = None

    def close() -> None:
        nonlocal current
        if current is not None:
            diagnostics.append(current)
            current = None

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        header = _match_header(stripped)

        if header is not None:
            close()
            severity, message = header
            current = _Diagnostic(severity, message)
            current.raw_lines.append(raw_line.rstrip())

            # The timestamped "E 0:00:.. file.gd:10 @ func(): msg" header also
            # carries its own location inline.
            ts = _TS_LOC.search(stripped)
            if ts:
                current.set_location(ts.group("file"), int(ts.group("line")), ts.group("func"))
            continue

        if current is None:
            continue

        if stripped == "":
            close()
            continue

        indented = raw_line[:1].isspace()
        if indented or _is_continuation(stripped):
            current.raw_lines.append(raw_line.rstrip())
            _apply_continuation(current, stripped)
            continue

        # A non-indented, non-header, non-blank line ends the current block.
        close()

    close()

    if not include_warnings:
        diagnostics = [d for d in diagnostics if d.severity != "warning"]

    payload = [d.to_dict() for d in diagnostics]
    deduped = _dedupe(payload)
    deduped.sort(key=lambda d: _SEVERITY_ORDER.get(d["severity"], 9))

    counts = {
        "total": len(deduped),
        "errors": sum(1 for d in deduped if d["severity"] in ("error", "script_error", "shader_error")),
        "parse_errors": sum(1 for d in deduped if d["severity"] == "parse_error"),
        "warnings": sum(1 for d in deduped if d["severity"] == "warning"),
    }
    return {"diagnostics": deduped, "counts": counts}


def _dedupe(diagnostics: list[dict]) -> list[dict]:
    seen: dict[tuple, dict] = {}
    order: list[tuple] = []
    for diag in diagnostics:
        key = (diag["severity"], diag["file"], diag["line"], diag["message"])
        if key in seen:
            seen[key]["occurrences"] += 1
        else:
            entry = dict(diag)
            entry["occurrences"] = 1
            seen[key] = entry
            order.append(key)
    return [seen[key] for key in order]


def _read_input(path: Optional[str]) -> str:
    if path and path != "-":
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    return sys.stdin.read()


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Parse Godot stdout/stderr into structured diagnostics (JSON)."
    )
    parser.add_argument(
        "file",
        nargs="?",
        default="-",
        help="Log file to read, or '-' for stdin (default: stdin).",
    )
    parser.add_argument(
        "--no-warnings",
        action="store_true",
        help="Drop warnings from the report.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON output.",
    )
    args = parser.parse_args(argv or sys.argv[1:])

    report = parse_log(_read_input(args.file), include_warnings=not args.no_warnings)
    print(json.dumps(report, indent=2 if args.pretty else None))
    # Exit non-zero when any error-level diagnostic was found, so shell callers
    # can branch on it.
    return 1 if report["counts"]["errors"] or report["counts"]["parse_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
