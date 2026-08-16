#!/usr/bin/env python3
"""Regression tests for CLI diagnostics matching what the Godot editor shows.

Two engine behaviours make a naive CLI run far quieter than the editor, and both
are covered here:

1. GDScript warnings are emitted through the *script debugger* channel, not to
   stdout. Without ``-d`` a headless run prints none of them, so a project the
   editor flags a dozen times comes back clean.
2. Godot degrades gracefully where the editor is fatal: a scene whose
   ``[ext_resource]`` is missing still loads and still instantiates, printing
   only an ``ERROR:`` line. A file-level pass/fail summary alone calls that ok.

The command-building tests run everywhere. The rest need a local ``godot`` CLI
(GODOT_BIN or ``godot`` on PATH) and are skipped with a notice when it is
missing, so the suite still passes without Godot installed.
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
VALIDATE_PROJECT = SKILL_ROOT / "scripts/debug/validate_project.py"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")
TEMP_ROOTS: list[Path] = []

# Every line here trips a different default-on GDScript analyzer warning.
WARNING_SCRIPT = """extends Node2D

var health: int = 10

func _ready() -> void:
\tvar unused_local = 5
\tvar quotient = 7 / 2
\tprint(quotient)
\tshadowing(1)

func shadowing(health) -> int:
\treturn health * 2
"""

CLEAN_SCRIPT = """extends Node2D

func _ready() -> void:
\tprint("clean boot ok")
"""


def godot_available() -> bool:
    return shutil.which(GODOT_BIN) is not None


def make_project(main_script: str, *, extra_scripts: dict[str, str] | None = None,
                 missing_dependency: bool = False) -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-warning-test-"))
    TEMP_ROOTS.append(root)
    (root / "scripts").mkdir()
    (root / "scenes").mkdir()
    (root / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="WarningTest"\n'
        'run/main_scene="res://scenes/main.tscn"\n',
        encoding="utf-8",
    )
    (root / "scripts/main.gd").write_text(main_script, encoding="utf-8")
    for name, source in (extra_scripts or {}).items():
        (root / "scripts" / name).write_text(source, encoding="utf-8")

    scene = (
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/main.gd" id="1"]\n'
        '[node name="Main" type="Node2D"]\n'
        'script = ExtResource("1")\n'
    )
    if missing_dependency:
        # A texture that was never created: the editor reports this loudly, but
        # load() still returns an instantiable PackedScene.
        scene = (
            '[gd_scene load_steps=3 format=3]\n'
            '[ext_resource type="Script" path="res://scripts/main.gd" id="1"]\n'
            '[ext_resource type="Texture2D" path="res://art/missing.png" id="2"]\n'
            '[node name="Main" type="Node2D"]\n'
            'script = ExtResource("1")\n'
            '[node name="Sprite2D" type="Sprite2D" parent="."]\n'
            'texture = ExtResource("2")\n'
        )
    (root / "scenes/main.tscn").write_text(scene, encoding="utf-8")
    return root


def run_project(project: Path, *extra: str) -> dict:
    result = subprocess.run(
        ["python3", str(RUN_PROJECT), str(project), "--quit-after", "10", "--timeout", "30", *extra],
        capture_output=True,
        text=True,
        check=False,
    )
    return json.loads(result.stdout)


def validate_project(project: Path, *extra: str) -> dict:
    result = subprocess.run(
        ["python3", str(VALIDATE_PROJECT), str(project), *extra],
        capture_output=True,
        text=True,
        check=False,
    )
    return json.loads(result.stdout)


def dry_run_command(project: Path, *extra: str) -> list[str]:
    result = subprocess.run(
        ["python3", str(RUN_PROJECT), str(project), "--dry-run", *extra],
        capture_output=True,
        text=True,
        check=False,
    )
    return json.loads(result.stdout)["command"]


def test_run_project_attaches_the_local_debugger_by_default() -> None:
    command = dry_run_command(make_project(CLEAN_SCRIPT))
    assert "--debug" in command, command
    assert "--ignore-error-breaks" in command, command
    # Both flags must precede --path so Godot parses them as engine options.
    assert command.index("--debug") < command.index("--path")


def test_run_project_no_debugger_opts_out() -> None:
    command = dry_run_command(make_project(CLEAN_SCRIPT), "--no-debugger")
    assert "--debug" not in command, command
    assert "--ignore-error-breaks" not in command, command


def test_run_project_reports_gdscript_warnings() -> None:
    if not godot_available():
        print("SKIP test_run_project_reports_gdscript_warnings (no godot)")
        return
    report = run_project(make_project(WARNING_SCRIPT))
    assert report["counts"]["warnings"] >= 3, report
    assert report["counts"]["errors"] == 0, report
    messages = " ".join(d["message"] for d in report["diagnostics"])
    assert "unused_local" in messages
    assert "Integer division" in messages
    assert "shadowing" in messages.lower() or "shadow" in messages.lower()
    located = [d for d in report["diagnostics"] if d["severity"] == "warning"]
    assert all(d["file"] == "res://scripts/main.gd" and d["line"] for d in located), located


def test_run_project_without_debugger_is_silent_about_warnings() -> None:
    """The bug this suite exists for: no -d means no warnings at all."""
    if not godot_available():
        print("SKIP test_run_project_without_debugger_is_silent_about_warnings (no godot)")
        return
    report = run_project(make_project(WARNING_SCRIPT), "--no-debugger")
    assert report["counts"]["warnings"] == 0, report


def test_run_project_still_bounded_and_clean_with_the_debugger_attached() -> None:
    """-d must not break into `debug>` or otherwise stall the run."""
    if not godot_available():
        print("SKIP test_run_project_still_bounded_and_clean_with_the_debugger_attached (no godot)")
        return
    report = run_project(make_project(CLEAN_SCRIPT))
    assert report["ok"] is True, report
    assert report["timed_out"] is False
    assert report["counts"]["total"] == 0, report


def test_run_project_does_not_stop_at_the_first_error() -> None:
    """--ignore-error-breaks: an error must not end the run at a debugger break."""
    if not godot_available():
        print("SKIP test_run_project_does_not_stop_at_the_first_error (no godot)")
        return
    script = (
        "extends Node2D\n"
        "func _ready() -> void:\n"
        "\tvar missing = get_node_or_null(\"Nope\")\n"
        "\tif missing == null:\n"
        "\t\tpush_error(\"first boom\")\n"
        "\tpush_error(\"second boom\")\n"
    )
    report = run_project(make_project(script))
    assert report["timed_out"] is False, report
    messages = " ".join(d["message"] for d in report["diagnostics"])
    assert "first boom" in messages and "second boom" in messages, report


def test_validate_project_reports_warnings_for_scripts_the_boot_never_loads() -> None:
    """check_project loads every file, so it covers scripts no scene references."""
    if not godot_available():
        print("SKIP test_validate_project_reports_warnings_for_scripts_the_boot_never_loads (no godot)")
        return
    project = make_project(CLEAN_SCRIPT, extra_scripts={"orphan.gd": WARNING_SCRIPT})
    report = validate_project(project)
    warnings = [d for d in report["diagnostics"] if d["severity"] == "warning"]
    assert warnings, report
    assert any(d["file"] == "res://scripts/orphan.gd" for d in warnings), warnings

    # A boot-and-quit run never touches orphan.gd, which is why both passes exist.
    boot = run_project(project)
    assert boot["counts"]["warnings"] == 0, boot


def test_validate_project_fails_on_a_missing_scene_dependency() -> None:
    if not godot_available():
        print("SKIP test_validate_project_fails_on_a_missing_scene_dependency (no godot)")
        return
    report = validate_project(make_project(CLEAN_SCRIPT, missing_dependency=True))
    assert report["ok"] is False, report
    assert report["counts"]["errors"] >= 1, report
    failed = report["static"]["failed"]
    assert any(f["path"] == "res://scenes/main.tscn" for f in failed), failed
    assert any("missing.png" in f["reason"] for f in failed), failed


def test_validate_project_passes_a_clean_project() -> None:
    if not godot_available():
        print("SKIP test_validate_project_passes_a_clean_project (no godot)")
        return
    report = validate_project(make_project(CLEAN_SCRIPT))
    assert report["ok"] is True, report
    assert report["counts"]["errors"] == 0 and report["counts"]["warnings"] == 0, report
    assert report["static"]["failed_count"] == 0


def test_validate_project_warnings_as_errors_flips_the_verdict() -> None:
    if not godot_available():
        print("SKIP test_validate_project_warnings_as_errors_flips_the_verdict (no godot)")
        return
    project = make_project(WARNING_SCRIPT)
    assert validate_project(project)["ok"] is True
    strict = validate_project(project, "--warnings-as-errors")
    assert strict["ok"] is False, strict
    assert strict["counts"]["warnings"] >= 3, strict


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    try:
        for test in tests:
            test()
        suffix = "" if godot_available() else " (godot-dependent tests skipped)"
        print(f"All {len(tests)} warning-visibility tests passed{suffix}.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()
