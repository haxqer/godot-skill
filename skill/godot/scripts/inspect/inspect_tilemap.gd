class_name GodotSkillInspectTilemap
extends RefCounted

# Reads a painted TileMapLayer or GridMap back as ASCII rows so a model without
# vision can verify the level it just painted. The legend printed here is
# exactly what paint_tilemap.ascii_map.legend (or paint_gridmap.legend) accepts,
# so inspect -> paint round-trips.

const AUTO_CHARS := "#@%&*+=oxABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const EMPTY_CHAR := "."

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    var scene_path: String = _normalize_res_path(params.get("scene_path", ""))
    if scene_path.is_empty():
        utils_script.log_error("inspect_tilemap requires scene_path, e.g. {\"scene_path\": \"scenes/level.tscn\"}")
        return

    var format: String = str(params.get("format", "json"))
    if format != "json" and format != "text":
        utils_script.log_error("inspect_tilemap.format must be \"json\" (default) or \"text\"; got: " + format)
        return

    if not FileAccess.file_exists(scene_path):
        utils_script.log_error("Scene file does not exist at: " + scene_path)
        return
    var packed = load(scene_path)
    if not (packed is PackedScene):
        utils_script.log_error("Failed to load PackedScene: " + scene_path)
        return
    var root: Node = (packed as PackedScene).instantiate()
    if root == null:
        utils_script.log_error("Failed to instantiate scene: " + scene_path)
        return

    var node := _select_node(root, params, scene_path)
    if node == null:
        root.free()
        return

    var report := {}
    if node is TileMapLayer:
        report = _report_tilemap(node as TileMapLayer, root, params, scene_path)
    else:
        report = _report_gridmap(node as GridMap, root, params, scene_path)
    root.free()
    if report.is_empty():
        return

    if format == "text":
        _print_text(report)
        return
    print(JSON.stringify(report))

# --- node selection ---------------------------------------------------------

func _select_node(root: Node, params: Dictionary, scene_path: String) -> Node:
    if params.has("node_path"):
        var requested: String = str(params.get("node_path", ""))
        var resolved := _resolve_node(root, requested)
        if resolved == null:
            utils_script.log_error("inspect_tilemap: no node at node_path \"%s\" in %s. Nodes in this scene: %s. Pass one of those paths, or omit node_path to auto-pick the first TileMapLayer/GridMap." % [requested, scene_path, _describe_nodes(root)])
            return null
        if not (resolved is TileMapLayer or resolved is GridMap):
            utils_script.log_error("inspect_tilemap: \"%s\" is a %s, not a TileMapLayer or GridMap. Nodes in this scene: %s" % [requested, resolved.get_class(), _describe_nodes(root)])
            return null
        return resolved

    var found := _find_paintable(root)
    if found == null:
        utils_script.log_error("inspect_tilemap found no TileMapLayer or GridMap in %s. Nodes in this scene: %s. Add one first, e.g. scene_batch {\"actions\": [{\"type\": \"add_node\", \"node_type\": \"TileMapLayer\", \"node_name\": \"Ground\"}]}, then paint it with paint_tilemap." % [scene_path, _describe_nodes(root)])
        return null
    utils_script.log_info("inspect_tilemap: node_path omitted, inspecting %s (%s)" % [_node_path(root, found), found.get_class()])
    return found

func _find_paintable(node: Node) -> Node:
    if node is TileMapLayer or node is GridMap:
        return node
    for child in node.get_children():
        var found := _find_paintable(child)
        if found != null:
            return found
    return null

func _resolve_node(root: Node, path_value: String) -> Node:
    var node_path := path_value
    if node_path.is_empty() or node_path == "." or node_path == "root":
        return root
    if node_path.begins_with("root/"):
        node_path = node_path.substr(5)
    if node_path.begins_with("/"):
        node_path = node_path.substr(1)
    if node_path.is_empty():
        return root
    return root.get_node_or_null(NodePath(node_path))

func _node_path(root: Node, node: Node) -> String:
    if node == root:
        return "root"
    return "root/" + str(root.get_path_to(node))

func _describe_nodes(root: Node) -> String:
    var entries: Array = []
    _collect_nodes(root, root, entries)
    if entries.size() > 24:
        var head: Array = entries.slice(0, 24)
        head.append("... (%d more)" % (entries.size() - 24))
        return ", ".join(PackedStringArray(head))
    return ", ".join(PackedStringArray(entries))

func _collect_nodes(root: Node, node: Node, entries: Array) -> void:
    entries.append("%s (%s)" % [_node_path(root, node), node.get_class()])
    for child in node.get_children():
        _collect_nodes(root, child, entries)

# --- TileMapLayer -----------------------------------------------------------

func _report_tilemap(layer: TileMapLayer, root: Node, params: Dictionary, scene_path: String) -> Dictionary:
    var used: Array[Vector2i] = layer.get_used_cells()
    var min_x := 0
    var min_y := 0
    var width := 0
    var height := 0
    if not used.is_empty():
        var first: Vector2i = used[0]
        min_x = first.x
        min_y = first.y
        var max_x := first.x
        var max_y := first.y
        for cell in used:
            min_x = mini(min_x, cell.x)
            min_y = mini(min_y, cell.y)
            max_x = maxi(max_x, cell.x)
            max_y = maxi(max_y, cell.y)
        width = max_x - min_x + 1
        height = max_y - min_y + 1
    if params.has("bounds"):
        var crop: Dictionary = _read_bounds(params.get("bounds"), false)
        if crop.is_empty():
            return {}
        min_x = int(crop["x"])
        min_y = int(crop["y"])
        width = int(crop["w"])
        height = int(crop["h"])

    var char_for_key := {}
    var legend_out := {}
    var used_chars := {}
    legend_out[EMPTY_CHAR] = null
    used_chars[EMPTY_CHAR] = true
    used_chars[" "] = true
    if params.has("legend"):
        if not _read_legend(params.get("legend"), char_for_key, legend_out, used_chars, false):
            return {}

    var rows: Array = []
    var counts := {}
    var cell_count := 0
    for row_index in range(height):
        var line := ""
        for column_index in range(width):
            var coords := Vector2i(min_x + column_index, min_y + row_index)
            var source_id := layer.get_cell_source_id(coords)
            if source_id == -1:
                line += EMPTY_CHAR
                continue
            cell_count += 1
            var atlas := layer.get_cell_atlas_coords(coords)
            var alternative := layer.get_cell_alternative_tile(coords)
            var key := _tilemap_key(source_id, atlas, alternative)
            if not char_for_key.has(key):
                var symbol := _next_char(used_chars)
                if symbol.is_empty():
                    utils_script.log_error("inspect_tilemap ran out of legend characters (%d distinct tiles, %d available). Pass an explicit \"legend\" for the tiles you care about, or crop the view with \"bounds\"." % [char_for_key.size() + 1, AUTO_CHARS.length()])
                    return {}
                char_for_key[key] = symbol
                used_chars[symbol] = true
                legend_out[symbol] = {
                    "source_id": source_id,
                    "atlas_coords": {"x": atlas.x, "y": atlas.y},
                    "alternative": alternative
                }
            var cell_symbol: String = char_for_key[key]
            line += cell_symbol
            counts[cell_symbol] = int(counts.get(cell_symbol, 0)) + 1
        rows.append(line)

    var tileset_path := ""
    if layer.tile_set != null:
        tileset_path = layer.tile_set.resource_path
    return {
        "ok": true,
        "scene_path": scene_path,
        "node_path": _node_path(root, layer),
        "node_type": "TileMapLayer",
        "tileset_path": tileset_path,
        "bounds": {"x": min_x, "y": min_y, "w": width, "h": height},
        "cell_count": cell_count,
        "legend": legend_out,
        "counts": counts,
        "rows": rows
    }

# --- GridMap ----------------------------------------------------------------

func _report_gridmap(grid: GridMap, root: Node, params: Dictionary, scene_path: String) -> Dictionary:
    var used: Array[Vector3i] = grid.get_used_cells()
    var min_x := 0
    var min_z := 0
    var width := 0
    var depth := 0
    var y_set := {}
    if not used.is_empty():
        var first: Vector3i = used[0]
        min_x = first.x
        min_z = first.z
        var max_x := first.x
        var max_z := first.z
        for cell in used:
            min_x = mini(min_x, cell.x)
            min_z = mini(min_z, cell.z)
            max_x = maxi(max_x, cell.x)
            max_z = maxi(max_z, cell.z)
            y_set[cell.y] = true
        width = max_x - min_x + 1
        depth = max_z - min_z + 1
    if params.has("bounds"):
        var crop: Dictionary = _read_bounds(params.get("bounds"), true)
        if crop.is_empty():
            return {}
        min_x = int(crop["x"])
        min_z = int(crop["z"])
        width = int(crop["w"])
        depth = int(crop["h"])

    var char_for_key := {}
    var legend_out := {}
    var used_chars := {}
    legend_out[EMPTY_CHAR] = null
    used_chars[EMPTY_CHAR] = true
    used_chars[" "] = true
    if params.has("legend"):
        if not _read_legend(params.get("legend"), char_for_key, legend_out, used_chars, true):
            return {}

    var levels: Array = y_set.keys()
    levels.sort()
    var layers: Array = []
    var counts := {}
    var cell_count := 0
    for raw_level in levels:
        var level_y: int = raw_level
        var rows: Array = []
        for row_index in range(depth):
            var line := ""
            for column_index in range(width):
                var coords := Vector3i(min_x + column_index, level_y, min_z + row_index)
                var item := grid.get_cell_item(coords)
                if item == GridMap.INVALID_CELL_ITEM:
                    line += EMPTY_CHAR
                    continue
                cell_count += 1
                var orientation := grid.get_cell_item_orientation(coords)
                var key := _gridmap_key(item, orientation)
                if not char_for_key.has(key):
                    var symbol := _next_char(used_chars)
                    if symbol.is_empty():
                        utils_script.log_error("inspect_tilemap ran out of legend characters (%d distinct items, %d available). Pass an explicit \"legend\" for the items you care about, or crop the view with \"bounds\"." % [char_for_key.size() + 1, AUTO_CHARS.length()])
                        return {}
                    char_for_key[key] = symbol
                    used_chars[symbol] = true
                    legend_out[symbol] = {"item": item, "orientation": orientation}
                var cell_symbol: String = char_for_key[key]
                line += cell_symbol
                counts[cell_symbol] = int(counts.get(cell_symbol, 0)) + 1
            rows.append(line)
        layers.append({"y": level_y, "rows": rows})

    var library_path := ""
    if grid.mesh_library != null:
        library_path = grid.mesh_library.resource_path
    return {
        "ok": true,
        "scene_path": scene_path,
        "node_path": _node_path(root, grid),
        "node_type": "GridMap",
        "mesh_library_path": library_path,
        "bounds": {"x": min_x, "z": min_z, "w": width, "h": depth},
        "cell_count": cell_count,
        "legend": legend_out,
        "counts": counts,
        "layers": layers
    }

# --- shared helpers ---------------------------------------------------------

func _read_bounds(raw_bounds: Variant, is_gridmap: bool) -> Dictionary:
    var axis := "z" if is_gridmap else "y"
    if not (raw_bounds is Dictionary):
        utils_script.log_error("inspect_tilemap.bounds must be an object like {\"x\": 0, \"%s\": 0, \"w\": 16, \"h\": 12}" % axis)
        return {}
    var bounds := raw_bounds as Dictionary
    var second := 0
    if is_gridmap:
        second = int(bounds.get("z", bounds.get("y", 0)))
    else:
        second = int(bounds.get("y", 0))
    var w: int = int(bounds.get("w", 0))
    var h: int = int(bounds.get("h", 0))
    if w <= 0 or h <= 0:
        utils_script.log_error("inspect_tilemap.bounds needs a positive \"w\" and \"h\", e.g. {\"x\": 0, \"%s\": 0, \"w\": 16, \"h\": 12}" % axis)
        return {}
    if is_gridmap:
        return {"x": int(bounds.get("x", 0)), "z": second, "w": w, "h": h}
    return {"x": int(bounds.get("x", 0)), "y": second, "w": w, "h": h}

func _read_legend(raw_legend: Variant, char_for_key: Dictionary, legend_out: Dictionary, used_chars: Dictionary, is_gridmap: bool) -> bool:
    var example := "{\"#\": {\"source_id\": 0, \"atlas_coords\": {\"x\": 0, \"y\": 0}}, \".\": null}"
    if is_gridmap:
        example = "{\"A\": {\"item\": 0, \"orientation\": 0}, \".\": null}"
    if not (raw_legend is Dictionary):
        utils_script.log_error("inspect_tilemap.legend must be an object mapping single characters to tiles — the same shape paint_tilemap.ascii_map.legend takes, e.g. " + example)
        return false
    var legend := raw_legend as Dictionary
    for raw_symbol in legend.keys():
        var symbol := str(raw_symbol)
        var value: Variant = legend[raw_symbol]
        if value == null:
            used_chars[symbol] = true
            continue
        if symbol == EMPTY_CHAR or symbol == " ":
            utils_script.log_error("inspect_tilemap.legend cannot map \"%s\" to a tile: \".\" and \" \" always mean an empty cell. Pick another character." % symbol)
            return false
        if symbol.length() != 1:
            utils_script.log_error("inspect_tilemap.legend keys must be single characters; got \"%s\". Use one character per tile, e.g. %s" % [symbol, example])
            return false
        if not (value is Dictionary):
            utils_script.log_error("inspect_tilemap.legend[\"%s\"] must be an object or null, e.g. %s" % [symbol, example])
            return false
        var entry := value as Dictionary
        if entry.has("terrain"):
            utils_script.log_error("inspect_tilemap.legend[\"%s\"] is a terrain entry, which cannot be read back: set_cells_terrain_connect stores concrete atlas tiles. Map those atlas tiles instead, or omit legend and let the characters be auto-assigned." % symbol)
            return false
        var key := ""
        if is_gridmap:
            var item: int = int(entry.get("item", -1))
            var orientation: int = int(entry.get("orientation", entry.get("orient", 0)))
            key = _gridmap_key(item, orientation)
            legend_out[symbol] = {"item": item, "orientation": orientation}
        else:
            var source_id: int = int(entry.get("source_id", 0))
            var atlas := Vector2i.ZERO
            var raw_atlas: Variant = entry.get("atlas_coords", {})
            if raw_atlas is Dictionary:
                var atlas_dict: Dictionary = raw_atlas as Dictionary
                atlas = Vector2i(int(atlas_dict.get("x", 0)), int(atlas_dict.get("y", 0)))
            elif raw_atlas is Array and (raw_atlas as Array).size() == 2:
                var atlas_array := raw_atlas as Array
                atlas = Vector2i(int(atlas_array[0]), int(atlas_array[1]))
            var alternative: int = int(entry.get("alternative", 0))
            key = _tilemap_key(source_id, atlas, alternative)
            legend_out[symbol] = {
                "source_id": source_id,
                "atlas_coords": {"x": atlas.x, "y": atlas.y},
                "alternative": alternative
            }
        char_for_key[key] = symbol
        used_chars[symbol] = true
    return true

func _next_char(used_chars: Dictionary) -> String:
    for index in range(AUTO_CHARS.length()):
        var symbol := AUTO_CHARS.substr(index, 1)
        if not used_chars.has(symbol):
            return symbol
    return ""

func _tilemap_key(source_id: int, atlas: Vector2i, alternative: int) -> String:
    return "%d/%d/%d/%d" % [source_id, atlas.x, atlas.y, alternative]

func _gridmap_key(item: int, orientation: int) -> String:
    return "%d/%d" % [item, orientation]

func _print_text(report: Dictionary) -> void:
    if report.has("layers"):
        for raw_layer in (report["layers"] as Array):
            var layer_entry: Dictionary = raw_layer
            print("y=%d" % int(layer_entry["y"]))
            for raw_row in (layer_entry["rows"] as Array):
                print(str(raw_row))
        return
    for raw_row in (report["rows"] as Array):
        print(str(raw_row))

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
