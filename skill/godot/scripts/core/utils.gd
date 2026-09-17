class_name GodotSkillUtils
extends RefCounted

static var debug_mode: bool = false
# Set by log_error so the dispatcher can exit non-zero when any operation
# reported a failure — CI and shell callers rely on the exit code.
static var had_errors: bool = false

static func log_debug(message: String) -> void:
    if debug_mode:
        print("[DEBUG] " + message)

static func log_info(message: String) -> void:
    print("[INFO] " + message)

static func log_error(message: String) -> void:
    had_errors = true
    printerr("[ERROR] " + message)

static func allowed_param_keys(script_path: String) -> Dictionary:
    # Derived from the sources rather than a hand-maintained table: every key the
    # operation (and everything it preloads) actually reads is allowed, so this
    # can flag an unknown key but can never reject a supported one, and new
    # operations need no registration. Shared by the dispatcher's parameter check
    # and the `help` operation, so both report the same key set.
    var keys := {}
    var key_regex := RegEx.create_from_string('\\.(?:get|has)\\(\\s*"([A-Za-z_][A-Za-z_0-9]*)"')
    var preload_regex := RegEx.create_from_string('preload\\(\\s*"([^"]+)"')
    var pending: Array[String] = [script_path.simplify_path()]
    var seen := {}
    while not pending.is_empty():
        var path: String = pending.pop_back()
        if seen.has(path):
            continue
        seen[path] = true
        if not FileAccess.file_exists(path):
            continue
        var source := FileAccess.get_file_as_string(path)
        if source.is_empty():
            continue
        for match_result in key_regex.search_all(source):
            keys[match_result.get_string(1)] = true
        for match_result in preload_regex.search_all(source):
            pending.append(path.get_base_dir().path_join(match_result.get_string(1)).simplify_path())
    return keys

static func operation_table(dispatcher_path: String) -> Dictionary:
    # operation name -> absolute script path, read out of the dispatcher's own
    # `match` arms. Same reason as allowed_param_keys: no hand-maintained list to
    # drift, so `help` and the unknown-operation suggestion always agree with what
    # the dispatcher can actually run.
    var table := {}
    var path := dispatcher_path.simplify_path()
    if not FileAccess.file_exists(path):
        return table
    var source := FileAccess.get_file_as_string(path)
    if source.is_empty():
        return table
    var arm_regex := RegEx.create_from_string('"([a-z_][a-z_0-9]*)"\\s*:\\s*[\\r\\n]+\\s*return local_dir\\.path_join\\(\\s*"([^"]+)"\\s*\\)')
    for match_result in arm_regex.search_all(source):
        table[match_result.get_string(1)] = path.get_base_dir().path_join(match_result.get_string(2)).simplify_path()
    return table

static func nearest_names(subject: String, candidates: Array, limit: int = 3, threshold: float = 0.5) -> PackedStringArray:
    # "did you mean" suggestions for a misspelled parameter key or operation name.
    var scored: Array = []
    for candidate in candidates:
        var text := str(candidate)
        var score: float = subject.similarity(text)
        if score >= threshold:
            scored.append({"key": text, "score": score})
    scored.sort_custom(func(a, b): return a.score > b.score)
    var best := PackedStringArray()
    for entry in scored.slice(0, limit):
        best.append(entry.key)
    return best

static func get_script_by_name(name_of_class: String) -> Script:
    if debug_mode:
        print("Attempting to get script for class: " + name_of_class)
    
    if ResourceLoader.exists(name_of_class, "Script"):
        var script = load(name_of_class) as Script
        if script:
            return script
    
    var global_classes = ProjectSettings.get_global_class_list()
    for global_class in global_classes:
        if global_class["class"] == name_of_class:
            var script = load(global_class["path"]) as Script
            if script:
                return script
    
    printerr("Could not find script for class: " + name_of_class)
    return null

static func instantiate_class(name_of_class: String) -> Object:
    if name_of_class.is_empty():
        return null
    
    var result = null
    if ClassDB.class_exists(name_of_class):
        if ClassDB.can_instantiate(name_of_class):
            result = ClassDB.instantiate(name_of_class)
    else:
        var script = get_script_by_name(name_of_class)
        if script is GDScript:
            result = script.new()
            
    return result
