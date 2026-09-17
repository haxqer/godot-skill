#!/usr/bin/env python3
"""Tests for the `help` operation — the skill's self-description.

`help` exists so a caller can ask the dispatcher what it supports instead of
reading the whole reference and guessing parameter names. That is only worth
anything if it cannot drift:

- the operation list is read out of dispatcher.gd's own match arms, so this test
  re-derives the same list with an independent regex and asserts set equality;
- every entry carries a curated `params` schema — only the keys that operation
  uses — and both it and the example are validated against the parameter keys the
  operation actually reads (`help '{"check_examples":true}'`), so a renamed
  parameter fails this suite instead of quietly teaching the next caller a dead key;
- an unknown operation or a misspelled key must name the nearest real ones and
  point at `help`, never just say "Unknown operation".

Needs a local `godot` CLI (GODOT_BIN or `godot` on PATH); skipped with a notice
otherwise.
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
DISPATCHER = SKILL_ROOT / "scripts/core/dispatcher.gd"
CATALOG = SKILL_ROOT / "scripts/core/op_examples.json"
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")
TEMP_ROOTS: list[Path] = []

# Independent of the GDScript: the same match arms, found by this test's own regex.
ARM_RE = re.compile(
    r'"([a-z_][a-z_0-9]*)"\s*:\s*[\r\n]+\s*return local_dir\.path_join\(\s*"([^"]+)"\s*\)'
)


def godot_available() -> bool:
    return shutil.which(GODOT_BIN) is not None


def fixture_copy() -> Path:
    root = Path(tempfile.mkdtemp(prefix="godot-help-test-"))
    TEMP_ROOTS.append(root)
    project = root / "project"
    shutil.copytree(FIXTURE_ROOT, project)
    return project


def scripts_copy() -> Path:
    """A throwaway copy of scripts/ so a test can mutate the catalog safely."""
    root = Path(tempfile.mkdtemp(prefix="godot-help-scripts-"))
    TEMP_ROOTS.append(root)
    shutil.copytree(SKILL_ROOT / "scripts", root / "scripts")
    return root / "scripts"


def dispatch(project: Path, operation: str, params: dict,
             dispatcher: Path = DISPATCHER) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [GODOT_BIN, "--headless", "--path", str(project), "--script", str(dispatcher),
         operation, json.dumps(params, separators=(",", ":"))],
        capture_output=True, text=True, check=False, timeout=120, stdin=subprocess.DEVNULL,
    )


def payload_of(result: subprocess.CompletedProcess[str]) -> dict:
    for line in reversed(result.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise AssertionError(f"help printed no JSON payload.\n{result.stdout}\n{result.stderr}")


def dispatcher_arms() -> dict[str, str]:
    return dict(ARM_RE.findall(DISPATCHER.read_text(encoding="utf-8")))


# --- tests -----------------------------------------------------------------

def test_catalog_is_valid_json_with_the_documented_fields() -> None:
    """Pure-python guard: runs even without godot."""
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    for name, entry in catalog.items():
        if name.startswith("_"):
            continue
        assert isinstance(entry, dict), name
        for field in ("summary", "params", "example", "notes", "see"):
            assert field in entry, f"{name} is missing {field}"
        assert isinstance(entry["summary"], str) and entry["summary"], name
        assert isinstance(entry["example"], dict), name
        assert isinstance(entry["notes"], list) and entry["notes"], name
        assert isinstance(entry["see"], str) and entry["see"], name
        # The curated schema is the point of the op: never empty, always prose.
        assert isinstance(entry["params"], dict) and entry["params"], f"{name} has no params schema"
        for key, meaning in entry["params"].items():
            assert isinstance(meaning, str) and len(meaning) > 10, f"{name}.params.{key}"
            assert meaning.startswith("("), f"{name}.params.{key} must open with (required)/(default: X)"
        # Batch operations document each action entry; "@op" refers to another entry.
        for type_name, spec in entry.get("action_types", {}).items():
            if isinstance(spec, str):
                assert spec.startswith("@"), f"{name}.action_types.{type_name}"
                assert spec[1:] in catalog, f"{name}.action_types.{type_name} -> {spec}"
            else:
                assert isinstance(spec, dict) and spec, f"{name}.action_types.{type_name}"


def test_catalog_covers_every_dispatcher_arm() -> None:
    """Also pure-python, so a missing entry fails fast without a Godot run."""
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    documented = {name for name in catalog if not name.startswith("_")}
    assert documented == set(dispatcher_arms()), (
        f"catalog/dispatcher mismatch: missing {sorted(set(dispatcher_arms()) - documented)}, "
        f"stale {sorted(documented - set(dispatcher_arms()))}"
    )


def test_help_lists_every_operation() -> None:
    if not godot_available():
        print("SKIP test_help_lists_every_operation (no godot)")
        return
    result = dispatch(fixture_copy(), "help", {})
    assert result.returncode == 0, result.stdout + result.stderr
    payload = payload_of(result)
    listed = {entry["op"] for entry in payload["operations"]}
    assert listed == set(dispatcher_arms()), (
        f"help lists {sorted(listed)}, dispatcher.gd has {sorted(dispatcher_arms())}"
    )
    assert payload["count"] == len(listed), payload["count"]
    for entry in payload["operations"]:
        assert entry["summary"] and "no entry" not in entry["summary"], entry
    assert "dispatcher.gd" in payload["usage"], payload["usage"]


def test_help_for_one_operation_carries_params_example_and_command() -> None:
    if not godot_available():
        print("SKIP test_help_for_one_operation_carries_params_example_and_command (no godot)")
        return
    result = dispatch(fixture_copy(), "help", {"op": "scene_batch"})
    assert result.returncode == 0, result.stdout + result.stderr
    payload = payload_of(result)
    assert payload["op"] == "scene_batch"
    assert "actions" in payload["params"], payload["params"]
    assert "scene_path" in payload["params"], payload["params"]
    # Curated, not the derived superset, and required keys come first.
    assert len(payload["params"]) <= 12, payload["params"]
    assert "accepted_keys" not in payload, "the derived superset is verbose-only"
    required = [k for k, v in payload["params"].items() if v.startswith("(required")]
    assert list(payload["params"])[:len(required)] == required, payload["params"]
    # Each action entry is documented, resolved from the standalone operation.
    add_node = payload["action_types"]["add_node"]
    assert "node_type" in add_node and "parent_node_path" in add_node, add_node
    assert "scene_path" not in add_node, "the batch owns scene_path, not the action"
    assert payload["example"]["actions"], payload["example"]
    assert payload["example"]["scene_path"], payload["example"]
    assert payload["notes"], payload
    assert payload["see"], payload
    command = payload["command"]
    assert "dispatcher.gd" in command, command
    assert command.startswith("godot --headless --path "), command
    assert " scene_batch '" in command, command
    # The command must be runnable as printed: the inlined JSON is the example.
    inlined = json.loads(command[command.index(" scene_batch '") + len(" scene_batch '"):-1])
    assert inlined == payload["example"], inlined


def test_help_params_are_curated_not_the_derived_superset() -> None:
    """The whole point: a caller reads a short schema, not 150 helper keys."""
    if not godot_available():
        print("SKIP test_help_params_are_curated_not_the_derived_superset (no godot)")
        return
    plain = dispatch(fixture_copy(), "help", {"op": "add_node"})
    assert plain.returncode == 0, plain.stdout + plain.stderr
    params = payload_of(plain)["params"]
    assert isinstance(params, dict), params
    assert len(params) <= 12, f"{len(params)} keys is a wall of text: {sorted(params)}"
    for key in ("scene_path", "parent_node_path", "node_type", "node_name"):
        assert key in params, f"{key} missing from the add_node schema: {sorted(params)}"
    assert params["scene_path"].startswith("(required)"), params["scene_path"]
    assert params["parent_node_path"].startswith("(default: \"root\")"), params["parent_node_path"]
    assert list(params)[0] == "scene_path", list(params)

    verbose = dispatch(fixture_copy(), "help", {"op": "add_node", "verbose": True})
    payload = payload_of(verbose)
    accepted = payload["accepted_keys"]
    assert accepted == sorted(accepted), "accepted_keys must be sorted"
    assert len(accepted) > len(payload["params"]), "verbose adds the derived superset"
    assert set(payload["params"]) <= set(accepted), "every documented key must be accepted"


def test_help_text_format_is_readable_lines() -> None:
    if not godot_available():
        print("SKIP test_help_text_format_is_readable_lines (no godot)")
        return
    project = fixture_copy()
    listing = dispatch(project, "help", {"format": "text"})
    assert listing.returncode == 0, listing.stdout + listing.stderr
    body = listing.stdout
    assert "add_node" in body and "scene_batch" in body, body
    for name in dispatcher_arms():
        assert re.search(rf"^  {re.escape(name)}\s", body, re.M), f"{name} missing from the text listing"

    one = dispatch(project, "help", {"op": "add_node", "format": "text"})
    assert one.returncode == 0, one.stdout + one.stderr
    assert "op:      add_node" in one.stdout, one.stdout
    assert "command: godot --headless" in one.stdout, one.stdout
    assert "notes:" in one.stdout and "params:" in one.stdout, one.stdout
    assert "  scene_path — (required)" in one.stdout, one.stdout
    assert "accepted_keys" not in one.stdout, one.stdout

    loud = dispatch(project, "help", {"op": "add_node", "format": "text", "verbose": True})
    assert loud.returncode == 0, loud.stdout + loud.stderr
    assert "accepted_keys (" in loud.stdout, loud.stdout

    bad_format = dispatch(project, "help", {"format": "yaml"})
    assert bad_format.returncode == 1, bad_format.stdout + bad_format.stderr
    assert "use \"json\" (default) or \"text\"" in bad_format.stderr, bad_format.stderr


def test_help_for_an_unknown_operation_exits_one_and_suggests() -> None:
    if not godot_available():
        print("SKIP test_help_for_an_unknown_operation_exits_one_and_suggests (no godot)")
        return
    result = dispatch(fixture_copy(), "help", {"op": "add_nod"})
    assert result.returncode == 1, result.stdout + result.stderr
    assert 'unknown operation "add_nod"' in result.stderr, result.stderr
    assert "did you mean add_node" in result.stderr, result.stderr
    assert "help '{}'" in result.stderr, result.stderr


def test_check_examples_reports_no_failures() -> None:
    """The guard that keeps op_examples.json honest.

    Every example key is re-derived from the operation's own sources. If this
    fails, the example is wrong (or the parameter was renamed) — fix the catalog,
    do not relax the test.
    """
    if not godot_available():
        print("SKIP test_check_examples_reports_no_failures (no godot)")
        return
    result = dispatch(fixture_copy(), "help", {"check_examples": True})
    payload = payload_of(result)
    assert payload["failures"] == [], payload["failures"]
    assert result.returncode == 0, result.stdout + result.stderr
    assert payload["operations"] == len(dispatcher_arms()), payload
    # Only operations whose script is not installed yet may be skipped, and the
    # rest must actually have been checked.
    missing = [name for name, rel in dispatcher_arms().items()
               if not (DISPATCHER.parent / rel).resolve().exists()]
    assert sorted(payload["skipped"]) == sorted(missing), (payload["skipped"], missing)
    assert payload["checked"] == payload["operations"] - len(payload["skipped"]), payload


def test_check_examples_fails_loudly_on_a_bad_key() -> None:
    """A drifted example must exit 1 and name the key, not pass quietly."""
    if not godot_available():
        print("SKIP test_check_examples_fails_loudly_on_a_bad_key (no godot)")
        return
    scripts = scripts_copy()
    catalog = json.loads((scripts / "core/op_examples.json").read_text(encoding="utf-8"))
    catalog["add_node"]["example"] = {"scene_path": "scenes/main.tscn", "parent_path": "root"}
    (scripts / "core/op_examples.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")

    result = dispatch(fixture_copy(), "help", {"check_examples": True},
                      dispatcher=scripts / "core/dispatcher.gd")
    assert result.returncode == 1, result.stdout + result.stderr
    payload = payload_of(result)
    assert payload["failures"], payload
    failure = payload["failures"][0]
    assert failure["op"] == "add_node" and failure["key"] == "parent_path", failure
    assert "parent_node_path" in failure["suggestions"], failure
    assert "which add_node never reads" in result.stderr, result.stderr
    assert "op_examples.json" in result.stderr, result.stderr


def test_unknown_dispatcher_operation_suggests_neighbours() -> None:
    """The dispatcher's own error had no way out of it: no names, no next step."""
    if not godot_available():
        print("SKIP test_unknown_dispatcher_operation_suggests_neighbours (no godot)")
        return
    result = dispatch(fixture_copy(), "scene_bacth", {"scene_path": "scenes/card.tscn"})
    assert result.returncode == 1, result.stdout + result.stderr
    assert "Unknown operation: scene_bacth" in result.stderr, result.stderr
    assert "did you mean scene_batch" in result.stderr, result.stderr
    assert "Run: help '{}' to list operations" in result.stderr, result.stderr


def test_unknown_parameter_error_points_at_help() -> None:
    if not godot_available():
        print("SKIP test_unknown_parameter_error_points_at_help (no godot)")
        return
    result = dispatch(fixture_copy(), "add_node", {
        "scene_path": "scenes/card.tscn", "parent_path": "root",
        "node_type": "Node2D", "node_name": "N"})
    assert result.returncode == 1, result.stdout + result.stderr
    assert "did you mean parent_node_path" in result.stderr, result.stderr
    assert "help '{\"op\":\"add_node\"}'" in result.stderr, result.stderr


def test_help_rejects_an_unknown_parameter_of_its_own() -> None:
    if not godot_available():
        print("SKIP test_help_rejects_an_unknown_parameter_of_its_own (no godot)")
        return
    result = dispatch(fixture_copy(), "help", {"operation": "add_node"})
    assert result.returncode == 1, result.stdout + result.stderr
    assert "Unknown parameter for help: operation" in result.stderr, result.stderr


def cleanup() -> None:
    while TEMP_ROOTS:
        shutil.rmtree(TEMP_ROOTS.pop(), ignore_errors=True)


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    try:
        for test in tests:
            test()
        suffix = "" if godot_available() else " (godot-dependent tests skipped)"
        print(f"All {len(tests)} help-operation tests passed{suffix}.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()
