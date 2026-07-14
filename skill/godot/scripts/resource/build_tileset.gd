class_name GodotSkillBuildTileset
extends RefCounted

# Authors or updates a TileSet .tres with atlas sources, exposed tiles, and
# collision/custom-data layers. TileSet construction is method-driven
# (add_source, create_tile, add_physics_layer), so it needs this dedicated op
# instead of plain property writes.

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var target_path := _normalize_res_path(params.get("resource_path", ""))
    if target_path.is_empty():
        utils_script.log_error("build_tileset requires resource_path")
        return

    var tile_set := _open_tileset(params, target_path)
    if tile_set == null:
        return

    var codec = codec_script.new()

    if params.has("tile_size"):
        var tile_size = codec.decode(params.get("tile_size"), "build_tileset.tile_size")
        if tile_size is Vector2i:
            tile_set.tile_size = tile_size
        elif tile_size is Dictionary:
            tile_set.tile_size = Vector2i(int(tile_size.get("x", 16)), int(tile_size.get("y", 16)))
        else:
            utils_script.log_error("build_tileset.tile_size must be a Vector2i value")
            return

    if not _ensure_physics_layers(tile_set, params.get("physics_layers", [])):
        return
    if not _ensure_custom_data_layers(tile_set, params.get("custom_data_layers", [])):
        return
    if not _ensure_terrain_sets(tile_set, params.get("terrain_sets", [])):
        return

    var sources = params.get("sources", [])
    if not (sources is Array):
        utils_script.log_error("build_tileset.sources must be an array")
        return
    var created_tiles := 0
    for raw_source in sources:
        if not (raw_source is Dictionary):
            utils_script.log_error("build_tileset.sources entries must be dictionaries")
            return
        var tile_count := _apply_source(tile_set, raw_source as Dictionary)
        if tile_count < 0:
            return
        created_tiles += tile_count

    if not _ensure_parent_directory(target_path):
        return
    var save_error := ResourceSaver.save(tile_set, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save TileSet %s: %s" % [target_path, error_string(save_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "resource_path": target_path,
        "source_count": tile_set.get_source_count(),
        "physics_layer_count": tile_set.get_physics_layers_count(),
        "custom_data_layer_count": tile_set.get_custom_data_layers_count(),
        "tiles_exposed": created_tiles
    }))

func _open_tileset(params: Dictionary, target_path: String) -> TileSet:
    if FileAccess.file_exists(target_path):
        var existing = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (existing is TileSet):
            utils_script.log_error("Existing resource is not a TileSet: " + target_path)
            return null
        return existing
    if not bool(params.get("create_if_missing", true)):
        utils_script.log_error("TileSet does not exist: " + target_path)
        return null
    return TileSet.new()

func _ensure_physics_layers(tile_set: TileSet, raw_layers: Variant) -> bool:
    if not (raw_layers is Array):
        utils_script.log_error("build_tileset.physics_layers must be an array")
        return false
    for index in range(raw_layers.size()):
        var layer = raw_layers[index]
        if not (layer is Dictionary):
            utils_script.log_error("physics_layers entries must be dictionaries")
            return false
        if index >= tile_set.get_physics_layers_count():
            tile_set.add_physics_layer()
        tile_set.set_physics_layer_collision_layer(index, int(layer.get("collision_layer", 1)))
        tile_set.set_physics_layer_collision_mask(index, int(layer.get("collision_mask", 1)))
    return true

func _ensure_custom_data_layers(tile_set: TileSet, raw_layers: Variant) -> bool:
    if not (raw_layers is Array):
        utils_script.log_error("build_tileset.custom_data_layers must be an array")
        return false
    for index in range(raw_layers.size()):
        var layer = raw_layers[index]
        if not (layer is Dictionary) or str(layer.get("name", "")).is_empty():
            utils_script.log_error("custom_data_layers entries require name")
            return false
        if index >= tile_set.get_custom_data_layers_count():
            tile_set.add_custom_data_layer()
        tile_set.set_custom_data_layer_name(index, str(layer.get("name")))
        var type_name := str(layer.get("type", "String"))
        var variant_type := _variant_type_from_name(type_name)
        if variant_type < 0:
            utils_script.log_error("Unsupported custom data layer type: " + type_name)
            return false
        tile_set.set_custom_data_layer_type(index, variant_type)
    return true

func _apply_source(tile_set: TileSet, source_params: Dictionary) -> int:
    var texture := _load_texture(str(source_params.get("texture", "")))
    if texture == null:
        return -1

    var region_size := Vector2i(tile_set.tile_size)
    if source_params.has("texture_region_size"):
        var raw_size = source_params.get("texture_region_size")
        if raw_size is Dictionary:
            region_size = Vector2i(int(raw_size.get("x", region_size.x)), int(raw_size.get("y", region_size.y)))

    var requested_id := int(source_params.get("source_id", -1))
    var source: TileSetAtlasSource = null
    if requested_id >= 0 and tile_set.has_source(requested_id):
        var existing = tile_set.get_source(requested_id)
        if not (existing is TileSetAtlasSource):
            utils_script.log_error("Existing source %d is not a TileSetAtlasSource" % requested_id)
            return -1
        source = existing
    else:
        source = TileSetAtlasSource.new()
        requested_id = tile_set.add_source(source, requested_id)

    source.texture = texture
    source.texture_region_size = region_size
    if source_params.has("margins"):
        var margins = source_params.get("margins")
        if margins is Dictionary:
            source.margins = Vector2i(int(margins.get("x", 0)), int(margins.get("y", 0)))
    if source_params.has("separation"):
        var separation = source_params.get("separation")
        if separation is Dictionary:
            source.separation = Vector2i(int(separation.get("x", 0)), int(separation.get("y", 0)))

    return _create_tiles(tile_set, source, source_params, texture, region_size)

func _create_tiles(tile_set: TileSet, source: TileSetAtlasSource, source_params: Dictionary, texture: Texture2D, region_size: Vector2i) -> int:
    var tiles = source_params.get("tiles", "all")
    var created := 0
    var tile_defaults = source_params.get("tile_defaults", {})
    if not (tile_defaults is Dictionary):
        utils_script.log_error("build_tileset tile_defaults must be a dictionary")
        return -1

    if tiles is String and tiles == "all":
        var margins := source.margins
        var separation := source.separation
        var columns := 0
        var rows := 0
        if region_size.x + separation.x > 0:
            columns = int((texture.get_width() - margins.x + separation.x) / float(region_size.x + separation.x))
        if region_size.y + separation.y > 0:
            rows = int((texture.get_height() - margins.y + separation.y) / float(region_size.y + separation.y))
        if columns <= 0 or rows <= 0:
            utils_script.log_error("Texture is smaller than one tile region")
            return -1
        for row in range(rows):
            for column in range(columns):
                var coords := Vector2i(column, row)
                if not source.has_tile(coords):
                    source.create_tile(coords)
                    created += 1
                if not _configure_tile_data(tile_set, source, coords, tile_defaults):
                    return -1
        return created

    if not (tiles is Array):
        utils_script.log_error("build_tileset source tiles must be \"all\" or an array")
        return -1
    for raw_tile in tiles:
        if not (raw_tile is Dictionary):
            utils_script.log_error("tiles entries must be dictionaries")
            return -1
        var tile = raw_tile as Dictionary
        var coords_value = tile.get("atlas_coords", {})
        var coords := Vector2i(int(coords_value.get("x", 0)), int(coords_value.get("y", 0))) if coords_value is Dictionary else Vector2i.ZERO
        var size_value = tile.get("size", {})
        var tile_span := Vector2i(1, 1)
        if size_value is Dictionary and not size_value.is_empty():
            tile_span = Vector2i(max(int(size_value.get("x", 1)), 1), max(int(size_value.get("y", 1)), 1))
        if not source.has_tile(coords):
            source.create_tile(coords, tile_span)
            created += 1
        var merged := (tile_defaults as Dictionary).duplicate(true)
        merged.merge(tile, true)
        if not _configure_tile_data(tile_set, source, coords, merged):
            return -1
    return created

func _configure_tile_data(tile_set: TileSet, source: TileSetAtlasSource, coords: Vector2i, tile_params: Dictionary) -> bool:
    var wants_collision := tile_params.has("collision")
    var wants_custom := tile_params.has("custom_data")
    var wants_terrain := tile_params.has("terrain_set") or tile_params.has("terrain") or tile_params.has("peering")
    if not (wants_collision or wants_custom or wants_terrain):
        return true

    var tile_data := source.get_tile_data(coords, 0)
    if tile_data == null:
        utils_script.log_error("No TileData at " + str(coords))
        return false

    if wants_collision:
        if tile_set.get_physics_layers_count() == 0:
            utils_script.log_error("Tile collision requires at least one physics_layers entry")
            return false
        var polygon := _resolve_collision_polygon(tile_params.get("collision"), source, coords)
        if polygon.is_empty():
            return false
        var layer_id := int(tile_params.get("collision_layer_index", 0))
        while tile_data.get_collision_polygons_count(layer_id) > 0:
            tile_data.remove_collision_polygon(layer_id, tile_data.get_collision_polygons_count(layer_id) - 1)
        tile_data.add_collision_polygon(layer_id)
        tile_data.set_collision_polygon_points(layer_id, 0, polygon)

    if wants_custom:
        var custom_data = tile_params.get("custom_data")
        if not (custom_data is Dictionary):
            utils_script.log_error("tiles custom_data must be a dictionary")
            return false
        for key in custom_data.keys():
            tile_data.set_custom_data(str(key), custom_data[key])

    if wants_terrain:
        if tile_params.has("terrain_set"):
            tile_data.terrain_set = int(tile_params.get("terrain_set"))
        if tile_params.has("terrain"):
            tile_data.terrain = int(tile_params.get("terrain"))
        var peering = tile_params.get("peering", {})
        if peering is Dictionary:
            for side in peering.keys():
                var constant_name := "CELL_NEIGHBOR_" + str(side).to_upper()
                if not ClassDB.class_get_integer_constant_list("TileSet").has(constant_name):
                    utils_script.log_error("Unknown peering side: " + str(side))
                    return false
                var neighbor := ClassDB.class_get_integer_constant("TileSet", constant_name)
                tile_data.set_terrain_peering_bit(neighbor, int(peering[side]))
    return true

func _resolve_collision_polygon(raw_collision: Variant, source: TileSetAtlasSource, coords: Vector2i) -> PackedVector2Array:
    if raw_collision is String and str(raw_collision) == "full_cell":
        # Collision points are relative to the tile center.
        var size := Vector2(source.get_tile_texture_region(coords).size)
        var half := size / 2.0
        return PackedVector2Array([
            Vector2(-half.x, -half.y),
            Vector2(half.x, -half.y),
            Vector2(half.x, half.y),
            Vector2(-half.x, half.y)
        ])
    if raw_collision is Array and raw_collision.size() >= 3:
        var points := PackedVector2Array()
        for raw_point in raw_collision:
            if raw_point is Dictionary:
                points.append(Vector2(float(raw_point.get("x", 0.0)), float(raw_point.get("y", 0.0))))
            elif raw_point is Array and raw_point.size() == 2:
                points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
            else:
                utils_script.log_error("Collision points must be {x,y} or [x,y]")
                return PackedVector2Array()
        return points
    utils_script.log_error("tiles collision must be \"full_cell\" or an array of 3+ points")
    return PackedVector2Array()

func _ensure_terrain_sets(tile_set: TileSet, raw_sets: Variant) -> bool:
    if not (raw_sets is Array):
        utils_script.log_error("build_tileset.terrain_sets must be an array")
        return false
    for index in range(raw_sets.size()):
        var terrain_set = raw_sets[index]
        if not (terrain_set is Dictionary):
            utils_script.log_error("terrain_sets entries must be dictionaries")
            return false
        if index >= tile_set.get_terrain_sets_count():
            tile_set.add_terrain_set()
        var mode_name := "TERRAIN_MODE_" + str(terrain_set.get("mode", "match_corners_and_sides")).to_upper()
        if not ClassDB.class_get_integer_constant_list("TileSet").has(mode_name):
            utils_script.log_error("Unknown terrain mode: " + str(terrain_set.get("mode")))
            return false
        tile_set.set_terrain_set_mode(index, ClassDB.class_get_integer_constant("TileSet", mode_name))
        var terrains = terrain_set.get("terrains", [])
        if not (terrains is Array):
            utils_script.log_error("terrain_sets terrains must be an array")
            return false
        for terrain_index in range(terrains.size()):
            var terrain = terrains[terrain_index]
            if not (terrain is Dictionary) or str(terrain.get("name", "")).is_empty():
                utils_script.log_error("terrains entries require name")
                return false
            if terrain_index >= tile_set.get_terrains_count(index):
                tile_set.add_terrain(index)
            tile_set.set_terrain_name(index, terrain_index, str(terrain.get("name")))
            var color = terrain.get("color", {})
            if color is Dictionary and not color.is_empty():
                tile_set.set_terrain_color(index, terrain_index, Color(
                    float(color.get("r", 0.5)),
                    float(color.get("g", 0.5)),
                    float(color.get("b", 0.5)),
                    float(color.get("a", 1.0))
                ))
    return true

func _variant_type_from_name(type_name: String) -> int:
    match type_name.to_lower():
        "bool":
            return TYPE_BOOL
        "int":
            return TYPE_INT
        "float":
            return TYPE_FLOAT
        "string":
            return TYPE_STRING
        "vector2":
            return TYPE_VECTOR2
        "vector2i":
            return TYPE_VECTOR2I
        "color":
            return TYPE_COLOR
        _:
            return -1

func _load_texture(raw_path: String) -> Texture2D:
    var texture_path := _normalize_res_path(raw_path)
    if texture_path.is_empty():
        utils_script.log_error("build_tileset sources require texture")
        return null

    if ResourceLoader.exists(texture_path):
        var resource = load(texture_path)
        if resource is Texture2D:
            return resource

    var absolute_path := ProjectSettings.globalize_path(texture_path)
    if not FileAccess.file_exists(absolute_path):
        utils_script.log_error("Texture file does not exist: " + texture_path)
        return null
    var image := Image.load_from_file(absolute_path)
    if image == null or image.is_empty():
        utils_script.log_error("Failed to load image data for texture: " + texture_path)
        return null
    var image_texture := ImageTexture.create_from_image(image)
    image_texture.take_over_path(texture_path)
    return image_texture

func _ensure_parent_directory(path: String) -> bool:
    var absolute_parent := ProjectSettings.globalize_path(path.get_base_dir())
    var error := DirAccess.make_dir_recursive_absolute(absolute_parent)
    if error != OK and error != ERR_ALREADY_EXISTS:
        utils_script.log_error("Failed to create resource directory: " + absolute_parent)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
