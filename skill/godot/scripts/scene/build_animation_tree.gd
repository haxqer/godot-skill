class_name GodotSkillBuildAnimationTree
extends RefCounted

# Builds an AnimationNodeStateMachine on an AnimationTree node from a
# declarative states/transitions description. States reference clips that
# already exist on the linked AnimationPlayer (create them with
# build_animation first). For blend trees or blend spaces, assemble the
# tree_root with resource_batch call_method instead.

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    var states = params.get("states", [])
    if not (states is Array) or states.is_empty():
        utils_script.log_error("build_animation_tree requires a non-empty states array")
        return

    var editor = scene_editor_script.new()
    if not editor.open_existing_scene(params.get("scene_path", "")):
        return

    var tree_node := _resolve_or_create_tree(editor, params)
    if tree_node == null:
        editor.cleanup()
        return

    var machine := AnimationNodeStateMachine.new()
    var first_state := ""
    for raw_state in states:
        if not (raw_state is Dictionary):
            utils_script.log_error("states entries must be dictionaries")
            editor.cleanup()
            return
        var state = raw_state as Dictionary
        var state_name := str(state.get("name", "")).strip_edges()
        if state_name.is_empty():
            utils_script.log_error("states entries require name")
            editor.cleanup()
            return
        if first_state.is_empty():
            first_state = state_name
        var animation_node := AnimationNodeAnimation.new()
        animation_node.animation = StringName(str(state.get("animation", state_name)))
        var position := Vector2.ZERO
        var raw_position = state.get("position", {})
        if raw_position is Dictionary and not raw_position.is_empty():
            position = Vector2(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)))
        machine.add_node(StringName(state_name), animation_node, position)

    var has_start_transition := false
    var transitions = params.get("transitions", [])
    if not (transitions is Array):
        utils_script.log_error("build_animation_tree.transitions must be an array")
        editor.cleanup()
        return
    for raw_transition in transitions:
        if not (raw_transition is Dictionary):
            utils_script.log_error("transitions entries must be dictionaries")
            editor.cleanup()
            return
        var transition_params = raw_transition as Dictionary
        var from_state := str(transition_params.get("from", ""))
        var to_state := str(transition_params.get("to", ""))
        if from_state.is_empty() or to_state.is_empty():
            utils_script.log_error("transitions entries require from and to")
            editor.cleanup()
            return
        if from_state == "Start":
            has_start_transition = true
        var transition := _build_transition(transition_params)
        if transition == null:
            editor.cleanup()
            return
        machine.add_transition(StringName(from_state), StringName(to_state), transition)

    # Without a Start transition the machine never enters a state at runtime.
    if not has_start_transition and bool(params.get("auto_start", true)):
        machine.add_transition(StringName("Start"), StringName(first_state), AnimationNodeStateMachineTransition.new())

    var tree := tree_node as AnimationTree
    tree.tree_root = machine
    tree.anim_player = NodePath(str(params.get("anim_player", "../AnimationPlayer")))
    tree.active = bool(params.get("active", true))

    if not editor.save_scene(params.get("save_path", "")):
        editor.cleanup()
        return
    editor.cleanup()

    print(JSON.stringify({
        "ok": true,
        "scene_path": str(params.get("scene_path", "")),
        "tree_node_path": str(params.get("tree_node_path", "root/AnimationTree")),
        "state_count": states.size(),
        "transition_count": transitions.size() + (0 if has_start_transition or not bool(params.get("auto_start", true)) else 1)
    }))

func _resolve_or_create_tree(editor, params: Dictionary) -> Node:
    var tree_path := str(params.get("tree_node_path", "root/AnimationTree"))
    var relative_path := tree_path.trim_prefix("root/").trim_prefix("root")
    var tree_node: Node = editor.scene_root if relative_path.is_empty() else editor.scene_root.get_node_or_null(NodePath(relative_path))

    if tree_node == null:
        if not bool(params.get("create_tree_if_missing", true)):
            utils_script.log_error("AnimationTree not found: " + tree_path)
            return null
        var parent_path := relative_path.get_base_dir()
        var added: bool = editor.add_node({
            "parent_node_path": "root" if parent_path.is_empty() else "root/" + parent_path,
            "node_type": "AnimationTree",
            "node_name": relative_path.get_file()
        })
        if not added:
            return null
        tree_node = editor.scene_root.get_node_or_null(NodePath(relative_path))

    if not (tree_node is AnimationTree):
        utils_script.log_error("Node is not an AnimationTree: " + tree_path)
        return null
    return tree_node

func _build_transition(transition_params: Dictionary) -> AnimationNodeStateMachineTransition:
    var transition := AnimationNodeStateMachineTransition.new()
    if transition_params.has("xfade_time"):
        transition.xfade_time = float(transition_params.get("xfade_time"))
    if transition_params.has("advance_condition"):
        transition.advance_condition = StringName(str(transition_params.get("advance_condition")))
    if transition_params.has("advance_expression"):
        transition.advance_expression = str(transition_params.get("advance_expression"))
    if transition_params.has("advance_mode"):
        var mode_name := "ADVANCE_MODE_" + str(transition_params.get("advance_mode")).to_upper()
        if not ClassDB.class_get_integer_constant_list("AnimationNodeStateMachineTransition").has(mode_name):
            utils_script.log_error("Unknown advance_mode: " + str(transition_params.get("advance_mode")))
            return null
        transition.advance_mode = ClassDB.class_get_integer_constant("AnimationNodeStateMachineTransition", mode_name)
    if transition_params.has("switch_mode"):
        var switch_name := "SWITCH_MODE_" + str(transition_params.get("switch_mode")).to_upper()
        if not ClassDB.class_get_integer_constant_list("AnimationNodeStateMachineTransition").has(switch_name):
            utils_script.log_error("Unknown switch_mode: " + str(transition_params.get("switch_mode")))
            return null
        transition.switch_mode = ClassDB.class_get_integer_constant("AnimationNodeStateMachineTransition", switch_name)
    return transition
