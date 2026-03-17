#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
EXPORT_WRAPPER = REPO_ROOT / "skill/godot/scripts/export/export_project.py"
TEMP_ROOTS: list[Path] = []


def main() -> None:
    try:
        test_release_dry_run_uses_release_flag_and_resolves_paths()
        test_debug_dry_run_uses_debug_flag()
        test_missing_project_file_fails_cleanly()
        print("All export wrapper tests passed.")
    finally:
        cleanup_temp_roots()


def test_release_dry_run_uses_release_flag_and_resolves_paths() -> None:
    project_path = copy_fixture_project()
    output_path = project_path / "build/windows/game.exe"
    payload = run_wrapper(
        [str(project_path), "Windows Desktop", str(output_path), "--dry-run", "--json"]
    )

    assert payload["mode"] == "release"
    assert payload["preset_name"] == "Windows Desktop"
    assert payload["project_path"] == str(project_path.resolve())
    assert payload["output_path"] == str(output_path.resolve())
    assert payload["command"] == [
        "godot",
        "--headless",
        "--path",
        str(project_path.resolve()),
        "--export-release",
        "Windows Desktop",
        str(output_path.resolve()),
    ]
    assert output_path.parent.is_dir()


def test_debug_dry_run_uses_debug_flag() -> None:
    project_path = copy_fixture_project()
    output_path = project_path / "build/android/game.apk"
    payload = run_wrapper(
        [
            str(project_path),
            "Android",
            str(output_path),
            "--mode",
            "debug",
            "--dry-run",
            "--json",
        ]
    )

    assert payload["mode"] == "debug"
    assert payload["command"][4] == "--export-debug"
    assert payload["command"][5] == "Android"
    assert payload["command"][6] == str(output_path.resolve())


def test_missing_project_file_fails_cleanly() -> None:
    temp_root = Path(tempfile.mkdtemp(prefix="godot-export-missing-project-"))
    try:
        result = subprocess.run(
            [
                "python3",
                str(EXPORT_WRAPPER),
                str(temp_root),
                "Web",
                str(temp_root / "build/web/index.html"),
                "--dry-run",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode != 0
        assert "Missing Godot project file" in result.stderr
    finally:
        shutil.rmtree(temp_root)


def copy_fixture_project() -> Path:
    temp_root = Path(tempfile.mkdtemp(prefix="godot-export-wrapper-test-"))
    TEMP_ROOTS.append(temp_root)
    project_path = temp_root / "project"
    shutil.copytree(FIXTURE_ROOT, project_path)
    return project_path


def cleanup_temp_roots() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def run_wrapper(args: list[str]) -> dict:
    result = subprocess.run(
        ["python3", str(EXPORT_WRAPPER), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"Export wrapper failed ({result.returncode}).\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return json.loads(result.stdout)


if __name__ == "__main__":
    main()
