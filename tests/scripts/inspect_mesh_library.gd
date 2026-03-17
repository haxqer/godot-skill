extends SceneTree

func _init() -> void:
    var args = OS.get_cmdline_args()
    var script_index = args.find("--script")
    if script_index == -1 or args.size() <= script_index + 2:
        printerr("[ERROR] Usage: godot --headless --path <project> --script inspect_mesh_library.gd <json_params>")
        quit(1)
        return

    var params_json = args[script_index + 2]
    var json = JSON.new()
    if json.parse(params_json) != OK:
        printerr("[ERROR] Failed to parse JSON params")
        quit(1)
        return

    var params = json.get_data()
    var resource_path = str(params.get("resource_path", ""))
    if resource_path.is_empty():
        printerr("[ERROR] resource_path is required")
        quit(1)
        return
    if not resource_path.begins_with("res://"):
        resource_path = "res://" + resource_path

    var resource = load(resource_path)
    if not (resource is MeshLibrary):
        printerr("[ERROR] Failed to load MeshLibrary: " + resource_path)
        quit(1)
        return

    var mesh_library := resource as MeshLibrary
    var items: Array = []
    for item_id in mesh_library.get_item_list():
        items.append({
            "id": int(item_id),
            "name": mesh_library.get_item_name(item_id),
            "has_mesh": mesh_library.get_item_mesh(item_id) != null,
            "shape_count": mesh_library.get_item_shapes(item_id).size()
        })

    print(JSON.stringify({
        "resource_path": resource_path,
        "count": items.size(),
        "items": items
    }))
    quit()
