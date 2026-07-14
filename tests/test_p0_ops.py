#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
DISPATCHER = REPO_ROOT / "skill/godot/scripts/core/dispatcher.gd"
PROBE = REPO_ROOT / "skill/godot/scripts/debug/probe_environment.py"
VALIDATOR = REPO_ROOT / "skill/godot/scripts/debug/validate_project.py"
IMPORTER = REPO_ROOT / "skill/godot/scripts/import/import_project.py"


def main() -> None:
    test_inspection_operations()
    test_resource_batch_is_transactional()
    test_resource_batch_call_method()
    test_project_batch_and_import_audit()
    test_project_batch_removals_are_idempotent()
    test_probe_import_wrapper_and_comprehensive_validation()
    print("All P0 operation tests passed.")


def test_inspection_operations() -> None:
    with fixture_project() as project:
        inspected = dispatch(project, "inspect_project", {})
        assert inspected["engine"]["version"]["major"] == 4
        assert inspected["input_actions"] == {}
        assert inspected["files"]["extension_counts"]["tscn"] == 3

        scene = dispatch(project, "inspect_scene", {"scene_path": "scenes/existing_ui.tscn"})
        assert scene["node_count"] == 3
        assert scene["nodes"][0]["path"] == "."

        resource = dispatch(project, "inspect_resource", {"resource_path": "theme/panel_style.tres"})
        assert resource["resource_type"] == "StyleBoxFlat"
        assert resource["property_schema"] == []
        with_schema = dispatch(
            project,
            "inspect_resource",
            {"resource_path": "theme/panel_style.tres", "include_schema": True},
        )
        assert with_schema["property_schema"]


def test_resource_batch_is_transactional() -> None:
    with fixture_project() as project:
        created = dispatch(
            project,
            "resource_batch",
            {
                "resource_path": "generated/style.tres",
                "create_if_missing": True,
                "resource_type": "StyleBoxFlat",
                "actions": [
                    {"type": "set_resource_name", "resource_name": "GeneratedStyle"},
                    {
                        "type": "set_properties",
                        "properties": {
                            "bg_color": {"__type": "Color", "r": 0.1, "g": 0.2, "b": 0.3, "a": 1},
                            "corner_radius_top_left": 6,
                        },
                    },
                    {"type": "set_metadata", "metadata": {"source": "test"}},
                ],
            },
        )
        assert created["ok"] is True
        inspected = dispatch(project, "inspect_resource", {"resource_path": "generated/style.tres"})
        assert inspected["resource_name"] == "GeneratedStyle"
        assert inspected["properties"]["corner_radius_top_left"] == 6

        dispatch_raw(
            project,
            "resource_batch",
            {
                "resource_path": "generated/should_not_exist.tres",
                "create_if_missing": True,
                "resource_type": "StyleBoxFlat",
                "actions": [{"type": "set_properties", "properties": {"missing_property": 1}}],
            },
            expected_returncode=1,
        )
        assert not (project / "generated/should_not_exist.tres").exists()


def test_resource_batch_call_method() -> None:
    with fixture_project() as project:
        created = dispatch(
            project,
            "resource_batch",
            {
                "resource_path": "generated/ramp.tres",
                "create_if_missing": True,
                "resource_type": "Gradient",
                "actions": [
                    {
                        "type": "call_method",
                        "method": "add_point",
                        "args": [0.5, {"__type": "Color", "r": 1, "g": 0, "b": 0, "a": 1}],
                    }
                ],
            },
        )
        assert created["ok"] is True
        inspected = dispatch(project, "inspect_resource", {"resource_path": "generated/ramp.tres"})
        assert len(inspected["properties"]["offsets"]["values"]) == 3

        dispatch_raw(
            project,
            "resource_batch",
            {
                "resource_path": "generated/never.tres",
                "create_if_missing": True,
                "resource_type": "Gradient",
                "actions": [{"type": "call_method", "method": "no_such_method", "args": []}],
            },
            expected_returncode=1,
        )
        assert not (project / "generated/never.tres").exists()


def test_project_batch_removals_are_idempotent() -> None:
    with fixture_project() as project:
        removed = dispatch_raw(
            project,
            "project_batch",
            {
                "actions": [
                    {"type": "remove_input_action", "action_name": "never_defined"},
                    {"type": "remove_autoload", "autoload_name": "NeverDefined"},
                    {"type": "clear_setting", "name": "application/config/never_defined"},
                ]
            },
        )
        assert "ERROR" not in removed.stderr, removed.stderr
        payload = json.loads(
            next(
                line
                for line in reversed(removed.stdout.splitlines())
                if line.strip().startswith("{") and line.strip().endswith("}")
            )
        )
        assert payload["ok"] is True


def test_project_batch_and_import_audit() -> None:
    with fixture_project() as project:
        changed = dispatch(
            project,
            "project_batch",
            {
                "actions": [
                    {"type": "add_input_action", "action_name": "jump", "deadzone": 0.25},
                    {
                        "type": "add_input_event",
                        "action_name": "jump",
                        "event": {
                            "__resource_type": "InputEventKey",
                            "properties": {"physical_keycode": 32},
                        },
                    },
                    {
                        "type": "add_autoload",
                        "autoload_name": "Status",
                        "path": "scripts/status_controller.gd",
                    },
                    {"type": "set_layer_name", "layer_type": "2d_physics", "layer": 1, "layer_name": "Player"},
                    {"type": "set_main_scene", "scene_path": "scenes/existing_ui.tscn"},
                    {"type": "set_setting", "name": "application/config/version", "value": "1.0.0"},
                ]
            },
        )
        assert changed["actions_applied"] == 6
        inspected = dispatch(project, "inspect_project", {})
        assert set(inspected["input_actions"]) == {"jump"}
        assert len(inspected["input_actions"]["jump"]["events"]) == 1
        assert inspected["autoloads"]["Status"] == "*res://scripts/status_controller.gd"

        clean = dispatch(project, "audit_imports", {})
        assert clean["ok"] is True
        orphan = project / "missing.png.import"
        orphan.write_text("[remap]\nimporter=\"image\"\n", encoding="utf-8")
        audited = dispatch(project, "audit_imports", {})
        assert audited["ok"] is False
        assert audited["counts"]["orphaned"] == 1


def test_probe_import_wrapper_and_comprehensive_validation() -> None:
    with fixture_project() as project:
        probe = run_json(["python3", str(PROBE), str(project)])
        assert probe["ok"] is True
        assert probe["engine"]["capabilities"]["export_patch"] is True

        imported = run_json(["python3", str(IMPORTER), str(project), "--audit-only"])
        assert imported["ok"] is True

        valid = run_json(["python3", str(VALIDATOR), str(project)])
        assert valid["ok"] is True
        assert valid["static"]["failed_count"] == 0

        plugin_dir = project / "addons/broken"
        plugin_dir.mkdir(parents=True)
        (plugin_dir / "plugin.cfg").write_text(
            '[plugin]\nname="Broken"\nscript="plugin.gd"\n',
            encoding="utf-8",
        )
        (plugin_dir / "plugin.gd").write_text("extends Node\n", encoding="utf-8")
        native_dir = project / "native"
        native_dir.mkdir()
        (native_dir / "broken.gdextension").write_text(
            '[configuration]\nentry_symbol="missing"\n\n[libraries]\nmacos.debug.arm64="res://native/missing.dylib"\n',
            encoding="utf-8",
        )
        invalid = run_json(["python3", str(VALIDATOR), str(project)], expected_returncode=1)
        failed_kinds = {failure["kind"] for failure in invalid["static"]["failed"]}
        assert {"extension", "plugin"}.issubset(failed_kinds)


class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-p0-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def dispatch(project: Path, operation: str, params: dict) -> dict:
    result = dispatch_raw(project, operation, params)
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"No JSON payload for {operation}.\n{result.stdout}\n{result.stderr}")


def dispatch_raw(project: Path, operation: str, params: dict, expected_returncode: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [
            "godot",
            "--headless",
            "--path",
            str(project),
            "--script",
            str(DISPATCHER),
            operation,
            json.dumps(params, separators=(",", ":")),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}.\n{result.stdout}\n{result.stderr}"
        )
    return result


def run_json(command: list[str], expected_returncode: int = 0) -> dict:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"Command returned {result.returncode}, expected {expected_returncode}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return json.loads(result.stdout)


if __name__ == "__main__":
    main()
