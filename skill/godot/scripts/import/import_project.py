#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import a Godot project and return a structured import audit.")
    parser.add_argument("project_path")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--dispatcher", type=Path)
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--audit-only", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def run_bounded(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return subprocess.CompletedProcess(command, -1, stdout, stderr + f"\n[import_project] timed out after {timeout}s")


def extract_payload(output: str) -> dict:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise RuntimeError("Import audit did not emit a JSON payload")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        raise SystemExit(f"Missing Godot project file: {project_path / 'project.godot'}")
    dispatcher = (args.dispatcher or Path(__file__).resolve().parents[1] / "core/dispatcher.gd").resolve()

    import_result: dict = {"ran": False, "returncode": 0, "stdout": "", "stderr": ""}
    if not args.audit_only:
        completed = run_bounded(
            [args.godot_bin, "--headless", "--path", str(project_path), "--import"],
            args.timeout,
        )
        import_result = {
            "ran": True,
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }

    audit_completed = run_bounded(
        [
            args.godot_bin,
            "--headless",
            "--path",
            str(project_path),
            "--script",
            str(dispatcher),
            "audit_imports",
            "{}",
        ],
        args.timeout,
    )
    try:
        audit = extract_payload(audit_completed.stdout)
    except (RuntimeError, json.JSONDecodeError) as exc:
        audit = {"ok": False, "error": str(exc)}

    payload = {
        "ok": import_result["returncode"] == 0 and audit_completed.returncode == 0 and bool(audit.get("ok", False)),
        "project_path": str(project_path),
        "import": import_result,
        "audit": audit,
        "audit_returncode": audit_completed.returncode,
        "audit_stderr": audit_completed.stderr,
    }
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
