@tool
extends RefCounted

## Declarative clip spec — the data every generator produces and every edit op
## transforms. Specs are plain Dictionaries (JSON-native) so the pure modifiers
## stay tier-1 testable without an editor.
##
## Shape:
##
##     {
##       "length": float,
##       "loop_mode": int,                 # Animation.LOOP_*
##       "markers": [ {"name": String, "time": float, "color": Color} ],
##       "tracks": [
##         {
##           "type": int,                  # Animation.TYPE_*
##           "path": String,               # NodePath string, relative to the player root
##           "enabled": bool,              # track_is_enabled
##           "compressed": bool,           # track_is_compressed (edit ops refuse these)
##           "keys": [ <key dicts> ],
##           # TYPE_VALUE only:
##           "interp": int,                # Animation.INTERPOLATION_*
##           "update_mode": int,           # Animation.UPDATE_*
##           # TYPE_POSITION_3D / ROTATION_3D / SCALE_3D only:
##           "interp": int,
##           "loop_wrap": bool,
##           # TYPE_AUDIO only:
##           "use_blend": bool,
##         },
##       ],
##     }
##
## Key dicts by track type:
##   TYPE_VALUE / TYPE_POSITION_3D / TYPE_ROTATION_3D / TYPE_SCALE_3D:
##       {"time": float, "value": Variant, "transition": float}
##   TYPE_METHOD:
##       {"time": float, "method": String, "args": Array}
##   TYPE_AUDIO:
##       {"time": float, "stream": Resource, "start_offset": float,
##        "end_offset": float}

const _VALUE_TYPES := [
	Animation.TYPE_VALUE,
	Animation.TYPE_POSITION_3D,
	Animation.TYPE_ROTATION_3D,
	Animation.TYPE_SCALE_3D,
]

const _SUPPORTED_TYPES := [
	Animation.TYPE_VALUE,
	Animation.TYPE_POSITION_3D,
	Animation.TYPE_ROTATION_3D,
	Animation.TYPE_SCALE_3D,
	Animation.TYPE_METHOD,
	Animation.TYPE_AUDIO,
]


# --- construction ----------------------------------------------------------

static func make(length: float, loop_mode: int = Animation.LOOP_NONE) -> Dictionary:
	return {"length": length, "loop_mode": loop_mode, "markers": [], "tracks": []}


static func is_value_type(type: int) -> bool:
	return _VALUE_TYPES.has(type)


static func is_supported_type(type: int) -> bool:
	return _SUPPORTED_TYPES.has(type)


static func type_name(type: int) -> String:
	match type:
		Animation.TYPE_VALUE:
			return "value"
		Animation.TYPE_POSITION_3D:
			return "position_3d"
		Animation.TYPE_ROTATION_3D:
			return "rotation_3d"
		Animation.TYPE_SCALE_3D:
			return "scale_3d"
		Animation.TYPE_METHOD:
			return "method"
		Animation.TYPE_AUDIO:
			return "audio"
		Animation.TYPE_BEZIER:
			return "bezier"
		Animation.TYPE_BLEND_SHAPE:
			return "blend_shape"
		Animation.TYPE_ANIMATION:
			return "animation"
	return "type_%d" % type


## Append a value-ish track and return it.
static func add_value_track(
	spec: Dictionary, path: String, keys: Array,
	interp: int = Animation.INTERPOLATION_LINEAR, type: int = Animation.TYPE_VALUE,
) -> Dictionary:
	var track := {
		"type": type,
		"path": path,
		"enabled": true,
		"compressed": false,
		"keys": keys,
		"interp": interp,
	}
	if type == Animation.TYPE_VALUE:
		track["update_mode"] = Animation.UPDATE_CONTINUOUS
	else:
		track["loop_wrap"] = true
	spec.tracks.append(track)
	return track


static func add_method_track(spec: Dictionary, path: String, keys: Array) -> Dictionary:
	var track := {
		"type": Animation.TYPE_METHOD,
		"path": path,
		"enabled": true,
		"compressed": false,
		"keys": keys,
	}
	spec.tracks.append(track)
	return track


static func add_audio_track(spec: Dictionary, path: String, keys: Array, use_blend: bool = false) -> Dictionary:
	var track := {
		"type": Animation.TYPE_AUDIO,
		"path": path,
		"enabled": true,
		"compressed": false,
		"use_blend": use_blend,
		"keys": keys,
	}
	spec.tracks.append(track)
	return track


static func add_marker(spec: Dictionary, name: String, time: float, color: Color = Color(1, 1, 1, 1)) -> void:
	spec.markers.append({"name": name, "time": time, "color": color})


# --- inspection ------------------------------------------------------------

static func clone(spec: Dictionary) -> Dictionary:
	return spec.duplicate(true)


static func key_count(track: Dictionary) -> int:
	return (track.get("keys", []) as Array).size()


static func total_key_count(spec: Dictionary) -> int:
	var count := 0
	for track in spec.get("tracks", []):
		count += key_count(track)
	return count


static func last_key_time(track: Dictionary) -> float:
	var keys: Array = track.get("keys", [])
	if keys.is_empty():
		return 0.0
	return float(keys[keys.size() - 1].get("time", 0.0))


static func first_key_value(track: Dictionary) -> Variant:
	var keys: Array = track.get("keys", [])
	if keys.is_empty():
		return null
	return keys[0].get("value")


static func find_track_index(spec: Dictionary, path: String, type: int = -1) -> int:
	var tracks: Array = spec.get("tracks", [])
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		if str(track.get("path", "")) != path:
			continue
		if type == -1 or int(track.get("type", -1)) == type:
			return i
	return -1


## Node part of a track path (everything before the first ":" separator).
## "A/B:position" -> "A/B", "A/B:modulate:a" -> "A/B".
static func node_path_of(path: String) -> String:
	var idx := path.find(":")
	if idx <= 0:
		return path
	return path.substr(0, idx)


## Property part of a track path. "A/B:modulate:a" -> "modulate:a".
static func property_of(path: String) -> String:
	var idx := path.find(":")
	if idx <= 0:
		return ""
	return path.substr(idx + 1)


static func track_label(track: Dictionary) -> String:
	return "%s [%s]" % [str(track.get("path", "")), type_name(int(track.get("type", -1)))]


static func sort_keys(track: Dictionary) -> void:
	var keys: Array = track.get("keys", [])
	keys.sort_custom(func(a, b): return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))


static func sort_all(spec: Dictionary) -> void:
	for track in spec.get("tracks", []):
		sort_keys(track)
	spec.markers.sort_custom(func(a, b): return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))


## Sort keys, drop empty tracks, and make sure the clip is at least as long as
## its last key. Returns a new spec.
static func normalize(spec: Dictionary) -> Dictionary:
	var out := clone(spec)
	sort_all(out)
	var kept: Array = []
	for track in out.tracks:
		if not (track.get("keys", []) as Array).is_empty():
			kept.append(track)
	out.tracks = kept
	var last := 0.0
	for track in out.tracks:
		last = maxf(last, last_key_time(track))
	out.length = maxf(float(out.get("length", 0.0)), last)
	return out


# --- value math ------------------------------------------------------------

static func value_kind(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return "float"
		TYPE_VECTOR2:
			return "vector2"
		TYPE_VECTOR3:
			return "vector3"
		TYPE_COLOR:
			return "color"
		TYPE_QUATERNION:
			return "quaternion"
	return "other"


static func can_lerp(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT, TYPE_INT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_QUATERNION:
			return true
	return false


static func lerp_value(a: Variant, b: Variant, t: float) -> Variant:
	if typeof(a) != typeof(b):
		return a
	match typeof(a):
		TYPE_FLOAT, TYPE_INT:
			return lerpf(float(a), float(b), t)
		TYPE_VECTOR2:
			return (a as Vector2).lerp(b as Vector2, t)
		TYPE_VECTOR3:
			return (a as Vector3).lerp(b as Vector3, t)
		TYPE_COLOR:
			return (a as Color).lerp(b as Color, t)
		TYPE_QUATERNION:
			return (a as Quaternion).slerp(b as Quaternion, t)
	return a


static func values_equal(a: Variant, b: Variant, tolerance: float) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT, TYPE_INT:
			return absf(float(a) - float(b)) <= tolerance
		TYPE_VECTOR2:
			return (a as Vector2).distance_to(b as Vector2) <= tolerance
		TYPE_VECTOR3:
			return (a as Vector3).distance_to(b as Vector3) <= tolerance
		TYPE_COLOR:
			var ca := a as Color
			var cb := b as Color
			return (
				absf(ca.r - cb.r) <= tolerance and absf(ca.g - cb.g) <= tolerance
				and absf(ca.b - cb.b) <= tolerance and absf(ca.a - cb.a) <= tolerance
			)
		TYPE_QUATERNION:
			var qa := a as Quaternion
			var qb := b as Quaternion
			# Compare by ANGLE, not by the dot product: `abs(dot) >= 1 - tolerance`
			# is quadratic near identity, so a 1e-4 cosine budget swallowed half a
			# degree and cleanup flattened real motion into a constant pose. The
			# tolerance is in radians, which is what callers can reason about.
			return qa.angle_to(qb) <= tolerance
		TYPE_STRING, TYPE_STRING_NAME:
			return str(a) == str(b)
	return a == b


static func component_of(value: Variant, axis: String) -> float:
	match typeof(value):
		TYPE_VECTOR2:
			return (value as Vector2).x if axis == "x" else (value as Vector2).y
		TYPE_VECTOR3:
			var v := value as Vector3
			if axis == "x":
				return v.x
			return v.y if axis == "y" else v.z
	return 0.0


## Mirror a value across the plane(s) named by `axes` ("x", "xy", ...). Vectors
## flip the listed components about `pivot` (a Vector2/Vector3; zero when
## omitted). Quaternions use the reflection identity q' = (w, x, -y, -z) for the
## X plane (and the cyclic permutations), so a mirrored rotation is still a
## proper rotation. Scalars and other types pass through unchanged.
static func negate_axes(value: Variant, axes: String, pivot: Variant = null) -> Variant:
	var flip_x := axes.contains("x")
	var flip_y := axes.contains("y")
	var flip_z := axes.contains("z")
	match typeof(value):
		TYPE_VECTOR2:
			var v := value as Vector2
			var p: Vector2 = pivot if pivot is Vector2 else Vector2.ZERO
			if flip_x:
				v.x = 2.0 * p.x - v.x
			if flip_y:
				v.y = 2.0 * p.y - v.y
			return v
		TYPE_VECTOR3:
			var v3 := value as Vector3
			var p3: Vector3 = pivot if pivot is Vector3 else Vector3.ZERO
			if flip_x:
				v3.x = 2.0 * p3.x - v3.x
			if flip_y:
				v3.y = 2.0 * p3.y - v3.y
			if flip_z:
				v3.z = 2.0 * p3.z - v3.z
			return v3
		TYPE_QUATERNION:
			var q := value as Quaternion
			var w := q.w
			var x := q.x
			var y := q.y
			var z := q.z
			if flip_x:
				y = -y
				z = -z
			if flip_y:
				x = -x
				z = -z
			if flip_z:
				x = -x
				y = -y
			## Quaternion's constructor order is (x, y, z, w).
			return Quaternion(x, y, z, w).normalized()
	return value


## Scale a value's distance from `baseline` by `factor` (1.0 = unchanged,
## 0.0 = collapsed onto the baseline). Quaternions scale the rotation relative
## to the baseline quaternion.
static func scale_delta(value: Variant, baseline: Variant, factor: float) -> Variant:
	if typeof(value) != typeof(baseline):
		return value
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(baseline) + (float(value) - float(baseline)) * factor
		TYPE_VECTOR2:
			return (baseline as Vector2) + ((value as Vector2) - (baseline as Vector2)) * factor
		TYPE_VECTOR3:
			return (baseline as Vector3) + ((value as Vector3) - (baseline as Vector3)) * factor
		TYPE_COLOR:
			var base := baseline as Color
			var cur := value as Color
			return Color(
				base.r + (cur.r - base.r) * factor,
				base.g + (cur.g - base.g) * factor,
				base.b + (cur.b - base.b) * factor,
				base.a + (cur.a - base.a) * factor,
			)
		TYPE_QUATERNION:
			# Scale the rotation *away from the baseline*, like every branch above:
			# slerping from identity ignored the baseline, so `amplitude(factor=0)`
			# snapped a non-neutral pose to rest instead of collapsing the motion.
			var base := baseline as Quaternion
			return (base * Quaternion.IDENTITY.inverse()) \
				.slerp((base.inverse() * (value as Quaternion)), factor) * base
	return value


# --- continuity ------------------------------------------------------------

## Flip quaternion keys that sit on the opposite hemisphere to their predecessor
## so consecutive rotation keys share a sign (dot >= 0). The rotation is
## unchanged; it keeps slerp/cubic interpolation and exporters on the short
## path. Non-quaternion keys are skipped. Mutates `keys` in place.
static func align_quaternions(keys: Array) -> void:
	var previous := Quaternion()
	var has_previous := false
	for key in keys:
		var value: Variant = key.get("value")
		if typeof(value) != TYPE_QUATERNION:
			continue
		var q := value as Quaternion
		if has_previous and q.dot(previous) < 0.0:
			q = -q
			key["value"] = q
		previous = q
		has_previous = true


## Force a looping key sequence to close: ensure a key sits exactly at `length`
## carrying (a copy of) the first key's value, so a linear or ping-pong loop
## wraps without a jump. No-op for empty keys or keys already past `length`.
## Mutates `keys` in place.
static func close_loop(keys: Array, length: float) -> void:
	if keys.is_empty():
		return
	var first: Dictionary = keys[0]
	if float(first.get("time", 0.0)) >= length:
		return
	var first_value: Variant = first.get("value")
	var last: Dictionary = keys[keys.size() - 1]
	if float(last.get("time", 0.0)) >= length - 0.000001:
		last["value"] = first_value
		last["time"] = length
		return
	var closing := {"time": length, "value": first_value}
	if first.has("transition"):
		closing["transition"] = first.get("transition")
	keys.append(closing)
