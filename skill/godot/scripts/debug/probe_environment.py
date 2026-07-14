#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


TOOLS = ["dotnet", "clang", "cmake", "scons", "java", "adb", "xcodebuild", "gradle"]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe the local Godot engine and platform toolchain.")
    parser.add_argument("project_path", nargs="?", default=".")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args(argv)


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, capture_output=True, text=True, check=False, timeout=30)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(command, -1, "", "timed out after 30s")


def template_candidates(version: str) -> list[Path]:
    version_parts = version.split(".")
    version_key = ".".join(version_parts[:3]) if len(version_parts) >= 3 else version
    home = Path.home()
    candidates = [
        home / "Library/Application Support/Godot/export_templates" / version_key,
        home / ".local/share/godot/export_templates" / version_key,
        home / ".godot/export_templates" / version_key,
    ]
    appdata = os.environ.get("APPDATA")
    if appdata:
        candidates.append(Path(appdata) / "Godot/export_templates" / version_key)
    return candidates


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    godot_path = shutil.which(args.godot_bin)
    version_result = run([args.godot_bin, "--version"]) if godot_path else None
    help_result = run([args.godot_bin, "--help"]) if godot_path else None
    version = version_result.stdout.strip() if version_result and version_result.returncode == 0 else ""
    help_text = help_result.stdout if help_result and help_result.returncode == 0 else ""
    candidates = template_candidates(version) if version else []
    installed_templates = next((path for path in candidates if path.is_dir()), None)

    project_files: list[Path] = []
    if (project_path / "project.godot").is_file():
        # Walk manually so hidden directories (.godot import cache, .git) are
        # pruned — rglob would scan thousands of cache files on big projects.
        for dirpath, dirnames, filenames in os.walk(project_path):
            dirnames[:] = [name for name in dirnames if not name.startswith(".")]
            project_files.extend(Path(dirpath) / name for name in filenames)
    payload = {
        "ok": bool(godot_path and version),
        "engine": {
            "executable": godot_path or "",
            "version": version,
            "capabilities": {
                "import": "--import" in help_text,
                "build_solutions": "--build-solutions" in help_text,
                "export_patch": "--export-patch" in help_text,
                "patches": "--patches" in help_text,
            },
        },
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "tools": {name: shutil.which(name) or "" for name in TOOLS},
        "export_templates": {
            "installed": installed_templates is not None,
            "path": str(installed_templates) if installed_templates else "",
            "searched": [str(path) for path in candidates],
        },
        "project": {
            "path": str(project_path),
            "valid": (project_path / "project.godot").is_file(),
            "has_csharp": any(path.suffix.lower() in {".cs", ".csproj"} for path in project_files),
            "has_gdextension": any(path.suffix.lower() == ".gdextension" for path in project_files),
            "has_plugins": any(path.name == "plugin.cfg" for path in project_files),
            "has_export_presets": (project_path / "export_presets.cfg").is_file(),
        },
    }
    print(json.dumps(payload, indent=2 if args.pretty else None))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
