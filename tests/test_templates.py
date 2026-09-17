#!/usr/bin/env python3
"""Regression tests for the copy-me GDScript templates and the playbooks.

The templates exist so a model never has to write a controller from memory, so
their whole value is that they are *known good*: every file must compile with
zero errors AND zero warnings under the same pass the skill tells callers to
run (``check_project`` with ``--debug --ignore-error-breaks``). A template that
ships a shadowed variable or an unused signal teaches the mistake it was meant
to prevent.

The playbooks are checked the same way for the thing a weak model does with
them: it copies a fenced block verbatim. So every ``json`` block, and every JSON
literal inside a ``bash`` dispatcher block, has to parse after the two absolute
path placeholders are substituted.

The Godot-dependent test is skipped with a notice when no ``godot`` CLI is
available (GODOT_BIN or ``godot`` on PATH); the document tests always run.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = REPO_ROOT / "skill/godot"
TEMPLATES_DIR = SKILL_ROOT / "templates/gdscript"
PLAYBOOKS = SKILL_ROOT / "references/playbooks.md"
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
DISPATCHER = SKILL_ROOT / "scripts/core/dispatcher.gd"
LOG_PARSER = SKILL_ROOT / "scripts/debug/godot_log_parser.py"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")

# The templates that are meant to be registered as autoloads. Their identifiers
# have to resolve at parse time or every UI template fails with
# `Identifier "GameManager" not declared in the current scope`.
AUTOLOADS = {
    "GameManager": "game_manager.gd",
    "SaveManager": "save_manager.gd",
    "SceneTransition": "scene_transition.gd",
    "AudioManager": "audio_manager.gd",
}

# audio_manager.gd warns (correctly) when the buses it wants are missing, so the
# check project gets the routing the playbooks tell callers to create first.
AUDIO_BUSES = {
    "buses": [
        {"name": "Master", "volume_db": 0.0},
        {"name": "Music", "send": "Master", "volume_db": -6.0},
        {"name": "SFX", "send": "Master", "volume_db": -3.0},
    ],
    "save_path": "audio/default_bus_layout.tres",
    "set_project_setting": True,
}

PLACEHOLDERS = {
    "/absolute/path/to/godot": str(SKILL_ROOT),
    "/absolute/path/to/project": "/tmp/example-project",
}


def godot_available() -> bool:
    return shutil.which(GODOT_BIN) is not None


def template_files() -> list[Path]:
    return sorted(TEMPLATES_DIR.glob("*.gd"))


# --- templates -------------------------------------------------------------

def test_templates_directory_holds_only_gd_files() -> None:
    stray = [p.name for p in TEMPLATES_DIR.iterdir() if p.suffix != ".gd"]
    assert not stray, f"templates/gdscript must contain only .gd files, found {stray}"
    assert len(template_files()) >= 20, template_files()


def test_every_template_compiles_with_zero_errors_and_zero_warnings() -> None:
    if not godot_available():
        print("SKIP test_every_template_compiles_with_zero_errors_and_zero_warnings (no godot)")
        return

    templates = template_files()
    with templates_project() as project:
        report, summary = check_subtree(project, "res://templates_check")

        assert summary["failed_count"] == 0, summary["failed"]
        assert summary["checked"] == len(templates), (summary["checked"], len(templates))

        offenders = [d for d in report["diagnostics"] if d["severity"] in ("error", "warning")]
        if offenders:
            for diagnostic in offenders:
                print("OFFENDING TEMPLATE: {file}:{line} [{severity}] {message}".format(
                    file=diagnostic.get("file") or "?",
                    line=diagnostic.get("line") or "?",
                    severity=diagnostic["severity"],
                    message=diagnostic["message"]))
        assert report["counts"]["errors"] == 0, report["counts"]
        assert report["counts"]["warnings"] == 0, report["counts"]
        assert report["counts"]["parse_errors"] == 0, report["counts"]


def test_class_name_templates_resolve_after_import() -> None:
    """A template that annotates another template's class_name must compile.

    hurtbox.gd says `var health: Health`, hitbox.gd says `signal hit(hurtbox:
    Hurtbox)`, hud.gd says `bind_health(health: Health)`. Those only resolve out
    of .godot/global_script_class_cache.cfg, which only `--import` writes.
    """
    if not godot_available():
        print("SKIP test_class_name_templates_resolve_after_import (no godot)")
        return

    declared = {}
    for path in template_files():
        match = re.search(r"^class_name (\w+)", path.read_text(encoding="utf-8"), re.M)
        if match:
            declared[match.group(1)] = path.name
    for expected in ("State", "StateMachine", "Health", "Hitbox", "Hurtbox", "ObjectPool", "Interactable"):
        assert expected in declared, (expected, declared)
    # No class_name may collide with an autoload singleton name — Godot rejects
    # that with `Class "X" hides an autoload singleton`.
    assert not (set(declared) & set(AUTOLOADS)), declared

    with templates_project() as project:
        cache = project / ".godot/global_script_class_cache.cfg"
        assert cache.exists(), "godot --import did not write the global class cache"
        cached = cache.read_text(encoding="utf-8")
        for class_name in declared:
            assert f'"{class_name}"' in cached, (class_name, cached[:400])


# --- playbooks -------------------------------------------------------------

def test_every_template_is_referenced_from_the_playbooks() -> None:
    text = PLAYBOOKS.read_text(encoding="utf-8")
    missing = [p.name for p in template_files() if f"templates/gdscript/{p.name}" not in text]
    assert not missing, f"templates not referenced from playbooks.md: {missing}"


def test_playbook_json_blocks_parse() -> None:
    failures = []
    for label, payload in playbook_json_payloads():
        try:
            json.loads(payload)
        except json.JSONDecodeError as error:
            failures.append(f"{label}: {error}\n{payload[:300]}")
    assert not failures, "\n\n".join(failures)


def test_playbook_bash_blocks_have_balanced_quotes() -> None:
    """Dispatcher JSON is passed as one single-quoted shell argument.

    An apostrophe anywhere in the block splits that argument, so the op receives
    truncated JSON. Catch it here rather than in a user's terminal.
    """
    for index, block in enumerate(fenced_blocks("bash")):
        assert block.count("'") % 2 == 0, f"bash block {index} has an unbalanced quote:\n{block[:300]}"


def test_playbook_internal_links_resolve() -> None:
    text = PLAYBOOKS.read_text(encoding="utf-8")
    anchors = set()
    for heading in re.findall(r"^#{2,3} (.+)$", text, re.M):
        slug = re.sub(r"[^a-z0-9 -]", "", heading.lower()).replace(" ", "-")
        anchors.add(slug)
    broken = [target for target in re.findall(r"\]\(#([a-z0-9-]+)\)", text) if target not in anchors]
    assert not broken, f"playbooks.md links to missing anchors: {broken}"


def test_playbook_routing_table_covers_every_playbook() -> None:
    text = PLAYBOOKS.read_text(encoding="utf-8")
    headings = re.findall(r"^## (\d+)\. ", text, re.M)
    assert len(headings) == 12, headings
    routing = text.split("## Driving Input In A Scenario")[0]
    for number in headings:
        assert f"[{number}." in routing, f"playbook {number} is missing from the routing table"


# --- helpers ---------------------------------------------------------------

def fenced_blocks(language: str) -> list[str]:
    text = PLAYBOOKS.read_text(encoding="utf-8")
    return [m.group(1) for m in re.finditer(rf"^```{language}\n(.*?)^```", text, re.S | re.M)]


def substitute(text: str) -> str:
    for placeholder, value in PLACEHOLDERS.items():
        text = text.replace(placeholder, value)
    return text


def playbook_json_payloads() -> list[tuple[str, str]]:
    """Every JSON a reader could copy: fenced ```json blocks plus the quoted
    JSON argument of every dispatcher call inside a ```bash block."""
    payloads = []
    for index, block in enumerate(fenced_blocks("json")):
        payloads.append((f"json block {index}", substitute(block)))
    for index, block in enumerate(fenced_blocks("bash")):
        parts = substitute(block).split("'")
        for position in range(1, len(parts), 2):
            candidate = parts[position].strip()
            if candidate.startswith("{") or candidate.startswith("["):
                payloads.append((f"bash block {index} argument {position // 2}", candidate))
    assert len(payloads) >= 30, f"only found {len(payloads)} JSON payloads in playbooks.md"
    return payloads


class templates_project:
    """A fixture-project copy with every template under templates_check/, the
    four autoloads registered, the audio buses created, and `--import` run."""

    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-templates-"))
        project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, project)

        check_dir = project / "templates_check"
        check_dir.mkdir()
        for template in template_files():
            shutil.copy(template, check_dir / template.name)

        settings = project / "project.godot"
        settings.write_text(
            settings.read_text(encoding="utf-8")
            + "\n[autoload]\n"
            + "".join(f'{name}="*res://templates_check/{file}"\n' for name, file in sorted(AUTOLOADS.items())),
            encoding="utf-8",
        )

        # Buses first: audio_manager.gd pushes a warning when they are missing,
        # and that warning would (correctly) fail the zero-warning assertion.
        dispatch(project, "setup_audio_buses", AUDIO_BUSES)
        # class_name templates only resolve out of the global class cache, and
        # a --script run never rebuilds it.
        subprocess.run([GODOT_BIN, "--headless", "--path", str(project), "--import"],
                       capture_output=True, text=True, check=False, timeout=180)
        self.project = project
        return project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def dispatch(project: Path, operation: str, params: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [GODOT_BIN, "--headless", "--path", str(project), "--script", str(DISPATCHER),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=180, stdin=subprocess.DEVNULL)


def check_subtree(project: Path, subtree: str) -> tuple[dict, dict]:
    """Run check_project with the debugger attached and parse the log.

    --debug --ignore-error-breaks is the whole point: without -d the engine
    emits no GDScript warnings at all, so a template full of them reads clean.
    """
    completed = subprocess.run(
        [GODOT_BIN, "--headless", "--debug", "--ignore-error-breaks", "--path", str(project),
         "--script", str(DISPATCHER), "check_project", json.dumps({"project_path": subtree})],
        capture_output=True, text=True, check=False, timeout=300, stdin=subprocess.DEVNULL)
    combined = completed.stdout + "\n" + completed.stderr

    parsed = subprocess.run(["python3", str(LOG_PARSER), "-"],
                            input=combined, capture_output=True, text=True, check=False)
    report = json.loads(parsed.stdout)

    summary = {}
    for line in reversed(completed.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            summary = json.loads(line)
            break
    assert summary, f"check_project printed no JSON summary:\n{combined[-2000:]}"
    return report, summary


def main() -> None:
    tests = [value for key, value in sorted(globals().items())
             if key.startswith("test_") and callable(value)]
    for test in tests:
        test()
    suffix = "" if godot_available() else " (godot-dependent tests skipped)"
    print(f"All {len(tests)} template tests passed{suffix}.")


if __name__ == "__main__":
    main()
