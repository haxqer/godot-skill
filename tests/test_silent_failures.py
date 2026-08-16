#!/usr/bin/env python3
"""Regression tests for tooling that reported success while something was wrong.

Each case here was a real defect: the command exited 0, or printed a clean JSON
summary, while the project was broken or the requested change had not been made.

- A misspelled parameter key was silently ignored, so the operation fell back to
  its default, saved the scene, and reported success.
- Reading a parameter with attribute access (``params.scene_path``) raised a
  GDScript runtime error on a missing key, which aborts ``execute()`` without
  recording an error — the dispatcher then exited 0.
- ``.gdshader`` files were only loaded, never compiled, so a shader full of
  syntax errors passed validation.
- ``run_tests.py`` reported a pass when the suite contained nothing to run.
- ``export_project.py`` trusted the exporter's exit code without checking that
  an artifact was actually produced.

The lint and pure-Python tests run everywhere. The rest need a local ``godot``
CLI (GODOT_BIN or ``godot`` on PATH) and are skipped with a notice.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = REPO_ROOT / "skill/godot"
SCRIPTS_ROOT = SKILL_ROOT / "scripts"
DISPATCHER = SCRIPTS_ROOT / "core/dispatcher.gd"
VALIDATE_PROJECT = SCRIPTS_ROOT / "debug/validate_project.py"
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")
TEMP_ROOTS: list[Path] = []

sys.path.insert(0, str(SCRIPTS_ROOT / "export"))
from export_project import artifact_is_present  # noqa: E402

# Dictionary members that are method calls, not parameter reads.
DICTIONARY_METHODS = {
    "get", "has", "keys", "values", "size", "is_empty", "erase", "merge",
    "duplicate", "hash", "has_all", "find_key", "get_or_add", "clear", "sort",
    "make_read_only", "is_read_only", "merged", "recursive_equal", "assign",
}
ATTRIBUTE_ACCESS = re.compile(r"\bparams\.([a-z_][a-z_0-9]*)")


def godot_available() -> bool:
    return shutil.which(GODOT_BIN) is not None


def fixture_copy() -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-silent-test-"))
    TEMP_ROOTS.append(root)
    project = root / "project"
    shutil.copytree(FIXTURE_ROOT, project)
    return project


def dispatch(project: Path, operation: str, params: dict, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [GODOT_BIN, "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params), *extra],
        capture_output=True,
        text=True,
        check=False,
        stdin=subprocess.DEVNULL,
    )


def test_no_attribute_style_parameter_access() -> None:
    """Keys must be read with get()/has().

    Two reasons, both of which produced silent failures: attribute access
    raises at runtime on a missing key (aborting execute() without recording an
    error, so the dispatcher exits 0), and the dispatcher's unknown-parameter
    check derives its allowlist from get()/has() literals, so an
    attribute-accessed key would be rejected as unknown.
    """
    offenders: list[str] = []
    for path in sorted(SCRIPTS_ROOT.rglob("*.gd")):
        source = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(source.splitlines(), start=1):
            if line.lstrip().startswith("#"):
                continue
            for name in ATTRIBUTE_ACCESS.findall(line):
                if name not in DICTIONARY_METHODS:
                    offenders.append(f"{path.relative_to(REPO_ROOT)}:{line_number}: params.{name}")
    assert not offenders, (
        "Use params.get(\"key\", default) / params.has(\"key\") instead of attribute access:\n"
        + "\n".join(offenders)
    )


def test_artifact_presence_check() -> None:
    root = Path(tempfile.mkdtemp(prefix="godot-artifact-test-"))
    TEMP_ROOTS.append(root)
    missing = root / "nothing.zip"
    assert artifact_is_present(missing) is False

    empty = root / "empty.zip"
    empty.write_bytes(b"")
    assert artifact_is_present(empty) is False

    real = root / "game.zip"
    real.write_bytes(b"PK\x03\x04")
    assert artifact_is_present(real) is True

    empty_dir = root / "bundle"
    empty_dir.mkdir()
    assert artifact_is_present(empty_dir) is False
    (empty_dir / "Info.plist").write_text("x", encoding="utf-8")
    assert artifact_is_present(empty_dir) is True


def test_unknown_parameter_is_rejected() -> None:
    if not godot_available():
        print("SKIP test_unknown_parameter_is_rejected (no godot)")
        return
    project = fixture_copy()
    before = (project / "scenes/card.tscn").read_text(encoding="utf-8")
    result = dispatch(project, "add_node", {
        "scene_path": "scenes/card.tscn",
        "parent_path": "root",            # real key is parent_node_path
        "node_type": "Node2D",
        "node_name": "Injected",
    })
    assert result.returncode != 0, result.stdout + result.stderr
    assert "Unknown parameter for add_node: parent_path" in result.stderr, result.stderr
    assert "parent_node_path" in result.stderr, "the error should suggest the real key"
    # The scene must be untouched: the old behaviour parented to the root and saved.
    assert (project / "scenes/card.tscn").read_text(encoding="utf-8") == before


def test_correct_parameters_still_accepted() -> None:
    if not godot_available():
        print("SKIP test_correct_parameters_still_accepted (no godot)")
        return
    project = fixture_copy()
    result = dispatch(project, "add_node", {
        "scene_path": "scenes/card.tscn",
        "parent_node_path": "root",
        "node_type": "Node2D",
        "node_name": "Good",
    })
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'name="Good"' in (project / "scenes/card.tscn").read_text(encoding="utf-8")


def test_unknown_parameter_inside_a_batch_action_is_rejected() -> None:
    if not godot_available():
        print("SKIP test_unknown_parameter_inside_a_batch_action_is_rejected (no godot)")
        return
    project = fixture_copy()
    result = dispatch(project, "scene_batch", {
        "scene_path": "scenes/card.tscn",
        "actions": [{"type": "add_node", "parent_path": "root",
                     "node_type": "Node2D", "node_name": "N"}],
    })
    assert result.returncode != 0, result.stdout + result.stderr
    assert "actions[0].parent_path" in result.stderr, result.stderr


def test_free_form_value_dictionaries_are_not_treated_as_parameters() -> None:
    """`properties` holds user data; its keys must never be checked as params."""
    if not godot_available():
        print("SKIP test_free_form_value_dictionaries_are_not_treated_as_parameters (no godot)")
        return
    project = fixture_copy()
    result = dispatch(project, "configure_node", {
        "scene_path": "scenes/card.tscn",
        "node_path": "root",
        "properties": {"name": "Renamed", "process_mode": 1},
    })
    assert "Unknown parameter" not in result.stderr, result.stderr
    assert result.returncode == 0, result.stdout + result.stderr


def test_skip_param_check_escape_hatch() -> None:
    if not godot_available():
        print("SKIP test_skip_param_check_escape_hatch (no godot)")
        return
    project = fixture_copy()
    result = dispatch(project, "add_node", {
        "scene_path": "scenes/card.tscn",
        "parent_path": "root",
        "node_type": "Node2D",
        "node_name": "Escaped",
    }, "--skip-param-check")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Unknown parameter" not in result.stderr


def test_missing_required_parameter_errors_instead_of_crashing() -> None:
    """export_mesh_library used to raise a runtime error here and still exit 0."""
    if not godot_available():
        print("SKIP test_missing_required_parameter_errors_instead_of_crashing (no godot)")
        return
    project = fixture_copy()
    result = dispatch(project, "export_mesh_library", {})
    assert result.returncode != 0, result.stdout + result.stderr
    assert "SCRIPT ERROR" not in result.stderr, "should be a reported error, not a crash"
    assert "requires scene_path and output_path" in result.stderr, result.stderr


def shader_project(shader_source: str) -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-shader-test-"))
    TEMP_ROOTS.append(root)
    (root / "shaders").mkdir()
    (root / "scenes").mkdir()
    (root / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="ShaderTest"\n'
        'run/main_scene="res://scenes/main.tscn"\n',
        encoding="utf-8",
    )
    (root / "scenes/main.tscn").write_text(
        '[gd_scene format=3]\n[node name="Main" type="Node2D"]\n', encoding="utf-8"
    )
    (root / "shaders/effect.gdshader").write_text(shader_source, encoding="utf-8")
    return root


BROKEN_SHADER = """shader_type canvas_item;

void fragment() {
\tCOLOR = vec4(1.0, 0.0, 0.0);
}
"""

VALID_SHADER = """shader_type canvas_item;

void fragment() {
\tCOLOR = vec4(1.0, 0.0, 0.0, 1.0);
}
"""


def validate(project: Path) -> dict:
    result = subprocess.run(
        ["python3", str(VALIDATE_PROJECT), str(project)],
        capture_output=True, text=True, check=False,
    )
    return json.loads(result.stdout)


def test_broken_shader_fails_validation() -> None:
    """load() never compiles a shader, so this used to pass cleanly."""
    if not godot_available():
        print("SKIP test_broken_shader_fails_validation (no godot)")
        return
    report = validate(shader_project(BROKEN_SHADER))
    assert report["ok"] is False, report
    shader_errors = [d for d in report["diagnostics"] if d["severity"] == "shader_error"]
    assert shader_errors, report["diagnostics"]
    # The compile error carries no path of its own; check_project's marker is
    # what lets the parser attribute it back to the file.
    assert shader_errors[0]["file"] == "res://shaders/effect.gdshader", shader_errors[0]
    assert shader_errors[0]["line"] == 4, shader_errors[0]


def test_valid_shader_passes_validation() -> None:
    if not godot_available():
        print("SKIP test_valid_shader_passes_validation (no godot)")
        return
    report = validate(shader_project(VALID_SHADER))
    assert report["ok"] is True, report
    assert report["counts"]["errors"] == 0, report


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    try:
        for test in tests:
            test()
        suffix = "" if godot_available() else " (godot-dependent tests skipped)"
        print(f"All {len(tests)} silent-failure tests passed{suffix}.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()
