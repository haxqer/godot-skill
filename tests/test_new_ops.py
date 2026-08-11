#!/usr/bin/env python3
"""Integration tests for the roadmap ops added on top of the content set:
codec method_calls/__curve/__gradient, paint_gridmap, bake_collision,
collision_from_sprite, bake_csg, bake_navmesh (2D+3D), build_theme, gltf_export,
project_batch shader_globals, and build_replication_config."""
from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
DISPATCHER = REPO_ROOT / "skill/godot/scripts/core/dispatcher.gd"


def main() -> None:
    test_codec_method_calls_and_curve()
    test_paint_gridmap()
    test_bake_collision_serializes_children()
    test_collision_from_sprite()
    test_bake_csg_mesh_and_replace()
    test_bake_navmesh_2d_and_3d()
    test_build_theme()
    test_gltf_export()
    test_shader_globals()
    test_build_replication_config()
    test_broken_op_exits_nonzero()
    test_input_guards()
    print("All new operation tests passed.")


def test_codec_method_calls_and_curve() -> None:
    """Inline __resource_type can now run ordered builder calls, and __curve /
    __gradient sugar inline builder-only resources."""
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "res/ramp.tres", "create_if_missing": True, "resource_type": "CurveTexture",
            "actions": [{"type": "set_properties", "properties": {
                "curve": {"__curve": {"min_value": 0, "max_value": 1, "points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]}}}}],
        })
        ramp = read(project, "res/ramp.tres")
        assert "point_count = 2" in ramp, ramp

        dispatch(project, "resource_batch", {
            "resource_path": "res/grad.tres", "create_if_missing": True, "resource_type": "GradientTexture1D",
            "actions": [{"type": "set_properties", "properties": {
                "gradient": {"__gradient": {"points": [
                    {"offset": 0, "color": {"__type": "Color", "r": 1, "g": 0, "b": 0, "a": 1}},
                    {"offset": 1, "color": {"__type": "Color", "r": 0, "g": 0, "b": 1, "a": 1}}]}}}}],
        })
        grad = read(project, "res/grad.tres")
        # Offsets [0, 1] equal Gradient's default and are omitted by ResourceSaver;
        # the non-default colors are the reliable signal that the ramp was built.
        assert "colors = PackedColorArray(1, 0, 0, 1, 0, 0, 1, 1)" in grad, grad
        # A method_calls build on an inline sub-resource also works.
        dispatch(project, "resource_batch", {
            "resource_path": "res/grad2.tres", "create_if_missing": True, "resource_type": "GradientTexture1D",
            "actions": [{"type": "set_properties", "properties": {
                "gradient": {"__resource_type": "Gradient", "method_calls": [
                    {"method": "add_point", "args": [0.5, {"__type": "Color", "r": 0, "g": 1, "b": 0, "a": 1}]}]}}}],
        })


def test_paint_gridmap() -> None:
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "meshlib/tiles.meshlib", "create_if_missing": True, "resource_type": "MeshLibrary",
            "actions": [
                {"type": "call_method", "method": "create_item", "args": [0]},
                {"type": "call_method", "method": "set_item_name", "args": [0, "box"]},
                {"type": "call_method", "method": "set_item_mesh", "args": [0, {"__resource_type": "BoxMesh"}]},
            ],
        })
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/world.tscn", "create_if_missing": True, "root_node_type": "Node3D", "root_node_name": "World",
            "actions": [{"type": "add_node", "node_type": "GridMap", "node_name": "Grid"}],
        })
        dispatch(project, "paint_gridmap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid", "mesh_library": "meshlib/tiles.meshlib",
            "fills": [{"from": [0, 0, 0], "to": [2, 0, 2], "item": 0}],
            "cells": [{"pos": [1, 1, 1], "item": 0, "orient": 22}],
        })
        world = read(project, "scenes/world.tscn")
        assert "GridMap" in world and "mesh_library" in world, world
        # invalid item id is rejected
        dispatch_raw(project, "paint_gridmap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid", "cells": [{"pos": [0, 0, 0], "item": 99}]},
            expected_returncode=1)


def test_bake_collision_serializes_children() -> None:
    with fixture_project() as project:
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/crate.tscn", "create_if_missing": True, "root_node_type": "Node3D", "root_node_name": "Crate",
            "actions": [{"type": "add_node", "node_type": "MeshInstance3D", "node_name": "Mesh",
                         "properties": {"mesh": {"__resource_type": "BoxMesh"}}}],
        })
        dispatch(project, "bake_collision", {"scene_path": "scenes/crate.tscn", "node_path": "root/Mesh", "mode": "trimesh"})
        crate = read(project, "scenes/crate.tscn")
        assert 'type="StaticBody3D"' in crate and "ConcavePolygonShape3D" in crate, crate

        # Idempotent rerun (separate process): the marker must survive the .tscn
        # round-trip so a second bake replaces rather than stacks a duplicate body.
        dispatch(project, "bake_collision", {"scene_path": "scenes/crate.tscn", "node_path": "root/Mesh", "mode": "trimesh"})
        crate2 = read(project, "scenes/crate.tscn")
        assert crate2.count('type="StaticBody3D"') == 1, crate2

        # Switching mode replaces the concave body with a convex one (still one body).
        dispatch(project, "bake_collision", {
            "scene_path": "scenes/crate.tscn", "save_path": "scenes/crate_cvx.tscn", "node_path": "root/Mesh", "mode": "convex"})
        cvx = read(project, "scenes/crate_cvx.tscn")
        assert "ConvexPolygonShape3D" in cvx and "ConcavePolygonShape3D" not in cvx, cvx
        assert cvx.count('type="StaticBody3D"') == 1, cvx


def test_collision_from_sprite() -> None:
    with fixture_project() as project:
        write_opaque_png(project / "art/blob.png", 8, 8)
        import_assets(project)
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/blob.tscn", "create_if_missing": True, "root_node_type": "Node2D", "root_node_name": "Blob",
            "actions": [{"type": "add_node", "node_type": "Sprite2D", "node_name": "Spr",
                         "properties": {"texture": {"__resource": "res://art/blob.png"}}}],
        })
        dispatch(project, "collision_from_sprite", {
            "scene_path": "scenes/blob.tscn", "node_path": "root/Spr", "texture": "art/blob.png", "one_way": True})
        blob = read(project, "scenes/blob.tscn")
        assert "CollisionPolygon2D" in blob and "polygon = PackedVector2Array" in blob, blob
        # Idempotent rerun (separate process): one opaque island stays one collider.
        dispatch(project, "collision_from_sprite", {
            "scene_path": "scenes/blob.tscn", "node_path": "root/Spr", "texture": "art/blob.png", "one_way": True})
        assert read(project, "scenes/blob.tscn").count('type="CollisionPolygon2D"') == 1


def test_bake_csg_mesh_and_replace() -> None:
    with fixture_project() as project:
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/proto.tscn", "create_if_missing": True, "root_node_type": "Node3D", "root_node_name": "Proto",
            "actions": [
                {"type": "add_node", "node_type": "CSGCombiner3D", "node_name": "Level"},
                {"type": "add_node", "parent_node_path": "root/Level", "node_type": "CSGBox3D", "node_name": "A"},
                {"type": "add_node", "parent_node_path": "root/Level", "node_type": "CSGBox3D", "node_name": "B",
                 "properties": {"position": {"__type": "Vector3", "x": 1.5, "y": 0, "z": 0}}},
            ],
        })
        dispatch(project, "bake_csg", {"scene_path": "scenes/proto.tscn", "node_path": "root/Level", "out_mesh": "meshes/level.res"})
        assert (project / "meshes/level.res").exists()
        dispatch(project, "bake_csg", {
            "scene_path": "scenes/proto.tscn", "save_path": "scenes/proto_baked.tscn", "node_path": "root/Level",
            "bake_collision": True, "replace_with_meshinstance": True})
        baked = read(project, "scenes/proto_baked.tscn")
        assert "MeshInstance3D" in baked and "CSGCombiner3D" not in baked and "StaticBody3D" in baked, baked
        # No out_mesh and no replace = nothing to produce → rejected, not a silent ok.
        dispatch_raw(project, "bake_csg", {"scene_path": "scenes/proto.tscn", "node_path": "root/Level"}, expected_returncode=1)


def test_input_guards() -> None:
    """Malformed inputs must fail fast (exit 1), never hang or silently pass."""
    with fixture_project() as project:
        # Non-object JSON params would otherwise skip the typed deferred call and hang.
        dispatch_raw(project, "resource_batch", [], expected_returncode=1)
        # Gradient with mismatched offsets/colors lengths.
        dispatch_raw(project, "resource_batch", {
            "resource_path": "g.tres", "create_if_missing": True, "resource_type": "GradientTexture1D",
            "actions": [{"type": "set_properties", "properties": {
                "gradient": {"__gradient": {"offsets": [0, 0.5, 1], "colors": ["#fff", "#000"]}}}}]},
            expected_returncode=1)
        # Navmesh outline with fewer than 3 points.
        dispatch_raw(project, "resource_batch", {
            "resource_path": "n.tres", "create_if_missing": True, "resource_type": "NavigationPolygon",
            "actions": [{"type": "bake_navmesh", "traversable_outlines": [[[0, 0], [100, 0]]]}]},
            expected_returncode=1)


def test_bake_navmesh_2d_and_3d() -> None:
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "nav/level2d.tres", "create_if_missing": True, "resource_type": "NavigationPolygon",
            "actions": [
                {"type": "set_properties", "properties": {"agent_radius": 8.0, "cell_size": 1.0}},
                {"type": "bake_navmesh",
                 "traversable_outlines": [[[0, 0], [512, 0], [512, 512], [0, 512]]],
                 "obstruction_outlines": [[[200, 200], [300, 200], [300, 300], [200, 300]]]},
            ],
        })
        nav2d = read(project, "nav/level2d.tres")
        assert "vertices" in nav2d and "polygon" in nav2d, nav2d

        dispatch(project, "resource_batch", {
            "resource_path": "nav/level3d.tres", "create_if_missing": True, "resource_type": "NavigationMesh",
            "actions": [
                {"type": "set_properties", "properties": {"agent_radius": 0.5, "agent_height": 1.8, "cell_size": 0.25, "cell_height": 0.2}},
                {"type": "bake_navmesh", "faces": [[0, 0, 0], [10, 0, 0], [10, 0, 10], [0, 0, 0], [10, 0, 10], [0, 0, 10]]},
            ],
        })
        assert "vertices" in read(project, "nav/level3d.tres")


def test_build_theme() -> None:
    with fixture_project() as project:
        dispatch(project, "build_theme", {
            "resource_path": "theme/main.tres", "default_font_size": 16, "default_base_scale": 1.0,
            "types": {"Button": {
                "styleboxes": {
                    "normal": {"bg_color": "#2a2a2a", "corner_radius": 6, "border_width": 1, "border_color": "#111111", "content_margin": 8},
                    "focus": {"__resource_type": "StyleBoxEmpty"}},
                "colors": {"font_color": "#ffffff"},
                "constants": {"h_separation": 8},
                "font_sizes": {"font_size": 16}}},
            "variations": {"HeaderLabel": {"base": "Label", "colors": {"font_color": "#88ccff"}, "font_sizes": {"font_size": 28}}},
        })
        theme = read(project, "theme/main.tres")
        assert 'type="Theme"' in theme and "StyleBoxFlat" in theme and "StyleBoxEmpty" in theme, theme
        assert "Button/colors/font_color = Color(1, 1, 1, 1)" in theme, theme
        assert 'HeaderLabel/base_type = &"Label"' in theme, theme


def test_gltf_export() -> None:
    with fixture_project() as project:
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/hero.tscn", "create_if_missing": True, "root_node_type": "Node3D", "root_node_name": "Hero",
            "actions": [{"type": "add_node", "node_type": "MeshInstance3D", "node_name": "Body",
                         "properties": {"mesh": {"__resource_type": "BoxMesh"}}}],
        })
        dispatch(project, "gltf_export", {"scene_path": "scenes/hero.tscn", "out": "export/hero.glb"})
        out = project / "export/hero.glb"
        assert out.exists() and out.stat().st_size > 0


def test_shader_globals() -> None:
    with fixture_project() as project:
        dispatch(project, "project_batch", {"actions": [
            {"type": "set_shader_global", "name": "wind_dir", "global_type": "vec3", "value": {"__type": "Vector3", "x": 1, "y": 0, "z": 0}},
            {"type": "set_shader_global", "name": "tint", "global_type": "color", "value": {"__type": "Color", "r": 1, "g": 0.5, "b": 0.2, "a": 1}},
        ]})
        godot = read(project, "project.godot")
        assert "[shader_globals]" in godot and "wind_dir" in godot and "tint" in godot, godot
        # clearing is idempotent
        dispatch(project, "project_batch", {"actions": [
            {"type": "clear_shader_global", "name": "wind_dir"},
            {"type": "clear_shader_global", "name": "missing"}]})
        assert "wind_dir" not in read(project, "project.godot")


def test_build_replication_config() -> None:
    with fixture_project() as project:
        result = dispatch(project, "build_replication_config", {
            "resource_path": "net/player_repl.tres", "properties": [
                {"path": ".:position", "spawn": True, "replication_mode": "on_change"},
                {"path": ".:velocity", "replication_mode": "always"}]})
        assert result["property_count"] == 2, result
        assert "SceneReplicationConfig" in read(project, "net/player_repl.tres")


def test_broken_op_exits_nonzero() -> None:
    """A parse error in an op script must surface as a non-zero exit, not a silent 0."""
    with fixture_project() as project:
        # An unknown operation is the closest deterministic proxy for a load failure.
        dispatch_raw(project, "does_not_exist", {}, expected_returncode=1)


# --- helpers ---------------------------------------------------------------

class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-newops-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def read(project: Path, rel: str) -> str:
    return (project / rel).read_text(encoding="utf-8")


def import_assets(project: Path) -> None:
    subprocess.run(["godot", "--headless", "--path", str(project), "--import"],
                   capture_output=True, text=True, check=False, timeout=120)


def write_opaque_png(path: Path, width: int, height: int) -> None:
    """A fully opaque RGBA PNG so opaque_to_polygons traces a single region."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = b"".join(b"\x00" + b"\xff\x00\x00\xff" * width for _ in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def dispatch(project: Path, operation: str, params: dict) -> dict:
    result = dispatch_raw(project, operation, params)
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"No JSON payload for {operation}.\n{result.stdout}\n{result.stderr}")


def dispatch_raw(project: Path, operation: str, params: dict, expected_returncode: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["godot", "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=120,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}.\n{result.stdout}\n{result.stderr}")
    return result


if __name__ == "__main__":
    main()
