#!/usr/bin/env python3
"""Integration tests for the runtime runner and the check_project operation.

The command-building test runs everywhere. The rest need a local ``godot`` CLI
(GODOT_BIN or ``godot`` on PATH) and are skipped with a notice when it is
missing, so the suite still passes in environments without Godot installed.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = REPO_ROOT / "skill/godot"
RUN_PROJECT = SKILL_ROOT / "scripts/debug/run_project.py"
DISPATCHER = SKILL_ROOT / "scripts/core/dispatcher.gd"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")
TEMP_ROOTS: list[Path] = []


def godot_available() -> bool:
    return shutil.which(GODOT_BIN) is not None


def make_project(main_script: str) -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-debug-test-"))
    TEMP_ROOTS.append(root)
    (root / "scripts").mkdir()
    (root / "scenes").mkdir()
    (root / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="DebugTest"\n'
        'run/main_scene="res://scenes/main.tscn"\n',
        encoding="utf-8",
    )
    (root / "scripts/main.gd").write_text(main_script, encoding="utf-8")
    (root / "scenes/main.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/main.gd" id="1"]\n'
        '[node name="Main" type="Node2D"]\n'
        'script = ExtResource("1")\n',
        encoding="utf-8",
    )
    return root


def run_project(project: Path, *extra: str) -> dict:
    result = subprocess.run(
        ["python3", str(RUN_PROJECT), str(project), "--quit-after", "10", "--timeout", "30", *extra],
        capture_output=True,
        text=True,
        check=False,
    )
    return json.loads(result.stdout)


def check_project(project: Path) -> dict:
    result = subprocess.run(
        [GODOT_BIN, "--headless", "--path", str(project), "--script", str(DISPATCHER), "check_project", "{}"],
        capture_output=True,
        text=True,
        check=False,
        stdin=subprocess.DEVNULL,
    )
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"No JSON summary from check_project.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")


CLEAN = """extends Node2D
func _ready() -> void:
\tprint("clean boot ok")
"""

RUNTIME_ERROR = """extends Node2D
func _ready() -> void:
\tvar n = get_node_or_null("Nope")
\tprint(n.position)
"""

PARSE_ERROR = """extends Node2D
func _ready() -> void:
\tvar x = undeclared_identifier + 1
"""


def test_run_project_dry_run_builds_expected_command() -> None:
    project = make_project(CLEAN)
    result = subprocess.run(
        ["python3", str(RUN_PROJECT), str(project), "res://scenes/main.tscn",
         "--quit-after", "42", "--dry-run"],
        capture_output=True,
        text=True,
        check=False,
    )
    payload = json.loads(result.stdout)
    command = payload["command"]
    assert command[0] == GODOT_BIN or command[0].endswith("godot")
    assert "--headless" in command
    assert "--quit-after" in command and command[command.index("--quit-after") + 1] == "42"
    assert command[-1] == "res://scenes/main.tscn"


def test_run_project_clean_boot_is_ok() -> None:
    if not godot_available():
        print("SKIP test_run_project_clean_boot_is_ok (no godot)")
        return
    report = run_project(make_project(CLEAN))
    assert report["ok"] is True, report
    assert report["counts"]["errors"] == 0
    assert report["timed_out"] is False


def test_run_project_detects_runtime_error() -> None:
    if not godot_available():
        print("SKIP test_run_project_detects_runtime_error (no godot)")
        return
    report = run_project(make_project(RUNTIME_ERROR))
    assert report["ok"] is False, report
    assert report["counts"]["errors"] >= 1
    diag = report["diagnostics"][0]
    assert diag["category"] == "null_reference"
    assert diag["file"] == "res://scripts/main.gd"
    assert diag["line"] == 4
    assert diag["function"] == "_ready"


def test_run_project_reports_parse_error() -> None:
    if not godot_available():
        print("SKIP test_run_project_reports_parse_error (no godot)")
        return
    report = run_project(make_project(PARSE_ERROR))
    assert report["ok"] is False
    assert report["counts"]["parse_errors"] >= 1
    parse_diags = [d for d in report["diagnostics"] if d["severity"] == "parse_error"]
    assert parse_diags and parse_diags[0]["file"] == "res://scripts/main.gd"


def test_check_project_flags_broken_script_and_passes_clean() -> None:
    if not godot_available():
        print("SKIP test_check_project_flags_broken_script_and_passes_clean (no godot)")
        return
    broken = check_project(make_project(PARSE_ERROR))
    assert broken["failed_count"] >= 1
    failed_paths = [f["path"] for f in broken["failed"]]
    assert "res://scripts/main.gd" in failed_paths

    clean = check_project(make_project(CLEAN))
    assert clean["failed_count"] == 0
    assert clean["ok"] == clean["checked"]


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    try:
        for test in tests:
            test()
        suffix = "" if godot_available() else " (godot-dependent tests skipped)"
        print(f"All {len(tests)} run/debug tests passed{suffix}.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()
