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
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"


def main() -> None:
    test_scene_batch_workflow()
    test_existing_scene_configuration()
    test_hierarchy_operations()
    test_signal_idempotency_and_disconnect()
    print("All scene operation tests passed.")


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


def copy_fixture_project() -> Path:
    temp_root = Path(tempfile.mkdtemp(prefix="godot-skill-test-"))
    project_path = temp_root / "project"
    shutil.copytree(FIXTURE_ROOT, project_path)
    return project_path


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
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"Inspector did not emit JSON.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")


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
