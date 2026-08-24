#!/usr/bin/env python3
"""Unit tests for the Godot log parser.

Pure Python: these run without a Godot install. The sample logs below are the
verbatim output captured from ``godot 4.7.stable`` for each error shape.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PARSER_DIR = REPO_ROOT / "skill/godot/scripts/debug"
sys.path.insert(0, str(PARSER_DIR))

from godot_log_parser import parse_log  # noqa: E402


RUNTIME_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

SCRIPT ERROR: Invalid access to property or key 'position' on a base object of type 'null instance'.
          at: _ready (res://scripts/main.gd:4)
          GDScript backtrace (most recent call first):
              [0] _ready (res://scripts/main.gd:4)
"""

USER_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

ERROR: custom boom happened
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] _ready (res://scripts/main.gd:3)
WARNING: this is a warning
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] _ready (res://scripts/main.gd:4)
"""

PARSE_LOG = """Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

SCRIPT ERROR: Parse Error: Identifier "undeclared_identifier" not declared in the current scope.
          at: GDScript::reload (res://scripts/main.gd:3)
SCRIPT ERROR: Parse Error: Function "call_missing_func()" not found in base self.
          at: GDScript::reload (res://scripts/main.gd:4)
ERROR: Failed to load script "res://scripts/main.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
"""

# Deeper backtrace: the crash site is the top ([0]) frame; the SCRIPT ERROR at:
# line already points there. Exercises multi-frame stack capture.
NESTED_LOG = """SCRIPT ERROR: Invalid call. Nonexistent function 'jump' in base 'Node2D (player.gd)'.
          at: _do (res://scripts/player.gd:20)
          GDScript backtrace (most recent call first):
              [0] _do (res://scripts/player.gd:20)
              [1] _ready (res://scripts/player.gd:8)
"""


def _only(report):
    assert len(report["diagnostics"]) == 1, report
    return report["diagnostics"][0]


def test_runtime_script_error():
    report = parse_log(RUNTIME_LOG)
    diag = _only(report)
    assert diag["severity"] == "script_error"
    assert diag["category"] == "null_reference"
    assert diag["file"] == "res://scripts/main.gd"
    assert diag["line"] == 4
    assert diag["function"] == "_ready"
    assert diag["stack"] == [{"function": "_ready", "file": "res://scripts/main.gd", "line": 4}]
    assert report["counts"] == {"total": 1, "errors": 1, "parse_errors": 0, "warnings": 0}


def test_push_error_uses_backtrace_location_not_cpp():
    # push_error's `at:` points at engine C++; the real location is backtrace [0].
    report = parse_log(USER_LOG)
    errors = [d for d in report["diagnostics"] if d["severity"] == "error"]
    warnings = [d for d in report["diagnostics"] if d["severity"] == "warning"]
    assert len(errors) == 1 and len(warnings) == 1
    err = errors[0]
    assert err["message"] == "custom boom happened"
    assert err["file"] == "res://scripts/main.gd"
    assert err["line"] == 3
    assert err["function"] == "_ready"
    warn = warnings[0]
    assert warn["file"] == "res://scripts/main.gd"
    assert warn["line"] == 4


def test_warnings_can_be_excluded():
    report = parse_log(USER_LOG, include_warnings=False)
    assert all(d["severity"] != "warning" for d in report["diagnostics"])
    assert report["counts"]["warnings"] == 0
    assert report["counts"]["errors"] == 1


def test_parse_errors():
    report = parse_log(PARSE_LOG)
    parse_errors = [d for d in report["diagnostics"] if d["severity"] == "parse_error"]
    assert len(parse_errors) == 2
    by_line = {d["line"]: d for d in parse_errors}
    assert by_line[3]["category"] == "undeclared_identifier"
    assert by_line[3]["file"] == "res://scripts/main.gd"
    assert "Parse Error:" not in by_line[3]["message"]  # prefix stripped into message body
    assert by_line[4]["category"] == "missing_method"
    # The follow-on "Failed to load script" is captured as an error.
    assert any(d["category"] == "resource_load" for d in report["diagnostics"])
    assert report["counts"]["parse_errors"] == 2


def test_nested_backtrace_frames_captured():
    report = parse_log(NESTED_LOG)
    diag = _only(report)
    assert diag["category"] == "missing_method"
    assert diag["file"] == "res://scripts/player.gd"
    assert diag["line"] == 20
    assert len(diag["stack"]) == 2
    assert diag["stack"][1] == {"function": "_ready", "file": "res://scripts/player.gd", "line": 8}


def test_clean_log_has_no_diagnostics():
    clean = (
        "Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org\n\n"
        "clean boot ok\n"
    )
    report = parse_log(clean)
    assert report["diagnostics"] == []
    assert report["counts"]["total"] == 0


def test_duplicate_errors_are_collapsed_with_count():
    doubled = RUNTIME_LOG + "\n" + RUNTIME_LOG.split("\n", 2)[2]
    report = parse_log(doubled)
    diag = _only(report)
    assert diag["occurrences"] == 2


def test_diagnostics_sorted_most_severe_first():
    report = parse_log(PARSE_LOG + USER_LOG)
    severities = [d["severity"] for d in report["diagnostics"]]
    # parse_error (0) and script/error (1-2) before warning (3)
    assert severities.index("parse_error") < severities.index("warning")


def test_unknown_message_still_reports_location_and_fallback_fix():
    log = (
        "SCRIPT ERROR: Something totally novel happened.\n"
        "          at: _ready (res://a.gd:9)\n"
    )
    diag = _only(parse_log(log))
    assert diag["category"] == "unknown"
    assert diag["file"] == "res://a.gd" and diag["line"] == 9
    assert diag["suggested_fix"]


def test_resource_loader_message_carries_its_own_location():
    # The resource text loader leads with "res://file:line - " instead of using
    # an `at:` continuation, so the location has to come out of the message.
    log = (
        "ERROR: res://scenes/main.tscn:9 - Parse Error: [ext_resource] referenced "
        "non-existent resource at: res://art/missing.png.\n"
    )
    diag = _only(parse_log(log))
    assert diag["severity"] == "error"
    assert diag["file"] == "res://scenes/main.tscn" and diag["line"] == 9


def test_at_line_location_beats_a_location_inside_the_message():
    # A message may mention some other res:// path; the `at:` crash site wins.
    log = (
        "SCRIPT ERROR: res://other.gd:99 - mentioned in passing\n"
        "          at: _ready (res://scripts/main.gd:4)\n"
    )
    diag = _only(parse_log(log))
    assert diag["file"] == "res://scripts/main.gd" and diag["line"] == 4


def test_gdscript_warning_from_the_debugger_channel_parses():
    # What `-d --ignore-error-breaks` adds to the log: analyzer warnings, each
    # attributed to GDScript::reload rather than a runtime function.
    log = (
        'WARNING: The local variable "unused_local" is declared but never used in '
        'the block. If this is intended, prefix it with an underscore: "_unused_local".\n'
        "     at: GDScript::reload (res://scripts/main.gd:6)\n"
        "WARNING: Integer division. Decimal part will be discarded.\n"
        "     at: GDScript::reload (res://scripts/main.gd:9)\n"
    )
    report = parse_log(log)
    assert report["counts"]["warnings"] == 2
    assert report["counts"]["errors"] == 0
    lines = [d["line"] for d in report["diagnostics"]]
    assert lines == [6, 9]
    # GDScript::reload is a synthetic frame, not a useful function name.
    assert all(d["function"] is None for d in report["diagnostics"])


def test_shader_error_is_attributed_via_the_compiling_marker():
    # Shader compile errors report a bare line with no path, so check_project
    # prints a marker naming the file it is about to compile.
    log = (
        "[INFO] Compiling shader: res://shaders/effect.gdshader\n"
        "--Main Shader--\n"
        'SHADER ERROR: Invalid arguments for the built-in function: "vec4(float,float,float)".\n'
        "          at: (null) (:4)\n"
    )
    diag = _only(parse_log(log))
    assert diag["severity"] == "shader_error"
    assert diag["file"] == "res://shaders/effect.gdshader" and diag["line"] == 4


def test_marker_does_not_leak_onto_unrelated_diagnostics():
    log = (
        "[INFO] Compiling shader: res://shaders/effect.gdshader\n"
        "SCRIPT ERROR: Parse Error: Identifier \"foo\" not declared in the current scope.\n"
        "          at: GDScript::reload (res://scripts/main.gd:3)\n"
    )
    diag = _only(parse_log(log))
    assert diag["file"] == "res://scripts/main.gd" and diag["line"] == 3


def test_invalid_scene_errors_are_categorised():
    # Printed by PackedScene.instantiate(); check_project's instantiate pass is
    # what makes them appear at all. The engine names the node, never the scene,
    # so `file` stays None — the scene path comes from check_project's JSON.
    log = (
        "ERROR: Invalid scene: root node Root cannot specify a parent node.\n"
        "   at: instantiate (scene/resources/packed_scene.cpp:221)\n"
        "ERROR: Invalid scene: node Child does not specify its parent node.\n"
        "   at: instantiate (scene/resources/packed_scene.cpp:209)\n"
    )
    report = parse_log(log)
    assert report["counts"]["errors"] == 2, report
    assert all(d["category"] == "scene_hierarchy" for d in report["diagnostics"]), report["diagnostics"]
    assert all(d["file"] is None for d in report["diagnostics"]), report["diagnostics"]
    assert "parent=" in report["diagnostics"][0]["suggested_fix"]


def test_vanished_parent_warning_is_attributed_to_its_scene():
    # This one names its scene inside the message and has no res:// location on
    # any continuation line, so the quoted path is the only thing to go on.
    log = (
        "WARNING: Parent path './VBox' for node 'Label' has vanished when "
        "instantiating: 'res://scenes/menu.tscn'.\n"
        "     at: instantiate (scene/resources/packed_scene.cpp:213)\n"
    )
    diag = _only(parse_log(log))
    assert diag["severity"] == "warning"
    assert diag["category"] == "scene_hierarchy"
    assert diag["file"] == "res://scenes/menu.tscn" and diag["line"] is None


def test_quoted_path_never_overrides_a_real_location():
    log = (
        "SCRIPT ERROR: something about 'res://scenes/other.tscn' went wrong\n"
        "          at: _ready (res://scripts/main.gd:4)\n"
    )
    diag = _only(parse_log(log))
    assert diag["file"] == "res://scripts/main.gd" and diag["line"] == 4


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"All {len(tests)} log parser tests passed.")


if __name__ == "__main__":
    main()
