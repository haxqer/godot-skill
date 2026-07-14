class_name GodotSkillVariantCodec
extends RefCounted

var utils_script = preload("./utils.gd")

func decode(value: Variant, context: String = "value") -> Variant:
    match typeof(value):
        TYPE_DICTIONARY:
            var dictionary := value as Dictionary
            if dictionary.has("__resource"):
                return _load_resource(dictionary.get("__resource"), context)
            if dictionary.has("__resource_type"):
                return _create_resource(dictionary, context)
            if dictionary.has("__gradient"):
                return _decode_gradient(dictionary.get("__gradient"), context)
            if dictionary.has("__curve"):
                return _decode_curve(dictionary.get("__curve"), context)
            if dictionary.has("__type"):
                return _decode_typed(dictionary, context)

            var decoded := {}
            for key in dictionary.keys():
                var raw_value = dictionary[key]
                var decoded_value = decode(raw_value, "%s.%s" % [context, str(key)])
                if decoded_value == null and raw_value != null:
                    return null
                decoded[key] = decoded_value
            return decoded
        TYPE_ARRAY:
            var decoded_array: Array = []
            for index in range(value.size()):
                var raw_item = value[index]
                var decoded_item = decode(raw_item, "%s[%d]" % [context, index])
                if decoded_item == null and raw_item != null:
                    return null
                decoded_array.append(decoded_item)
            return decoded_array
        _:
            return value

func encode(value: Variant, max_depth: int = 2, visited: Dictionary = {}) -> Variant:
    if max_depth < 0:
        return {"__truncated": true, "type": type_string(typeof(value))}

    match typeof(value):
        TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return value
        TYPE_STRING_NAME:
            return {"__type": "StringName", "value": str(value)}
        TYPE_NODE_PATH:
            return {"__type": "NodePath", "value": str(value)}
        TYPE_VECTOR2:
            return {"__type": "Vector2", "x": value.x, "y": value.y}
        TYPE_VECTOR2I:
            return {"__type": "Vector2i", "x": value.x, "y": value.y}
        TYPE_RECT2:
            return {
                "__type": "Rect2",
                "position": encode(value.position, max_depth - 1, visited),
                "size": encode(value.size, max_depth - 1, visited)
            }
        TYPE_RECT2I:
            return {
                "__type": "Rect2i",
                "position": encode(value.position, max_depth - 1, visited),
                "size": encode(value.size, max_depth - 1, visited)
            }
        TYPE_VECTOR3:
            return {"__type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
        TYPE_VECTOR3I:
            return {"__type": "Vector3i", "x": value.x, "y": value.y, "z": value.z}
        TYPE_TRANSFORM2D:
            return {
                "__type": "Transform2D",
                "x": encode(value.x, max_depth - 1, visited),
                "y": encode(value.y, max_depth - 1, visited),
                "origin": encode(value.origin, max_depth - 1, visited)
            }
        TYPE_VECTOR4:
            return {"__type": "Vector4", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
        TYPE_VECTOR4I:
            return {"__type": "Vector4i", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
        TYPE_PLANE:
            return {
                "__type": "Plane",
                "normal": encode(value.normal, max_depth - 1, visited),
                "d": value.d
            }
        TYPE_QUATERNION:
            return {"__type": "Quaternion", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
        TYPE_AABB:
            return {
                "__type": "AABB",
                "position": encode(value.position, max_depth - 1, visited),
                "size": encode(value.size, max_depth - 1, visited)
            }
        TYPE_BASIS:
            return {
                "__type": "Basis",
                "x": encode(value.x, max_depth - 1, visited),
                "y": encode(value.y, max_depth - 1, visited),
                "z": encode(value.z, max_depth - 1, visited)
            }
        TYPE_TRANSFORM3D:
            return {
                "__type": "Transform3D",
                "basis": encode(value.basis, max_depth - 1, visited),
                "origin": encode(value.origin, max_depth - 1, visited)
            }
        TYPE_PROJECTION:
            return {
                "__type": "Projection",
                "x": encode(value.x, max_depth - 1, visited),
                "y": encode(value.y, max_depth - 1, visited),
                "z": encode(value.z, max_depth - 1, visited),
                "w": encode(value.w, max_depth - 1, visited)
            }
        TYPE_COLOR:
            return {"__type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
        TYPE_DICTIONARY:
            var encoded_dictionary := {}
            for key in value.keys():
                encoded_dictionary[str(key)] = encode(value[key], max_depth - 1, visited)
            return encoded_dictionary
        TYPE_ARRAY:
            var encoded_array: Array = []
            for item in value:
                encoded_array.append(encode(item, max_depth - 1, visited))
            return encoded_array
        TYPE_PACKED_BYTE_ARRAY:
            return _encode_packed("PackedByteArray", value)
        TYPE_PACKED_INT32_ARRAY:
            return _encode_packed("PackedInt32Array", value)
        TYPE_PACKED_INT64_ARRAY:
            return _encode_packed("PackedInt64Array", value)
        TYPE_PACKED_FLOAT32_ARRAY:
            return _encode_packed("PackedFloat32Array", value)
        TYPE_PACKED_FLOAT64_ARRAY:
            return _encode_packed("PackedFloat64Array", value)
        TYPE_PACKED_STRING_ARRAY:
            return _encode_packed("PackedStringArray", value)
        TYPE_PACKED_VECTOR2_ARRAY:
            return _encode_packed_values("PackedVector2Array", value, max_depth, visited)
        TYPE_PACKED_VECTOR3_ARRAY:
            return _encode_packed_values("PackedVector3Array", value, max_depth, visited)
        TYPE_PACKED_COLOR_ARRAY:
            return _encode_packed_values("PackedColorArray", value, max_depth, visited)
        TYPE_PACKED_VECTOR4_ARRAY:
            return _encode_packed_values("PackedVector4Array", value, max_depth, visited)
        TYPE_OBJECT:
            return _encode_object(value, max_depth, visited)
        TYPE_RID:
            return {"__type": "RID", "id": value.get_id()}
        TYPE_CALLABLE:
            return {"__type": "Callable", "method": str(value.get_method())}
        TYPE_SIGNAL:
            return {"__type": "Signal", "name": str(value.get_name())}
        _:
            return {"__unsupported_type": type_string(typeof(value)), "value": str(value)}

func apply_properties(target: Object, raw_properties: Variant, context: String = "properties", use_indexed: bool = false) -> bool:
    if not (raw_properties is Dictionary):
        utils_script.log_error(context + " must be a dictionary")
        return false

    for raw_name in raw_properties.keys():
        var property_name := str(raw_name)
        if not use_indexed and not _has_property(target, property_name):
            utils_script.log_error("Property does not exist at %s: %s" % [context, property_name])
            return false
        var raw_value = raw_properties[raw_name]
        var decoded_value = decode(raw_value, "%s.%s" % [context, property_name])
        if decoded_value == null and raw_value != null:
            return false
        if use_indexed:
            target.set_indexed(NodePath(property_name), decoded_value)
        else:
            target.set(property_name, decoded_value)
    return true

func _decode_typed(dictionary: Dictionary, context: String) -> Variant:
    var type_name := str(dictionary.get("__type", ""))
    match type_name:
        "Vector2":
            return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))
        "Vector2i":
            return Vector2i(int(dictionary.get("x", 0)), int(dictionary.get("y", 0)))
        "Rect2":
            if dictionary.has("x") or dictionary.has("y") or dictionary.has("width") or dictionary.has("height"):
                return Rect2(
                    float(dictionary.get("x", 0.0)),
                    float(dictionary.get("y", 0.0)),
                    float(dictionary.get("width", 0.0)),
                    float(dictionary.get("height", 0.0))
                )
            return Rect2(
                _decode_vector2(dictionary.get("position", {}), context + ".position"),
                _decode_vector2(dictionary.get("size", {}), context + ".size")
            )
        "Rect2i":
            if dictionary.has("x") or dictionary.has("y") or dictionary.has("width") or dictionary.has("height"):
                return Rect2i(
                    int(dictionary.get("x", 0)),
                    int(dictionary.get("y", 0)),
                    int(dictionary.get("width", 0)),
                    int(dictionary.get("height", 0))
                )
            return Rect2i(
                _decode_vector2i(dictionary.get("position", {}), context + ".position"),
                _decode_vector2i(dictionary.get("size", {}), context + ".size")
            )
        "Vector3":
            return Vector3(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)), float(dictionary.get("z", 0.0)))
        "Vector3i":
            return Vector3i(int(dictionary.get("x", 0)), int(dictionary.get("y", 0)), int(dictionary.get("z", 0)))
        "Transform2D":
            return Transform2D(
                _decode_vector2(dictionary.get("x", {}), context + ".x"),
                _decode_vector2(dictionary.get("y", {}), context + ".y"),
                _decode_vector2(dictionary.get("origin", {}), context + ".origin")
            )
        "Vector4":
            return Vector4(
                float(dictionary.get("x", 0.0)),
                float(dictionary.get("y", 0.0)),
                float(dictionary.get("z", 0.0)),
                float(dictionary.get("w", 0.0))
            )
        "Vector4i":
            return Vector4i(
                int(dictionary.get("x", 0)),
                int(dictionary.get("y", 0)),
                int(dictionary.get("z", 0)),
                int(dictionary.get("w", 0))
            )
        "Plane":
            return Plane(_decode_vector3(dictionary.get("normal", {}), context + ".normal"), float(dictionary.get("d", 0.0)))
        "Quaternion":
            return Quaternion(
                float(dictionary.get("x", 0.0)),
                float(dictionary.get("y", 0.0)),
                float(dictionary.get("z", 0.0)),
                float(dictionary.get("w", 1.0))
            )
        "AABB":
            return AABB(
                _decode_vector3(dictionary.get("position", {}), context + ".position"),
                _decode_vector3(dictionary.get("size", {}), context + ".size")
            )
        "Basis":
            return Basis(
                _decode_vector3(dictionary.get("x", {}), context + ".x"),
                _decode_vector3(dictionary.get("y", {}), context + ".y"),
                _decode_vector3(dictionary.get("z", {}), context + ".z")
            )
        "Transform3D":
            return Transform3D(
                _decode_typed(dictionary.get("basis", {"__type": "Basis"}), context + ".basis"),
                _decode_vector3(dictionary.get("origin", {}), context + ".origin")
            )
        "Projection":
            return Projection(
                _decode_vector4(dictionary.get("x", {}), context + ".x"),
                _decode_vector4(dictionary.get("y", {}), context + ".y"),
                _decode_vector4(dictionary.get("z", {}), context + ".z"),
                _decode_vector4(dictionary.get("w", {}), context + ".w")
            )
        "Color":
            return Color(
                float(dictionary.get("r", 0.0)),
                float(dictionary.get("g", 0.0)),
                float(dictionary.get("b", 0.0)),
                float(dictionary.get("a", 1.0))
            )
        "NodePath":
            return NodePath(str(dictionary.get("value", "")))
        "StringName":
            return StringName(str(dictionary.get("value", "")))
        "PackedByteArray":
            return PackedByteArray(dictionary.get("values", []))
        "PackedInt32Array":
            return PackedInt32Array(dictionary.get("values", []))
        "PackedInt64Array":
            return PackedInt64Array(dictionary.get("values", []))
        "PackedFloat32Array":
            return PackedFloat32Array(dictionary.get("values", []))
        "PackedFloat64Array":
            return PackedFloat64Array(dictionary.get("values", []))
        "PackedStringArray":
            return PackedStringArray(dictionary.get("values", []))
        "PackedVector2Array":
            return PackedVector2Array(_decode_typed_array(dictionary.get("values", []), context, "Vector2"))
        "PackedVector3Array":
            return PackedVector3Array(_decode_typed_array(dictionary.get("values", []), context, "Vector3"))
        "PackedColorArray":
            return PackedColorArray(_decode_typed_array(dictionary.get("values", []), context, "Color"))
        "PackedVector4Array":
            return PackedVector4Array(_decode_typed_array(dictionary.get("values", []), context, "Vector4"))
        _:
            utils_script.log_error("Unsupported typed JSON value at %s: %s" % [context, type_name])
            return null

func _create_resource(dictionary: Dictionary, context: String) -> Resource:
    var type_name := str(dictionary.get("__resource_type", ""))
    var candidate = utils_script.instantiate_class(type_name)
    if not (candidate is Resource):
        utils_script.log_error("Resource type cannot be instantiated at %s: %s" % [context, type_name])
        if candidate != null and candidate is Node:
            candidate.free()
        return null

    var resource := candidate as Resource
    if dictionary.has("resource_name"):
        resource.resource_name = str(dictionary.get("resource_name"))
    if dictionary.has("properties") and not apply_properties(resource, dictionary.get("properties"), context + ".properties"):
        return null
    # Ordered builder calls run after property writes so resources whose state is
    # populated only through methods (e.g. Curve.add_point, Gradient.add_point,
    # SceneReplicationConfig.add_property) can be inlined without a separate op.
    if dictionary.has("method_calls") and not invoke_method_calls(resource, dictionary.get("method_calls"), context + ".method_calls"):
        return null
    return resource

func invoke_method_calls(target: Object, raw_calls: Variant, context: String) -> bool:
    if not (raw_calls is Array):
        utils_script.log_error(context + " must be an array")
        return false
    for index in range(raw_calls.size()):
        var raw_call = raw_calls[index]
        if not (raw_call is Dictionary):
            utils_script.log_error("%s[%d] must be a dictionary" % [context, index])
            return false
        var method_name := str(raw_call.get("method", ""))
        if method_name.is_empty():
            utils_script.log_error("%s[%d] requires method" % [context, index])
            return false
        if not target.has_method(method_name):
            utils_script.log_error("%s[%d]: %s has no method %s" % [context, index, target.get_class(), method_name])
            return false
        var raw_args = raw_call.get("args", [])
        var decoded_args = decode(raw_args, "%s[%d].args" % [context, index])
        if not (decoded_args is Array):
            return false
        var result = target.callv(method_name, decoded_args)
        if bool(raw_call.get("expect_ok", false)) and (not (result is int) or result != OK):
            utils_script.log_error("%s[%d]: %s expected OK but returned %s" % [context, index, method_name, str(result)])
            return false
    return true

func _decode_gradient(raw: Variant, context: String) -> Gradient:
    if not (raw is Dictionary):
        utils_script.log_error(context + ".__gradient must be a dictionary")
        return null
    var spec := raw as Dictionary
    var gradient := Gradient.new()
    if spec.has("interpolation_mode"):
        gradient.interpolation_mode = int(spec.get("interpolation_mode"))
    if spec.has("interpolation_color_space"):
        gradient.interpolation_color_space = int(spec.get("interpolation_color_space"))
    if spec.has("points"):
        var points = spec.get("points")
        if not (points is Array):
            utils_script.log_error(context + ".points must be an array")
            return null
        var offsets := PackedFloat32Array()
        var colors := PackedColorArray()
        for index in range(points.size()):
            var point = points[index]
            if not (point is Dictionary):
                utils_script.log_error("%s.points[%d] must be a dictionary" % [context, index])
                return null
            offsets.append(float(point.get("offset", 0.0)))
            var color = decode(point.get("color", {"__type": "Color", "r": 1, "g": 1, "b": 1}), "%s.points[%d].color" % [context, index])
            if not (color is Color):
                utils_script.log_error("%s.points[%d].color must decode to a Color" % [context, index])
                return null
            colors.append(color)
        gradient.offsets = offsets
        gradient.colors = colors
        return gradient
    if spec.has("offsets") and spec.has("colors"):
        var raw_offsets = decode(spec.get("offsets"), context + ".offsets")
        var raw_colors = decode(spec.get("colors"), context + ".colors")
        if not (raw_offsets is Array) or not (raw_colors is Array) or raw_offsets.size() != raw_colors.size():
            utils_script.log_error(context + ".offsets and .colors must be equal-length arrays")
            return null
        gradient.offsets = PackedFloat32Array(raw_offsets)
        gradient.colors = PackedColorArray(raw_colors)
        return gradient
    utils_script.log_error(context + ".__gradient requires points, or offsets + colors")
    return null

func _decode_curve(raw: Variant, context: String) -> Curve:
    if not (raw is Dictionary):
        utils_script.log_error(context + ".__curve must be a dictionary")
        return null
    var spec := raw as Dictionary
    var curve := Curve.new()
    if spec.has("min_value"):
        curve.min_value = float(spec.get("min_value"))
    if spec.has("max_value"):
        curve.max_value = float(spec.get("max_value"))
    if spec.has("bake_resolution"):
        curve.bake_resolution = int(spec.get("bake_resolution"))
    var points = spec.get("points", [])
    if not (points is Array):
        utils_script.log_error(context + ".points must be an array")
        return null
    for index in range(points.size()):
        var point = points[index]
        if not (point is Dictionary):
            utils_script.log_error("%s.points[%d] must be a dictionary" % [context, index])
            return null
        curve.add_point(
            Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))),
            float(point.get("left_tangent", 0.0)),
            float(point.get("right_tangent", 0.0)),
            int(point.get("left_mode", 0)),
            int(point.get("right_mode", 0))
        )
    return curve

func _load_resource(raw_path: Variant, context: String) -> Resource:
    var resource_path := _normalize_res_path(raw_path)
    if resource_path.is_empty():
        utils_script.log_error("Empty resource reference at " + context)
        return null
    var resource = load(resource_path)
    if not (resource is Resource):
        utils_script.log_error("Failed to load resource at %s: %s" % [context, resource_path])
        return null
    return resource

func _encode_object(value: Object, max_depth: int, visited: Dictionary) -> Variant:
    if value == null:
        return null
    if not (value is Resource):
        return {"__object_type": value.get_class(), "instance_id": value.get_instance_id()}

    var resource := value as Resource
    var path := resource.resource_path
    if not path.is_empty() and not path.contains("::"):
        return {"__resource": path, "resource_type": resource.get_class()}
    if max_depth <= 0:
        return {"__resource_type": resource.get_class(), "__truncated": true}

    var instance_id := resource.get_instance_id()
    if visited.has(instance_id):
        return {"__resource_type": resource.get_class(), "__cycle": true}
    visited[instance_id] = true

    var properties := {}
    for property_info in resource.get_property_list():
        var property_name := str(property_info.get("name", ""))
        var usage := int(property_info.get("usage", 0))
        if property_name.is_empty() or usage & PROPERTY_USAGE_STORAGE == 0:
            continue
        properties[property_name] = encode(resource.get(property_name), max_depth - 1, visited)
    visited.erase(instance_id)
    return {
        "__resource_type": resource.get_class(),
        "resource_name": resource.resource_name,
        "properties": properties
    }

func _encode_packed(type_name: String, values: Variant) -> Dictionary:
    return {"__type": type_name, "values": Array(values)}

func _encode_packed_values(type_name: String, values: Variant, max_depth: int, visited: Dictionary) -> Dictionary:
    var encoded_values: Array = []
    for value in values:
        encoded_values.append(encode(value, max_depth - 1, visited))
    return {"__type": type_name, "values": encoded_values}

func _decode_typed_array(values: Variant, context: String, expected_type: String) -> Array:
    var result: Array = []
    if not (values is Array):
        utils_script.log_error(context + ".values must be an array")
        return result
    for index in range(values.size()):
        var raw_value = values[index]
        if raw_value is Dictionary and not raw_value.has("__type"):
            raw_value = raw_value.duplicate()
            raw_value["__type"] = expected_type
        result.append(decode(raw_value, "%s.values[%d]" % [context, index]))
    return result

func _decode_vector2(value: Variant, context: String) -> Vector2:
    if value is Vector2:
        return value
    if value is Dictionary:
        return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
    utils_script.log_error(context + " must be a Vector2 dictionary")
    return Vector2.ZERO

func _decode_vector2i(value: Variant, context: String) -> Vector2i:
    if value is Vector2i:
        return value
    if value is Dictionary:
        return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
    utils_script.log_error(context + " must be a Vector2i dictionary")
    return Vector2i.ZERO

func _decode_vector3(value: Variant, context: String) -> Vector3:
    if value is Vector3:
        return value
    if value is Dictionary:
        return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
    utils_script.log_error(context + " must be a Vector3 dictionary")
    return Vector3.ZERO

func _decode_vector4(value: Variant, context: String) -> Vector4:
    if value is Vector4:
        return value
    if value is Dictionary:
        return Vector4(
            float(value.get("x", 0.0)),
            float(value.get("y", 0.0)),
            float(value.get("z", 0.0)),
            float(value.get("w", 0.0))
        )
    utils_script.log_error(context + " must be a Vector4 dictionary")
    return Vector4.ZERO

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://") or path.begins_with("user://"):
        return path
    return "res://" + path.trim_prefix("/")

func _has_property(target: Object, property_name: String) -> bool:
    for property_info in target.get_property_list():
        if str(property_info.get("name", "")) == property_name:
            return true
    return false
