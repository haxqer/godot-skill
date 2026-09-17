#!/usr/bin/env python3
"""Validate a Godot project's resources, plugins, GDExtensions, and C# solutions.

This runs the ``check_project`` dispatcher operation, which loads every script,
scene, shader, and resource in the project — and instantiates every scene — then
reports what the engine said while doing it.

Three things make this match what the Godot editor shows, instead of the much
quieter output a plain CLI run produces:

- It runs the static linter (``lint_project.py``) first and merges its
  diagnostics into the same ``diagnostics`` array, before Godot is started at
  all. That pass needs no Godot binary and reports what the engine never says
  out loud: Godot 3 API in a 4.x project, ``:=`` on an un-inferable value,
  ``$Panel/Missing`` node paths, ``[connection]`` blocks pointing at a method
  nobody wrote, and ``res://`` files that do not exist. Lint errors alone make
  ``ok`` false; ``--no-lint`` opts out.

- It passes ``-d --ignore-error-breaks``. GDScript warnings are emitted through
  the script debugger channel, never straight to stdout, so without ``-d`` a
  headless run prints no warnings at all. ``--ignore-error-breaks`` keeps the
  local debugger from breaking on the first error.
- It parses the captured stdout+stderr with ``godot_log_parser`` and folds the
  result into the verdict. Godot degrades gracefully on a lot of real breakage
  (a scene whose ``[ext_resource]`` is missing still loads and instantiates), so
  the file-level pass/fail list alone reports ``ok`` while the log carries the
  actual ``ERROR:`` lines.
- It asks ``check_project`` to instantiate scenes (``--no-instantiate`` opts
  out). ``load()`` accepts every broken node hierarchy; only
  ``PackedScene.instantiate()`` rejects a scene whose root carries ``parent=``
  or whose non-root node has no ``parent=`` (``ERROR: Invalid scene: ...``,
  a null return, and an entry in ``static.failed`` — all of which fail the run),
  and only instantiating prints the ``WARNING: Parent path ... has vanished``
  that a mistyped ``parent=`` produces. Instantiating runs each scene root
  script's ``_init()`` and its stored-property setters; ``--no-instantiate``
  is the escape hatch when that is not wanted.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from godot_log_parser import parse_log  # noqa: E402
from lint_project import lint_project  # noqa: E402


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Godot resources, plugins, GDExtensions, and C# solutions.")
    parser.add_argument("project_path")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--dispatcher", type=Path)
    parser.add_argument("--project-subpath", default="")
    parser.add_argument("--csharp", choices=["auto", "always", "never"], default="auto")
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument(
        "--no-warnings",
        action="store_true",
        help="Drop warnings from the diagnostics report (errors still fail the run).",
    )
    parser.add_argument(
        "--no-instantiate",
        dest="instantiate",
        action="store_false",
        help=(
            "Only load scenes, do not instantiate them. Skips the pass that catches an "
            "invalid node hierarchy (and stops project _init()/setter code from running)."
        ),
    )
    parser.add_argument(
        "--warnings-as-errors",
        action="store_true",
        help="Fail the run when any warning is reported, not just on errors.",
    )
    parser.add_argument(
        "--no-debugger",
        dest="debugger",
        action="store_false",
        help=(
            "Do not attach the local stdout debugger (-d --ignore-error-breaks). "
            "GDScript warnings are only emitted through the debugger channel, so "
            "this suppresses every warning the editor would show."
        ),
    )
    parser.add_argument(
        "--no-lint",
        dest="lint",
        action="store_false",
        help=(
            "Skip the static lint pass (scripts/debug/lint_project.py). That pass needs no "
            "Godot binary, runs first, and reports Godot 3 API, un-inferable ':=', broken "
            "NodePaths, dead [connection] targets, and missing res:// files."
        ),
    )
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def extract_payload(output: str) -> dict:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    return {"failed_count": 1, "failed": [{"kind": "validator", "reason": "check_project emitted no JSON"}]}


def command_result(completed: subprocess.CompletedProcess[str]) -> dict:
    return {"returncode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def run_bounded(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return subprocess.CompletedProcess(command, -1, stdout, stderr + f"\n[validate_project] timed out after {timeout}s")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        raise SystemExit(f"Missing Godot project file: {project_path / 'project.godot'}")
    dispatcher = (args.dispatcher or Path(__file__).resolve().parents[1] / "core/dispatcher.gd").resolve()

    # The static lint runs first: it needs no Godot binary, finishes in well under
    # a second, and catches the failures the engine is quiet about (a missing
    # ext_resource still loads, a wrong [connection] path is dropped silently).
    lint: dict = {"ran": False}
    lint_diagnostics: list[dict] = []
    if args.lint:
        lint = lint_project(
            project_path,
            subpath=args.project_subpath.replace("res://", ""),
            warnings_as_errors=args.warnings_as_errors,
        )
        lint["ran"] = True
        for entry in lint["diagnostics"]:
            merged = dict(entry)
            merged.setdefault("function", None)
            merged.setdefault("stack", [])
            merged.setdefault("raw", "")
            merged["occurrences"] = 1
            merged["source"] = "lint"
            lint_diagnostics.append(merged)
        if args.no_warnings:
            lint_diagnostics = [d for d in lint_diagnostics if d["severity"] != "warning"]

    # Passed explicitly rather than left to the operation's default: this is the
    # comprehensive pass, and a scene that cannot be instantiated must fail it.
    params: dict = {"instantiate": args.instantiate}
    if args.project_subpath:
        params["project_path"] = args.project_subpath
    command = [args.godot_bin, "--headless"]
    if args.debugger:
        # -d routes GDScript warnings to stdout; --ignore-error-breaks keeps the
        # local debugger from breaking (and ending the run) on the first error.
        command += ["--debug", "--ignore-error-breaks"]
    command += ["--path", str(project_path), "--script", str(dispatcher), "check_project", json.dumps(params)]
    checked = run_bounded(command, args.timeout)
    static = extract_payload(checked.stdout)
    report = parse_log(checked.stdout + "\n" + checked.stderr, include_warnings=not args.no_warnings)

    csproj_files = sorted(project_path.glob("*.csproj"))
    csharp_requested = args.csharp == "always" or (args.csharp == "auto" and bool(csproj_files))
    csharp: dict = {"requested": csharp_requested, "ran": False, "projects": [str(path) for path in csproj_files]}
    if csharp_requested:
        if not csproj_files:
            csharp.update({"ok": False, "error": "no .csproj file found"})
        elif not shutil.which("dotnet"):
            csharp.update({"ok": False, "error": "dotnet executable not found"})
        else:
            built = run_bounded(
                [args.godot_bin, "--headless", "--path", str(project_path), "--build-solutions", "--quit"],
                args.timeout,
            )
            csharp.update({"ran": True, "ok": built.returncode == 0, **command_result(built)})
    else:
        csharp["ok"] = True

    counts = report["counts"]
    lint_errors = sum(1 for d in lint_diagnostics if d["severity"] == "error")
    lint_warnings = sum(1 for d in lint_diagnostics if d["severity"] == "warning")
    counts["errors"] += lint_errors
    counts["warnings"] += lint_warnings
    counts["total"] += len(lint_diagnostics)
    log_clean = counts["errors"] == 0 and counts["parse_errors"] == 0
    if args.warnings_as_errors and counts["warnings"]:
        log_clean = False
    ok = (
        checked.returncode == 0
        and int(static.get("failed_count", 1)) == 0
        and bool(csharp.get("ok", False))
        and log_clean
    )
    payload = {
        "ok": ok,
        "project_path": str(project_path),
        "static": static,
        "counts": counts,
        # Lint diagnostics come first: a Godot 3 identifier or a missing file is
        # usually the cause of the engine errors underneath it.
        "diagnostics": lint_diagnostics + report["diagnostics"],
        "lint": {key: lint[key] for key in ("ran", "ok", "counts", "categories", "scan_summary")
                 if key in lint},
        "godot": command_result(checked),
        "csharp": csharp,
    }
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
