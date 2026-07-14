#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
RUNNER = REPO_ROOT / "skill/godot/scripts/debug/run_scenario.py"


def main() -> None:
    root = Path(tempfile.mkdtemp(prefix="godot-scenario-test-"))
    try:
        project = root / "project"
        shutil.copytree(FIXTURE_ROOT, project)
        screenshot = root / "captures/status.png"
        scenario_path = root / "scenario.json"
        scenario_path.write_text(
            json.dumps(
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
                }
            ),
            encoding="utf-8",
        )
        result = subprocess.run(
            ["python3", str(RUNNER), str(project), str(scenario_path), "--pretty"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(f"Scenario failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
        payload = json.loads(result.stdout)
        assert payload["ok"] is True
        assert all(item["passed"] for item in payload["assertions"])
        assert payload["screenshots"][0]["width"] == 640
        assert payload["screenshots"][0]["height"] == 360
        assert screenshot.is_file() and screenshot.stat().st_size > 0
        assert payload["performance"]["fps"]["samples"] == 3
        print("All scenario runner tests passed.")
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
