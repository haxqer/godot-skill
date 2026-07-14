#!/usr/bin/env python3
"""Tests for the run_tests.py GUT/GdUnit4 wrapper (detection + command shape)."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
RUNNER = REPO_ROOT / "skill/godot/scripts/test/run_tests.py"


def main() -> None:
    test_no_framework_detected()
    test_gut_detection_and_command()
    test_gdunit4_detection_and_command()
    test_gut_real_execution_path()
    print("All run_tests wrapper tests passed.")


def test_no_framework_detected() -> None:
    with fixture_project() as project:
        payload = run_wrapper(project, expected_returncode=1)
        assert payload["ok"] is False
        assert payload["framework"] == "none"


def test_gut_detection_and_command() -> None:
    with fixture_project() as project:
        (project / "addons/gut").mkdir(parents=True)
        (project / "addons/gut/gut_cmdln.gd").write_text("extends SceneTree\n", encoding="utf-8")
        (project / "test").mkdir()
        payload = run_wrapper(project, "--dry-run")
        assert payload["ok"] is True
        assert payload["framework"] == "gut"
        assert payload["tests_dir"] == "res://test"
        assert "res://addons/gut/gut_cmdln.gd" in payload["command"]
        assert "-gexit" in payload["command"]


def test_gdunit4_detection_and_command() -> None:
    with fixture_project() as project:
        (project / "addons/gdUnit4/bin").mkdir(parents=True)
        (project / "addons/gdUnit4/bin/GdUnitCmdTool.gd").write_text("extends SceneTree\n", encoding="utf-8")
        (project / "tests").mkdir()
        payload = run_wrapper(project, "--dry-run")
        assert payload["ok"] is True
        assert payload["framework"] == "gdunit4"
        assert payload["tests_dir"] == "res://tests"
        assert "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" in payload["command"]
        assert "--continue" in payload["command"]


def test_gut_real_execution_path() -> None:
    """Exercise the non-dry-run path with a stub gut_cmdln.gd so the wrapper's
    actual invocation, exit-code mapping, and output-tail capture are covered
    without installing the real GUT addon."""
    with fixture_project() as project:
        (project / "addons/gut").mkdir(parents=True)
        (project / "addons/gut/gut_cmdln.gd").write_text(
            "extends SceneTree\n"
            "func _init() -> void:\n"
            "    print(\"STUB GUT: 3 passed / 0 failed\")\n"
            "    quit(0)\n",
            encoding="utf-8",
        )
        (project / "test").mkdir()
        payload = run_wrapper(project)
        assert payload["ok"] is True
        assert payload["status"] == "passed"
        assert "STUB GUT" in payload["output_tail"]

        (project / "addons/gut/gut_cmdln.gd").write_text(
            "extends SceneTree\n"
            "func _init() -> void:\n"
            "    print(\"STUB GUT: 1 failed\")\n"
            "    quit(1)\n",
            encoding="utf-8",
        )
        failed = run_wrapper(project, expected_returncode=1)
        assert failed["ok"] is False
        assert failed["status"] == "failed"


class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-tests-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def run_wrapper(project: Path, *extra_args: str, expected_returncode: int = 0) -> dict:
    result = subprocess.run(
        ["python3", str(RUNNER), str(project), *extra_args],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"run_tests returned {result.returncode}, expected {expected_returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return json.loads(result.stdout)


if __name__ == "__main__":
    main()
