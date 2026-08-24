#!/usr/bin/env python3
"""Validate a Godot project's resources, plugins, GDExtensions, and C# solutions.

This runs the ``check_project`` dispatcher operation, which loads every script,
scene, shader, and resource in the project — and instantiates every scene — then
reports what the engine said while doing it.

Two things make this match what the Godot editor shows, instead of the much
quieter output a plain CLI run produces:

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
        "diagnostics": report["diagnostics"],
        "godot": command_result(checked),
        "csharp": csharp,
    }
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
