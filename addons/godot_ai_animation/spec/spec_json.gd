@tool
extends RefCounted

## Clip spec <-> JSON-safe dictionaries (the `spec_export` / `spec_apply`
## interchange format).
##
## Every value carries its type so a round-trip is exact: numbers stay numbers,
## and Vector2/Vector3/Color/Quaternion are tagged dictionaries. Audio streams
## are referenced by `res://` path (resources cannot be inlined in JSON).
##
## Envelope:
##     { "format": "godot-ai-animation-clip", "version": 1,
##       "length": float, "loop_mode": int, "markers": [...], "tracks": [...] }

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

const FORMAT := "godot-ai-animation-clip"
const VERSION := 1


# --- encode ----------------------------------------------------------------

static func encode_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return {"ok": float(value)}
		TYPE_VECTOR2:
			var v2 := value as Vector2
			return {"ok": {"kind": "vector2", "x": v2.x, "y": v2.y}}
		TYPE_VECTOR3:
			var v3 := value as Vector3
			return {"ok": {"kind": "vector3", "x": v3.x, "y": v3.y, "z": v3.z}}
		TYPE_COLOR:
			var color := value as Color
			return {"ok": {"kind": "color", "r": color.r, "g": color.g, "b": color.b, "a": color.a}}
		TYPE_QUATERNION:
			var quat := value as Quaternion
			return {"ok": {"kind": "quaternion", "x": quat.x, "y": quat.y, "z": quat.z, "w": quat.w}}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"Cannot encode a %s value in a clip spec" % ClipSpec.value_kind(value))


static func decode_value(raw: Variant) -> Dictionary:
	if raw is float or raw is int:
		return {"ok": float(raw)}
	if not raw is Dictionary:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"A key value must be a number or a {kind: ...} dict (got %s)" % type_string(typeof(raw)))
	var dict: Dictionary = raw
	if not dict.has("kind"):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "A value dict needs a 'kind'")
	match str(dict.kind):
		"vector2":
			return {"ok": Vector2(_number(dict, "x"), _number(dict, "y"))}
		"vector3":
			return {"ok": Vector3(_number(dict, "x"), _number(dict, "y"), _number(dict, "z"))}
		"color":
			return {"ok": Color(_number(dict, "r"), _number(dict, "g"), _number(dict, "b"), _number(dict, "a", 1.0))}
		"quaternion":
			return {"ok": Quaternion(_number(dict, "x"), _number(dict, "y"), _number(dict, "z"), _number(dict, "w", 1.0))}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "Unknown value kind '%s'" % str(dict.kind))


static func _number(dict: Dictionary, key: String, fallback: float = 0.0) -> float:
	if not dict.has(key):
		return fallback
	var value = dict[key]
	if value is float or value is int:
		return float(value)
	return fallback


# --- spec -> JSON dict -----------------------------------------------------

static func to_json(spec: Dictionary) -> Dictionary:
	var out := {
		"format": FORMAT,
		"version": VERSION,
		"length": float(spec.get("length", 0.0)),
		"loop_mode": int(spec.get("loop_mode", Animation.LOOP_NONE)),
		"markers": [],
		"tracks": [],
	}
	for marker in spec.get("markers", []):
		var color := encode_value(marker.get("color", Color(1, 1, 1, 1)))
		out.markers.append({
			"name": str(marker.get("name", "")),
			"time": float(marker.get("time", 0.0)),
			"color": color.ok if color.has("ok") else null,
		})
	for track in spec.get("tracks", []):
		out.tracks.append(_track_to_json(track))
	return out


static func _track_to_json(track: Dictionary) -> Dictionary:
	var type := int(track.get("type", Animation.TYPE_VALUE))
	var out := {
		"type": type,
		"path": str(track.get("path", "")),
		"enabled": bool(track.get("enabled", true)),
		"keys": [],
	}
	if ClipSpec.is_value_type(type):
		out["interp"] = int(track.get("interp", Animation.INTERPOLATION_LINEAR))
		if type == Animation.TYPE_VALUE:
			out["update_mode"] = int(track.get("update_mode", Animation.UPDATE_CONTINUOUS))
		else:
			out["loop_wrap"] = bool(track.get("loop_wrap", true))
	elif type == Animation.TYPE_AUDIO:
		out["use_blend"] = bool(track.get("use_blend", false))
	for key in track.get("keys", []):
		match type:
			Animation.TYPE_METHOD:
				out.keys.append({
					"time": float(key.get("time", 0.0)),
					"method": str(key.get("method", "")),
					"args": key.get("args", []),
				})
			Animation.TYPE_AUDIO:
				var stream: Resource = key.get("stream")
				out.keys.append({
					"time": float(key.get("time", 0.0)),
					"stream": stream.resource_path if stream != null else "",
					"start_offset": float(key.get("start_offset", 0.0)),
					"end_offset": float(key.get("end_offset", 0.0)),
				})
			_:
				var encoded := encode_value(key.get("value"))
				out.keys.append({
					"time": float(key.get("time", 0.0)),
					"value": encoded.ok if encoded.has("ok") else null,
					"transition": float(key.get("transition", 1.0)),
				})
	return out


# --- JSON dict -> spec -----------------------------------------------------

static func from_json(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "A clip spec must be a JSON object")
	var dict: Dictionary = raw
	if str(dict.get("format", "")) != FORMAT:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Not a %s document (got format '%s')" % [FORMAT, str(dict.get("format", ""))])
	if int(dict.get("version", 0)) > VERSION:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Clip spec version %d is newer than this toolkit supports (%d)" % [int(dict.version), VERSION])
	var spec := ClipSpec.make(float(dict.get("length", 0.0)), int(dict.get("loop_mode", Animation.LOOP_NONE)))
	for marker in dict.get("markers", []):
		var color := decode_value(marker.get("color"))
		spec.markers.append({
			"name": str(marker.get("name", "")),
			"time": float(marker.get("time", 0.0)),
			"color": color.ok if color.has("ok") else Color(1, 1, 1, 1),
		})
	var tracks: Array = dict.get("tracks", [])
	if tracks.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The clip spec has no tracks")
	for index in tracks.size():
		var built := _track_from_json(tracks[index], index)
		if built.has("error"):
			return built
		spec.tracks.append(built.track)
	return {"spec": spec, "track_count": spec.tracks.size(), "key_count": ClipSpec.total_key_count(spec)}


static func _track_from_json(raw: Variant, index: int) -> Dictionary:
	if not raw is Dictionary:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "tracks[%d] must be an object" % index)
	var dict: Dictionary = raw
	var type := int(dict.get("type", -1))
	if not ClipSpec.is_supported_type(type):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"tracks[%d] has unsupported type %d" % [index, type])
	var path := str(dict.get("path", ""))
	if path.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "tracks[%d] has an empty path" % index)
	var track := {
		"type": type,
		"path": path,
		"enabled": bool(dict.get("enabled", true)),
		"compressed": false,
		"keys": [],
	}
	if ClipSpec.is_value_type(type):
		track["interp"] = int(dict.get("interp", Animation.INTERPOLATION_LINEAR))
		if type == Animation.TYPE_VALUE:
			track["update_mode"] = int(dict.get("update_mode", Animation.UPDATE_CONTINUOUS))
		else:
			track["loop_wrap"] = bool(dict.get("loop_wrap", true))
	elif type == Animation.TYPE_AUDIO:
		track["use_blend"] = bool(dict.get("use_blend", false))
	var keys: Array = dict.get("keys", [])
	if keys.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "tracks[%d] has no keys" % index)
	for key_index in keys.size():
		var key: Dictionary = keys[key_index]
		var time := float(key.get("time", 0.0))
		match type:
			Animation.TYPE_METHOD:
				var method := str(key.get("method", ""))
				if method.is_empty():
					return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
						"tracks[%d].keys[%d] has no method" % [index, key_index])
				track.keys.append({"time": time, "method": method, "args": key.get("args", [])})
			Animation.TYPE_AUDIO:
				var stream_path := str(key.get("stream", ""))
				if stream_path.is_empty():
					return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
						"tracks[%d].keys[%d] has no stream path" % [index, key_index])
				if not ResourceLoader.exists(stream_path):
					return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
						"Audio stream not found: %s" % stream_path)
				track.keys.append({
					"time": time,
					"stream": load(stream_path),
					"start_offset": float(key.get("start_offset", 0.0)),
					"end_offset": float(key.get("end_offset", 0.0)),
				})
			_:
				var decoded := decode_value(key.get("value"))
				if decoded.has("error"):
					return ErrorCodes.make(decoded.error.code,
						"tracks[%d].keys[%d]: %s" % [index, key_index, str(decoded.error.message)])
				track.keys.append({
					"time": time,
					"value": decoded.ok,
					"transition": float(key.get("transition", 1.0)),
				})
	return {"track": track}


# --- path remapping --------------------------------------------------------

## Rewrite every track's node part to `target_path` (keeps the properties).
static func remap_node(spec: Dictionary, target_path: String) -> Dictionary:
	var out := ClipSpec.clone(spec)
	for track in out.tracks:
		var property := ClipSpec.property_of(str(track.get("path", "")))
		track["path"] = "%s:%s" % [target_path, property] if not property.is_empty() else target_path
	return out


# --- summaries -------------------------------------------------------------

static func summarize(spec: Dictionary) -> Dictionary:
	var types := {}
	for track in spec.get("tracks", []):
		var label := ClipSpec.type_name(int(track.get("type", -1)))
		types[label] = int(types.get(label, 0)) + 1
	return {
		"length": float(spec.get("length", 0.0)),
		"loop_mode": int(spec.get("loop_mode", Animation.LOOP_NONE)),
		"track_count": (spec.get("tracks", []) as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"track_types": types,
		"paths": _paths(spec),
	}


static func _paths(spec: Dictionary) -> Array:
	var paths: Array = []
	for track in spec.get("tracks", []):
		paths.append(str(track.get("path", "")))
	return paths
