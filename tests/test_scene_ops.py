#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DISPATCHER = REPO_ROOT / "skill/godot/scripts/core/dispatcher.gd"
INSPECTOR = REPO_ROOT / "tests/scripts/inspect_scene.gd"
MESH_LIBRARY_INSPECTOR = REPO_ROOT / "tests/scripts/inspect_mesh_library.gd"
ASSET_PREPARER = REPO_ROOT / "tests/scripts/prepare_test_assets.gd"
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
TEMP_ROOTS: list[Path] = []


def main() -> None:
    try:
        test_scene_batch_workflow()
        test_existing_scene_configuration()
        test_hierarchy_operations()
        test_signal_idempotency_and_disconnect()
        test_save_scene_copy()
        test_save_scene_legacy_new_path_alias()
        test_load_sprite_with_generated_texture()
        test_export_mesh_library_from_generated_scene()
        test_get_uid_reads_existing_sidecar()
        test_get_uid_reports_missing_sidecar_cleanly()
        test_resave_resources_reports_actual_sidecar_results()
        print("All scene operation tests passed.")
    finally:
        cleanup_temp_roots()


def test_scene_batch_workflow() -> None:
    project_path = copy_fixture_project()
    run_dispatcher(
        project_path,
        "scene_batch",
        {
            "scene_path": "scenes/menu.tscn",
            "create_if_missing": True,
            "root_node_type": "Control",
            "root_node_name": "Menu",
            "actions": [
                {
                    "type": "add_node",
                    "parent_node_path": "root",
                    "node_type": "PanelContainer",
                    "node_name": "Panel",
                },
                {
                    "type": "configure_control",
                    "node_path": "root/Panel",
                    "layout_preset": "FULL_RECT",
                    "theme_overrides": {
                        "styleboxes": {
                            "panel": {"__resource": "res://theme/panel_style.tres"}
                        }
                    },
                },
                {
                    "type": "add_node",
                    "parent_node_path": "root/Panel",
                    "node_type": "VBoxContainer",
                    "node_name": "MenuVBox",
                },
                {
                    "type": "add_node",
                    "parent_node_path": "root/Panel/MenuVBox",
                    "node_type": "Label",
                    "node_name": "Title",
                    "properties": {"text": "Main Menu"},
                },
                {
                    "type": "add_node",
                    "parent_node_path": "root/Panel/MenuVBox",
                    "node_type": "Button",
                    "node_name": "StartButton",
                    "properties": {"text": "Start"},
                },
                {
                    "type": "configure_control",
                    "node_path": "root/Panel/MenuVBox/StartButton",
                    "size_flags_horizontal": "EXPAND_FILL",
                    "custom_minimum_size": {"__type": "Vector2", "x": 240, "y": 64},
                    "theme_overrides": {
                        "colors": {
                            "font_color": {"__type": "Color", "r": 1, "g": 0.25, "b": 0.25, "a": 1}
                        },
                        "constants": {"outline_size": 2},
                    },
                },
                {
                    "type": "attach_script",
                    "node_path": "root",
                    "script_path": "scripts/menu_controller.gd",
                    "script_properties": {
                        "menu_title": "Main Menu",
                        "click_count": 3,
                    },
                },
                {
                    "type": "connect_signal",
                    "node_path": "root/Panel/MenuVBox/StartButton",
                    "signal_name": "pressed",
                    "target_node_path": "root",
                    "method_name": "_on_start_pressed",
                    "binds": ["clicked"],
                },
            ],
        },
    )
    snapshot = inspect_scene(project_path, "scenes/menu.tscn")

    root = snapshot["nodes"]["root"]
    panel = snapshot["nodes"]["root/Panel"]
    button = snapshot["nodes"]["root/Panel/MenuVBox/StartButton"]
    title = snapshot["nodes"]["root/Panel/MenuVBox/Title"]

    assert root["script_path"] == "res://scripts/menu_controller.gd"
    assert root["menu_title"] == "Main Menu"
    assert root["click_count"] == 3
    assert title["text"] == "Main Menu"
    assert panel["theme_styleboxes"]["panel"] == "res://theme/panel_style.tres"
    assert button["text"] == "Start"
    assert button["size_flags_horizontal"] == 3
    assert button["custom_minimum_size"] == {"x": 240.0, "y": 64.0}
    assert_color_close(
        button["theme_colors"]["font_color"],
        {"r": 1.0, "g": 0.25, "b": 0.25, "a": 1.0},
    )
    assert button["theme_constants"]["outline_size"] == 2

    pressed_connections = [
        connection
        for connection in snapshot["connections"]
        if connection["source_path"] == "root/Panel/MenuVBox/StartButton" and connection["signal"] == "pressed"
    ]
    assert len(pressed_connections) == 1
    assert pressed_connections[0]["target_path"] == "root"
    assert pressed_connections[0]["method"] == "_on_start_pressed"
    assert pressed_connections[0]["flags"] & 2 == 2
    assert pressed_connections[0]["binds"] == ["clicked"]


def test_existing_scene_configuration() -> None:
    project_path = copy_fixture_project()
    run_dispatcher(
        project_path,
        "configure_node",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "node_path": "root/StatusLabel",
            "properties": {"text": "Ready"},
            "groups_add": ["status_text"],
            "metadata": {"purpose": "primary"},
        },
    )
    run_dispatcher(
        project_path,
        "configure_control",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "node_path": "root/StatusLabel",
            "custom_minimum_size": {"__type": "Vector2", "x": 120, "y": 24},
            "theme_overrides": {
                "colors": {
                    "font_color": {"__type": "Color", "r": 0.2, "g": 0.8, "b": 0.4, "a": 1}
                }
            },
        },
    )
    run_dispatcher(
        project_path,
        "attach_script",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "node_path": "root",
            "script_path": "scripts/status_controller.gd",
            "script_properties": {"screen_id": "status"},
        },
    )

    snapshot = inspect_scene(project_path, "scenes/existing_ui.tscn")
    root = snapshot["nodes"]["root"]
    label = snapshot["nodes"]["root/StatusLabel"]
    cancel_button = snapshot["nodes"]["root/CancelButton"]

    assert root["script_path"] == "res://scripts/status_controller.gd"
    assert root["screen_id"] == "status"
    assert label["text"] == "Ready"
    assert label["groups"] == ["status_text"]
    assert label["metadata"] == {"purpose": "primary"}
    assert label["custom_minimum_size"] == {"x": 120.0, "y": 24.0}
    assert_color_close(
        label["theme_colors"]["font_color"],
        {"r": 0.2, "g": 0.8, "b": 0.4, "a": 1.0},
    )
    assert cancel_button["text"] == "Cancel"


def test_hierarchy_operations() -> None:
    project_path = copy_fixture_project()
    run_dispatcher(
        project_path,
        "instantiate_scene",
        {
            "scene_path": "scenes/hierarchy.tscn",
            "parent_node_path": "root/Container",
            "instance_scene_path": "scenes/card.tscn",
            "node_name": "CardA",
        },
    )
    run_dispatcher(
        project_path,
        "reparent_node",
        {
            "scene_path": "scenes/hierarchy.tscn",
            "node_path": "root/Standalone",
            "new_parent_node_path": "root/Container",
            "keep_global_transform": False,
            "index": 0,
        },
    )
    run_dispatcher(
        project_path,
        "reorder_node",
        {
            "scene_path": "scenes/hierarchy.tscn",
            "node_path": "root/Container/CardA",
            "index": 0,
        },
    )
    run_dispatcher(
        project_path,
        "remove_node",
        {
            "scene_path": "scenes/hierarchy.tscn",
            "node_path": "root/RemoveMe",
        },
    )

    snapshot = inspect_scene(project_path, "scenes/hierarchy.tscn")
    assert snapshot["order"]["root"] == ["root/Container"]
    assert snapshot["order"]["root/Container"] == [
        "root/Container/CardA",
        "root/Container/Standalone",
    ]
    assert "root/RemoveMe" not in snapshot["nodes"]
    assert snapshot["nodes"]["root/Container/CardA"]["type"] == "Node"


def test_signal_idempotency_and_disconnect() -> None:
    project_path = copy_fixture_project()
    params = {
        "scene_path": "scenes/existing_ui.tscn",
        "node_path": "root/CancelButton",
        "signal_name": "pressed",
        "target_node_path": "root",
        "method_name": "_on_cancel_pressed",
    }

    run_dispatcher(
        project_path,
        "attach_script",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "node_path": "root",
            "script_path": "scripts/status_controller.gd",
            "script_properties": {"screen_id": "before"},
        },
    )
    run_dispatcher(project_path, "connect_signal", params)
    run_dispatcher(project_path, "connect_signal", params)

    snapshot = inspect_scene(project_path, "scenes/existing_ui.tscn")
    pressed_connections = [
        connection
        for connection in snapshot["connections"]
        if connection["source_path"] == "root/CancelButton" and connection["signal"] == "pressed"
    ]
    assert len(pressed_connections) == 1
    assert pressed_connections[0]["target_path"] == "root"
    assert pressed_connections[0]["method"] == "_on_cancel_pressed"

    run_dispatcher(project_path, "disconnect_signal", params)
    snapshot = inspect_scene(project_path, "scenes/existing_ui.tscn")
    pressed_connections = [
        connection
        for connection in snapshot["connections"]
        if connection["source_path"] == "root/CancelButton" and connection["signal"] == "pressed"
    ]
    assert pressed_connections == []


def test_save_scene_copy() -> None:
    project_path = copy_fixture_project()
    run_dispatcher(
        project_path,
        "save_scene",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "save_path": "scenes/copied_ui.tscn",
        },
    )

    original = inspect_scene(project_path, "scenes/existing_ui.tscn")
    copied = inspect_scene(project_path, "scenes/copied_ui.tscn")

    assert (project_path / "scenes/copied_ui.tscn").is_file()
    assert original["nodes"]["root/StatusLabel"]["text"] == "Pending"
    assert copied["nodes"]["root/StatusLabel"]["text"] == "Pending"
    assert copied["nodes"]["root/CancelButton"]["text"] == "Cancel"


def test_save_scene_legacy_new_path_alias() -> None:
    project_path = copy_fixture_project()
    run_dispatcher(
        project_path,
        "save_scene",
        {
            "scene_path": "scenes/existing_ui.tscn",
            "new_path": "scenes/copied_ui_legacy.tscn",
        },
    )

    assert (project_path / "scenes/copied_ui_legacy.tscn").is_file()


def test_load_sprite_with_generated_texture() -> None:
    project_path = copy_fixture_project()
    prepare_test_assets(
        project_path,
        {
            "action": "create_sprite_fixture",
            "scene_path": "scenes/sprite_scene.tscn",
            "texture_path": "textures/test_gradient.tres",
        },
    )
    run_dispatcher(
        project_path,
        "load_sprite",
        {
            "scene_path": "scenes/sprite_scene.tscn",
            "node_path": "root",
            "texture_path": "textures/test_gradient.tres",
        },
    )

    snapshot = inspect_scene(project_path, "scenes/sprite_scene.tscn")
    root = snapshot["nodes"]["root"]
    assert root["type"] == "Sprite2D"
    assert root["texture_path"] == "res://textures/test_gradient.tres"


def test_export_mesh_library_from_generated_scene() -> None:
    project_path = copy_fixture_project()
    prepare_test_assets(
        project_path,
        {
            "action": "create_mesh_fixture",
            "scene_path": "scenes/mesh_source.tscn",
        },
    )
    run_dispatcher(
        project_path,
        "export_mesh_library",
        {
            "scene_path": "scenes/mesh_source.tscn",
            "output_path": "libraries/test_mesh_library.tres",
        },
    )

    payload = inspect_mesh_library(project_path, "libraries/test_mesh_library.tres")
    assert payload["count"] == 1
    assert payload["items"][0]["name"] == "Crate"
    assert payload["items"][0]["has_mesh"] is True
    assert payload["items"][0]["shape_count"] >= 1


def test_get_uid_reads_existing_sidecar() -> None:
    project_path = copy_fixture_project()
    uid_path = project_path / "scripts/menu_controller.gd.uid"
    uid_path.write_text("uid://menu-controller-test\n", encoding="utf-8")

    payload = get_uid(project_path, "scripts/menu_controller.gd")
    assert payload["exists"] is True
    assert payload["file"] == "res://scripts/menu_controller.gd"
    assert payload["uidPath"] == "res://scripts/menu_controller.gd.uid"
    assert payload["uid"] == "uid://menu-controller-test"
    assert payload["absolutePath"] == str((project_path / "scripts/menu_controller.gd").resolve())
    assert payload["absoluteUidPath"] == str(uid_path.resolve())


def test_get_uid_reports_missing_sidecar_cleanly() -> None:
    project_path = copy_fixture_project()

    payload = get_uid(project_path, "scripts/menu_controller.gd")
    assert payload["exists"] is False
    assert payload["uid"] == ""
    assert payload["uidPath"] == "res://scripts/menu_controller.gd.uid"
    assert "attempt regeneration" in payload["message"]
    assert ".uid files" in payload["message"]


def test_resave_resources_reports_actual_sidecar_results() -> None:
    project_path = copy_fixture_project()
    candidate_paths = sorted(project_path.joinpath("scripts").glob("*.gd"))
    before_sidecars = {
        str(Path(str(path) + ".uid").resolve())
        for path in candidate_paths
        if Path(str(path) + ".uid").is_file()
    }
    before_missing_count = sum(
        1 for path in candidate_paths if not Path(str(path) + ".uid").is_file()
    )

    result = run_dispatcher(
        project_path,
        "resave_resources",
        {
            "project_path": "scripts",
        },
    )
    combined = f"{result.stdout}\n{result.stderr}"
    assert "Resave operation complete." in combined
    payload = extract_json_payload(result.stdout)

    after_sidecars = {
        str(Path(str(path) + ".uid").resolve())
        for path in candidate_paths
        if Path(str(path) + ".uid").is_file()
    }
    created_sidecars = after_sidecars - before_sidecars
    after_missing_count = sum(
        1 for path in candidate_paths if not Path(str(path) + ".uid").is_file()
    )

    assert payload["project_path"] == "res://scripts/"
    assert payload["resources_missing_uid_before"] == before_missing_count
    assert payload["uid_regeneration_attempts"] == before_missing_count
    assert payload["uid_sidecars_created"] == len(created_sidecars)
    assert payload["resources_still_missing_uid"] == after_missing_count


def copy_fixture_project() -> Path:
    temp_root = Path(tempfile.mkdtemp(prefix="godot-skill-test-"))
    TEMP_ROOTS.append(temp_root)
    project_path = temp_root / "project"
    shutil.copytree(FIXTURE_ROOT, project_path)
    return project_path


def cleanup_temp_roots() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def run_dispatcher(project_path: Path, operation: str, params: dict) -> subprocess.CompletedProcess[str]:
    return run_godot_command(
        [
            "godot",
            "--headless",
            "--path",
            str(project_path),
            "--script",
            str(DISPATCHER),
            operation,
            json.dumps(params, separators=(",", ":")),
        ]
    )


def prepare_test_assets(project_path: Path, params: dict) -> dict:
    result = run_godot_command(
        [
            "godot",
            "--headless",
            "--path",
            str(project_path),
            "--script",
            str(ASSET_PREPARER),
            json.dumps(params, separators=(",", ":")),
        ]
    )
    return extract_json_payload(result.stdout)


def inspect_scene(project_path: Path, scene_path: str) -> dict:
    result = run_godot_command(
        [
            "godot",
            "--headless",
            "--path",
            str(project_path),
            "--script",
            str(INSPECTOR),
            json.dumps({"scene_path": scene_path}, separators=(",", ":")),
        ]
    )
    return extract_json_payload(result.stdout)


def inspect_mesh_library(project_path: Path, resource_path: str) -> dict:
    result = run_godot_command(
        [
            "godot",
            "--headless",
            "--path",
            str(project_path),
            "--script",
            str(MESH_LIBRARY_INSPECTOR),
            json.dumps({"resource_path": resource_path}, separators=(",", ":")),
        ]
    )
    return extract_json_payload(result.stdout)


def get_uid(project_path: Path, file_path: str) -> dict:
    result = run_dispatcher(
        project_path,
        "get_uid",
        {
            "file_path": file_path,
        },
    )
    return extract_json_payload(result.stdout)


def extract_json_payload(output: str) -> dict:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"Expected JSON payload.\nOUTPUT:\n{output}")


def run_godot_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    combined = f"{result.stdout}\n{result.stderr}"
    if "ObjectDB instances leaked" in combined or "RID of type" in combined:
        raise AssertionError(f"Godot leak warning detected.\nCommand: {' '.join(command)}\nOutput:\n{combined}")
    if result.returncode != 0:
        raise AssertionError(f"Godot command failed ({result.returncode}).\nCommand: {' '.join(command)}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
    return result


def assert_color_close(actual: dict, expected: dict, tolerance: float = 1e-6) -> None:
    for channel, expected_value in expected.items():
        actual_value = actual[channel]
        if not math.isclose(actual_value, expected_value, rel_tol=tolerance, abs_tol=tolerance):
            raise AssertionError(f"Color channel {channel} mismatch: expected {expected_value}, got {actual_value}")


if __name__ == "__main__":
    main()
