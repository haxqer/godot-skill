#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
RUNNER = REPO_ROOT / "skill/godot/scripts/debug/run_scenario.py"
TEMP_ROOTS: list[Path] = []

sys.path.insert(0, str(REPO_ROOT / "skill/godot/scripts/debug"))
from run_scenario import needs_rendering  # noqa: E402

# The two UI scenes below are written into the throwaway copy of the fixture
# project rather than into tests/fixtures, because other modules assert on that
# project's file counts. BrokenScreen is the failure mode this feature exists
# for: controls added with layout_mode 0 and no offsets all land on each other.
BROKEN_UI_SCENE = """[gd_scene format=3]

[node name="BrokenScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Backdrop" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0

[node name="TitleLabel" type="Label" parent="."]
layout_mode = 0
offset_right = 160.0
offset_bottom = 30.0
text = "Title"

[node name="SubtitleLabel" type="Label" parent="."]
layout_mode = 0
offset_right = 160.0
offset_bottom = 30.0
text = "Subtitle"

[node name="StartButton" type="Button" parent="."]
layout_mode = 0
offset_right = 160.0
offset_bottom = 30.0
text = "Start"

[node name="ZeroBox" type="Panel" parent="."]
layout_mode = 0
offset_left = 200.0
offset_top = 200.0
offset_right = 200.0
offset_bottom = 200.0

[node name="OffscreenLabel" type="Label" parent="."]
layout_mode = 0
offset_left = -400.0
offset_top = 40.0
offset_right = -240.0
offset_bottom = 70.0
text = "Off"
"""

CONTAINER_UI_SCENE = """[gd_scene format=3]

[node name="ContainerScreen" type="MarginContainer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 8
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 8
theme_override_constants/margin_bottom = 8

[node name="Backdrop" type="ColorRect" parent="."]
layout_mode = 2

[node name="Body" type="VBoxContainer" parent="."]
layout_mode = 2

[node name="TitleLabel" type="Label" parent="Body"]
layout_mode = 2
text = "Container Title"

[node name="BodyLabel" type="Label" parent="Body"]
layout_mode = 2
text = "Body copy"

[node name="Row" type="HBoxContainer" parent="Body"]
layout_mode = 2

[node name="OkButton" type="Button" parent="Body/Row"]
layout_mode = 2
text = "OK"

[node name="CancelButton" type="Button" parent="Body/Row"]
layout_mode = 2
text = "Cancel"
"""


def workspace() -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-scenario-test-"))
    TEMP_ROOTS.append(root)
    project = root / "project"
    shutil.copytree(FIXTURE_ROOT, project)
    (project / "scenes/broken_ui.tscn").write_text(BROKEN_UI_SCENE, encoding="utf-8")
    (project / "scenes/container_ui.tscn").write_text(CONTAINER_UI_SCENE, encoding="utf-8")
    return root


def run_case(root: Path, scenario: dict) -> tuple[subprocess.CompletedProcess[str], dict]:
    scenario_path = root / "scenario.json"
    scenario_path.write_text(json.dumps(scenario), encoding="utf-8")
    result = subprocess.run(
        ["python3", str(RUNNER), str(root / "project"), str(scenario_path), "--pretty"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result, json.loads(result.stdout)


def controls_by_path(report: dict) -> dict[str, dict]:
    return {entry["path"]: entry for entry in report["controls"]}


def findings_of(report: dict, kind: str) -> list[dict]:
    return [finding for finding in report["findings"] if finding["kind"] == kind]


def test_input_assertions_and_screenshot() -> None:
    root = workspace()
    screenshot = root / "captures/status.png"
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/existing_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "settle_frames": 2,
            "steps": [
                {"type": "mouse_motion", "position": {"x": 20, "y": 20}},
                {
                    "type": "assert",
                    "assertion": "property",
                    "node_path": "StatusLabel",
                    "property": "text",
                    "expected": "Pending",
                },
                {"type": "set_property", "node_path": "StatusLabel", "property": "text", "value": "Ready"},
                {
                    "type": "wait_until",
                    "node_path": "StatusLabel",
                    "property": "text",
                    "expected": "Ready",
                    "timeout_seconds": 2,
                },
                {"type": "screenshot", "path": str(screenshot)},
                {"type": "log_marker", "message": "status-verified"},
            ],
            "assertions": [
                {"assertion": "node_exists", "node_path": "CancelButton"},
                {"assertion": "visible", "node_path": "StatusLabel", "expected": True},
            ],
            "performance_frames": 3,
            "log_assertions": [{"contains": "[SCENARIO] status-verified"}],
            "performance_assertions": [
                {"monitor": "node_count", "statistic": "maximum", "operator": "greater_or_equal", "value": 3}
            ],
        },
    )
    if result.returncode != 0:
        raise AssertionError(f"Scenario failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
    assert payload["ok"] is True
    assert all(item["passed"] for item in payload["assertions"])
    assert payload["screenshots"][0]["width"] == 640
    assert payload["screenshots"][0]["height"] == 360
    assert screenshot.is_file() and screenshot.stat().st_size > 0
    assert payload["performance"]["fps"]["samples"] == 3


def test_ui_report_describes_the_laid_out_ui() -> None:
    """The report has to be usable as a substitute for looking at the window."""
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/existing_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [{"type": "ui_report", "label": "status-screen"}],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["ok"] is True
    # No screenshot step, so the run stayed headless and captured no image.
    assert payload["screenshots"] == []

    report = payload["ui_reports"][0]
    assert report["label"] == "status-screen"
    assert report["passed"] is True
    assert report["viewport"] == {"width": 640, "height": 360}
    assert report["rect_format"] == "[x, y, width, height]"
    assert report["counts"] == {"controls": 3, "visible": 3, "hidden": 0, "findings": 0}

    controls = controls_by_path(report)
    assert set(controls) == {".", "StatusLabel", "CancelButton"}
    # Rects are the post-layout global rects, matching the offsets in the .tscn.
    assert controls["."]["rect"] == [0, 0, 640, 360]
    assert controls["StatusLabel"]["rect"] == [16, 16, 96, 23]
    assert controls["CancelButton"]["rect"] == [16, 56, 92, 31]
    assert controls["StatusLabel"]["class"] == "Label"
    assert controls["StatusLabel"]["text"] == "Pending"
    assert controls["CancelButton"]["text"] == "Cancel"
    # Visible controls carry no per-entry flag; hidden ones are simply absent.
    assert "visible" not in controls["StatusLabel"]
    assert report["findings"] == []


def test_ui_report_flags_a_hand_placed_scene() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/broken_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [{"type": "ui_report", "label": "broken"}],
            "assertions": [],
        },
    )
    # Findings alone do not fail a scenario; only fail_on does.
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["ok"] is True
    report = payload["ui_reports"][0]
    assert report["passed"] is True

    overlaps = {tuple(finding["nodes"]) for finding in findings_of(report, "overlap")}
    assert overlaps == {
        ("TitleLabel", "SubtitleLabel"),
        ("TitleLabel", "StartButton"),
        ("SubtitleLabel", "StartButton"),
    }
    for finding in findings_of(report, "overlap"):
        assert finding["parent"] == "."
        assert finding["overlap_rect"] == [0, 0, 160, 30]
        assert finding["ratio"] == 1
        assert all(rect[:3] == [0, 0, 160] for rect in finding["rects"])

    zero_size = findings_of(report, "zero_size")
    assert [finding["nodes"] for finding in zero_size] == [["ZeroBox"]]
    assert zero_size[0]["rects"] == [[200, 200, 0, 0]]

    offscreen = findings_of(report, "offscreen")
    assert [finding["nodes"] for finding in offscreen] == [["OffscreenLabel"]]
    assert offscreen[0]["rects"] == [[-400, 40, 160, 30]]

    # The full-bleed ColorRect behind everything is a background layer, not an
    # overlap: it is listed, but never named in a finding.
    assert controls_by_path(report)["Backdrop"]["rect"] == [0, 0, 640, 360]
    named = {path for finding in report["findings"] for path in finding["nodes"]}
    assert "Backdrop" not in named


def test_container_layout_reports_no_overlap() -> None:
    """Siblings that share a slot by design must not be reported."""
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/container_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [
                {"type": "ui_report", "label": "containers", "fail_on": ["overlap", "zero_size", "offscreen"]}
            ],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["ok"] is True
    report = payload["ui_reports"][0]
    assert report["findings"] == []
    assert report["passed"] is True

    controls = controls_by_path(report)
    # The exemption is doing real work: these two siblings occupy the very same
    # rect, and only their MarginContainer parent keeps that from being a finding.
    assert controls["Backdrop"]["rect"] == controls["Body"]["rect"]
    # The box containers really did arrange their children side by side.
    assert controls["Body/TitleLabel"]["rect"][1] < controls["Body/BodyLabel"]["rect"][1]
    assert controls["Body/Row/OkButton"]["rect"][0] < controls["Body/Row/CancelButton"]["rect"][0]


def test_fail_on_flips_the_scenario_to_failed() -> None:
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/broken_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [
                {"type": "ui_report", "label": "gated", "fail_on": ["overlap"]},
                {"type": "log_marker", "message": "still-running"},
            ],
            "assertions": [{"assertion": "node_exists", "node_path": "TitleLabel"}],
        },
    )
    assert result.returncode == 1, result.stdout + result.stderr
    assert payload["ok"] is False
    assert payload["returncode"] == 1
    assert payload["ui_reports"][0]["passed"] is False
    gated = [error for error in payload["errors"] if error.startswith("UI finding (overlap) in gated:")]
    assert len(gated) == 3, payload["errors"]
    # A gated finding records the failure without aborting the scenario.
    assert payload["assertions"][0]["passed"] is True

    # An ungated kind leaves the scenario passing even though it is reported.
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/broken_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [{"type": "ui_report", "fail_on": ["offscreen"]}],
            "assertions": [],
        },
    )
    assert result.returncode == 1, "the fixture is offscreen too"
    assert len(payload["errors"]) == 1


def test_unknown_fail_on_kind_is_rejected() -> None:
    """A typo must not silently gate on nothing."""
    root = workspace()
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/broken_ui.tscn",
            "steps": [{"type": "ui_report", "fail_on": ["overlaps"]}],
            "assertions": [],
        },
    )
    assert result.returncode == 1
    assert payload["ok"] is False
    assert any("unknown kind 'overlaps'" in error for error in payload["errors"]), payload["errors"]


def test_ui_report_writes_a_file_and_scopes_to_node_path() -> None:
    root = workspace()
    report_path = root / "reports/layout.json"
    result, payload = run_case(
        root,
        {
            "scene_path": "scenes/container_ui.tscn",
            "viewport_size": {"width": 640, "height": 360},
            "steps": [{"type": "ui_report", "node_path": "Body/Row", "path": str(report_path)}],
            "assertions": [],
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    report = payload["ui_reports"][0]
    assert report["file"] == str(report_path)
    assert json.loads(report_path.read_text(encoding="utf-8")) == report
    # Paths stay relative to the scene root even when the walk is scoped, so
    # they can be pasted straight into a later assertion's node_path.
    assert sorted(controls_by_path(report)) == ["Body/Row", "Body/Row/CancelButton", "Body/Row/OkButton"]


def test_hidden_controls_are_opt_in() -> None:
    root = workspace()
    scenario = {
        "scene_path": "scenes/existing_ui.tscn",
        "viewport_size": {"width": 640, "height": 360},
        "steps": [
            {"type": "set_property", "node_path": "CancelButton", "property": "visible", "value": False},
            {"type": "ui_report", "label": "default"},
            {"type": "ui_report", "label": "with-hidden", "include_hidden": True},
        ],
        "assertions": [],
    }
    result, payload = run_case(root, scenario)
    assert result.returncode == 0, result.stdout + result.stderr

    default_report, hidden_report = payload["ui_reports"]
    assert "CancelButton" not in controls_by_path(default_report)
    assert default_report["counts"] == {"controls": 2, "visible": 2, "hidden": 1, "findings": 0}

    hidden_entry = controls_by_path(hidden_report)["CancelButton"]
    assert hidden_entry["visible"] is False
    assert hidden_entry["self_hidden"] is True
    assert hidden_report["counts"] == {"controls": 3, "visible": 2, "hidden": 1, "findings": 0}
    # Hidden controls are described but never produce findings.
    assert hidden_report["findings"] == []


def test_ui_report_does_not_force_a_rendered_window() -> None:
    assert needs_rendering({"steps": [{"type": "ui_report"}, {"type": "log_marker"}]}) is False
    assert needs_rendering({"steps": [{"type": "screenshot", "path": "/tmp/x.png"}]}) is True


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    try:
        for test in tests:
            test()
        print(f"All {len(tests)} scenario runner tests passed.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()
