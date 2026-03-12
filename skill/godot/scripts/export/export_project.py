#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


MODE_TO_FLAG = {
    "debug": "--export-debug",
    "release": "--export-release",
    "pack": "--export-pack",
}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a Godot export preset through the local godot CLI."
    )
    parser.add_argument("project_path", help="Path to the Godot project directory")
    parser.add_argument("preset_name", help="Exact preset name from export_presets.cfg")
    parser.add_argument("output_path", help="Output file path for the exported artifact")
    parser.add_argument(
        "--mode",
        choices=sorted(MODE_TO_FLAG),
        default="release",
        help="Export mode to use (default: release)",
    )
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", "godot"),
        help="Godot executable to invoke (default: GODOT_BIN or godot)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the resolved command without running it",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit a JSON payload instead of a shell-style command string",
    )
    return parser.parse_args(argv)


def resolve_paths(project_path_arg: str, output_path_arg: str) -> tuple[Path, Path]:
    project_path = Path(project_path_arg).expanduser().resolve()
    output_path = Path(output_path_arg).expanduser().resolve()
    project_file = project_path / "project.godot"
    if not project_file.is_file():
        raise SystemExit(f"Missing Godot project file: {project_file}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return project_path, output_path


def build_command(
    godot_bin: str,
    mode: str,
    project_path: Path,
    preset_name: str,
    output_path: Path,
) -> list[str]:
    return [
        godot_bin,
        "--headless",
        "--path",
        str(project_path),
        MODE_TO_FLAG[mode],
        preset_name,
        str(output_path),
    ]


def emit(command: list[str], project_path: Path, preset_name: str, output_path: Path, mode: str, as_json: bool) -> None:
    if as_json:
        print(
            json.dumps(
                {
                    "command": command,
                    "project_path": str(project_path),
                    "preset_name": preset_name,
                    "output_path": str(output_path),
                    "mode": mode,
                }
            )
        )
        return
    print(shlex.join(command))


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path, output_path = resolve_paths(args.project_path, args.output_path)
    command = build_command(
        godot_bin=args.godot_bin,
        mode=args.mode,
        project_path=project_path,
        preset_name=args.preset_name,
        output_path=output_path,
    )
    if args.dry_run:
        emit(command, project_path, args.preset_name, output_path, args.mode, args.json)
        return 0
    completed = subprocess.run(command, check=False)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
