#!/usr/bin/env python3
"""Run a Godot project's GUT or GdUnit4 test suite headlessly.

Godot ships no built-in unit-test framework for project code, so this wrapper
auto-detects the two community standards and normalizes their CLI and exit
codes into one JSON result:

- GUT   (addons/gut):     exit 0 = pass, 1 = failures
- GdUnit4 (addons/gdUnit4): exit 0 = pass, 100 = failures, 101 = warnings
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_TEST_DIRS = ["test", "tests"]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run GUT or GdUnit4 tests headlessly and report structured JSON.")
    parser.add_argument("project_path")
    parser.add_argument("--framework", choices=["auto", "gut", "gdunit4"], default="auto")
    parser.add_argument("--tests-dir", default="", help="Project-relative tests directory (default: test/ or tests/)")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--junit-xml", default="", help="Also write a JUnit XML report to this absolute path (GUT only)")
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--dry-run", action="store_true", help="Report detection and the exact command without running")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def detect_framework(project_path: Path) -> str:
    if (project_path / "addons/gut/gut_cmdln.gd").is_file():
        return "gut"
    if (project_path / "addons/gdUnit4/bin/GdUnitCmdTool.gd").is_file():
        return "gdunit4"
    return "none"


def resolve_tests_dir(project_path: Path, requested: str) -> str:
    if requested:
        return requested.removeprefix("res://").strip("/")
    for candidate in DEFAULT_TEST_DIRS:
        if (project_path / candidate).is_dir():
            return candidate
    return ""


def build_command(framework: str, args: argparse.Namespace, project_path: Path, tests_dir: str) -> list[str]:
    command = [args.godot_bin, "--headless", "--path", str(project_path)]
    if framework == "gut":
        command.extend(["-s", "res://addons/gut/gut_cmdln.gd", f"-gdir=res://{tests_dir}", "-ginclude_subdirs", "-gexit"])
        if args.junit_xml:
            command.append(f"-gjunit_xml_file={args.junit_xml}")
    else:
        command.extend(["-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--add", f"res://{tests_dir}", "--continue"])
    return command


def interpret(framework: str, returncode: int) -> tuple[bool, str]:
    if framework == "gut":
        return returncode == 0, {0: "passed"}.get(returncode, "failed")
    statuses = {0: "passed", 100: "failed", 101: "passed_with_warnings"}
    return returncode in (0, 101), statuses.get(returncode, f"runner_error_{returncode}")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        raise SystemExit(f"Missing Godot project file: {project_path / 'project.godot'}")

    framework = args.framework if args.framework != "auto" else detect_framework(project_path)
    if framework == "none":
        print(json.dumps({
            "ok": False,
            "framework": "none",
            "errors": [
                "No test framework detected. Install GUT (addons/gut) or GdUnit4 (addons/gdUnit4); Godot has no built-in project test runner."
            ],
        }, indent=2 if args.pretty else None))
        return 1

    tests_dir = resolve_tests_dir(project_path, args.tests_dir)
    if not tests_dir:
        print(json.dumps({
            "ok": False,
            "framework": framework,
            "errors": ["No tests directory found; pass --tests-dir or create test/ or tests/"],
        }, indent=2 if args.pretty else None))
        return 1

    command = build_command(framework, args, project_path, tests_dir)
    payload: dict = {"framework": framework, "tests_dir": f"res://{tests_dir}", "command": command}

    if args.dry_run:
        payload["ok"] = True
        payload["dry_run"] = True
        print(json.dumps(payload, indent=2 if args.pretty else None))
        return 0

    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        payload.update({"ok": False, "timed_out": True, "errors": [f"Test run timed out after {args.timeout}s"]})
        print(json.dumps(payload, indent=2 if args.pretty else None))
        return 1

    ok, status = interpret(framework, completed.returncode)
    tail = "\n".join((completed.stdout + "\n" + completed.stderr).strip().splitlines()[-40:])
    payload.update({"ok": ok, "status": status, "returncode": completed.returncode, "output_tail": tail})
    if framework == "gdunit4":
        reports = project_path / "reports"
        if reports.is_dir():
            payload["reports_dir"] = str(reports)
    if args.junit_xml and Path(args.junit_xml).is_file():
        payload["junit_xml"] = args.junit_xml
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
