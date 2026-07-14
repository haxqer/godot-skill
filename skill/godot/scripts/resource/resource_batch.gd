class_name GodotSkillResourceBatch
extends RefCounted

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var target_path := _normalize_res_path(params.get("resource_path", params.get("save_path", "")))
    if target_path.is_empty():
        utils_script.log_error("resource_batch requires resource_path or save_path")
        return

    var resource := _open_resource(params, target_path)
    if resource == null:
        return

    var actions = params.get("actions", [])
    if not (actions is Array):
        utils_script.log_error("resource_batch actions must be an array")
        return

    var codec = codec_script.new()
    for index in range(actions.size()):
        var raw_action = actions[index]
        if not (raw_action is Dictionary):
            utils_script.log_error("resource_batch action %d must be a dictionary" % index)
            return
        if not _apply_action(resource, raw_action, codec):
            utils_script.log_error("resource_batch aborted at action %d" % index)
            return

    if not _ensure_parent_directory(target_path):
        return
    var save_error := ResourceSaver.save(resource, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save resource %s: %s" % [target_path, error_string(save_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "resource_path": target_path,
        "resource_type": resource.get_class(),
        "actions_applied": actions.size()
    }))

func _open_resource(params: Dictionary, target_path: String) -> Resource:
    var duplicate_from := _normalize_res_path(params.get("duplicate_from", ""))
    if not duplicate_from.is_empty():
        var source = ResourceLoader.load(duplicate_from, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (source is Resource):
            utils_script.log_error("Failed to load duplicate_from resource: " + duplicate_from)
            return null
        return (source as Resource).duplicate(bool(params.get("duplicate_subresources", true)))

    if FileAccess.file_exists(target_path):
        var existing = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (existing is Resource):
            utils_script.log_error("Failed to load resource: " + target_path)
            return null
        return existing

    if not bool(params.get("create_if_missing", false)):
        utils_script.log_error("Resource does not exist: " + target_path)
        return null

    var resource_type := str(params.get("resource_type", "Resource"))
    var candidate = utils_script.instantiate_class(resource_type)
    if not (candidate is Resource):
        utils_script.log_error("Resource type cannot be instantiated: " + resource_type)
        return null
    return candidate

func _apply_action(resource: Resource, action: Dictionary, codec: RefCounted) -> bool:
    var action_type := str(action.get("type", ""))
    match action_type:
        "set_properties":
            return codec.apply_properties(resource, action.get("properties", {}), "set_properties.properties")
        "set_indexed_properties":
            return codec.apply_properties(resource, action.get("properties", {}), "set_indexed_properties.properties", true)
        "set_metadata":
            var metadata = action.get("metadata", {})
            if not (metadata is Dictionary):
                utils_script.log_error("set_metadata.metadata must be a dictionary")
                return false
            for key in metadata.keys():
                var raw_value = metadata[key]
                var value = codec.decode(raw_value, "set_metadata.%s" % str(key))
                if value == null and raw_value != null:
                    return false
                resource.set_meta(StringName(str(key)), value)
            return true
        "remove_metadata":
            var names = action.get("names", [])
            if not (names is Array):
                utils_script.log_error("remove_metadata.names must be an array")
                return false
            for name in names:
                resource.remove_meta(StringName(str(name)))
            return true
        "set_resource_name":
            resource.resource_name = str(action.get("resource_name", ""))
            return true
        "call_method":
            return _call_method(resource, action, codec)
        "bake_navmesh":
            return _bake_navmesh(resource, action)
        _:
            utils_script.log_error("Unsupported resource_batch action: " + action_type)
            return false

func _bake_navmesh(resource: Resource, action: Dictionary) -> bool:
    if resource is NavigationPolygon:
        var geom2d := NavigationMeshSourceGeometryData2D.new()
        var traversable = action.get("traversable_outlines", [])
        if not (traversable is Array) or traversable.is_empty():
            utils_script.log_error("bake_navmesh requires a non-empty traversable_outlines for NavigationPolygon")
            return false
        for outline in traversable:
            var points := _packed_vector2(outline, "bake_navmesh.traversable_outlines")
            if points.size() < 3:
                utils_script.log_error("bake_navmesh.traversable_outlines entries need at least 3 points")
                return false
            geom2d.add_traversable_outline(points)
        for outline in action.get("obstruction_outlines", []):
            var points := _packed_vector2(outline, "bake_navmesh.obstruction_outlines")
            if points.size() < 3:
                utils_script.log_error("bake_navmesh.obstruction_outlines entries need at least 3 points")
                return false
            geom2d.add_obstruction_outline(points)
        NavigationServer2D.bake_from_source_geometry_data(resource, geom2d)
        if resource.get_polygon_count() == 0:
            utils_script.log_error("bake_navmesh produced no 2D polygons; check outlines and agent_radius/cell_size")
            return false
        return true

    if resource is NavigationMesh:
        var geom3d := NavigationMeshSourceGeometryData3D.new()
        var faces = action.get("faces", [])
        if faces is Array and not faces.is_empty():
            var verts := _packed_vector3(faces, "bake_navmesh.faces")
            if verts.size() < 3 or verts.size() % 3 != 0:
                utils_script.log_error("bake_navmesh.faces must be triangles (a multiple of 3 vertices)")
                return false
            geom3d.add_faces(verts, Transform3D.IDENTITY)
        for raw_mesh in action.get("source_meshes", []):
            if not (raw_mesh is Dictionary):
                utils_script.log_error("bake_navmesh.source_meshes entries must be dictionaries")
                return false
            var mesh_path := _normalize_res_path(raw_mesh.get("mesh", ""))
            var mesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
            if not (mesh is Mesh):
                utils_script.log_error("bake_navmesh.source_meshes could not load Mesh: " + mesh_path)
                return false
            geom3d.add_mesh(mesh, Transform3D.IDENTITY)
        if geom3d.get_vertices().is_empty():
            utils_script.log_error("bake_navmesh requires faces or source_meshes for NavigationMesh")
            return false
        NavigationServer3D.bake_from_source_geometry_data(resource, geom3d)
        if resource.get_polygon_count() == 0:
            utils_script.log_error("bake_navmesh produced no 3D polygons; check geometry and agent settings")
            return false
        return true

    utils_script.log_error("bake_navmesh target must be a NavigationPolygon or NavigationMesh, got " + resource.get_class())
    return false

func _packed_vector2(raw_outline: Variant, context: String) -> PackedVector2Array:
    var points := PackedVector2Array()
    if not (raw_outline is Array):
        utils_script.log_error(context + " entries must be arrays of points")
        return points
    for raw_point in raw_outline:
        if raw_point is Array and raw_point.size() == 2:
            points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
        elif raw_point is Dictionary and raw_point.has("x") and raw_point.has("y"):
            points.append(Vector2(float(raw_point.get("x")), float(raw_point.get("y"))))
        else:
            utils_script.log_error(context + " points must be [x,y] or {x,y}")
            return PackedVector2Array()
    return points

func _packed_vector3(raw_points: Variant, context: String) -> PackedVector3Array:
    var points := PackedVector3Array()
    if not (raw_points is Array):
        utils_script.log_error(context + " must be an array of points")
        return points
    for raw_point in raw_points:
        if raw_point is Array and raw_point.size() == 3:
            points.append(Vector3(float(raw_point[0]), float(raw_point[1]), float(raw_point[2])))
        elif raw_point is Dictionary and raw_point.has("x") and raw_point.has("y") and raw_point.has("z"):
            points.append(Vector3(float(raw_point.get("x")), float(raw_point.get("y")), float(raw_point.get("z"))))
        else:
            utils_script.log_error(context + " points must be [x,y,z] or {x,y,z}")
            return PackedVector3Array()
    return points

func _call_method(resource: Resource, action: Dictionary, codec: RefCounted) -> bool:
    var method_name := str(action.get("method", ""))
    if method_name.is_empty():
        utils_script.log_error("call_method requires method")
        return false
    if not resource.has_method(method_name):
        utils_script.log_error("Resource %s does not have method: %s" % [resource.get_class(), method_name])
        return false

    var raw_args = action.get("args", [])
    if not (raw_args is Array):
        utils_script.log_error("call_method.args must be an array")
        return false
    var args = codec.decode(raw_args, "call_method.args")
    if not (args is Array):
        return false

    var result = resource.callv(method_name, args)
    if bool(action.get("expect_ok", false)) and (not (result is int) or result != OK):
        utils_script.log_error("call_method %s expected OK but returned: %s" % [method_name, str(result)])
        return false
    return true

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
