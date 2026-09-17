class_name GodotSkillHelp
extends RefCounted

# Self-describing operation index, so a caller can ask the dispatcher what it
# supports instead of reading 600 lines of reference and guessing parameter
# names. Nothing here is hand-maintained: the operation list is read out of
# dispatcher.gd's match arms and the accepted parameter keys are re-derived from
# each operation's own sources by the same function the dispatcher's parameter
# check uses. Only the prose (summary / params / example / notes / see) lives in
# op_examples.json, and `help '{"check_examples":true}'` fails when any of that
# drifts away from the keys its operation actually reads.

var utils_script = preload("./utils.gd")

const CATALOG_FILE := "op_examples.json"
const DISPATCHER_FILE := "dispatcher.gd"
# Keys a batch operation owns itself, so an action inside `actions` never repeats
# them. Trimmed off when an action_types entry is written as "@<operation>".
const BATCH_OWNED_KEYS := ["scene_path", "save_path"]

func execute(params: Dictionary) -> void:
    var format := str(params.get("format", "json"))
    if format != "json" and format != "text":
        utils_script.log_error("help: unknown format \"%s\" — use \"json\" (default) or \"text\"." % format)
        return

    var dispatcher_path := _sibling_path(DISPATCHER_FILE)
    var table: Dictionary = utils_script.operation_table(dispatcher_path)
    if table.is_empty():
        utils_script.log_error(
            "help: could not read the operation list from %s. Re-install the skill so scripts/core/ is intact." % dispatcher_path)
        return

    var catalog := _load_catalog()
    if catalog.is_empty():
        return

    if bool(params.get("check_examples", false)):
        _check_examples(table, catalog, format)
        return

    var operation := str(params.get("op", "")).strip_edges()
    if operation.is_empty():
        _print_list(table, catalog, format, dispatcher_path)
        return
    _print_operation(operation, table, catalog, format, dispatcher_path, bool(params.get("verbose", false)))

# --- modes -----------------------------------------------------------------

func _print_list(table: Dictionary, catalog: Dictionary, format: String, dispatcher_path: String) -> void:
    var names := table.keys()
    names.sort()
    var operations: Array = []
    for name_value in names:
        var operation := str(name_value)
        operations.append({"op": operation, "summary": _summary_for(operation, catalog)})

    var usage := "godot --headless --path %s --script %s <operation> '<json params>'" % [
        _project_dir(), _absolute(dispatcher_path)]

    if format == "text":
        print("%d operations. Parameters are one JSON object." % operations.size())
        print(usage)
        print("One operation in full:  help '{\"op\":\"add_node\"}'")
        print("Validate the catalog:   help '{\"check_examples\":true}'")
        for entry in operations:
            print("  %-26s %s" % [entry["op"], entry["summary"]])
        return

    print(JSON.stringify({
        "operations": operations,
        "count": operations.size(),
        "usage": usage,
        "next": "help '{\"op\":\"<name>\"}' for that operation's parameters, an example, its gotchas, and a runnable command"
    }, "", false))

func _print_operation(operation: String, table: Dictionary, catalog: Dictionary, format: String, dispatcher_path: String, verbose: bool) -> void:
    if not table.has(operation):
        var unknown := "help: unknown operation \"%s\"" % operation
        var near: PackedStringArray = utils_script.nearest_names(operation, table.keys())
        if not near.is_empty():
            unknown += " (did you mean " + ", ".join(near) + "?)"
        unknown += ". Run: help '{}' to list all %d operations." % table.size()
        utils_script.log_error(unknown)
        return

    var accepted: Array = []
    if verbose:
        var allowed: Dictionary = utils_script.allowed_param_keys(str(table[operation]))
        accepted = allowed.keys()
        accepted.sort()

    var entry := _dict(catalog, operation)
    if entry.is_empty():
        utils_script.log_error(
            "help: %s has no entry in %s. Add one, or read references/automation_api.md for its parameters."
            % [operation, CATALOG_FILE])
        return

    var schema := _ordered_schema(_dict(entry, "params"))
    var action_types := _resolve_action_types(entry, catalog)
    var example := _dict(entry, "example")
    var notes := _array(entry, "notes")
    var see := _text(entry, "see", "references/automation_api.md")
    var summary := _summary_for(operation, catalog)
    var command := "godot --headless --path %s --script %s %s '%s'" % [
        _project_dir(), _absolute(dispatcher_path), operation, JSON.stringify(example, "", false)]

    if format == "text":
        print("op:      " + operation)
        print("summary: " + summary)
        print("see:     " + see)
        print("command: " + command)
        print("params:")
        for key in schema.keys():
            print("  %s — %s" % [str(key), str(schema[key])])
        if not action_types.is_empty():
            print("actions[].type:")
            for type_value in action_types.keys():
                print("  " + str(type_value) + ":")
                var type_schema := _ordered_schema(_dict(action_types, str(type_value)))
                for key in type_schema.keys():
                    print("    %s — %s" % [str(key), str(type_schema[key])])
        if not notes.is_empty():
            print("notes:")
            for note in notes:
                print("  - " + str(note))
        if verbose:
            print("accepted_keys (%d, every key the param check allows):" % accepted.size())
            print("  " + ", ".join(PackedStringArray(accepted)))
        return

    var payload := {
        "op": operation,
        "summary": summary,
        "params": schema,
        "example": example,
        "notes": notes,
        "see": see,
        "command": command
    }
    if not action_types.is_empty():
        payload["action_types"] = action_types
    if verbose:
        payload["accepted_keys"] = accepted
    print(JSON.stringify(payload, "", false))

func _resolve_action_types(entry: Dictionary, catalog: Dictionary) -> Dictionary:
    # A batch operation documents each `actions` entry here. "@<operation>" means
    # "that operation's params, minus the keys the batch owns", so the schema is
    # written once and cannot drift between the standalone op and the action.
    var resolved := {}
    var raw := _dict(entry, "action_types")
    for type_value in raw.keys():
        var type_name := str(type_value)
        var spec: Variant = raw[type_name]
        if spec is Dictionary:
            resolved[type_name] = spec
            continue
        var ref_name := str(spec)
        if not ref_name.begins_with("@"):
            resolved[type_name] = {}
            continue
        var referenced := _ordered_schema(_dict(_dict(catalog, ref_name.substr(1)), "params"))
        var trimmed := {}
        for key_value in referenced.keys():
            var key := str(key_value)
            if key in BATCH_OWNED_KEYS:
                continue
            trimmed[key] = referenced[key]
        resolved[type_name] = trimmed
    return resolved

func _ordered_schema(schema: Dictionary) -> Dictionary:
    # Required keys first: that is the reading order a caller needs.
    var ordered := {}
    var optional: Array = []
    for key_value in schema.keys():
        var key := str(key_value)
        if str(schema[key]).begins_with("(required"):
            ordered[key] = schema[key]
        else:
            optional.append(key)
    for key_value in optional:
        var key := str(key_value)
        ordered[key] = schema[key]
    return ordered

func _check_examples(table: Dictionary, catalog: Dictionary, format: String) -> void:
    # The guard that keeps the catalog honest: every example key is re-checked
    # against the keys its operation really reads, so a renamed parameter breaks
    # this run instead of silently teaching the next caller a dead key.
    var failures: Array = []
    var skipped: Array = []
    var checked := 0

    var names := table.keys()
    names.sort()
    for name_value in names:
        var operation := str(name_value)
        if not catalog.has(operation):
            failures.append({"op": operation, "key": "(no entry in %s)" % CATALOG_FILE, "suggestions": []})
            utils_script.log_error(
                "help check_examples: %s has no entry in scripts/core/%s. Add {summary, example, notes, see} for it."
                % [operation, CATALOG_FILE])
            continue
        var allowed: Dictionary = utils_script.allowed_param_keys(str(table[operation]))
        if allowed.is_empty():
            # Source unreadable (the op script is not installed) — the dispatcher
            # never blocks on that either, so do not invent a failure here.
            skipped.append(operation)
            continue
        checked += 1
        var entry := _dict(catalog, operation)
        var example := _dict(entry, "example")
        _check_keys(operation, example, allowed, "", failures)
        var index := 0
        for action in _array(example, "actions"):
            if action is Dictionary:
                _check_keys(operation, action, allowed, "actions[%d]." % index, failures)
            index += 1

        # The curated schema is the documentation a caller reads, so it must never
        # name a key the operation would reject.
        var schema := _dict(entry, "params")
        if schema.is_empty():
            failures.append({"op": operation, "key": "(no params schema)", "suggestions": []})
            utils_script.log_error(
                ("help check_examples: %s has no \"params\" schema in scripts/core/%s. "
                + "Add {\"<key>\": \"<meaning, with (required) or (default: X) and the value shape>\"} "
                + "for every key the operation uses.") % [operation, CATALOG_FILE])
        else:
            _check_keys(operation, schema, allowed, "params.", failures)

        var action_types := _resolve_action_types(entry, catalog)
        for type_value in action_types.keys():
            var type_name := str(type_value)
            var type_schema := _dict(action_types, type_name)
            if type_schema.is_empty():
                failures.append({"op": operation, "key": "action_types.%s" % type_name, "suggestions": []})
                utils_script.log_error(
                    ("help check_examples: %s action_types.%s resolves to nothing in scripts/core/%s. "
                    + "Use a {key: meaning} object, or \"@<operation>\" naming an entry that has a params schema.")
                    % [operation, type_name, CATALOG_FILE])
                continue
            _check_keys(operation, type_schema, allowed, "action_types.%s." % type_name, failures)

    for key_value in catalog.keys():
        var key := str(key_value)
        if key.begins_with("_") or table.has(key):
            continue
        var near: PackedStringArray = utils_script.nearest_names(key, table.keys())
        failures.append({"op": key, "key": "(not a dispatcher operation)", "suggestions": Array(near)})
        var stale := "help check_examples: %s is in %s but is not an operation dispatcher.gd can run" % [key, CATALOG_FILE]
        if not near.is_empty():
            stale += " (did you mean " + ", ".join(near) + "?)"
        utils_script.log_error(stale + ". Remove the entry or add the match arm.")

    if format == "text":
        print("check_examples: operations=%d checked=%d skipped=%d failures=%d" % [
            table.size(), checked, skipped.size(), failures.size()])
        for failure in failures:
            print("  FAIL %s -> %s" % [failure["op"], failure["key"]])
        if not skipped.is_empty():
            print("  skipped (operation script not installed): " + ", ".join(PackedStringArray(skipped)))
        return

    print(JSON.stringify({
        "checked": checked,
        "operations": table.size(),
        "skipped": skipped,
        "failures": failures
    }, "", false))

func _check_keys(operation: String, values: Dictionary, allowed: Dictionary, prefix: String, failures: Array) -> void:
    for key_value in values.keys():
        var key := str(key_value)
        if allowed.has(key):
            continue
        var near: PackedStringArray = utils_script.nearest_names(key, allowed.keys())
        failures.append({"op": operation, "key": prefix + key, "suggestions": Array(near)})
        var message := "help check_examples: the %s catalog entry names %s%s, which %s never reads" % [
            operation, prefix, key, operation]
        if not near.is_empty():
            message += " (did you mean " + ", ".join(near) + "?)"
        utils_script.log_error(message + ". Fix the example in scripts/core/" + CATALOG_FILE + ".")

# --- helpers ---------------------------------------------------------------

func _summary_for(operation: String, catalog: Dictionary) -> String:
    var entry := _dict(catalog, operation)
    if entry.is_empty():
        return "(no entry in %s yet — read references/automation_api.md)" % CATALOG_FILE
    return _text(entry, "summary", "")

func _load_catalog() -> Dictionary:
    var path := _sibling_path(CATALOG_FILE)
    if not FileAccess.file_exists(path):
        utils_script.log_error("help: catalog not found at %s. Re-install the skill so scripts/core/ is intact." % path)
        return {}
    var source := FileAccess.get_file_as_string(path)
    var json := JSON.new()
    if json.parse(source) != OK:
        utils_script.log_error("help: %s is not valid JSON (line %d: %s). Fix the file." % [
            path, json.get_error_line(), json.get_error_message()])
        return {}
    var data: Variant = json.get_data()
    if not (data is Dictionary):
        utils_script.log_error("help: %s must contain a JSON object keyed by operation name." % path)
        return {}
    var catalog: Dictionary = data
    if catalog.is_empty():
        utils_script.log_error("help: %s is empty; it must hold one entry per operation." % path)
    return catalog

func _sibling_path(file_name: String) -> String:
    var here := str(get_script().resource_path)
    return here.get_base_dir().path_join(file_name).simplify_path()

func _absolute(path: String) -> String:
    return ProjectSettings.globalize_path(path).simplify_path()

func _project_dir() -> String:
    var directory := _absolute("res://").trim_suffix("/")
    if directory.is_empty():
        return "<project>"
    return directory

# Typed reads of the catalog. Deliberately not `entry.get("key", default)`: the
# dispatcher derives an operation's accepted parameter keys from exactly that
# literal, so reading catalog fields that way would make "summary", "notes" and
# friends look like parameters of `help`.
func _dict(source: Dictionary, key: String) -> Dictionary:
    if source.has(key) and source[key] is Dictionary:
        return source[key]
    return {}

func _array(source: Dictionary, key: String) -> Array:
    if source.has(key) and source[key] is Array:
        return source[key]
    return []

func _text(source: Dictionary, key: String, fallback: String) -> String:
    if source.has(key):
        return str(source[key])
    return fallback
