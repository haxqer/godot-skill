#!/usr/bin/env python3
"""Run a Godot 4.7 project headlessly and report the debugger's errors.

This is the "run the game and read the debugger" half of the diagnose-and-fix
loop. It launches the project for a bounded number of frames, captures the exact
stdout/stderr the Godot debugger prints (runtime script errors, engine errors,
push_error/push_warning, and boot-time parse errors), and returns them as
structured diagnostics via ``godot_log_parser`` so the caller can open each
``file:line`` and fix it, then re-run to confirm.

Design notes:

- It never passes ``-d``. The ``-d`` local debugger drops into an interactive
  ``debug>`` prompt that blocks forever on stdin under automation. Running
  without ``-d`` still prints full ``SCRIPT ERROR`` blocks with ``at:`` file:line
  and a GDScript backtrace, which is all we need.
- ``--quit-after`` bounds a clean run; a wall-clock ``--timeout`` is the safety
  net that also flags real hangs / infinite loops.
- Use ``--quit-after`` >= 2. A known engine quirk makes headless
  ``--quit`` / ``--quit-after 1`` fail resource import on a project's first run.

Example::

    python3 run_project.py /abs/path/to/project --quit-after 120 --timeout 60
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from godot_log_parser import parse_log  # noqa: E402


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a Godot project headlessly and report debugger errors as JSON."
    )
    parser.add_argument("project_path", help="Path to the Godot project directory")
    parser.add_argument(
        "scene",
        nargs="?",
        default=None,
        help="Optional scene to run (res://... or a path) instead of the main scene.",
    )
    parser.add_argument(
        "--quit-after",
        type=int,
        default=120,
        help="Quit after N frames/iterations (default: 120; use >= 2).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
        help="Hard wall-clock timeout in seconds before the process is killed (default: 60).",
    )
    parser.add_argument(
        "--no-headless",
        dest="headless",
        action="store_false",
        help="Run with a real window/audio instead of headless (default: headless).",
    )
    parser.add_argument(
        "--no-warnings",
        action="store_true",
        help="Drop warnings from the diagnostics report.",
    )
    parser.add_argument(
        "--godot-bin",
        default=os.environ.get("GODOT_BIN", "godot"),
        help="Godot executable to invoke (default: GODOT_BIN or godot).",
    )
    parser.add_argument(
        "--log-file",
        default=None,
        help="Also write the raw captured log to this path.",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Include the full raw log in the JSON output under 'raw_log'.",
    )
    parser.add_argument(
        "--extra-arg",
        action="append",
        default=[],
        dest="extra_args",
        help="Extra argument to pass through to Godot (repeatable).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the resolved command as JSON without running it.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print the JSON output.",
    )
    return parser.parse_args(argv)


def build_command(args: argparse.Namespace, project_path: Path) -> list[str]:
    command = [args.godot_bin]
    if args.headless:
        command.append("--headless")
    command += ["--path", str(project_path)]
    if args.quit_after and args.quit_after > 0:
        command += ["--quit-after", str(args.quit_after)]
    command += list(args.extra_args)
    if args.scene:
        command.append(args.scene)
    return command


def run(command: list[str], timeout: float) -> tuple[str, int, bool, float]:
    """Run the command, returning (output, exit_code, timed_out, elapsed).

    Uses a new process group so a hung Godot (and any child it spawned) can be
    killed as a group on timeout. stdin is /dev/null so nothing can block on it.
    """
    start = time.monotonic()
    try:
        proc = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit(
            json.dumps(
                {
                    "ok": False,
                    "error": f"Godot executable not found: {command[0]} ({exc}). "
                    "Install Godot 4.7 or set GODOT_BIN / --godot-bin.",
                }
            )
        )

    timed_out = False
    try:
        output, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        _kill_group(proc)
        try:
            output, _ = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            output = ""
    elapsed = time.monotonic() - start
    return output or "", proc.returncode if proc.returncode is not None else -1, timed_out, elapsed


def _kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            proc.kill()
        except ProcessLookupError:
            pass


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project_path = Path(args.project_path).expanduser().resolve()
    if not (project_path / "project.godot").is_file():
        print(
            json.dumps(
                {"ok": False, "error": f"Missing Godot project file: {project_path / 'project.godot'}"}
            )
        )
        return 2

    command = build_command(args, project_path)

    if args.dry_run:
        print(json.dumps({"command": command, "project_path": str(project_path)}))
        return 0

    output, exit_code, timed_out, elapsed = run(command, args.timeout)

    if args.log_file:
        log_path = Path(args.log_file).expanduser()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(output, encoding="utf-8")

    report = parse_log(output, include_warnings=not args.no_warnings)
    counts = report["counts"]
    ok = (not timed_out) and counts["errors"] == 0 and counts["parse_errors"] == 0

    result = {
        "ok": ok,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "elapsed_seconds": round(elapsed, 2),
        "command": command,
        "counts": counts,
        "diagnostics": report["diagnostics"],
    }
    if timed_out:
        result["note"] = (
            "Process exceeded the timeout and was killed. This usually means the project hung, "
            "blocked on input, or entered an infinite loop; the diagnostics below are from the "
            "partial output captured before the kill."
        )
    if args.log_file:
        result["log_file"] = str(Path(args.log_file).expanduser())
    if args.raw:
        result["raw_log"] = output

    print(json.dumps(result, indent=2 if args.pretty else None))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
