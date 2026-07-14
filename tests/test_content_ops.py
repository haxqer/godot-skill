#!/usr/bin/env python3
"""Integration tests for the content authoring ops: build_sprite_frames atlas
mode, build_tileset, paint_tilemap, build_animation, and setup_audio_buses."""
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
    test_instantiate_scene_does_not_duplicate_children()
    test_sprite_frames_atlas_mode()
    test_build_tileset_and_paint_tilemap()
    test_tileset_collision_custom_data_and_terrains()
    test_set_import_options_wav_loop()
    test_build_animation()
    test_build_animation_tree()
    test_setup_audio_buses()
    print("All content operation tests passed.")


def test_instantiate_scene_does_not_duplicate_children() -> None:
    """Regression: re-owning an instanced scene's internal children serialized
    duplicates of them into the parent scene (and leaked nodes at runtime)."""
    with fixture_project() as project:
        dispatch_raw(
            project,
            "scene_batch",
            {
                "scene_path": "scenes/widget.tscn",
                "create_if_missing": True,
                "root_node_type": "Node2D",
                "root_node_name": "Widget",
                "actions": [
                    {"type": "add_node", "node_type": "Sprite2D", "node_name": "Icon"},
                    {"type": "add_node", "node_type": "Label", "node_name": "Caption"},
                ],
            },
        )
        dispatch_raw(
            project,
            "scene_batch",
            {
                "scene_path": "scenes/holder.tscn",
                "create_if_missing": True,
                "root_node_type": "Node2D",
                "actions": [
                    {
                        "type": "instantiate_scene",
                        "instance_scene_path": "scenes/widget.tscn",
                        "node_name": "WidgetInstance",
                    }
                ],
            },
        )
        holder = dispatch(project, "inspect_scene", {"scene_path": "scenes/holder.tscn"})
        # Only the root + the instance placeholder must be stored; the
        # instance's Icon/Caption children live in widget.tscn, not here.
        names = [node["name"] for node in holder["nodes"]]
        assert names == ["root", "WidgetInstance"], names


def test_sprite_frames_atlas_mode() -> None:
    with fixture_project() as project:
        write_png(project / "art/sheet.png", width=32, height=16)
        import_assets(project)
        dispatch_raw(
            project,
            "scene_batch",
            {
                "scene_path": "scenes/mob.tscn",
                "create_if_missing": True,
                "root_node_type": "Node2D",
                "actions": [
                    {"type": "add_node", "node_type": "AnimatedSprite2D", "node_name": "Sprite"},
                    {
                        "type": "build_sprite_frames",
                        "node_path": "root/Sprite",
                        "spritesheet": "art/sheet.png",
                        "grid": {"cell_width": 8, "cell_height": 8},
                        "animations": [
                            {"name": "idle", "fps": 6, "loop": True, "frames": [{"row": 0, "cols": [0, 1, 2, 3]}]},
                            {
                                "name": "attack",
                                "fps": 12,
                                "frames": [
                                    {"index": 4, "duration": 2.0},
                                    {"region": {"x": 8, "y": 8, "width": 8, "height": 8}},
                                ],
                            },
                        ],
                        "resource_save_path": "anims/mob_frames.tres",
                    },
                ],
            },
        )
        frames = dispatch(
            project,
            "inspect_resource",
            {"resource_path": "anims/mob_frames.tres", "max_resource_depth": 5},
        )
        assert frames["resource_type"] == "SpriteFrames"
        animations = {scalar(entry["name"]): entry for entry in frames["properties"]["animations"]}
        assert set(animations) == {"idle", "attack"}
        assert len(animations["idle"]["frames"]) == 4
        assert bool(animations["idle"]["loop"])  # stored as int 1
        attack_frames = animations["attack"]["frames"]
        assert len(attack_frames) == 2
        assert attack_frames[0]["duration"] == 2.0


def test_build_tileset_and_paint_tilemap() -> None:
    with fixture_project() as project:
        write_png(project / "art/tiles.png", width=32, height=16)
        import_assets(project)
        built = dispatch(
            project,
            "build_tileset",
            {
                "resource_path": "tilesets/world.tres",
                "tile_size": {"x": 16, "y": 16},
                "physics_layers": [{"collision_layer": 1}],
                "custom_data_layers": [{"name": "kind", "type": "string"}],
                "sources": [{"source_id": 0, "texture": "art/tiles.png", "tiles": "all"}],
            },
        )
        assert built["ok"] is True
        assert built["source_count"] == 1
        assert built["tiles_exposed"] == 2
        assert built["physics_layer_count"] == 1

        dispatch_raw(
            project,
            "scene_batch",
            {
                "scene_path": "scenes/level.tscn",
                "create_if_missing": True,
                "root_node_type": "Node2D",
                "actions": [{"type": "add_node", "node_type": "TileMapLayer", "node_name": "Ground"}],
            },
        )
        painted = dispatch(
            project,
            "paint_tilemap",
            {
                "scene_path": "scenes/level.tscn",
                "node_path": "root/Ground",
                "tile_set": "tilesets/world.tres",
                "cells": [{"coords": {"x": 0, "y": 0}, "source_id": 0, "atlas_coords": {"x": 0, "y": 0}}],
                "fills": [
                    {
                        "from": {"x": 0, "y": 1},
                        "to": {"x": 4, "y": 1},
                        "source_id": 0,
                        "atlas_coords": {"x": 1, "y": 0},
                    }
                ],
            },
        )
        assert painted["ok"] is True
        scene = dispatch(project, "inspect_scene", {"scene_path": "scenes/level.tscn"})
        ground = next(node for node in scene["nodes"] if node["name"] == "Ground")
        assert ground["type"] == "TileMapLayer"
        tile_data = ground["properties"]["tile_map_data"]["values"]
        assert len(tile_data) > 2

        # Painting an unexposed atlas tile must fail (exit 1) and leave the scene unsaved.
        result = dispatch_raw(
            project,
            "paint_tilemap",
            {
                "scene_path": "scenes/level.tscn",
                "node_path": "root/Ground",
                "cells": [{"coords": {"x": 9, "y": 9}, "source_id": 0, "atlas_coords": {"x": 9, "y": 9}}],
            },
            expected_returncode=1,
        )
        assert "has no tile at" in result.stdout + result.stderr


def test_tileset_collision_custom_data_and_terrains() -> None:
    with fixture_project() as project:
        write_png(project / "art/tiles.png", width=32, height=16)
        import_assets(project)
        built = dispatch(
            project,
            "build_tileset",
            {
                "resource_path": "tilesets/solid.tres",
                "tile_size": {"x": 16, "y": 16},
                "physics_layers": [{"collision_layer": 1}],
                "custom_data_layers": [{"name": "kind", "type": "string"}],
                "terrain_sets": [
                    {"mode": "match_sides", "terrains": [{"name": "grass", "color": {"r": 0, "g": 1, "b": 0, "a": 1}}]}
                ],
                "sources": [
                    {
                        "source_id": 0,
                        "texture": "art/tiles.png",
                        "tiles": "all",
                        "tile_defaults": {
                            "collision": "full_cell",
                            "custom_data": {"kind": "ground"},
                            "terrain_set": 0,
                            "terrain": 0,
                            "peering": {"left_side": 0, "right_side": 0},
                        },
                    }
                ],
            },
        )
        assert built["ok"] is True
        assert built["tiles_exposed"] == 2

        inspected = dispatch(
            project,
            "inspect_resource",
            {"resource_path": "tilesets/solid.tres", "max_resource_depth": 4},
        )
        source = inspected["properties"]["sources/0"]["properties"]
        # Per-tile collision polygons serialize as "<x>:<y>/<alt>/physics_layer_0/polygon_0/points".
        assert any("physics_layer_0/polygon_0/points" in key for key in source), sorted(source)[:20]
        assert any("custom_data_0" in key for key in source)
        assert any("terrain_set" in key for key in source)

        # terrain_fills paints through set_cells_terrain_connect without errors.
        dispatch_raw(
            project,
            "scene_batch",
            {
                "scene_path": "scenes/tlevel.tscn",
                "create_if_missing": True,
                "root_node_type": "Node2D",
                "actions": [{"type": "add_node", "node_type": "TileMapLayer", "node_name": "Ground"}],
            },
        )
        painted = dispatch(
            project,
            "paint_tilemap",
            {
                "scene_path": "scenes/tlevel.tscn",
                "node_path": "root/Ground",
                "tile_set": "tilesets/solid.tres",
                "terrain_fills": [
                    {"cells": [{"x": 0, "y": 0}, {"x": 1, "y": 0}], "terrain_set": 0, "terrain": 0}
                ],
            },
        )
        assert painted["ok"] is True


def test_set_import_options_wav_loop() -> None:
    with fixture_project() as project:
        write_wav(project / "audio/step.wav")
        import_assets(project)
        # Importer enum is offset from the resource enum: on the WAV importer
        # 0=Detect From WAV, 1=Disabled, 2=Forward — so 2 yields LOOP_FORWARD (1).
        patched = dispatch(
            project,
            "set_import_options",
            {"file_path": "audio/step.wav", "options": {"edit/loop_mode": 2}},
        )
        assert patched["ok"] is True
        assert patched["reimport_required"] is True
        assert patched["invalidated_artifacts"], "expected the stale import artifact to be dropped"
        import_assets(project)
        stream = dispatch(project, "inspect_resource", {"resource_path": "audio/step.wav"})
        assert stream["resource_type"] == "AudioStreamWAV"
        assert stream["properties"]["loop_mode"] == 1  # LOOP_FORWARD


def test_build_animation() -> None:
    with fixture_project() as project:
        built = dispatch(
            project,
            "build_animation",
            {
                "animation_name": "blink",
                "length": 0.8,
                "loop_mode": "linear",
                "tracks": [
                    {
                        "type": "value",
                        "path": "StatusLabel:modulate",
                        "update_mode": "continuous",
                        "keys": [
                            {"time": 0.0, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 1}},
                            {"time": 0.4, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 0.2}},
                            {"time": 0.8, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 1}},
                        ],
                    },
                    {
                        "type": "method",
                        "path": ".",
                        "keys": [{"time": 0.8, "method": "queue_redraw", "args": []}],
                    },
                ],
                "resource_save_path": "anims/blink.tres",
                "scene_path": "scenes/existing_ui.tscn",
                "player_node_path": "root/AnimationPlayer",
            },
        )
        assert built["ok"] is True
        assert built["track_count"] == 2
        assert built["attached_to_scene"] is True

        animation = dispatch(project, "inspect_resource", {"resource_path": "anims/blink.tres"})
        assert animation["resource_type"] == "Animation"
        assert animation["properties"]["length"] == 0.8

        scene = dispatch(project, "inspect_scene", {"scene_path": "scenes/existing_ui.tscn"})
        player = next(node for node in scene["nodes"] if node["name"] == "AnimationPlayer")
        assert player["type"] == "AnimationPlayer"
        # The default "" library is stored under the "libraries/" key prefix.
        assert any(key.startswith("libraries") for key in player["properties"])


def test_build_animation_tree() -> None:
    with fixture_project() as project:
        dispatch(
            project,
            "build_animation",
            {
                "animation_name": "idle",
                "length": 0.5,
                "loop_mode": "linear",
                "tracks": [
                    {
                        "type": "value",
                        "path": "StatusLabel:modulate",
                        "keys": [{"time": 0.0, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 1}}],
                    }
                ],
                "scene_path": "scenes/existing_ui.tscn",
                "player_node_path": "root/AnimationPlayer",
            },
        )
        built = dispatch(
            project,
            "build_animation_tree",
            {
                "scene_path": "scenes/existing_ui.tscn",
                "tree_node_path": "root/AnimationTree",
                "anim_player": "../AnimationPlayer",
                "states": [{"name": "idle", "animation": "idle"}],
                "transitions": [],
            },
        )
        assert built["ok"] is True
        assert built["state_count"] == 1
        assert built["transition_count"] == 1  # auto Start -> idle

        scene = dispatch(project, "inspect_scene", {"scene_path": "scenes/existing_ui.tscn"})
        tree = next(node for node in scene["nodes"] if node["name"] == "AnimationTree")
        assert tree["type"] == "AnimationTree"
        assert "tree_root" in tree["properties"]


def test_setup_audio_buses() -> None:
    with fixture_project() as project:
        result = dispatch(
            project,
            "setup_audio_buses",
            {
                "buses": [
                    {"name": "Master", "volume_db": -3.0},
                    {"name": "Music", "send": "Master", "volume_db": -6.0},
                    {
                        "name": "SFX",
                        "send": "Master",
                        "effects": [{"type": "AudioEffectLowPassFilter", "properties": {"cutoff_hz": 4000.0}}],
                    },
                ],
                # Non-default path so the project setting actually gets written
                # (values equal to the engine default are omitted on save).
                "save_path": "audio/buses.tres",
            },
        )
        assert result["ok"] is True
        assert result["buses"] == ["Master", "Music", "SFX"]
        assert result["project_setting_updated"] is True

        layout = dispatch(project, "inspect_resource", {"resource_path": "audio/buses.tres"})
        assert layout["resource_type"] == "AudioBusLayout"
        project_text = (project / "project.godot").read_text(encoding="utf-8")
        assert "audio/buses.tres" in project_text

        # Rerunning the same spec must be idempotent: no duplicate buses.
        rerun = dispatch(
            project,
            "setup_audio_buses",
            {
                "buses": [
                    {"name": "Master", "volume_db": -3.0},
                    {"name": "Music", "send": "Master", "volume_db": -6.0},
                    {"name": "SFX", "send": "Master"},
                ],
                "save_path": "audio/buses.tres",
            },
        )
        assert rerun["buses"] == ["Master", "Music", "SFX"]


def scalar(value):
    """Unwrap typed-JSON scalars like {"__type": "StringName", "value": "idle"}."""
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-content-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def write_wav(path: Path, samples: int = 220) -> None:
    """Write a tiny valid 16-bit mono PCM WAV (silence)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    sample_rate = 22050
    data = b"\x00\x00" * samples
    header = (
        b"RIFF"
        + struct.pack("<I", 36 + len(data))
        + b"WAVEfmt "
        + struct.pack("<IHHIIHH", 16, 1, 1, sample_rate, sample_rate * 2, 2, 16)
        + b"data"
        + struct.pack("<I", len(data))
    )
    path.write_bytes(header + data)


def import_assets(project: Path) -> None:
    """Run Godot's importer so raw images get .import sidecars, matching the
    real pipeline where saved .tres files reference imported textures."""
    subprocess.run(
        ["godot", "--headless", "--path", str(project), "--import"],
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )


def write_png(path: Path, width: int, height: int) -> None:
    """Write a tiny valid RGBA PNG without external dependencies."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = b"".join(
        b"\x00" + bytes(4 * width) if y % 2 == 0 else b"\x00" + b"\xff\x00\x00\xff" * width
        for y in range(height)
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


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
        timeout=120,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}.\n{result.stdout}\n{result.stderr}"
        )
    return result


if __name__ == "__main__":
    main()
