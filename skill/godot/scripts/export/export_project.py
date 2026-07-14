#!/usr/bin/env python3
from __future__ import annotations

import argparse
import configparser
import json
import os
import platform
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


MODE_TO_FLAG = {
    "debug": "--export-debug",
    "release": "--export-release",
    "pack": "--export-pack",
    "patch": "--export-patch",
}

PLATFORM_EXTENSIONS = {
    "Android": {".apk", ".aab"},
    "iOS": {".zip"},
    "VisionOS": {".zip"},
    "Web": {".html", ".zip"},
    "Windows Desktop": {".exe", ".zip"},
    "Linux/X11": {".x86_64", ".zip"},
    "Linux": {".x86_64", ".zip"},
    "macOS": {".zip", ".dmg"},
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
        "--patches",
        nargs="+",
        default=[],
        help="Base PCK/ZIP patches for --mode patch, passed as a comma-separated --patches value",
    )
    parser.add_argument(
        "--preflight-only",
        action="store_true",
        help="Validate the preset, environment, and output path without exporting",
    )
    parser.add_argument(
        "--skip-preflight",
        action="store_true",
        help="Skip preflight checks before a real export",
    )
    parser.add_argument(
        "--strict-preflight",
        action="store_true",
        help="Fail dry-run when preflight reports errors",
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
    patches: list[Path] | None = None,
) -> list[str]:
    command = [
        godot_bin,
        "--headless",
        "--path",
        str(project_path),
        MODE_TO_FLAG[mode],
        preset_name,
        str(output_path),
    ]
    if patches:
        command.extend(["--patches", ",".join(str(path) for path in patches)])
    return command


def parse_presets(project_path: Path) -> list[dict[str, str]]:
    preset_file = project_path / "export_presets.cfg"
    if not preset_file.is_file():
        return []
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    try:
        parser.read(preset_file, encoding="utf-8")
    except configparser.Error:
        return []
    presets = []
    for section in parser.sections():
        if not section.startswith("preset.") or section.endswith(".options"):
            continue
        values = {key: value.strip().strip('"') for key, value in parser.items(section)}
        values["section"] = section
        presets.append(values)
    return presets


def installed_template_path(godot_bin: str) -> Path | None:
    executable = shutil.which(godot_bin)
    if not executable:
        return None
    completed = subprocess.run([godot_bin, "--version"], capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        return None
    parts = completed.stdout.strip().split(".")
    version = ".".join(parts[:3]) if len(parts) >= 3 else completed.stdout.strip()
    candidates = [
        Path.home() / "Library/Application Support/Godot/export_templates" / version,
        Path.home() / ".local/share/godot/export_templates" / version,
        Path.home() / ".godot/export_templates" / version,
    ]
    if os.environ.get("APPDATA"):
        candidates.append(Path(os.environ["APPDATA"]) / "Godot/export_templates" / version)
    return next((path for path in candidates if path.is_dir()), None)


def preflight(
    project_path: Path,
    preset_name: str,
    output_path: Path,
    mode: str,
    patches: list[Path],
    godot_bin: str,
) -> dict:
    errors: list[str] = []
    warnings: list[str] = []
    presets = parse_presets(project_path)
    preset = next((item for item in presets if item.get("name") == preset_name), None)
    if not (project_path / "export_presets.cfg").is_file():
        errors.append("export_presets.cfg is missing")
    elif preset is None:
        errors.append(f"Export preset does not exist: {preset_name}")

    platform_name = preset.get("platform", "") if preset else ""
    if not shutil.which(godot_bin):
        errors.append(f"Godot executable was not found: {godot_bin}")
    templates = installed_template_path(godot_bin)
    if templates is None:
        if mode in {"pack", "patch"}:
            warnings.append("Matching Godot export templates were not found (not required for pack/patch data exports)")
        else:
            errors.append("Matching Godot export templates were not found")

    if mode == "patch" and not patches:
        errors.append("Patch mode requires at least one --patches base artifact")
    if mode != "patch" and patches:
        errors.append("--patches can only be used with --mode patch")
    for patch_path in patches:
        if not patch_path.is_file():
            errors.append(f"Patch base artifact does not exist: {patch_path}")

    expected_extensions = PLATFORM_EXTENSIONS.get(platform_name)
    if mode in {"pack", "patch"}:
        expected_extensions = {".pck", ".zip"}
    if expected_extensions and output_path.suffix.lower() not in expected_extensions:
        warnings.append(
            f"Output extension {output_path.suffix or '<none>'} is unusual for {platform_name or mode}; "
            f"expected one of {sorted(expected_extensions)}"
        )

    host = platform.system()
    if platform_name in {"iOS", "VisionOS"} and (host != "Darwin" or not shutil.which("xcodebuild")):
        errors.append(f"{platform_name} export requires macOS with Xcode")
    if platform_name == "macOS" and host != "Darwin":
        warnings.append("macOS signing and notarization require a macOS host")
    if platform_name == "Android" and not shutil.which("java"):
        errors.append("Android export requires a configured JDK")
    if platform_name in {"Windows Desktop", "Linux", "Linux/X11"} and "server" in preset_name.lower():
        warnings.append("Dedicated server presets should disable rendering and include the dedicated_server feature tag")
    if output_path.is_relative_to(project_path):
        warnings.append("Export output is inside the project tree; confirm it is excluded from source imports and version control")

    return {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "preset": preset or {},
        "available_presets": [item.get("name", "") for item in presets],
        "platform": platform_name,
        "export_templates": str(templates) if templates else "",
        "host": host,
    }


def emit(
    command: list[str],
    project_path: Path,
    preset_name: str,
    output_path: Path,
    mode: str,
    as_json: bool,
    preflight_result: dict,
) -> None:
    if as_json:
        print(
            json.dumps(
                {
                    "command": command,
                    "project_path": str(project_path),
                    "preset_name": preset_name,
                    "output_path": str(output_path),
                    "mode": mode,
                    "preflight": preflight_result,
                }
            )
        )
        return
    print(shlex.join(command))


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path, output_path = resolve_paths(args.project_path, args.output_path)
    patches = [Path(path).expanduser().resolve() for path in args.patches]
    command = build_command(
        godot_bin=args.godot_bin,
        mode=args.mode,
        project_path=project_path,
        preset_name=args.preset_name,
        output_path=output_path,
        patches=patches,
    )
    preflight_result = preflight(
        project_path,
        args.preset_name,
        output_path,
        args.mode,
        patches,
        args.godot_bin,
    )
    if args.preflight_only:
        emit(command, project_path, args.preset_name, output_path, args.mode, True, preflight_result)
        return 0 if preflight_result["ok"] else 1
    if args.dry_run:
        emit(command, project_path, args.preset_name, output_path, args.mode, args.json, preflight_result)
        return 1 if args.strict_preflight and not preflight_result["ok"] else 0
    if not args.skip_preflight and not preflight_result["ok"]:
        emit(command, project_path, args.preset_name, output_path, args.mode, True, preflight_result)
        return 1
    completed = subprocess.run(command, check=False)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
