#!/usr/bin/env python3
"""Tests for the Godot-free static linter (scripts/debug/lint_project.py).

The linter is the fast pass a weak model runs before touching Godot: it reports
Godot 3 API in a 4.x project, `:=` on values Godot cannot type, node paths that
do not exist in the scene the script is attached to, dead [connection] targets,
and missing res:// files.

Two properties matter more than coverage and are asserted here:

- **No false positives.** The unmodified fixture project must lint completely
  clean; a linter that cries wolf on working code is worse than none.
- **Every diagnostic carries a fix.** The message names the file and line, the
  suggested_fix names the exact replacement (and, for a broken node path, the
  children that *do* exist, which is what lets a model self-correct).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "tests/fixtures/minimal_project"
LINTER = REPO_ROOT / "skill/godot/scripts/debug/lint_project.py"
VALIDATOR = REPO_ROOT / "skill/godot/scripts/debug/validate_project.py"
RENAME_DOC = REPO_ROOT / "skill/godot/references/godot3_to_4.md"
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")

LEGACY_SCRIPT = """extends KinematicBody2D

onready var label = $Label

func _ready():
\tyield(get_tree(), "idle_frame")
\tvar speed = rand_range(1, 2)
\tconnect("pressed", self, "_on_pressed")
\trect_min_size = Vector2(4, 4)
\t# rand_range(0, 1) in a comment must not be reported
\tvar note = "onready var in a string must not be reported"
\tprint(label, speed, note)
"""

HUD_SCRIPT = """extends Control

@onready var missing: Label = $Panel/Missing
@onready var ghost: Label = %Ghost
@onready var title: Label = $Panel/Title

func _ready() -> void:
\tvar parsed := JSON.parse_string("{}")
\tvar ratio: float = 100.0
\tprint("%d%%" % ratio, missing, ghost, title, parsed)
"""

HUD_SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/hud.gd" id="1_h"]
[ext_resource type="Texture2D" path="res://art/missing.png" id="2_m"]

[node name="Hud" type="Control"]
script = ExtResource("1_h")

[node name="Panel" type="Panel" parent="."]

[node name="Title" type="Label" parent="Panel"]

[node name="Icon" type="TextureRect" parent="Panel"]
texture = ExtResource("2_m")

[connection signal="pressed" from="Panel" to="." method="_on_button_pressed"]
"""

INFERENCE_POSITIVES = """extends Node

var untyped_array = []
var loose: Array = []
var data: Dictionary = {}

func _untyped_helper():
\treturn 5

func demo() -> void:
\tvar a := $Node
\tvar b := %Unique
\tvar c := get_node("X")
\tvar d := get_node_or_null("X")
\tvar e := data.get("k")
\tvar f := preload("res://scripts/positives.gd").instantiate()
\tvar g := JSON.parse_string("{}")
\tvar h := null
\tvar i := untyped_array[0]
\tvar j := loose[1]
\tvar k := _untyped_helper()
\tvar l := Callable(self, "demo").call()
\tvar m := ResourceLoader.load("res://scripts/negatives.gd")
\tvar n := preload("res://scripts/negatives.gd")
\tprint(a, b, c, d, e, f, g, h, i, j, k, l, m, n)
"""

# Every line of this one is typed code Godot compiles clean. Each `var` here was a
# false positive at some point, so they stay as regressions.
INFERENCE_NEGATIVES = """extends Node

var corners: Array[Color] = [Color.RED, Color.BLUE]
var points: PackedVector2Array = PackedVector2Array()
var params: Dictionary = {}
var options: Dictionary = {}

func _normalize_res_path(value: Variant) -> String:
\treturn str(value)

func _sample_performance(frames: int) -> Dictionary:
\treturn {"frames": frames}

func demo(ts: Dictionary, editor: Node) -> void:
\tvar save_path := _normalize_res_path(params.get("save_path", "x"))
\tvar want_ascii := bool(options.get("ascii", false))
\tvar columns := clampi(int(options.get("ascii_width", 64)), 8, 400)
\tvar mode_name := "TERRAIN_MODE_" + str(ts.get("mode", "x")).to_upper()
\tvar performance := await _sample_performance(30)
\tvar best := corners[0]
\tvar point := points[0]
\tvar config := ConfigFile.new()
\tvar error := config.load("res://project.godot")
\tvar casted := (editor.get("name") as String)
\tvar chosen := "a" if want_ascii else "b"
\tvar flag := params.has("x") and options.has("y")
\tvar total := 1 + int(params.get("n", 0))
\tvar joined := str(columns) + "/" + str(best)
\tvar pct := columns % 4
\tvar made := Vector2(1, 2)
\tvar node_name := editor.name
\tvar saved := editor.save_scene("res://x.tscn")
\tvar maybe := _sample_performance(1) if want_ascii else null
\tprint(save_path, want_ascii, columns, mode_name, performance, best, point, config, error,
\t\tcasted, chosen, flag, total, joined, pct, made, node_name, saved, maybe)
"""

# --- fixtures taken from real Godot 4 projects ------------------------------
# Every construct below is code Godot 4.7 compiles with no diagnostic.
REAL_WORLD_SCRIPT = """extends Control

var params: Dictionary = {}

# pop-star-2 / menghuanxiyouv2: get_node() on ANOTHER node is not relative to
# the node this script is attached to, so it cannot be resolved from here.
func fill(slot: Node, dialogue: Node) -> void:
\tvar button: TextureButton = slot.get_node("ContinueButton")
\tvar body := dialogue.get_node("Body") as Label
\tvar icon: Node = _row().get_node("Icon")
\tprint(button, body, icon)

func _row() -> Node:
\treturn self

# task-bar-hero: the return type lives on the second physical line.
func _label(text_value: String, font_size: int, color: Color, title_font := false,
\talignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
\tvar label := Label.new()
\tlabel.text = text_value
\tlabel.add_theme_font_size_override("font_size", font_size)
\tlabel.add_theme_color_override("font_color", color)
\tlabel.horizontal_alignment = alignment
\treturn label if not title_font else label

func build() -> void:
\tvar title := _label("Hello", 19, Color("f3b552"), true)
\tvar result := DiagnosticsExporter.export(self)
\tvar legacy := LegacySystem.empty()
\tprint(title, result, legacy)
"""

# casualgame1: a project function named `export`. The Godot 3 form is a
# declaration prefix (`export(int) var hp`), never a call.
USER_EXPORT_SCRIPT = """class_name DiagnosticsExporter
extends RefCounted

static func export(game, content_validation: Dictionary = {}) -> Dictionary:
\treturn {"game": game, "checks": content_validation}
"""

# slgv1: a project static method named `empty`, called on a Capitalised type.
USER_EMPTY_SCRIPT = """class_name LegacySystem
extends RefCounted

static func empty() -> Dictionary:
\treturn {}
"""

REAL_WORLD_SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/real_world.gd" id="1_r"]

[node name="RealWorld" type="Control"]
script = ExtResource("1_r")
"""

# hax-maplestory: connections that target a C# handler.
CSHARP_SCRIPT = """using Godot;

public partial class Panel : Control
{
    private void OnPressed()
    {
        GD.Print("pressed");
    }
}
"""

CSHARP_SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://Panel.cs" id="1_cs"]

[node name="Panel" type="Control"]
script = ExtResource("1_cs")

[node name="Button" type="Button" parent="."]

[connection signal="pressed" from="Button" to="." method="OnPressed"]
"""

# The same rules, on the real Godot 3 constructs.
GENUINE_GODOT3_SCRIPT = """extends Control

export(int, 0, 10) var armor = 1

func _ready():
\tvar items = []
\tif items.empty():
\t\tpass
\tprint($Nope)
"""

GENUINE_GODOT3_SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/genuine.gd" id="1_g"]

[node name="Genuine" type="Control"]
script = ExtResource("1_g")
"""

# A parent scene that instances two sub-scenes. Both sub-scene scripts must be
# checked against their OWN tree, never the level's.
INSTANCED_FIXTURE = {
    "scripts/player_ref.gd": """extends CharacterBody2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = %Hitbox

func _ready() -> void:
\tprint(sprite, hitbox)
""",
    "scripts/dialog_ref.gd": """extends CanvasLayer

@onready var root_control: Control = %DialogRoot

func _ready() -> void:
\tprint(root_control)
""",
    "scenes/player_ref.tscn": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/player_ref.gd" id="1_p"]

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1_p")

[node name="Sprite2D" type="Sprite2D" parent="."]

[node name="Hitbox" type="Area2D" parent="." groups=["hurt", "player"]]
unique_name_in_owner = true
""",
    "scenes/dialog_ref.tscn": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/dialog_ref.gd" id="1_d"]

[node name="DialogBox" type="CanvasLayer"]
script = ExtResource("1_d")

[node name="DialogRoot" type="Control" parent="."]
unique_name_in_owner = true
""",
    "scenes/level_1.tscn": """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/player_ref.tscn" id="1_pl"]
[ext_resource type="PackedScene" path="res://scenes/dialog_ref.tscn" id="2_dl"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(400, 32)

[node name="Level1" type="Node2D"]

[node name="Ground" type="StaticBody2D" parent="."]

[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]
shape = SubResource("RectangleShape2D_1")

[node name="Player" parent="." instance=ExtResource("1_pl")]
position = Vector2(64, 64)

[node name="Sprite2D" parent="Player" index="0"]
modulate = Color(1, 0.5, 0.5, 1)

[node name="DialogBox" parent="." instance=ExtResource("2_dl")]
""",
}

# The scene each bundled template's header documents, transcribed from the
# "Expected scene tree" block at the top of the file.
TEMPLATE_SCENES = {
    "player_platformer_2d": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/player_platformer_2d.gd" id="1"]

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]

[node name="Sprite2D" type="Sprite2D" parent="."]
""",
    "player_topdown_2d": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/player_topdown_2d.gd" id="1"]

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]

[node name="Sprite2D" type="Sprite2D" parent="."]
""",
    "player_fps_3d": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/player_fps_3d.gd" id="1"]

[node name="Player" type="CharacterBody3D"]
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]

[node name="CameraPivot" type="Node3D" parent="."]

[node name="Camera3D" type="Camera3D" parent="CameraPivot"]
""",
    "enemy_patrol_2d": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/enemy_patrol_2d.gd" id="1"]

[node name="Enemy" type="CharacterBody2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]

[node name="Sprite2D" type="Sprite2D" parent="."]

[node name="EdgeCheck" type="RayCast2D" parent="."]

[node name="WallCheck" type="RayCast2D" parent="."]
""",
    "interactable": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/interactable.gd" id="1"]

[node name="Chest" type="Area2D" groups=["interactable"]]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]

[node name="Sprite2D" type="Sprite2D" parent="."]

[node name="Prompt" type="Label" parent="."]
""",
    "hud": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/hud.gd" id="1"]

[node name="HUD" type="CanvasLayer"]
script = ExtResource("1")

[node name="TopLeft" type="MarginContainer" parent="."]

[node name="Vitals" type="VBoxContainer" parent="TopLeft"]

[node name="HealthBar" type="ProgressBar" parent="TopLeft/Vitals"]
unique_name_in_owner = true

[node name="LivesLabel" type="Label" parent="TopLeft/Vitals"]
unique_name_in_owner = true

[node name="TopRight" type="MarginContainer" parent="."]

[node name="ScoreLabel" type="Label" parent="TopRight"]
unique_name_in_owner = true
""",
    "dialog_box": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/dialog_box.gd" id="1"]

[node name="DialogBox" type="CanvasLayer"]
script = ExtResource("1")

[node name="DialogRoot" type="Control" parent="."]
unique_name_in_owner = true

[node name="Anchor" type="MarginContainer" parent="DialogRoot"]

[node name="Box" type="PanelContainer" parent="DialogRoot/Anchor"]

[node name="Body" type="VBoxContainer" parent="DialogRoot/Anchor/Box"]

[node name="SpeakerLabel" type="Label" parent="DialogRoot/Anchor/Box/Body"]
unique_name_in_owner = true

[node name="BodyLabel" type="RichTextLabel" parent="DialogRoot/Anchor/Box/Body"]
unique_name_in_owner = true
""",
    "main_menu": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
script = ExtResource("1")

[node name="Center" type="CenterContainer" parent="."]

[node name="Buttons" type="VBoxContainer" parent="Center"]

[node name="NewGameButton" type="Button" parent="Center/Buttons"]
unique_name_in_owner = true

[node name="ContinueButton" type="Button" parent="Center/Buttons"]
unique_name_in_owner = true

[node name="SettingsButton" type="Button" parent="Center/Buttons"]
unique_name_in_owner = true

[node name="QuitButton" type="Button" parent="Center/Buttons"]
unique_name_in_owner = true
""",
    "pause_menu": """[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/pause_menu.gd" id="1"]

[node name="PauseMenu" type="CanvasLayer"]
script = ExtResource("1")

[node name="PauseRoot" type="Control" parent="."]
unique_name_in_owner = true

[node name="Dim" type="ColorRect" parent="PauseRoot"]

[node name="Center" type="CenterContainer" parent="PauseRoot"]

[node name="Dialog" type="PanelContainer" parent="PauseRoot/Center"]

[node name="Body" type="VBoxContainer" parent="PauseRoot/Center/Dialog"]

[node name="ResumeButton" type="Button" parent="PauseRoot/Center/Dialog/Body"]
unique_name_in_owner = true

[node name="QuitButton" type="Button" parent="PauseRoot/Center/Dialog/Body"]
unique_name_in_owner = true
""",
}

# A level that instances three of those scenes — the shape that used to make the
# linter check a sub-scene's script against the level's tree.
TEMPLATE_LEVEL = """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/player_platformer_2d.tscn" id="1"]
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="2"]
[ext_resource type="PackedScene" path="res://scenes/dialog_box.tscn" id="3"]

[node name="Level" type="Node2D"]

[node name="Ground" type="StaticBody2D" parent="."]

[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]

[node name="Player" parent="." instance=ExtResource("1")]

[node name="HUD" parent="." instance=ExtResource("2")]

[node name="DialogBox" parent="." instance=ExtResource("3")]
"""

WARNING_ONLY_SCRIPT = """extends Node

signal done

func _ready() -> void:
\temit_signal("done")
"""


def main() -> None:
    test_clean_fixture_has_zero_diagnostics()
    test_every_category_is_reported_with_file_line_and_fix()
    test_node_path_fix_lists_the_real_children()
    test_only_filter_and_path_filter()
    test_exit_codes()
    test_comments_and_strings_are_not_scanned()
    test_rule_table_and_doc_are_in_sync()
    test_the_skills_own_scripts_lint_clean()
    test_inference_classifies_the_outermost_expression()
    test_real_world_false_positives_stay_silent()
    test_instanced_subscenes_resolve_in_their_own_scene()
    test_bundled_templates_attach_cleanly()
    test_prefilter_never_hides_a_rule()
    test_validate_project_merges_lint_errors()
    print("All lint_project tests passed.")


# --- tests -----------------------------------------------------------------

def test_clean_fixture_has_zero_diagnostics() -> None:
    """No false positives on working Godot 4 code — the important guarantee."""
    with fixture_project() as project:
        report, code = lint(project)
        assert report["counts"] == {"total": 0, "errors": 0, "warnings": 0, "parse_errors": 0}, report
        assert report["ok"] is True, report
        assert code == 0, code
        assert report["scan_summary"]["gd"] == 2, report["scan_summary"]
        assert report["scan_summary"]["tscn"] == 3, report["scan_summary"]
        assert report["scan_summary"]["project_godot"] == 1, report["scan_summary"]


def test_every_category_is_reported_with_file_line_and_fix() -> None:
    with fixture_project() as project:
        broken_project(project)
        report, code = lint(project)
        assert code == 1, report
        assert report["ok"] is False, report
        for category in ("godot3_api", "inference", "node_ref", "unique_name",
                         "signal_target", "missing_resource"):
            assert report["categories"][category] >= 1, (category, report["categories"])
        for entry in report["diagnostics"]:
            assert entry["suggested_fix"].strip(), entry
            assert entry["file"], entry
            assert entry["line"], entry
            assert entry["severity"] in ("error", "warning"), entry

        # godot3_api: file + line + the exact 4.x replacement in the fix.
        rules = {entry["rule"]: entry for entry in report["diagnostics"]}
        for rule_id, needle in (("onready_var", "@onready"), ("yield_call", "await"),
                                ("rand_range", "randf_range"), ("connect_string", ".connect("),
                                ("rect_min_size", "custom_minimum_size"),
                                ("kinematicbody2d_class", "CharacterBody2D")):
            entry = rules[rule_id]
            assert entry["category"] == "godot3_api", entry
            assert needle in entry["suggested_fix"], entry
        assert rules["onready_var"]["file"] == "res://scripts/legacy.gd", rules["onready_var"]
        assert rules["onready_var"]["line"] == line_of(LEGACY_SCRIPT, "onready var label")
        assert rules["yield_call"]["line"] == line_of(LEGACY_SCRIPT, "yield(get_tree()")
        # The class rule fires in the script and in the scene that uses the type.
        assert rules["kinematicbody2d_class"]["file"] == "res://scripts/legacy.gd"

        # inference
        infer = rules["infer_json"]
        assert infer["category"] == "inference" and infer["severity"] == "error", infer
        assert infer["file"] == "res://scripts/hud.gd", infer
        assert infer["line"] == line_of(HUD_SCRIPT, "JSON.parse_string"), infer
        assert "var raw: Variant = JSON.parse_string(text)" in infer["suggested_fix"], infer
        assert "gdscript_conventions.md" in infer["suggested_fix"], infer

        # node_ref
        node_ref = rules["node_path_missing"]
        assert node_ref["file"] == "res://scripts/hud.gd", node_ref
        assert node_ref["line"] == line_of(HUD_SCRIPT, "$Panel/Missing"), node_ref
        assert "res://scenes/hud.tscn" in node_ref["message"], node_ref

        # unique_name
        unique = rules["unique_name_missing"]
        assert unique["category"] == "unique_name", unique
        assert unique["file"] == "res://scripts/hud.gd", unique
        assert unique["line"] == line_of(HUD_SCRIPT, "%Ghost"), unique
        assert "unique_name_in_owner = true" in unique["suggested_fix"], unique

        # signal_target: the connection names a method the script does not define.
        signal = rules["connection_method_missing"]
        assert signal["file"] == "res://scenes/hud.tscn", signal
        assert signal["line"] == line_of(HUD_SCENE, "[connection"), signal
        assert "_on_button_pressed" in signal["suggested_fix"], signal

        # missing_resource: the ext_resource and the autoload.
        ext = rules["missing_ext_resource"]
        assert ext["file"] == "res://scenes/hud.tscn", ext
        assert ext["line"] == line_of(HUD_SCENE, "missing.png"), ext
        autoload = rules["project_resource"]
        assert autoload["file"] == "res://project.godot", autoload
        assert "res://scripts/nope.gd" in autoload["message"], autoload


def test_node_path_fix_lists_the_real_children() -> None:
    """The fix must name the scene, the attaching node, and the existing children."""
    with fixture_project() as project:
        broken_project(project)
        report, _ = lint(project)
        entry = next(d for d in report["diagnostics"] if d["rule"] == "node_path_missing")
        fix = entry["suggested_fix"]
        assert "res://scenes/hud.tscn" in fix, fix
        assert "Panel has children: Title, Icon" in fix, fix
        assert "Missing" in fix, fix


def test_only_filter_and_path_filter() -> None:
    with fixture_project() as project:
        broken_project(project)
        report, _ = lint(project, "--only", "godot3_api")
        assert {d["category"] for d in report["diagnostics"]} == {"godot3_api"}, report
        report, _ = lint(project, "--only", "node_ref,unique_name")
        assert {d["category"] for d in report["diagnostics"]} == {"node_ref", "unique_name"}, report

        # --path restricts the walk; scenes/ diagnostics disappear.
        report, _ = lint(project, "--path", "scripts")
        files = {d["file"] for d in report["diagnostics"]}
        assert "res://scenes/hud.tscn" not in files, files
        assert "res://scripts/legacy.gd" in files, files

        bad = run([str(LINTER), str(project), "--only", "nope"])
        assert bad.returncode != 0 and "Valid categories" in bad.stderr, bad.stderr


def test_exit_codes() -> None:
    with fixture_project() as project:
        (project / "scripts/warner.gd").write_text(WARNING_ONLY_SCRIPT, encoding="utf-8")
        report, code = lint(project)
        assert code == 0 and report["ok"] is True, report
        assert report["counts"]["warnings"] == 1, report
        strict, strict_code = lint(project, "--warnings-as-errors")
        assert strict_code == 1 and strict["ok"] is False, strict


def test_comments_and_strings_are_not_scanned() -> None:
    """A `#` comment and a string literal must never trip a rule, and `%` as the
    modulo/format operator must never read as a %UniqueName reference."""
    with fixture_project() as project:
        broken_project(project)
        report, _ = lint(project)
        lines = {(d["file"], d["line"]) for d in report["diagnostics"]}
        commented = line_of(LEGACY_SCRIPT, "# rand_range(0, 1)")
        stringed = line_of(LEGACY_SCRIPT, "onready var in a string")
        assert ("res://scripts/legacy.gd", commented) not in lines, lines
        assert ("res://scripts/legacy.gd", stringed) not in lines, lines
        formatted = line_of(HUD_SCRIPT, '"%d%%" % ratio')
        assert ("res://scripts/hud.gd", formatted) not in lines, lines


def test_rule_table_and_doc_are_in_sync() -> None:
    """references/godot3_to_4.md is generated from the rule table — every rule's
    Godot 3 token has to be in it, or a model reading the doc misses the fix."""
    sys.path.insert(0, str(REPO_ROOT / "skill/godot/scripts/debug"))
    import lint_project  # noqa: E402

    doc = RENAME_DOC.read_text(encoding="utf-8")
    for rule in lint_project.GODOT3_RULES:
        assert rule["token"] in doc, f"{rule['id']}: token {rule['token']!r} missing from {RENAME_DOC}"
        assert rule["id"] in doc, f"{rule['id']} missing from {RENAME_DOC}"
    listed = run([str(LINTER), "--list-rules"])
    assert listed.returncode == 0, listed.stderr
    assert listed.stdout in doc, "godot3_to_4.md is stale: regenerate it from --list-rules"


def test_the_skills_own_scripts_lint_clean() -> None:
    """The bundled GDScript is the ground truth: Godot compiles all of it with
    zero errors and zero warnings, so the linter must report nothing on it.

    This is the false-positive gate. Every regression caught here so far came from
    a rule matching a token anywhere on the line instead of the expression that
    actually lands in the variable (`params.get()` nested inside a `-> String`
    call, `config.load()` mistaken for the global `load()`)."""
    with fixture_project() as project:
        shutil.copytree(REPO_ROOT / "skill/godot/scripts", project / "scripts", dirs_exist_ok=True)
        scripts = list((project / "scripts").rglob("*.gd"))
        assert len(scripts) > 30, f"expected the bundled GDScript, found {len(scripts)} files"
        report, code = lint(project)
        offenders = [d for d in report["diagnostics"]
                     if d["category"] in ("inference", "missing_resource")
                     or (d["category"] == "godot3_api" and d["severity"] == "error")]
        assert not offenders, "false positives on the skill's own scripts:\n" + "\n".join(
            f"  {d['rule']} {d['file']}:{d['line']} {d['message'][:90]}" for d in offenders[:20])
        assert report["counts"]["errors"] == 0, report["counts"]
        assert code == 0, code


def test_inference_classifies_the_outermost_expression() -> None:
    """Both directions of the `:=` analysis, in one project."""
    with fixture_project() as project:
        (project / "scripts/positives.gd").write_text(INFERENCE_POSITIVES, encoding="utf-8")
        (project / "scripts/negatives.gd").write_text(INFERENCE_NEGATIVES, encoding="utf-8")
        report, _ = lint(project, "--only", "inference")

        flagged = {(d["file"], d["line"]): d["rule"] for d in report["diagnostics"]}
        for needle, expected in (
                (":= $Node", "infer_dollar"),
                (":= %Unique", "infer_unique"),
                (':= get_node("X")', "infer_get_node"),
                (':= get_node_or_null("X")', "infer_get_node"),
                (':= data.get("k")', "infer_get"),
                (".instantiate()", "infer_instantiate"),
                (":= JSON.parse_string", "infer_json"),
                (":= null", "infer_null"),
                (":= untyped_array[0]", "infer_subscript"),
                (":= loose[1]", "infer_subscript"),
                (":= _untyped_helper()", "infer_untyped_call"),
                ('"demo").call()', "infer_call")):
            line = line_of(INFERENCE_POSITIVES, needle)
            key = ("res://scripts/positives.gd", line)
            assert flagged.get(key) == expected, (needle, line, flagged.get(key))

        # Severity is not cosmetic here. Verified on godot 4.7: `:= $Node`,
        # `%Unique`, `get_node()` and `.instantiate()` all COMPILE (they infer the
        # bare type Node, which is the risk), while `.get()`, an untyped subscript,
        # JSON.parse_string, null, `.call()` and a call into an untyped function are
        # hard parse errors. The message must not claim otherwise.
        by_rule = {d["rule"]: d for d in report["diagnostics"]}
        for rule_id in ("infer_dollar", "infer_unique", "infer_get_node", "infer_instantiate"):
            entry = by_rule[rule_id]
            assert entry["severity"] == "warning", entry
            assert "compiles" in entry["message"], entry
            assert "parse" not in entry["message"].split("compiles")[0], entry
        for rule_id in ("infer_get", "infer_subscript", "infer_json", "infer_null",
                        "infer_call", "infer_untyped_call"):
            entry = by_rule[rule_id]
            assert entry["severity"] == "error", entry
            assert "refuses to parse" in entry["message"], entry
        # load()/preload() infer Resource/PackedScene and are not reported at all.
        assert "infer_load" not in by_rule, by_rule.get("infer_load")

        # Nothing in negatives.gd may be reported — every line there is code Godot
        # types just fine, and each one is a false positive this linter shipped with.
        bad = [d for d in report["diagnostics"] if d["file"].endswith("negatives.gd")]
        assert not bad, "\n".join(f"{d['rule']} line {d['line']}" for d in bad)


def test_real_world_false_positives_stay_silent() -> None:
    """Cases taken from nine real Godot 4 projects that Godot compiles clean.

    Each one is a rule that used to match a token instead of the construct it is
    actually about: a call on another object, a user function that happens to be
    named `export`/`empty`, a signature that wraps onto a second line, a C#
    handler."""
    with fixture_project() as project:
        (project / "scripts/real_world.gd").write_text(REAL_WORLD_SCRIPT, encoding="utf-8")
        (project / "scripts/exporter.gd").write_text(USER_EXPORT_SCRIPT, encoding="utf-8")
        (project / "scripts/legacy_system.gd").write_text(USER_EMPTY_SCRIPT, encoding="utf-8")
        (project / "scenes/real_world.tscn").write_text(REAL_WORLD_SCENE, encoding="utf-8")
        (project / "Panel.cs").write_text(CSHARP_SCRIPT, encoding="utf-8")
        (project / "scenes/csharp.tscn").write_text(CSHARP_SCENE, encoding="utf-8")
        report, code = lint(project)
        assert not report["diagnostics"], "\n".join(
            f"  {d['rule']} {d['file']}:{d['line']} {d['message'][:100]}"
            for d in report["diagnostics"])
        assert code == 0, code

    # The same rules still fire on the real Godot 3 constructs, in a project that
    # does not define `export`/`empty` itself.
    with fixture_project() as project:
        (project / "scripts/genuine.gd").write_text(GENUINE_GODOT3_SCRIPT, encoding="utf-8")
        (project / "scenes/genuine.tscn").write_text(GENUINE_GODOT3_SCENE, encoding="utf-8")
        report, code = lint(project, "--only", "godot3_api,node_ref")
        rules = {d["rule"] for d in report["diagnostics"]}
        assert {"export_hint", "empty_call", "node_path_missing"} <= rules, rules
        assert code == 1, code


def test_instanced_subscenes_resolve_in_their_own_scene() -> None:
    """A `[node ... instance=ExtResource(...)]` is another scene's root.

    Its script's `$Path` and `%Name` resolve against that scene's tree and owner,
    so the parent must not check them against its own — and a `groups=["a","b"]`
    attribute must not derail the [node] parser, which used to charge every
    property line under it (`script =`, `unique_name_in_owner =`) to the
    previous node."""
    with fixture_project() as project:
        for name, text in INSTANCED_FIXTURE.items():
            (project / name).write_text(text, encoding="utf-8")
        report, code = lint(project, "--only", "node_ref,unique_name")
        assert not report["diagnostics"], "\n".join(
            f"  {d['rule']} {d['file']}:{d['line']} {d['message'][:120]}"
            for d in report["diagnostics"])
        assert code == 0, code

        # A path that really is missing is still reported — against the sub-scene
        # that attaches the script, not the level that instances it.
        player = project / "scripts/player_ref.gd"
        player.write_text(player.read_text(encoding="utf-8")
                          + "\n@onready var gone: Node = $Missing\n", encoding="utf-8")
        report, code = lint(project, "--only", "node_ref")
        assert len(report["diagnostics"]) == 1, report["diagnostics"]
        entry = report["diagnostics"][0]
        assert entry["file"] == "res://scripts/player_ref.gd", entry
        assert "res://scenes/player_ref.tscn" in entry["message"], entry
        assert code == 1, code


def test_bundled_templates_attach_cleanly() -> None:
    """Every templates/gdscript file that uses `$`/`%`, attached to the scene its
    own header documents, plus a level that instances three of them."""
    with fixture_project() as project:
        source = REPO_ROOT / "skill/godot/templates/gdscript"
        for name in TEMPLATE_SCENES:
            shutil.copy(source / f"{name}.gd", project / "scripts" / f"{name}.gd")
        for name, text in TEMPLATE_SCENES.items():
            (project / "scenes" / f"{name}.tscn").write_text(text, encoding="utf-8")
        (project / "scenes/template_level.tscn").write_text(TEMPLATE_LEVEL, encoding="utf-8")
        report, code = lint(project)
        offenders = [d for d in report["diagnostics"]
                     if d["category"] in ("node_ref", "unique_name")]
        assert not offenders, "\n".join(
            f"  {d['rule']} {d['file']}:{d['line']} {d['message'][:120]}" for d in offenders)
        assert report["scan_summary"]["scene_script_pairs"] >= len(TEMPLATE_SCENES), \
            report["scan_summary"]
        assert code == 0, [d["rule"] for d in report["diagnostics"]]


def test_prefilter_never_hides_a_rule() -> None:
    """The literal-word prefilter must be a pure speed-up, never a filter.

    It exists because running ~90 regexes on every line of a 30k-line project
    costs a second; it works by testing one alternation of the literal words the
    patterns require. Get that word list wrong — `\\bemit_signal` reads as the
    core "bemit_signal" if escape sequences are not stripped first — and rules go
    quietly dead. So: run every project fixture with the prefilter and with it
    forced open, and diff."""
    sys.path.insert(0, str(REPO_ROOT / "skill/godot/scripts/debug"))
    import lint_project  # noqa: E402

    class _AlwaysMatches:
        @staticmethod
        def search(_text: str) -> bool:
            return True

    def fingerprint(path: Path) -> list[tuple]:
        report = lint_project.lint_project(path)
        return sorted((d["rule"], d["file"], d["line"]) for d in report["diagnostics"])

    with fixture_project() as project:
        broken_project(project)
        (project / "scripts/positives.gd").write_text(INFERENCE_POSITIVES, encoding="utf-8")
        (project / "scripts/negatives.gd").write_text(INFERENCE_NEGATIVES, encoding="utf-8")
        (project / "scripts/genuine.gd").write_text(GENUINE_GODOT3_SCRIPT, encoding="utf-8")
        (project / "scenes/genuine.tscn").write_text(GENUINE_GODOT3_SCENE, encoding="utf-8")
        for name, text in INSTANCED_FIXTURE.items():
            (project / name).write_text(text, encoding="utf-8")

        fast = fingerprint(project)
        saved = (lint_project._GD_ANY, lint_project._SCENE_ANY)
        lint_project._GD_ANY = lint_project._SCENE_ANY = _AlwaysMatches
        try:
            complete = fingerprint(project)
        finally:
            lint_project._GD_ANY, lint_project._SCENE_ANY = saved
        assert fast == complete, (
            "the prefilter hid these: " + str([k for k in complete if k not in fast][:10]))
        assert fast, "the fixture must produce diagnostics for this to prove anything"
        # And every rule really does have a literal anchor to filter on.
        assert not lint_project._GD_ALWAYS and not lint_project._SCENE_ALWAYS, (
            "rules with no literal core are evaluated on every line: "
            + str([r["id"] for r in lint_project._GD_ALWAYS + lint_project._SCENE_ALWAYS]))


def test_validate_project_merges_lint_errors() -> None:
    if shutil.which(GODOT_BIN) is None:
        print("SKIP test_validate_project_merges_lint_errors (no godot)")
        return
    with fixture_project() as project:
        broken_project(project)
        result = run(["python3", str(VALIDATOR), str(project)])
        report = json.loads(result.stdout)
        assert report["ok"] is False, report
        assert result.returncode == 1, result.returncode
        assert report["lint"]["ran"] is True, report["lint"]
        lint_entries = [d for d in report["diagnostics"] if d.get("source") == "lint"]
        assert lint_entries, report["diagnostics"]
        categories = {d["category"] for d in lint_entries}
        assert {"godot3_api", "node_ref", "unique_name"} <= categories, categories
        assert report["counts"]["errors"] >= report["lint"]["counts"]["errors"], report["counts"]
        # Every lint entry keeps the parser's diagnostic shape so the two merge.
        for entry in lint_entries:
            assert set(("severity", "category", "message", "file", "line", "suggested_fix")) <= set(entry)

        # --no-lint drops the pass entirely.
        plain = json.loads(run(["python3", str(VALIDATOR), str(project), "--no-lint"]).stdout)
        assert plain["lint"] == {"ran": False}, plain["lint"]
        assert not [d for d in plain["diagnostics"] if d.get("source") == "lint"], plain


# --- helpers ---------------------------------------------------------------

class fixture_project:
    def __enter__(self) -> Path:
        self.root = Path(tempfile.mkdtemp(prefix="godot-skill-lint-"))
        self.project = self.root / "project"
        shutil.copytree(FIXTURE_ROOT, self.project)
        return self.project

    def __exit__(self, *_: object) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


def broken_project(project: Path) -> None:
    """Add one instance of every failure class the linter is supposed to catch."""
    (project / "scripts/legacy.gd").write_text(LEGACY_SCRIPT, encoding="utf-8")
    (project / "scripts/hud.gd").write_text(HUD_SCRIPT, encoding="utf-8")
    (project / "scenes/hud.tscn").write_text(HUD_SCENE, encoding="utf-8")
    settings = (project / "project.godot").read_text(encoding="utf-8")
    (project / "project.godot").write_text(
        settings + '\n[autoload]\n\nGameState="*res://scripts/nope.gd"\n', encoding="utf-8")


def line_of(text: str, needle: str) -> int:
    for number, line in enumerate(text.splitlines(), start=1):
        if needle in line:
            return number
    raise AssertionError(f"{needle!r} not found in fixture text")


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    if command and command[0] == str(LINTER):
        command = ["python3", *command]
    return subprocess.run(command, capture_output=True, text=True, check=False, timeout=300)


def lint(project: Path, *extra: str) -> tuple[dict, int]:
    result = run(["python3", str(LINTER), str(project), *extra])
    assert result.stdout.strip(), result.stderr
    return json.loads(result.stdout), result.returncode


if __name__ == "__main__":
    main()
