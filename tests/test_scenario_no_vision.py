#!/usr/bin/env python3
"""Scenario steps that describe a run in text instead of in pixels.

Every assertion here stands in for something a sighted caller would have read
off a screenshot: the ASCII layout map, the property tree dump, and the
screenshot summary/expectations produced from `image_describe.describe`.
"""
from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
RUNNER = REPO_ROOT / "skill/godot/scripts/debug/run_scenario.py"
TEMP_ROOTS: list[Path] = []

# Written into the throwaway copy of the fixture project, never into
# tests/fixtures — other modules assert on that project's file counts.
COLOURED_UI_SCENE = """[gd_scene format=3]

[node name="ColouredScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Backdrop" type="ColorRect" parent="."]
layout_mode = 0
offset_right = 640.0
offset_bottom = 320.0
color = Color(0.2, 0.4, 0.9, 1)

[node name="StartButton" type="Button" parent="."]
layout_mode = 0
offset_left = 40.0
offset_top = 200.0
offset_right = 200.0
offset_bottom = 240.0
text = "Start"
"""

BLACK_UI_SCENE = """[gd_scene format=3]

[node name="BlackScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Backdrop" type="ColorRect" parent="."]
layout_mode = 0
offset_right = 640.0
offset_bottom = 320.0
color = Color(0, 0, 0, 1)
"""

TREE_SCENE = """[gd_scene format=3]

[node name="World" type="Node2D"]

[node name="Player" type="Sprite2D" parent="."]
position = Vector2(120, 80)

[node name="Muzzle" type="Marker2D" parent="Player"]
position = Vector2(8, -4)

[node name="HiddenPickup" type="Node2D" parent="."]
visible = false
position = Vector2(300, 40)
"""


def has_godot() -> bool:
    return shutil.which("godot") is not None


def workspace() -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-no-vision-test-"))
    TEMP_ROOTS.append(root)
    project = root / "project"
    shutil.copytree(FIXTURE_ROOT, project)
    (project / "scenes/coloured_ui.tscn").write_text(COLOURED_UI_SCENE, encoding="utf-8")
    (project / "scenes/black_ui.tscn").write_text(BLACK_UI_SCENE, encoding="utf-8")
    (project / "scenes/tree_world.tscn").write_text(TREE_SCENE, encoding="utf-8")
    return root


def run_case(root: Path, scenario: dict) -> tuple[subprocess.CompletedProcess[str], dict]:
    scenario_path = root / "scenario.json"
    scenario_path.write_text(json.dumps(scenario), encoding="utf-8")
    result = subprocess.run(
        [
            "python3", str(RUNNER), str(root / "project"), str(scenario_path),
            "--pretty", "--log-file", str(root / "run.log"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result, json.loads(result.stdout)


def engine_log(root: Path) -> str:
    """Everything the runner printed — the ASCII rows and tree lines live here."""
    return (root / "run.log").read_text(encoding="utf-8")


def expected_ascii_rows(width: int, viewport_width: int, viewport_height: int) -> int:
    """The runner's row formula: width * (height / width) * 0.5, rounded."""
    return max(int(math.floor(width * viewport_height / viewport_width * 0.5 + 0.5)), 1)


def can_render(root: Path) -> bool:
    """Screenshots need a real framebuffer; headless CI without one cannot."""
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 64, "height": 64},
            "steps": [{"type": "screenshot", "path": str(root / "captures/probe.png")}],
            "assertions": [],
        },
    )
    return result.returncode == 0 and bool(payload.get("screenshots"))


def test_ui_report_ascii_draws_every_control() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [{"type": "ui_report", "label": "boot", "ascii": True, "ascii_width": 80}],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    report = payload["ui_reports"][0]
    rows = report["ascii"]

    # Character cells are ~2:1, so the map is half as tall as the aspect ratio.
    assert len(rows) == expected_ascii_rows(80, 640, 320) == 20, len(rows)
    assert all(len(row) == 80 for row in rows), [len(row) for row in rows]

    drawing = "\n".join(rows)
    # Every visible Control is drawn as a named box.
    assert "Backdrop" in drawing, drawing
    assert "StartButton" in drawing, drawing
    # Boxes are boxes: corners, horizontal and vertical edges.
    assert "+" in drawing and "-" in drawing and "|" in drawing, drawing
    # The button sits in the lower-left of a 640x320 viewport, so its box must
    # start below the halfway row and left of the halfway column.
    button_rows = [index for index, row in enumerate(rows) if "StartButton" in row]
    assert button_rows and button_rows[0] > len(rows) // 2, button_rows
    assert rows[button_rows[0]].index("StartButton") < 40, rows[button_rows[0]]

    # The rows are printed too, so a log reader sees them without the payload.
    assert "[SCENARIO] ui_report boot ascii 80x20" in engine_log(root)

    # Off by default, and nothing else about the report changes.
    _, plain = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [{"type": "ui_report", "label": "boot"}],
            "assertions": [],
        },
    )
    plain_report = plain["ui_reports"][0]
    assert "ascii" not in plain_report
    assert plain_report["controls"] == report["controls"]
    assert plain_report["counts"] == report["counts"]


def test_ui_report_ascii_width_is_configurable() -> None:
    root = workspace()
    _, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [{"type": "ui_report", "ascii": True, "ascii_width": 40}],
            "assertions": [],
        },
    )
    rows = payload["ui_reports"][0]["ascii"]
    assert len(rows) == expected_ascii_rows(40, 640, 320) == 10
    assert all(len(row) == 40 for row in rows)


def test_dump_tree_reports_nodes_and_indented_lines() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/tree_world.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [
                {
                    "type": "dump_tree",
                    "label": "after_boot",
                    "properties": ["visible", "position", "text", "nonexistent_property"],
                }
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    dump = payload["tree_dumps"][0]
    assert dump["label"] == "after_boot"
    assert dump["node_path"] == "."
    assert dump["node_count"] == 4 == len(dump["nodes"]) == len(dump["lines"])

    nodes = {entry["path"]: entry for entry in dump["nodes"]}
    assert set(nodes) == {".", "Player", "Player/Muzzle", "HiddenPickup"}
    assert nodes["."]["type"] == "Node2D"
    assert nodes["Player"]["type"] == "Sprite2D"
    # Requested properties the node actually has, typed through the codec.
    assert nodes["Player"]["props"]["visible"] is True
    assert nodes["Player"]["props"]["position"] == {"__type": "Vector2", "x": 120, "y": 80}
    assert nodes["HiddenPickup"]["props"]["visible"] is False
    # A property the node does not have is skipped, never an error.
    assert "text" not in nodes["Player"]["props"]
    assert "nonexistent_property" not in nodes["Player"]["props"]

    lines = dump["lines"]
    assert lines[0] == "World (Node2D) visible=true position=(0, 0)"
    assert lines[1].startswith("  Player (Sprite2D) ")
    assert "position=(120, 80)" in lines[1]
    assert lines[2].startswith("    Muzzle (Marker2D) ")
    assert not lines[0].startswith(" ")

    # The tree is printed as well, so a log reader never has to parse JSON.
    log = engine_log(root)
    assert "[SCENARIO] dump_tree after_boot node_path=. nodes=4" in log
    for line in lines:
        assert line in log, line


def test_dump_tree_scopes_and_limits_depth() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/tree_world.tscn",
            "steps": [
                {"type": "dump_tree", "label": "scoped", "node_path": "Player"},
                {"type": "dump_tree", "label": "shallow", "max_depth": 1},
                {"type": "dump_tree", "label": "absolute", "node_path": "/root/World"},
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    scoped, shallow, absolute = payload["tree_dumps"]
    assert [entry["path"] for entry in scoped["nodes"]] == [".", "Muzzle"]
    # max_depth 1 keeps the root and its direct children only.
    assert [entry["path"] for entry in shallow["nodes"]] == [".", "Player", "HiddenPickup"]
    assert absolute["node_count"] == 4


def test_dump_tree_missing_node_says_what_to_pass() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/tree_world.tscn",
            "steps": [{"type": "dump_tree", "node_path": "Nope"}],
            "assertions": [],
        },
    )
    assert result.returncode == 1
    assert payload["ok"] is False
    assert any(
        "dump_tree node not found: Nope" in error and "/root/" in error for error in payload["errors"]
    ), payload["errors"]


def test_screenshot_summary_and_expectations() -> None:
    root = workspace()
    if not can_render(root):
        print("SKIP test_screenshot_summary_and_expectations (no framebuffer to render into)")
        return

    coloured = root / "captures/coloured.png"
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [
                {
                    "type": "screenshot",
                    "path": str(coloured),
                    "expect": {"not_blank": True, "min_opaque_ratio": 0.5},
                    "describe": {"ascii": True, "ascii_width": 40},
                }
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["ok"] is True
    shot = payload["screenshots"][0]
    assert shot["passed"] is True
    summary = shot["summary"]
    assert summary["width"] == 640 and summary["height"] == 320
    assert summary["blank"] is False
    assert summary["opaque_ratio"] >= 0.5
    assert summary["mean_color"].startswith("#")
    assert summary["dominant_colors"], summary
    # describe.ascii rides along on the summary and is printed.
    rows = summary["ascii"]
    assert len(rows) == expected_ascii_rows(40, 640, 320) == 10
    assert all(len(row) == 40 for row in rows)
    assert any(row.strip() for row in rows), rows
    log = engine_log(root)
    assert "[SCENARIO] screenshot " in log
    assert " blank=false " in log and "dominant=#" in log
    for row in rows:
        assert row in log, row


def test_screenshot_expect_not_blank_fails_on_a_black_scene() -> None:
    root = workspace()
    if not can_render(root):
        print("SKIP test_screenshot_expect_not_blank_fails_on_a_black_scene (no framebuffer to render into)")
        return

    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/black_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [
                {
                    "type": "screenshot",
                    "path": str(root / "captures/black.png"),
                    "expect": {"not_blank": True},
                },
                {"type": "log_marker", "message": "still-running"},
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 1, result.stdout + result.stderr
    assert payload["ok"] is False
    shot = payload["screenshots"][0]
    assert shot["passed"] is False
    assert shot["summary"]["blank"] is True
    blank_errors = [error for error in payload["errors"] if "expect.not_blank failed" in error]
    assert len(blank_errors) == 1, payload["errors"]
    # The message names the numbers a caller cannot see for themselves.
    assert "unique colour(s)" in blank_errors[0], blank_errors[0]
    assert "opaque_ratio" in blank_errors[0], blank_errors[0]
    # A failed expectation records the failure without aborting the scenario.
    assert "[SCENARIO] still-running" in engine_log(root)


def test_screenshot_min_opaque_ratio_names_the_number_seen() -> None:
    root = workspace()
    if not can_render(root):
        print("SKIP test_screenshot_min_opaque_ratio_names_the_number_seen (no framebuffer to render into)")
        return

    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [
                {
                    "type": "screenshot",
                    "path": str(root / "captures/ratio.png"),
                    "expect": {"min_opaque_ratio": 1.5},
                }
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 1
    ratio_errors = [error for error in payload["errors"] if "expect.min_opaque_ratio failed" in error]
    assert len(ratio_errors) == 1, payload["errors"]
    assert "is below 1.5" in ratio_errors[0], ratio_errors[0]


def test_screenshot_compare_to_gates_a_regression() -> None:
    root = workspace()
    if not can_render(root):
        print("SKIP test_screenshot_compare_to_gates_a_regression (no framebuffer to render into)")
        return

    reference = root / "captures/reference.png"
    result, _ = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 160, "height": 80},
            "steps": [{"type": "screenshot", "path": str(reference)}],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr

    # Same scene against its own capture: no difference, so the gate passes.
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 160, "height": 80},
            "steps": [
                {
                    "type": "screenshot",
                    "path": str(root / "captures/same.png"),
                    "expect": {"max_diff_ratio": 0.02, "compare_to": str(reference)},
                }
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["screenshots"][0]["summary"]["diff_ratio"] == 0

    # A different scene at the same size blows past the allowance.
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/black_ui.tscn",
            "viewport_size": {"width": 160, "height": 80},
            "steps": [
                {
                    "type": "screenshot",
                    "path": str(root / "captures/changed.png"),
                    "expect": {"max_diff_ratio": 0.02, "compare_to": str(reference)},
                }
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 1
    diff_errors = [error for error in payload["errors"] if "expect.max_diff_ratio failed" in error]
    assert len(diff_errors) == 1, payload["errors"]
    assert "of the pixels differ from the reference" in diff_errors[0]


def test_screenshot_expect_typo_is_rejected() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 160, "height": 80},
            "steps": [
                {"type": "screenshot", "path": str(root / "captures/typo.png"), "expect": {"not_blanc": True}}
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 1
    assert any(
        "expect has unknown key 'not_blanc'" in error and "not_blank" in error for error in payload["errors"]
    ), payload["errors"]


def test_unknown_step_type_lists_the_supported_ones() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {"scene_path": "scenes/tree_world.tscn", "steps": [{"type": "dump_three"}], "assertions": []},
    )
    assert result.returncode == 1
    assert any(
        "Unsupported step type at 0: 'dump_three'" in error and "dump_tree" in error
        for error in payload["errors"]
    ), payload["errors"]


def test_payload_survives_printed_ascii_and_tree_lines() -> None:
    """The wrapper must find the result JSON past everything the steps print."""
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/coloured_ui.tscn",
            "viewport_size": {"width": 640, "height": 320},
            "steps": [
                {"type": "ui_report", "label": "boot", "ascii": True},
                {"type": "dump_tree", "label": "boot"},
            ],
            "assertions": [{"assertion": "node_exists", "node_path": "StartButton"}],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["ok"] is True
    assert payload["ui_reports"][0]["ascii"]
    assert payload["tree_dumps"][0]["nodes"]
    assert payload["assertions"][0]["passed"] is True
    # --pretty keeps the new fields readable rather than collapsing them.
    assert '"ascii": [' in result.stdout
    assert '"tree_dumps": [' in result.stdout
    assert '"lines": [' in result.stdout


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    if not has_godot():
        print("SKIP scenario no-vision tests (godot binary not found on PATH)")
        return
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    try:
        for test in tests:
            test()
        print(f"All {len(tests)} scenario no-vision tests passed.")
    finally:
        cleanup()


if __name__ == "__main__":
    sys.exit(main())
