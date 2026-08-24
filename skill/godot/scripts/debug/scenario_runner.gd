#!/usr/bin/env -S godot --headless --script
extends SceneTree

var codec_script = preload("../core/variant_codec.gd")
var codec = codec_script.new()
var scenario: Dictionary = {}
var scene_root: Node
var assertion_results: Array = []
var screenshots: Array = []
var ui_reports: Array = []
var errors: Array[String] = []

const UI_FINDING_KINDS = ["zero_size", "offscreen", "overlap"]
# Controls whose only job is to fill an area behind their siblings. A backdrop
# that fully covers a sibling is a background layer, not a layout mistake.
const UI_BACKDROP_CLASSES = ["ColorRect", "Panel", "TextureRect", "NinePatchRect", "ReferenceRect"]

const MONITORS = {
    "fps": Performance.TIME_FPS,
    "process_time": Performance.TIME_PROCESS,
    "physics_process_time": Performance.TIME_PHYSICS_PROCESS,
    "static_memory": Performance.MEMORY_STATIC,
    "node_count": Performance.OBJECT_NODE_COUNT,
    "resource_count": Performance.OBJECT_RESOURCE_COUNT,
    "draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
    "primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
    "video_memory": Performance.RENDER_VIDEO_MEM_USED
}

func _init() -> void:
    var args := OS.get_cmdline_args()
    var script_index := args.find("--script")
    var scenario_index := script_index + 2
    if script_index < 0 or scenario_index >= args.size():
        printerr("scenario_runner requires a scenario JSON file path")
        quit(2)
        return
    var file := FileAccess.open(args[scenario_index], FileAccess.READ)
    if file == null:
        printerr("Cannot open scenario file: " + args[scenario_index])
        quit(2)
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        printerr("Scenario file must contain a JSON object")
        quit(2)
        return
    scenario = parsed
    call_deferred("_run")

func _run() -> void:
    var scene_path := _normalize_res_path(scenario.get("scene_path", ""))
    var packed = load(scene_path)
    if not (packed is PackedScene):
        _fail("Failed to load scene: " + scene_path)
        _finish({})
        return
    scene_root = packed.instantiate()
    if scene_root == null:
        _fail("Failed to instantiate scene: " + scene_path)
        _finish({})
        return

    # A headless run opens a 64x64 window, so anchors, container layout and
    # viewport-space input coordinates would resolve against a viewport no
    # player ever sees. Always size the root: the scenario's viewport_size when
    # given, otherwise the project's own configured resolution.
    var viewport_size = scenario.get("viewport_size", {})
    if not (viewport_size is Dictionary):
        viewport_size = {}
    root.size = Vector2i(
        int(viewport_size.get("width", ProjectSettings.get_setting("display/window/size/viewport_width", 1152))),
        int(viewport_size.get("height", ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
    )
    root.add_child(scene_root)
    current_scene = scene_root
    print("[SCENARIO] Loaded " + scene_path)

    await _wait_frames(max(int(scenario.get("settle_frames", 2)), 1))
    var steps = scenario.get("steps", [])
    if not (steps is Array):
        _fail("steps must be an array")
    else:
        for index in range(steps.size()):
            if not (steps[index] is Dictionary):
                _fail("Step %d must be a dictionary" % index)
                break
            if not await _run_step(steps[index], index):
                break

    var assertions = scenario.get("assertions", [])
    if assertions is Array:
        for index in range(assertions.size()):
            if assertions[index] is Dictionary:
                _run_assertion(assertions[index], "assertions[%d]" % index)
            else:
                _fail("Assertion %d must be a dictionary" % index)
    else:
        _fail("assertions must be an array")

    var performance := await _sample_performance(max(int(scenario.get("performance_frames", 1)), 1))
    _finish(performance)

func _run_step(step: Dictionary, index: int) -> bool:
    var step_type := str(step.get("type", ""))
    match step_type:
        "wait_frames":
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "wait_seconds":
            await create_timer(max(float(step.get("seconds", 0.0)), 0.0)).timeout
        "action":
            var action_name := StringName(str(step.get("action_name", "")))
            if action_name.is_empty():
                _fail("Step %d action_name is required" % index)
                return false
            var pressed := bool(step.get("pressed", true))
            if pressed:
                Input.action_press(action_name, float(step.get("strength", 1.0)))
            else:
                Input.action_release(action_name)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
            if pressed and bool(step.get("release_after", false)):
                Input.action_release(action_name)
                await process_frame
        "key":
            var event := InputEventKey.new()
            event.pressed = bool(step.get("pressed", true))
            event.echo = bool(step.get("echo", false))
            event.keycode = int(step.get("keycode", 0))
            event.physical_keycode = int(step.get("physical_keycode", 0))
            event.unicode = int(step.get("unicode", 0))
            Input.parse_input_event(event)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "mouse_button":
            var event := InputEventMouseButton.new()
            event.button_index = int(step.get("button_index", MOUSE_BUTTON_LEFT))
            event.pressed = bool(step.get("pressed", true))
            event.double_click = bool(step.get("double_click", false))
            event.factor = float(step.get("factor", 1.0))
            event.position = _vector2(step.get("position", {}))
            event.global_position = event.position
            Input.parse_input_event(event)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "mouse_motion":
            var event := InputEventMouseMotion.new()
            event.position = _vector2(step.get("position", {}))
            event.global_position = event.position
            event.relative = _vector2(step.get("relative", {}))
            event.velocity = _vector2(step.get("velocity", {}))
            Input.parse_input_event(event)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "joypad_button":
            var event := InputEventJoypadButton.new()
            event.device = int(step.get("device", 0))
            event.button_index = int(step.get("button_index", 0))
            event.pressed = bool(step.get("pressed", true))
            event.pressure = float(step.get("pressure", 1.0))
            Input.parse_input_event(event)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "joypad_motion":
            var event := InputEventJoypadMotion.new()
            event.device = int(step.get("device", 0))
            event.axis = int(step.get("axis", 0))
            event.axis_value = float(step.get("axis_value", 0.0))
            Input.parse_input_event(event)
            await _wait_frames(max(int(step.get("frames", 1)), 1))
        "assert":
            _run_assertion(step, "steps[%d]" % index)
        "wait_until":
            if not await _wait_until(step, index):
                return false
        "set_property":
            var node := _resolve_node(str(step.get("node_path", ".")))
            if node == null:
                _fail("Step %d set_property node not found: %s" % [index, str(step.get("node_path", "."))])
                return false
            var property_path := str(step.get("property", ""))
            if property_path.is_empty():
                _fail("Step %d set_property requires property" % index)
                return false
            var value = codec.decode(step.get("value"), "steps[%d].value" % index)
            if value == null and step.get("value") != null:
                _fail("Step %d set_property value failed to decode" % index)
                return false
            node.set_indexed(NodePath(property_path), value)
            await process_frame
        "screenshot":
            if not await _capture_screenshot(step, index):
                return false
        "ui_report":
            if not await _run_ui_report(step, index):
                return false
        "log_marker":
            print("[SCENARIO] " + str(step.get("message", "marker")))
        _:
            _fail("Unsupported step type at %d: %s" % [index, step_type])
            return false
    return true

func _wait_until(step: Dictionary, index: int) -> bool:
    # Polls a property assertion every frame until it passes or the timeout
    # elapses — replaces brittle fixed wait_frames guesses.
    var property_path := str(step.get("property", ""))
    if property_path.is_empty():
        _fail("Step %d wait_until requires property" % index)
        return false
    var expected = codec.decode(step.get("expected"), "steps[%d].expected" % index)
    var operator := str(step.get("operator", "equals"))
    var tolerance := float(step.get("tolerance", 0.000001))
    var timeout_seconds: float = max(float(step.get("timeout_seconds", 5.0)), 0.01)
    var node_path := str(step.get("node_path", "."))

    var elapsed := 0.0
    while elapsed < timeout_seconds:
        var node := _resolve_node(node_path)
        if node != null:
            var actual = node.get_indexed(NodePath(property_path))
            if _compare(actual, expected, operator, tolerance):
                return true
        await process_frame
        elapsed += root.get_process_delta_time() if root != null else 0.016

    _fail("Step %d wait_until timed out after %.2fs: %s.%s %s expected" % [index, timeout_seconds, node_path, property_path, operator])
    return false

func _run_assertion(assertion: Dictionary, label: String) -> void:
    var assertion_type := str(assertion.get("assertion", assertion.get("assert_type", "property")))
    var node_path := str(assertion.get("node_path", "."))
    var node := _resolve_node(node_path)
    var passed := false
    var actual: Variant = null
    var message := ""

    if assertion_type == "node_exists":
        passed = node != null
        actual = passed
        message = "node exists: " + node_path
    elif assertion_type == "visible":
        actual = node != null and node is CanvasItem and (node as CanvasItem).is_visible_in_tree()
        passed = bool(actual) == bool(assertion.get("expected", true))
        message = "node visibility: " + node_path
    elif assertion_type == "property":
        if node == null:
            message = "node not found: " + node_path
        else:
            var property_path := str(assertion.get("property", ""))
            if property_path.is_empty():
                message = "property is required"
            else:
                actual = node.get_indexed(NodePath(property_path))
                var raw_expected = assertion.get("expected", assertion.get("equals"))
                var expected = codec.decode(raw_expected, label + ".expected")
                var operator := str(assertion.get("operator", "equals"))
                passed = _compare(actual, expected, operator, float(assertion.get("tolerance", 0.000001)))
                message = "%s.%s %s expected value" % [node_path, property_path, operator]
    else:
        message = "unsupported assertion type: " + assertion_type

    assertion_results.append({
        "label": str(assertion.get("label", label)),
        "passed": passed,
        "message": message,
        "actual": codec.encode(actual, 2)
    })
    if not passed:
        errors.append("Assertion failed: " + message)

func _compare(actual: Variant, expected: Variant, operator: String, tolerance: float) -> bool:
    match operator:
        "equals":
            return actual == expected
        "not_equals":
            return actual != expected
        "greater_than":
            return _is_ordered_pair(actual, expected) and actual > expected
        "greater_or_equal":
            return _is_ordered_pair(actual, expected) and actual >= expected
        "less_than":
            return _is_ordered_pair(actual, expected) and actual < expected
        "less_or_equal":
            return _is_ordered_pair(actual, expected) and actual <= expected
        "contains":
            if actual is String or actual is StringName:
                return str(actual).contains(str(expected))
            if actual is Array or actual is Dictionary or actual is PackedStringArray:
                return expected in actual
            return false
        "approx":
            if actual is float or actual is int:
                return abs(float(actual) - float(expected)) <= tolerance
            if actual is Vector2 and expected is Vector2:
                return actual.is_equal_approx(expected) or actual.distance_to(expected) <= tolerance
            if actual is Vector3 and expected is Vector3:
                return actual.is_equal_approx(expected) or actual.distance_to(expected) <= tolerance
            return actual == expected
        _:
            return false

func _is_ordered_pair(actual: Variant, expected: Variant) -> bool:
    var actual_numeric := actual is int or actual is float
    var expected_numeric := expected is int or expected is float
    if actual_numeric and expected_numeric:
        return true
    return typeof(actual) == typeof(expected) and (actual is String or actual is StringName)

func _capture_screenshot(step: Dictionary, index: int) -> bool:
    var raw_path := str(step.get("path", ""))
    if raw_path.is_empty():
        _fail("Screenshot step %d requires path" % index)
        return false
    await process_frame
    RenderingServer.force_draw(false, 0.0)
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("Screenshot image is empty: " + raw_path)
        return false
    var absolute_path := raw_path
    if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
        absolute_path = ProjectSettings.globalize_path(raw_path)
    var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
    if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
        _fail("Failed to create screenshot directory: " + absolute_path.get_base_dir())
        return false
    var save_error := image.save_png(absolute_path)
    if save_error != OK:
        _fail("Failed to save screenshot %s: %s" % [absolute_path, error_string(save_error)])
        return false
    screenshots.append({"path": absolute_path, "width": image.get_width(), "height": image.get_height()})
    return true

func _run_ui_report(step: Dictionary, index: int) -> bool:
    # Text description of the laid-out UI, for callers that cannot look at a
    # screenshot. Every rect is the post-layout global rect, so the report is
    # the same thing a rendered window would show.
    var label := str(step.get("label", "steps[%d]" % index))
    var node_path := str(step.get("node_path", "."))
    var subtree_root := _resolve_node(node_path)
    if subtree_root == null:
        _fail("Step %d ui_report node not found: %s" % [index, node_path])
        return false

    var fail_on: Array = []
    var raw_fail_on = step.get("fail_on", [])
    if not (raw_fail_on is Array):
        _fail("Step %d ui_report fail_on must be an array" % index)
        return false
    for raw_kind in raw_fail_on:
        var kind := str(raw_kind)
        if kind == "any":
            fail_on = UI_FINDING_KINDS.duplicate()
            break
        if not UI_FINDING_KINDS.has(kind):
            _fail("Step %d ui_report fail_on has unknown kind '%s' (expected \"any\" or one of %s)" % [index, kind, ", ".join(UI_FINDING_KINDS)])
            return false
        fail_on.append(kind)

    # Containers place their children through a deferred sort, so rects sampled
    # in the same frame the scene (or any property feeding a minimum size) was
    # touched still read (0, 0) and every child would look stacked. Settle here
    # rather than making callers remember a wait_frames step.
    await _wait_frames(max(int(step.get("settle_frames", 2)), 1))

    var include_hidden := bool(step.get("include_hidden", false))
    var min_overlap_ratio := clampf(float(step.get("min_overlap_ratio", 0.1)), 0.0, 1.0)
    var strict_overlap := bool(step.get("strict_overlap", false))

    # Paths stay relative to the scene root even when node_path scopes the walk,
    # so every path in the report can be pasted straight into an assertion.
    var collected: Array = []
    _collect_controls(subtree_root, str(scene_root.get_path_to(subtree_root)), "", collected)

    var entries: Array = []
    var visible_records: Array = []
    var hidden_count := 0
    for record in collected:
        var control: Control = record["node"]
        var is_visible := control.is_visible_in_tree()
        if not is_visible:
            hidden_count += 1
            if not include_hidden:
                continue
        var rect := control.get_global_rect()
        var entry := {
            "path": record["path"],
            "class": control.get_class(),
            "rect": _rect_array(rect)
        }
        var text_value := _control_text(control)
        if not text_value.is_empty():
            entry["text"] = text_value
        if control.top_level:
            entry["top_level"] = true
        if include_hidden:
            entry["visible"] = is_visible
            if not control.visible:
                entry["self_hidden"] = true
        entries.append(entry)
        if is_visible:
            visible_records.append({
                "node": control,
                "path": record["path"],
                "parent_path": record["parent_path"],
                "rect": rect
            })

    var findings := _find_ui_issues(visible_records, min_overlap_ratio, strict_overlap)
    var kind_counts := {}
    for kind in UI_FINDING_KINDS:
        kind_counts[kind] = 0
    for finding in findings:
        kind_counts[finding["kind"]] += 1

    var gated: Array = []
    for finding in findings:
        if fail_on.has(finding["kind"]):
            gated.append(finding)

    var visible_rect := root.get_visible_rect() if root != null else Rect2()
    var report := {
        "label": label,
        "node_path": node_path,
        "passed": gated.is_empty(),
        "rect_format": "[x, y, width, height]",
        "viewport": {"width": _round_number(visible_rect.size.x), "height": _round_number(visible_rect.size.y)},
        "counts": {
            "controls": entries.size(),
            "visible": visible_records.size(),
            "hidden": hidden_count,
            "findings": findings.size()
        },
        "controls": entries,
        "findings": findings
    }

    var raw_path := str(step.get("path", ""))
    if not raw_path.is_empty():
        var absolute_path := raw_path
        if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
            absolute_path = ProjectSettings.globalize_path(raw_path)
        var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
        if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
            _fail("Failed to create ui_report directory: " + absolute_path.get_base_dir())
            return false
        report["file"] = absolute_path
        var file := FileAccess.open(absolute_path, FileAccess.WRITE)
        if file == null:
            _fail("Failed to write ui_report %s: %s" % [absolute_path, error_string(FileAccess.get_open_error())])
            return false
        file.store_string(JSON.stringify(report, "  "))
        file.close()

    ui_reports.append(report)
    print("[SCENARIO] ui_report %s controls=%d visible=%d hidden=%d findings=%d zero_size=%d offscreen=%d overlap=%d" % [
        label, entries.size(), visible_records.size(), hidden_count, findings.size(),
        kind_counts["zero_size"], kind_counts["offscreen"], kind_counts["overlap"]
    ])
    for finding in gated:
        errors.append("UI finding (%s) in %s: %s" % [finding["kind"], label, finding["message"]])
    return true

func _collect_controls(node: Node, path: String, parent_path: String, out: Array) -> void:
    if node is Control:
        out.append({"node": node, "path": path, "parent_path": parent_path})
    for child in node.get_children():
        var child_path := str(child.name) if path == "." else path + "/" + str(child.name)
        _collect_controls(child, child_path, path, out)

func _find_ui_issues(records: Array, min_overlap_ratio: float, strict_overlap: bool) -> Array:
    var findings: Array = []
    var sized: Array = []
    for record in records:
        var control: Control = record["node"]
        var rect: Rect2 = record["rect"]
        if rect.size.x <= 0.0 or rect.size.y <= 0.0:
            findings.append({
                "kind": "zero_size",
                "nodes": [record["path"]],
                "rects": [_rect_array(rect)],
                "message": "%s (%s) has a %s x %s rect at (%s, %s) — it draws nothing" % [
                    record["path"], control.get_class(),
                    _round_number(rect.size.x), _round_number(rect.size.y),
                    _round_number(rect.position.x), _round_number(rect.position.y)
                ]
            })
            continue
        var viewport_rect := control.get_viewport_rect()
        if not viewport_rect.intersects(rect):
            findings.append({
                "kind": "offscreen",
                "nodes": [record["path"]],
                "rects": [_rect_array(rect)],
                "viewport_rect": _rect_array(viewport_rect),
                "message": "%s (%s) rect %s lies entirely outside the viewport %s" % [
                    record["path"], control.get_class(),
                    str(_rect_array(rect)), str(_rect_array(viewport_rect))
                ]
            })
        sized.append(record)

    # Group by the real parent object: a Control's siblings are what its parent
    # arranges, and non-Control nodes may sit between two Controls in the path.
    var groups: Array = []
    var group_by_parent := {}
    for record in sized:
        if (record["node"] as Control).top_level:
            continue
        var parent := (record["node"] as Control).get_parent()
        if parent == null:
            continue
        var key := parent.get_instance_id()
        if not group_by_parent.has(key):
            group_by_parent[key] = groups.size()
            groups.append({"parent": parent, "records": []})
        groups[group_by_parent[key]]["records"].append(record)

    for group in groups:
        if not _overlap_is_meaningful(group["parent"]):
            continue
        var parent_note := "lays children out side by side" if group["parent"] is Container else "leaves placement to the author"
        var members: Array = group["records"]
        for first in range(members.size()):
            for second in range(first + 1, members.size()):
                var a: Dictionary = members[first]
                var b: Dictionary = members[second]
                var a_rect: Rect2 = a["rect"]
                var b_rect: Rect2 = b["rect"]
                var shared := a_rect.intersection(b_rect)
                if shared.size.x <= 0.0 or shared.size.y <= 0.0:
                    continue
                var smaller_area: float = min(a_rect.get_area(), b_rect.get_area())
                var ratio := shared.get_area() / smaller_area if smaller_area > 0.0 else 0.0
                if ratio < min_overlap_ratio:
                    continue
                if not strict_overlap and (_is_backdrop_for(a, b) or _is_backdrop_for(b, a)):
                    continue
                var parent_path := str(a["parent_path"])
                findings.append({
                    "kind": "overlap",
                    "nodes": [a["path"], b["path"]],
                    "rects": [_rect_array(a_rect), _rect_array(b_rect)],
                    "parent": parent_path if not parent_path.is_empty() else ".",
                    "overlap_rect": _rect_array(shared),
                    "ratio": _round_number(ratio),
                    "message": "%s (%s) %s and %s (%s) %s cover %d%% of the smaller rect, but their parent %s (%s) %s" % [
                        a["path"], (a["node"] as Control).get_class(), str(_rect_array(a_rect)),
                        b["path"], (b["node"] as Control).get_class(), str(_rect_array(b_rect)),
                        int(round(ratio * 100.0)),
                        parent_path if not parent_path.is_empty() else ".",
                        (group["parent"] as Node).get_class(),
                        parent_note
                    ]
                })
    return findings

func _overlap_is_meaningful(parent: Node) -> bool:
    # Overlap only means something where placement was authored: under a plain
    # node the offsets/anchors are the author's, and the side-by-side containers
    # below are documented never to stack. Every other Container (MarginContainer,
    # PanelContainer, CenterContainer, AspectRatioContainer, ScrollContainer,
    # SubViewportContainer, TabContainer) hands each child the same slot, and a
    # custom Container's sort rule is unknown — neither is reported.
    if not (parent is Container):
        return true
    return parent is BoxContainer or parent is GridContainer or parent is FlowContainer or parent is SplitContainer

func _is_backdrop_for(candidate: Dictionary, other: Dictionary) -> bool:
    var control: Control = candidate["node"]
    var candidate_rect: Rect2 = candidate["rect"]
    var other_rect: Rect2 = other["rect"]
    if not candidate_rect.encloses(other_rect):
        return false
    for class_name_value in UI_BACKDROP_CLASSES:
        if control.is_class(class_name_value):
            return true
    return false

func _control_text(control: Control) -> String:
    if not ("text" in control):
        return ""
    var raw = control.get("text")
    if not (raw is String or raw is StringName):
        return ""
    var text_value := str(raw).strip_edges().replace("\n", " ")
    if text_value.length() > 60:
        text_value = text_value.substr(0, 57) + "..."
    return text_value

func _rect_array(rect: Rect2) -> Array:
    return [
        _round_number(rect.position.x),
        _round_number(rect.position.y),
        _round_number(rect.size.x),
        _round_number(rect.size.y)
    ]

func _round_number(value: float) -> Variant:
    var rounded := snappedf(value, 0.01)
    if is_equal_approx(rounded, round(rounded)):
        return int(round(rounded))
    return rounded

func _sample_performance(frames: int) -> Dictionary:
    var samples := {}
    for monitor_name in MONITORS:
        samples[monitor_name] = []
    for _frame in range(frames):
        await process_frame
        for monitor_name in MONITORS:
            samples[monitor_name].append(float(Performance.get_monitor(MONITORS[monitor_name])))
    var summary := {}
    for monitor_name in samples:
        var values: Array = samples[monitor_name]
        var total := 0.0
        var minimum := INF
        var maximum := -INF
        for value in values:
            total += value
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        summary[monitor_name] = {
            "average": total / max(values.size(), 1),
            "minimum": minimum,
            "maximum": maximum,
            "samples": values.size()
        }
    return summary

func _wait_frames(count: int) -> void:
    for _frame in range(count):
        await process_frame

func _resolve_node(path_value: String) -> Node:
    if scene_root == null:
        return null
    var path := path_value.strip_edges()
    if path.is_empty() or path == "." or path == "root" or path == str(scene_root.name):
        return scene_root
    if path.begins_with("root/"):
        path = path.trim_prefix("root/")
    elif path.begins_with(str(scene_root.name) + "/"):
        path = path.trim_prefix(str(scene_root.name) + "/")
    return scene_root.get_node_or_null(NodePath(path))

func _vector2(value: Variant) -> Vector2:
    if value is Dictionary:
        return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
    return Vector2.ZERO

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")

func _fail(message: String) -> void:
    errors.append(message)
    printerr("[SCENARIO ERROR] " + message)

func _finish(performance: Dictionary) -> void:
    var result := {
        "ok": errors.is_empty(),
        "scene_path": _normalize_res_path(scenario.get("scene_path", "")),
        "assertions": assertion_results,
        "screenshots": screenshots,
        "ui_reports": ui_reports,
        "performance": performance,
        "errors": errors
    }
    print(JSON.stringify(result))
    if is_instance_valid(scene_root):
        scene_root.queue_free()
        await process_frame
    quit(0 if errors.is_empty() else 1)
