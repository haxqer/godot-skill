#!/usr/bin/env python3
"""Integration tests for the ASCII level round trip: paint_tilemap.ascii_map,
paint_gridmap.ascii_layers, and the inspect_tilemap op that reads either back as
text so a model without vision can verify what it painted."""
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

# Two 16x16 tiles sliced out of a 32x16 sheet: atlas (0,0) and (1,0).
WALL = {"source_id": 0, "atlas_coords": {"x": 0, "y": 0}, "alternative": 0}
FLOOR = {"source_id": 0, "atlas_coords": {"x": 1, "y": 0}, "alternative": 0}
LEGEND = {"#": WALL, "o": FLOOR, ".": None}
ROOM = ["#####", "#ooo#", "#####"]


def main() -> None:
    if shutil.which("godot") is None:
        print("SKIP test_ascii_tilemap (no godot on PATH)")
        return
    test_tilemap_ascii_round_trip()
    test_tilemap_ascii_errors_and_erase_unlisted()
    test_tilemap_ascii_combines_with_cells_and_scene_batch()
    test_tilemap_ascii_terrain_legend_and_empty_layer()
    test_gridmap_ascii_layers_round_trip()
    test_inspect_tilemap_node_discovery()
    print("All ascii tilemap tests passed.")


def test_tilemap_ascii_round_trip() -> None:
    """Paint from ASCII, read it back identically with an explicit legend, and
    with an auto-assigned one; the auto legend is itself repaintable."""
    with fixture_project() as project:
        setup_tileset(project)
        add_tilemap_scene(project, "scenes/level.tscn", "Ground")
        painted = dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/level.tscn",
            "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "ascii_map": {"legend": LEGEND, "rows": ROOM, "origin": {"x": 0, "y": 0}},
        })
        assert painted["ok"] is True, painted

        # --- explicit legend: the rows must come back byte-identical ---------
        report = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert report["rows"] == ROOM, report
        assert report["node_type"] == "TileMapLayer", report
        assert report["node_path"] == "root/Ground", report
        assert report["tileset_path"] == "res://tilesets/world.tres", report
        assert report["bounds"] == {"x": 0, "y": 0, "w": 5, "h": 3}, report
        assert report["cell_count"] == 15, report
        assert report["counts"] == {"#": 12, "o": 3}, report
        assert report["legend"]["."] is None, report
        assert report["legend"]["#"] == WALL, report

        # --- no legend: characters are auto-assigned in first-seen order -----
        auto = dispatch(project, "inspect_tilemap", {"scene_path": "scenes/level.tscn"})
        assert auto["node_path"] == "root/Ground", auto
        assert auto["rows"] == ["#####", "#@@@#", "#####"], auto
        assert auto["legend"]["#"] == WALL, auto
        assert auto["legend"]["@"] == FLOOR, auto
        # ... and identical to the explicit run once translated through the legends.
        assert translate(auto["rows"], auto["legend"], LEGEND) == ROOM, auto

        # --- the printed legend is exactly what paint_tilemap accepts --------
        add_tilemap_scene(project, "scenes/copy.tscn", "Ground")
        dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/copy.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "ascii_map": {"legend": auto["legend"], "rows": auto["rows"]},
        })
        copied = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/copy.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert copied["rows"] == ROOM, copied

        # --- bounds crops the window ----------------------------------------
        cropped = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground", "legend": LEGEND,
            "bounds": {"x": 1, "y": 0, "w": 3, "h": 2}})
        assert cropped["rows"] == ["###", "ooo"], cropped
        assert cropped["bounds"] == {"x": 1, "y": 0, "w": 3, "h": 2}, cropped

        # --- format: text prints the rows and nothing else -------------------
        text = dispatch_raw(project, "inspect_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground",
            "legend": LEGEND, "format": "text"})
        lines = [line for line in text.stdout.splitlines() if line.strip()]
        assert lines[-3:] == ROOM, text.stdout
        assert not any(line.startswith("{") for line in lines), text.stdout


def test_tilemap_ascii_errors_and_erase_unlisted() -> None:
    with fixture_project() as project:
        setup_tileset(project)
        add_tilemap_scene(project, "scenes/level.tscn", "Ground")
        dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "ascii_map": {"legend": LEGEND, "rows": ROOM},
        })
        before = (project / "scenes/level.tscn").read_bytes()

        # A character missing from the legend fails loudly and saves nothing.
        failed = dispatch_raw(project, "paint_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground",
            "ascii_map": {"legend": LEGEND, "rows": ["#Z#", "#Q#"]},
        }, expected_returncode=1)
        output = failed.stdout + failed.stderr
        assert "not in the legend" in output, output
        assert "'Z'" in output and "'Q'" in output, output
        assert "'#'" in output and "'o'" in output, output
        assert (project / "scenes/level.tscn").read_bytes() == before, "scene must be untouched"

        # '.' leaves cells alone by default ...
        dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground",
            "ascii_map": {"legend": LEGEND, "rows": ["..."], "origin": {"x": 1, "y": 1}},
        })
        kept = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert kept["rows"] == ROOM, kept

        # ... and erases them with erase_unlisted.
        dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground",
            "ascii_map": {"legend": LEGEND, "rows": ["..."], "origin": {"x": 1, "y": 1},
                          "erase_unlisted": True},
        })
        erased = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/level.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert erased["rows"] == ["#####", "#...#", "#####"], erased
        assert erased["counts"] == {"#": 12}, erased

        # Ragged rows are a warning, not an error: the short row stops early.
        ragged = dispatch_raw(project, "paint_tilemap", {
            "scene_path": "scenes/ragged.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "ascii_map": {"legend": LEGEND, "rows": ["####", "##"]},
        }, expected_returncode=1)  # scene does not exist yet -> the op must say so
        assert "does not exist" in ragged.stdout + ragged.stderr, ragged.stdout

        add_tilemap_scene(project, "scenes/ragged.tscn", "Ground")
        warned = dispatch_raw(project, "paint_tilemap", {
            "scene_path": "scenes/ragged.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "ascii_map": {"legend": LEGEND, "rows": ["####", "##"]},
        })
        assert "[WARN]" in warned.stdout and "unequal lengths" in warned.stdout, warned.stdout
        report = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/ragged.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert report["rows"] == ["####", "##.."], report


def test_tilemap_ascii_combines_with_cells_and_scene_batch() -> None:
    with fixture_project() as project:
        setup_tileset(project)
        add_tilemap_scene(project, "scenes/combo.tscn", "Ground")
        # cells run before ascii_map, so the ascii wins where they overlap.
        dispatch(project, "paint_tilemap", {
            "scene_path": "scenes/combo.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/world.tres",
            "cells": [
                {"coords": {"x": 0, "y": 0}, "source_id": 0, "atlas_coords": {"x": 1, "y": 0}},
                {"coords": {"x": 0, "y": 2}, "source_id": 0, "atlas_coords": {"x": 1, "y": 0}},
            ],
            "ascii_map": {"legend": LEGEND, "rows": ["##"]},
        })
        combo = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/combo.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert combo["rows"] == ["##", "..", "o."], combo

        # The scene_batch action form takes the same ascii_map, and rows may be
        # one \n-separated string.
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/batch.tscn", "create_if_missing": True,
            "root_node_type": "Node2D", "root_node_name": "root",
            "actions": [
                {"type": "add_node", "node_type": "TileMapLayer", "node_name": "Ground"},
                {"type": "paint_tilemap", "node_path": "root/Ground",
                 "tile_set": "tilesets/world.tres",
                 "ascii_map": {"legend": LEGEND, "rows": "###\n#o#\n###",
                               "origin": {"x": 2, "y": 3}}},
            ],
        })
        batched = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/batch.tscn", "node_path": "root/Ground", "legend": LEGEND})
        assert batched["rows"] == ["###", "#o#", "###"], batched
        assert batched["bounds"] == {"x": 2, "y": 3, "w": 3, "h": 3}, batched


def test_tilemap_ascii_terrain_legend_and_empty_layer() -> None:
    """A legend entry with a terrain is collected and painted through
    set_cells_terrain_connect after the plain cells."""
    with fixture_project() as project:
        write_png(project / "art/tiles.png", width=32, height=16)
        import_assets(project)
        dispatch(project, "build_tileset", {
            "resource_path": "tilesets/terrain.tres",
            "tile_size": {"x": 16, "y": 16},
            "terrain_sets": [{"mode": "match_sides",
                              "terrains": [{"name": "grass", "color": {"r": 0, "g": 1, "b": 0, "a": 1}}]}],
            "sources": [{"source_id": 0, "texture": "art/tiles.png", "tiles": "all",
                         "tile_defaults": {"terrain_set": 0, "terrain": 0,
                                           "peering": {"left_side": 0, "right_side": 0,
                                                       "top_side": 0, "bottom_side": 0}}}],
        })
        add_tilemap_scene(project, "scenes/terrain.tscn", "Ground")

        # An empty layer inspects cleanly instead of erroring.
        empty = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/terrain.tscn", "node_path": "root/Ground"})
        assert empty["rows"] == [], empty
        assert empty["cell_count"] == 0, empty
        assert empty["bounds"] == {"x": 0, "y": 0, "w": 0, "h": 0}, empty

        painted = dispatch_raw(project, "paint_tilemap", {
            "scene_path": "scenes/terrain.tscn", "node_path": "root/Ground",
            "tile_set": "tilesets/terrain.tres",
            "ascii_map": {"legend": {"#": WALL, "G": {"terrain_set": 0, "terrain": 0}, ".": None},
                          "rows": ["#..", ".GG"]},
        })
        # 'G' is routed to set_cells_terrain_connect, '#' to set_cell. This
        # synthetic 2-tile atlas has no tile matching the terrain neighbourhood,
        # which the engine handles by painting nothing at all - so the op warns
        # instead of reporting a clean save over an empty map.
        assert "[WARN] paint_tilemap.ascii_map terrain legend" in painted.stdout, painted.stdout
        assert "left 2 of 2 cells empty" in painted.stdout, painted.stdout
        report = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/terrain.tscn", "node_path": "root/Ground"})
        assert report["rows"] == ["#"], report
        assert report["cell_count"] == 1, report

        # Mixing the two forms in one legend entry is rejected with a fix.
        mixed = dispatch_raw(project, "paint_tilemap", {
            "scene_path": "scenes/terrain.tscn", "node_path": "root/Ground",
            "ascii_map": {"legend": {"X": {"source_id": 0, "terrain": 0}}, "rows": ["X"]},
        }, expected_returncode=1)
        assert "mixes a terrain with an atlas tile" in mixed.stdout + mixed.stderr


def test_gridmap_ascii_layers_round_trip() -> None:
    with fixture_project() as project:
        dispatch(project, "resource_batch", {
            "resource_path": "meshlib/tiles.meshlib", "create_if_missing": True,
            "resource_type": "MeshLibrary",
            "actions": [
                {"type": "call_method", "method": "create_item", "args": [0]},
                {"type": "call_method", "method": "set_item_name", "args": [0, "box"]},
                {"type": "call_method", "method": "set_item_mesh",
                 "args": [0, {"__resource_type": "BoxMesh"}]},
                {"type": "call_method", "method": "create_item", "args": [1]},
                {"type": "call_method", "method": "set_item_name", "args": [1, "slab"]},
                {"type": "call_method", "method": "set_item_mesh",
                 "args": [1, {"__resource_type": "BoxMesh"}]},
            ],
        })
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/world.tscn", "create_if_missing": True,
            "root_node_type": "Node3D", "root_node_name": "root",
            "actions": [{"type": "add_node", "node_type": "GridMap", "node_name": "Grid"}],
        })
        grid_legend = {"A": {"item": 0, "orientation": 0}, "B": {"item": 1, "orientation": 0}, ".": None}
        ground = ["AAAA", "A..A", "AAAA"]
        upper = ["B..B", "....", "B..B"]
        dispatch(project, "paint_gridmap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid",
            "mesh_library": "meshlib/tiles.meshlib",
            "legend": grid_legend,
            "ascii_layers": [{"y": 0, "rows": ground}, {"y": 1, "rows": upper}],
        })

        report = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid", "legend": grid_legend})
        assert report["node_type"] == "GridMap", report
        assert report["mesh_library_path"] == "res://meshlib/tiles.meshlib", report
        assert report["bounds"] == {"x": 0, "z": 0, "w": 4, "h": 3}, report
        assert report["layers"] == [{"y": 0, "rows": ground}, {"y": 1, "rows": upper}], report
        assert report["cell_count"] == 14, report
        assert report["counts"] == {"A": 10, "B": 4}, report

        # Auto legend: 'A' -> '#', 'B' -> '@' in first-seen order.
        auto = dispatch(project, "inspect_tilemap", {"scene_path": "scenes/world.tscn"})
        assert auto["node_path"] == "root/Grid", auto
        assert auto["layers"][0]["rows"] == ["####", "#..#", "####"], auto
        assert auto["legend"]["#"] == {"item": 0, "orientation": 0}, auto

        # format: text prints one y= header per layer.
        text = dispatch_raw(project, "inspect_tilemap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid",
            "legend": grid_legend, "format": "text"})
        lines = [line for line in text.stdout.splitlines() if line.strip()]
        assert lines[-8:] == ["y=0"] + ground + ["y=1"] + upper, text.stdout

        # An unknown character is rejected here too.
        failed = dispatch_raw(project, "paint_gridmap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid",
            "legend": grid_legend, "ascii_layers": [{"y": 0, "rows": ["AAZA"]}],
        }, expected_returncode=1)
        assert "not in the legend" in failed.stdout + failed.stderr, failed.stdout

        # erase_unlisted clears the layer-0 interior ring instead of skipping it.
        dispatch(project, "paint_gridmap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid",
            "legend": grid_legend, "erase_unlisted": True,
            "ascii_layers": [{"y": 0, "rows": ["....", "....", "...."]}],
        })
        erased = dispatch(project, "inspect_tilemap", {
            "scene_path": "scenes/world.tscn", "node_path": "root/Grid", "legend": grid_legend})
        assert [layer["y"] for layer in erased["layers"]] == [1], erased


def test_inspect_tilemap_node_discovery() -> None:
    with fixture_project() as project:
        dispatch_raw(project, "scene_batch", {
            "scene_path": "scenes/plain.tscn", "create_if_missing": True,
            "root_node_type": "Node2D", "root_node_name": "root",
            "actions": [{"type": "add_node", "node_type": "Sprite2D", "node_name": "Icon"}],
        })
        missing = dispatch_raw(project, "inspect_tilemap",
                               {"scene_path": "scenes/plain.tscn"}, expected_returncode=1)
        output = missing.stdout + missing.stderr
        assert "found no TileMapLayer or GridMap" in output, output
        assert "root (Node2D)" in output and "root/Icon (Sprite2D)" in output, output

        wrong = dispatch_raw(project, "inspect_tilemap",
                             {"scene_path": "scenes/plain.tscn", "node_path": "root/Icon"},
                             expected_returncode=1)
        assert "is a Sprite2D, not a TileMapLayer or GridMap" in wrong.stdout + wrong.stderr

        gone = dispatch_raw(project, "inspect_tilemap",
                            {"scene_path": "scenes/plain.tscn", "node_path": "root/Nope"},
                            expected_returncode=1)
        assert "no node at node_path" in gone.stdout + gone.stderr

        bad_format = dispatch_raw(project, "inspect_tilemap",
                                  {"scene_path": "scenes/plain.tscn", "format": "ascii"},
                                  expected_returncode=1)
        assert "must be \"json\" (default) or \"text\"" in bad_format.stdout + bad_format.stderr


# --- helpers ---------------------------------------------------------------

def setup_tileset(project: Path) -> None:
    write_png(project / "art/tiles.png", width=32, height=16)
    import_assets(project)
    built = dispatch(project, "build_tileset", {
        "resource_path": "tilesets/world.tres",
        "tile_size": {"x": 16, "y": 16},
        "sources": [{"source_id": 0, "texture": "art/tiles.png", "tiles": "all"}],
    })
    assert built["tiles_exposed"] == 2, built


def add_tilemap_scene(project: Path, scene_path: str, node_name: str) -> None:
    dispatch_raw(project, "scene_batch", {
        "scene_path": scene_path, "create_if_missing": True,
        "root_node_type": "Node2D", "root_node_name": "root",
        "actions": [{"type": "add_node", "node_type": "TileMapLayer", "node_name": node_name}],
    })


def translate(rows: list, source_legend: dict, target_legend: dict) -> list:
    """Re-letter `rows` from one legend into another so two inspect runs can be
    compared regardless of which characters were assigned."""
    to_target = {}
    for symbol, tile in target_legend.items():
        to_target[json.dumps(tile, sort_keys=True)] = symbol
    mapping = {symbol: to_target[json.dumps(tile, sort_keys=True)]
               for symbol, tile in source_legend.items()}
    return ["".join(mapping[char] for char in row) for row in rows]


class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-ascii-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def import_assets(project: Path) -> None:
    subprocess.run(["godot", "--headless", "--path", str(project), "--import"],
                   capture_output=True, text=True, check=False, timeout=120)


def write_png(path: Path, width: int, height: int) -> None:
    """A tiny valid RGBA PNG without external dependencies."""
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = b"".join(
        b"\x00" + bytes(4 * width) if y % 2 == 0 else b"\x00" + b"\xff\x00\x00\xff" * width
        for y in range(height)
    )

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


def dispatch_raw(project: Path, operation: str, params: dict,
                 expected_returncode: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["godot", "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=120,
    )
    if result.returncode != expected_returncode:
        raise AssertionError(
            f"{operation} returned {result.returncode}, expected {expected_returncode}."
            f"\n{result.stdout}\n{result.stderr}")
    return result


if __name__ == "__main__":
    main()
