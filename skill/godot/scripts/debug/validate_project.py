#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Godot resources, plugins, GDExtensions, and C# solutions.")
    parser.add_argument("project_path")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--dispatcher", type=Path)
    parser.add_argument("--project-subpath", default="")
    parser.add_argument("--csharp", choices=["auto", "always", "never"], default="auto")
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def extract_payload(output: str) -> dict:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    return {"failed_count": 1, "failed": [{"kind": "validator", "reason": "check_project emitted no JSON"}]}


def command_result(completed: subprocess.CompletedProcess[str]) -> dict:
    return {"returncode": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}


def run_bounded(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, capture_output=True, text=True, check=False, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return subprocess.CompletedProcess(command, -1, stdout, stderr + f"\n[validate_project] timed out after {timeout}s")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        raise SystemExit(f"Missing Godot project file: {project_path / 'project.godot'}")
    dispatcher = (args.dispatcher or Path(__file__).resolve().parents[1] / "core/dispatcher.gd").resolve()

    params = {"project_path": args.project_subpath} if args.project_subpath else {}
    checked = run_bounded(
        [args.godot_bin, "--headless", "--path", str(project_path), "--script", str(dispatcher), "check_project", json.dumps(params)],
        args.timeout,
    )
    static = extract_payload(checked.stdout)

    csproj_files = sorted(project_path.glob("*.csproj"))
    csharp_requested = args.csharp == "always" or (args.csharp == "auto" and bool(csproj_files))
    csharp: dict = {"requested": csharp_requested, "ran": False, "projects": [str(path) for path in csproj_files]}
    if csharp_requested:
        if not csproj_files:
            csharp.update({"ok": False, "error": "no .csproj file found"})
        elif not shutil.which("dotnet"):
            csharp.update({"ok": False, "error": "dotnet executable not found"})
        else:
            built = run_bounded(
                [args.godot_bin, "--headless", "--path", str(project_path), "--build-solutions", "--quit"],
                args.timeout,
            )
            csharp.update({"ran": True, "ok": built.returncode == 0, **command_result(built)})
    else:
        csharp["ok"] = True

    ok = checked.returncode == 0 and int(static.get("failed_count", 1)) == 0 and bool(csharp.get("ok", False))
    payload = {
        "ok": ok,
        "project_path": str(project_path),
        "static": static,
        "godot": command_result(checked),
        "csharp": csharp,
    }
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
