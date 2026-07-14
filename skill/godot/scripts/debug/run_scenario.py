#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a deterministic Godot input/assertion/screenshot/performance scenario.")
    parser.add_argument("project_path")
    parser.add_argument("scenario_path")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--runner", type=Path)
    parser.add_argument("--timeout", type=float, default=120.0)
    render_group = parser.add_mutually_exclusive_group()
    render_group.add_argument("--headless", action="store_true", help="Force headless mode even when screenshots are requested")
    render_group.add_argument("--no-headless", action="store_true", help="Force a rendered window")
    parser.add_argument("--log-file", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def extract_payload(output: str) -> dict:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    return {"ok": False, "errors": ["scenario runner emitted no JSON payload"]}


def compare(actual: float, operator: str, expected: float) -> bool:
    return {
        "less_than": actual < expected,
        "less_or_equal": actual <= expected,
        "greater_than": actual > expected,
        "greater_or_equal": actual >= expected,
        "equals": actual == expected,
    }.get(operator, False)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    scenario_path = Path(args.scenario_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        raise SystemExit(f"Missing Godot project file: {project_path / 'project.godot'}")
    scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
    runner = (args.runner or Path(__file__).with_name("scenario_runner.gd")).resolve()
    needs_rendering = any(step.get("type") == "screenshot" for step in scenario.get("steps", []))
    use_headless = args.headless or (not args.no_headless and not needs_rendering)
    command = [args.godot_bin]
    if use_headless:
        command.append("--headless")
    command.extend(["--path", str(project_path), "--script", str(runner), str(scenario_path)])
    try:
        completed = subprocess.run(command, capture_output=True, text=True, check=False, timeout=args.timeout)
    except subprocess.TimeoutExpired as exc:
        payload = {
            "ok": False,
            "timed_out": True,
            "timeout": args.timeout,
            "errors": [f"Scenario timed out after {args.timeout}s (hang or blocking step)"],
            "stdout": (exc.stdout or b"").decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or ""),
        }
        print(json.dumps(payload, indent=2 if args.pretty else None))
        return 1
    combined = completed.stdout + "\n" + completed.stderr
    if args.log_file:
        args.log_file.expanduser().resolve().write_text(combined, encoding="utf-8")
    result = extract_payload(completed.stdout)

    log_results = []
    for index, assertion in enumerate(scenario.get("log_assertions", [])):
        pattern = str(assertion.get("regex", re.escape(str(assertion.get("contains", "")))))
        count = len(re.findall(pattern, combined, re.MULTILINE))
        minimum = int(assertion.get("min_count", 1))
        maximum = assertion.get("max_count")
        passed = count >= minimum and (maximum is None or count <= int(maximum))
        log_results.append({"label": assertion.get("label", f"log_assertions[{index}]"), "passed": passed, "count": count, "pattern": pattern})

    performance_results = []
    for index, assertion in enumerate(scenario.get("performance_assertions", [])):
        monitor = str(assertion.get("monitor", ""))
        statistic = str(assertion.get("statistic", "average"))
        actual = result.get("performance", {}).get(monitor, {}).get(statistic)
        expected = float(assertion.get("value", 0.0))
        operator = str(assertion.get("operator", "less_or_equal"))
        passed = actual is not None and compare(float(actual), operator, expected)
        performance_results.append({
            "label": assertion.get("label", f"performance_assertions[{index}]"),
            "passed": passed,
            "monitor": monitor,
            "statistic": statistic,
            "actual": actual,
            "operator": operator,
            "expected": expected,
        })

    failed_external = [item for item in [*log_results, *performance_results] if not item["passed"]]
    result.update({
        "ok": bool(result.get("ok", False)) and completed.returncode == 0 and not failed_external,
        "returncode": completed.returncode,
        "log_assertions": log_results,
        "performance_assertions": performance_results,
    })
    if failed_external:
        result.setdefault("errors", []).extend(f"External assertion failed: {item['label']}" for item in failed_external)
    print(json.dumps(result, indent=2 if args.pretty else None))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
