#!/usr/bin/env python3
"""Unit tests for the Godot log parser.

Pure Python: these run without a Godot install. The sample logs below are the
verbatim output captured from ``godot 4.7.stable`` for each error shape.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PARSER_DIR = REPO_ROOT / "skill/godot/scripts/debug"
sys.path.insert(0, str(PARSER_DIR))

from godot_log_parser import parse_log  # noqa: E402


RUNTIME_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

SCRIPT ERROR: Invalid access to property or key 'position' on a base object of type 'null instance'.
          at: _ready (res://scripts/main.gd:4)
          GDScript backtrace (most recent call first):
              [0] _ready (res://scripts/main.gd:4)
"""

USER_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: custom boom happened
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] _ready (res://scripts/main.gd:3)
WARNING: this is a warning
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] _ready (res://scripts/main.gd:4)
"""

PARSE_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

SCRIPT ERROR: Parse Error: Identifier "undeclared_identifier" not declared in the current scope.
          at: GDScript::reload (res://scripts/main.gd:3)
SCRIPT ERROR: Parse Error: Function "call_missing_func()" not found in base self.
          at: GDScript::reload (res://scripts/main.gd:4)
ERROR: Failed to load script "res://scripts/main.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
"""

# Deeper backtrace: the crash site is the top ([0]) frame; the SCRIPT ERROR at:
# line already points there. Exercises multi-frame stack capture.
NESTED_LOG = """SCRIPT ERROR: Invalid call. Nonexistent function 'jump' in base 'Node2D (player.gd)'.
          at: _do (res://scripts/player.gd:20)
          GDScript backtrace (most recent call first):
              [0] _do (res://scripts/player.gd:20)
              [1] _ready (res://scripts/player.gd:8)
"""


def _only(report):
    assert len(report["diagnostics"]) == 1, report
    return report["diagnostics"][0]


def test_runtime_script_error():
    report = parse_log(RUNTIME_LOG)
    diag = _only(report)
    assert diag["severity"] == "script_error"
    assert diag["category"] == "null_reference"
    assert diag["file"] == "res://scripts/main.gd"
    assert diag["line"] == 4
    assert diag["function"] == "_ready"
    assert diag["stack"] == [{"function": "_ready", "file": "res://scripts/main.gd", "line": 4}]
    assert report["counts"] == {"total": 1, "errors": 1, "parse_errors": 0, "warnings": 0}


def test_push_error_uses_backtrace_location_not_cpp():
    # push_error's `at:` points at engine C++; the real location is backtrace [0].
    report = parse_log(USER_LOG)
    errors = [d for d in report["diagnostics"] if d["severity"] == "error"]
    warnings = [d for d in report["diagnostics"] if d["severity"] == "warning"]
    assert len(errors) == 1 and len(warnings) == 1
    err = errors[0]
    assert err["message"] == "custom boom happened"
    assert err["file"] == "res://scripts/main.gd"
    assert err["line"] == 3
    assert err["function"] == "_ready"
    warn = warnings[0]
    assert warn["file"] == "res://scripts/main.gd"
    assert warn["line"] == 4


def test_warnings_can_be_excluded():
    report = parse_log(USER_LOG, include_warnings=False)
    assert all(d["severity"] != "warning" for d in report["diagnostics"])
    assert report["counts"]["warnings"] == 0
    assert report["counts"]["errors"] == 1


def test_parse_errors():
    report = parse_log(PARSE_LOG)
    parse_errors = [d for d in report["diagnostics"] if d["severity"] == "parse_error"]
    assert len(parse_errors) == 2
    by_line = {d["line"]: d for d in parse_errors}
    assert by_line[3]["category"] == "undeclared_identifier"
    assert by_line[3]["file"] == "res://scripts/main.gd"
    assert "Parse Error:" not in by_line[3]["message"]  # prefix stripped into message body
    assert by_line[4]["category"] == "missing_method"
    # The follow-on "Failed to load script" is captured as an error.
    assert any(d["category"] == "resource_load" for d in report["diagnostics"])
    assert report["counts"]["parse_errors"] == 2


def test_nested_backtrace_frames_captured():
    report = parse_log(NESTED_LOG)
    diag = _only(report)
    assert diag["category"] == "missing_method"
    assert diag["file"] == "res://scripts/player.gd"
    assert diag["line"] == 20
    assert len(diag["stack"]) == 2
    assert diag["stack"][1] == {"function": "_ready", "file": "res://scripts/player.gd", "line": 8}


def test_clean_log_has_no_diagnostics():
    clean = (
        "Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org\n\n"
        "clean boot ok\n"
    )
    report = parse_log(clean)
    assert report["diagnostics"] == []
    assert report["counts"]["total"] == 0


def test_duplicate_errors_are_collapsed_with_count():
    doubled = RUNTIME_LOG + "\n" + RUNTIME_LOG.split("\n", 2)[2]
    report = parse_log(doubled)
    diag = _only(report)
    assert diag["occurrences"] == 2


def test_diagnostics_sorted_most_severe_first():
    report = parse_log(PARSE_LOG + USER_LOG)
    severities = [d["severity"] for d in report["diagnostics"]]
    # parse_error (0) and script/error (1-2) before warning (3)
    assert severities.index("parse_error") < severities.index("warning")


def test_unknown_message_still_reports_location_and_fallback_fix():
    log = (
        "SCRIPT ERROR: Something totally novel happened.\n"
        "          at: _ready (res://a.gd:9)\n"
    )
    diag = _only(parse_log(log))
    assert diag["category"] == "unknown"
    assert diag["file"] == "res://a.gd" and diag["line"] == 9
    assert diag["suggested_fix"]


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"All {len(tests)} log parser tests passed.")


if __name__ == "__main__":
    main()
