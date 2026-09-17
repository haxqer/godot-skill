#!/usr/bin/env python3
"""Integration tests for script-backed custom resources: the `__script` typed
JSON value, resource_batch's `script` parameter, and the script fields
inspect_resource reports for a `class_name X extends Resource` .tres."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
DISPATCHER = REPO_ROOT / "skill/godot/scripts/core/dispatcher.gd"

ITEM_DATA_GD = """class_name ItemData
extends Resource

@export var display_name: String = ""
@export var price: int = 0
@export var icon: Texture2D
@export var tags: Array[String] = []
@export var stats: Dictionary = {}
"""

PICKUP_GD = """extends Node2D

@export var item: ItemData
"""

ENEMY_BRAIN_GD = """class_name EnemyBrain
extends Node2D

@export var speed: float = 1.0
"""


def main() -> None:
    if shutil.which("godot") is None:
        print("SKIP test_script_resources (no godot on PATH)")
        return
    test_resource_batch_creates_script_backed_tres()
    test_inspect_resource_reports_script_class_and_properties()
    test_inline_script_value_on_a_scene_node()
    test_unknown_export_property_lists_the_valid_names()
    test_node_script_is_rejected_by_base_class()
    test_script_and_resource_type_together_is_rejected()
    test_duplicate_from_keeps_the_script()
    print("All script resource tests passed.")


def test_resource_batch_creates_script_backed_tres() -> None:
    """create_if_missing + script builds an instance of a project class the
    ClassDB-based resource_type can never reach, and ResourceSaver writes the
    same header the editor does."""
    with fixture_project() as project:
        report = dispatch(project, "resource_batch", {
            "resource_path": "items/sword.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {
                "display_name": "Sword",
                "price": 100,
                "tags": ["melee", "sharp"],
                "stats": {
                    "material": {"__resource_type": "StandardMaterial3D", "properties": {
                        "albedo_color": {"__type": "Color", "r": 1, "g": 0, "b": 0, "a": 1}}},
                    "ramp": {"__gradient": {"points": [
                        {"offset": 0, "color": {"__type": "Color", "r": 0, "g": 0, "b": 0, "a": 1}},
                        {"offset": 1, "color": {"__type": "Color", "r": 0, "g": 1, "b": 0, "a": 1}}]}},
                },
            }}],
        })
        assert report["script_class"] == "ItemData", report
        assert report["script_path"] == "res://items/item_data.gd", report

        sword = read(project, "items/sword.tres")
        # The header the editor writes for a custom resource: the engine base in
        # `type`, the script's class_name in `script_class`.
        assert sword.startswith('[gd_resource type="Resource" script_class="ItemData" format=3]'), sword
        assert '[ext_resource type="Script" path="res://items/item_data.gd"' in sword, sword
        assert "script = ExtResource(" in sword, sword
        assert 'display_name = "Sword"' in sword, sword
        assert "price = 100" in sword, sword
        # An untyped JSON array must land in the Array[String] export instead of
        # being dropped, which is what a bare Object.set() would do.
        assert 'tags = Array[String](["melee", "sharp"])' in sword, sword
        assert '[sub_resource type="StandardMaterial3D"' in sword, sword
        assert '[sub_resource type="Gradient"' in sword, sword
        assert '"material": SubResource(' in sword, sword


def test_inspect_resource_reports_script_class_and_properties() -> None:
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "items/sword.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {
                "display_name": "Sword", "price": 100, "tags": ["melee"]}}],
        })
        report = dispatch(project, "inspect_resource", {"resource_path": "items/sword.tres"})
        assert report["resource_type"] == "Resource", report
        assert report["script_class"] == "ItemData", report
        assert report["script_path"] == "res://items/item_data.gd", report
        assert report["script_properties"] == [
            "display_name", "price", "icon", "tags", "stats"], report
        # The script exports are part of the ordinary property listing too.
        assert report["properties"]["display_name"] == "Sword", report["properties"]
        assert report["properties"]["price"] == 100, report["properties"]
        assert report["properties"]["tags"] == ["melee"], report["properties"]


def test_inline_script_value_on_a_scene_node() -> None:
    """An inline __script value builds a sub-resource inside a .tscn, so a node
    export typed as a custom resource can be filled in one scene_batch."""
    with fixture_project() as project:
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/pickup.tscn",
            "create_if_missing": True,
            "root_node_type": "Node2D",
            "root_node_name": "Pickup",
            "actions": [{
                "type": "attach_script",
                "node_path": "root",
                "script_path": "items/pickup.gd",
                "script_properties": {"item": {
                    "__script": "res://items/item_data.gd",
                    "properties": {"display_name": "Potion", "price": 25, "tags": ["consumable"]},
                }},
            }],
        })
        pickup = read(project, "scenes/pickup.tscn")
        assert '[ext_resource type="Script" path="res://items/item_data.gd"' in pickup, pickup
        assert '[sub_resource type="Resource"' in pickup, pickup
        assert "script = ExtResource(" in pickup, pickup
        assert 'display_name = "Potion"' in pickup, pickup
        assert 'tags = Array[String](["consumable"])' in pickup, pickup
        assert "item = SubResource(" in pickup, pickup


def test_unknown_export_property_lists_the_valid_names() -> None:
    """A misspelled export must fail loudly and name what the script accepts."""
    with fixture_project() as project:
        result = dispatch_raw(project, "resource_batch", {
            "resource_path": "items/broken.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {"displayname": "Sword"}}],
        }, expected_returncode=1)
        assert "displayname" in result.stderr, result.stderr
        assert "did you mean display_name" in result.stderr, result.stderr
        assert "ItemData script properties:" in result.stderr, result.stderr
        for name in ("display_name", "price", "icon", "tags", "stats"):
            assert name in result.stderr, result.stderr
        assert not (project / "items/broken.tres").exists()


def test_node_script_is_rejected_by_base_class() -> None:
    """Pointing a resource at a Node script must name the real base class."""
    with fixture_project() as project:
        result = dispatch_raw(project, "resource_batch", {
            "resource_path": "items/brain.tres",
            "create_if_missing": True,
            "script": "res://items/enemy_brain.gd",
            "actions": [],
        }, expected_returncode=1)
        assert "extends Node2D" in result.stderr, result.stderr
        assert "attach_script" in result.stderr, result.stderr
        assert not (project / "items/brain.tres").exists()

        # Same guard for the inline typed value.
        inline = dispatch_raw(project, "resource_batch", {
            "resource_path": "items/holder.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {
                "stats": {"brain": {"__script": "res://items/enemy_brain.gd"}}}}],
        }, expected_returncode=1)
        assert "extends Node2D" in inline.stderr, inline.stderr

        # And a script path that does not exist yet.
        missing = dispatch_raw(project, "resource_batch", {
            "resource_path": "items/missing.tres",
            "create_if_missing": True,
            "script": "res://items/nope.gd",
            "actions": [],
        }, expected_returncode=1)
        assert "script not found" in missing.stderr, missing.stderr


def test_script_and_resource_type_together_is_rejected() -> None:
    with fixture_project() as project:
        result = dispatch_raw(project, "resource_batch", {
            "resource_path": "items/conflict.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {
                "stats": {"nested": {
                    "__script": "res://items/item_data.gd",
                    "__resource_type": "Gradient",
                }}}}],
        }, expected_returncode=1)
        assert "both __script and __resource_type" in result.stderr, result.stderr

        # On resource_batch itself the script wins and the contradiction is reported.
        report = dispatch(project, "resource_batch", {
            "resource_path": "items/override.tres",
            "create_if_missing": True,
            "resource_type": "Gradient",
            "script": "res://items/item_data.gd",
            "actions": [],
        })
        assert report["script_class"] == "ItemData", report


def test_duplicate_from_keeps_the_script() -> None:
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "items/sword.tres",
            "create_if_missing": True,
            "script": "res://items/item_data.gd",
            "actions": [{"type": "set_properties", "properties": {
                "display_name": "Sword", "price": 100, "tags": ["melee"]}}],
        })
        report = dispatch(project, "resource_batch", {
            "resource_path": "items/great_sword.tres",
            "duplicate_from": "items/sword.tres",
            "actions": [{"type": "set_properties", "properties": {"display_name": "Great Sword", "price": 250}}],
        })
        assert report["script_class"] == "ItemData", report
        copy = read(project, "items/great_sword.tres")
        assert copy.startswith('[gd_resource type="Resource" script_class="ItemData" format=3]'), copy
        assert '[ext_resource type="Script" path="res://items/item_data.gd"' in copy, copy
        assert "script = ExtResource(" in copy, copy
        assert 'display_name = "Great Sword"' in copy, copy
        assert "price = 250" in copy, copy
        assert 'tags = Array[String](["melee"])' in copy, copy


# --- helpers ---------------------------------------------------------------

class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-scriptres-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        items = self.project / "items"
        items.mkdir(parents=True, exist_ok=True)
        (items / "item_data.gd").write_text(ITEM_DATA_GD, encoding="utf-8")
        (items / "pickup.gd").write_text(PICKUP_GD, encoding="utf-8")
        (items / "enemy_brain.gd").write_text(ENEMY_BRAIN_GD, encoding="utf-8")
        # Without an import pass the project has no global class cache, so
        # `@export var item: ItemData` does not resolve and pickup.gd fails to
        # compile.
        import_assets(self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def read(project: Path, rel: str) -> str:
    return (project / rel).read_text(encoding="utf-8")


def import_assets(project: Path) -> None:
    subprocess.run(["godot", "--headless", "--path", str(project), "--import"],
                   capture_output=True, text=True, check=False, timeout=180)


def dispatch(project: Path, operation: str, params: dict) -> dict:
    result = dispatch_raw(project, operation, params)
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"No JSON payload for {operation}.\n{result.stdout}\n{result.stderr}")


def dispatch_raw(project: Path, operation: str, params: dict,
                 expected_returncode: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["godot", "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=180,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}."
            f"\n{result.stdout}\n{result.stderr}")
    return result


if __name__ == "__main__":
    main()
