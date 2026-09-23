@tool
extends RefCounted

## Pure spec -> spec transforms. Every function takes a spec and returns a new
## one (inputs are never mutated), so the whole edit surface is tier-1 testable
## without an editor. Value semantics are documented per op; unsupported value
## types pass through untouched rather than being corrupted.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

const _TIME_EPSILON := 0.000001
const _PROPERTY_ROTATION := ["rotation", "rotation_degrees", "quaternion"]
const _PROPERTY_POSITION := ["position", "global_position", "offset"]
const _PROPERTY_SCALE := ["scale"]


# --- retime ----------------------------------------------------------------

## Scale every key time (and the clip length) by `factor`, or scale to
## `target_length`. With `keys_only` the length changes but key times do not.
static func retime(spec: Dictionary, factor: float, target_length: float, keys_only: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var length := float(out.get("length", 0.0))
	var scale := factor
	if target_length > 0.0:
		scale = target_length / length if length > 0.0 else 1.0
	if is_equal_approx(scale, 1.0):
		return out
	if not keys_only:
		for track in out.tracks:
			for key in track.keys:
				key["time"] = float(key.get("time", 0.0)) * scale
		for marker in out.markers:
			marker["time"] = float(marker.get("time", 0.0)) * scale
		out.length = length * scale
	else:
		out.length = length * scale
	return out


# --- retarget --------------------------------------------------------------

## Rewrite track paths. `remaps` is a list of
## `{from, to, mode}` with mode:
##   "exact"  — the whole track path equals `from` (property included)
##   "node"   — the node part equals `from`; the property is kept
##   "prefix" — the node part equals `from` or starts with `from + "/"`
## The first matching remap wins. Returns `{spec, changed}`.
static func retarget(spec: Dictionary, remaps: Array) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var changed := 0
	for track in out.tracks:
		var path := str(track.get("path", ""))
		for remap in remaps:
			var from := str(remap.get("from", ""))
			var to := str(remap.get("to", ""))
			var mode := str(remap.get("mode", "node"))
			if from.is_empty():
				continue
			var new_path := ""
			match mode:
				"exact":
					if path == from:
						new_path = to
				"prefix":
					var node := ClipSpec.node_path_of(path)
					if node == from:
						new_path = to + path.substr(from.length())
					elif node.begins_with(from + "/"):
						new_path = to + path.substr(from.length())
				_:
					var node := ClipSpec.node_path_of(path)
					if node == from:
						new_path = to + path.substr(from.length())
			if not new_path.is_empty() and new_path != path:
				track["path"] = new_path
				changed += 1
				break
	return {"spec": out, "changed": changed}


# --- reverse ---------------------------------------------------------------

## Mirror every key time about the clip length, so the clip plays backwards.
static func reverse(spec: Dictionary) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var length := float(out.get("length", 0.0))
	for track in out.tracks:
		for key in track.keys:
			key["time"] = length - float(key.get("time", 0.0))
		ClipSpec.sort_keys(track)
	for marker in out.markers:
		marker["time"] = length - float(marker.get("time", 0.0))
	out.markers.sort_custom(func(a, b): return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
	return out


# --- mirror ----------------------------------------------------------------

## Mirror values across the plane(s) named by `axes` ("x", "y", "z", "xy", ...).
## Position/offset components flip about `pivot`; rotations are mirrored as
## proper rotations (float 2D rotation and quaternion/euler tracks negate);
## scale is only touched when `include_scale` is set; other properties and
## method/audio tracks pass through. Returns `{spec, changed}`.
static func mirror(spec: Dictionary, axes: String, pivot: Variant, include_scale: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var changed := 0
	for track in out.tracks:
		var type := int(track.get("type", -1))
		if not ClipSpec.is_value_type(type):
			continue
		var property := ClipSpec.property_of(str(track.get("path", "")))
		var base := property.split(":")[0]
		var sub := property.split(":")[1] if property.contains(":") else ""
		for key in track.keys:
			var value: Variant = key.get("value")
			var kind := ClipSpec.value_kind(value)
			if type == Animation.TYPE_ROTATION_3D or _PROPERTY_ROTATION.has(base):
				if kind == "float":
					key["value"] = -float(value)
					changed += 1
				elif kind == "vector3":
					var quat := Quaternion.from_euler(value as Vector3)
					key["value"] = ClipSpec.negate_axes(quat, axes).to_euler()
					changed += 1
				elif kind == "quaternion":
					key["value"] = ClipSpec.negate_axes(value, axes)
					changed += 1
			elif _PROPERTY_POSITION.has(base):
				if kind == "vector2" or kind == "vector3":
					var mirror_pivot: Variant = null
					if pivot is Vector2 or pivot is Vector3:
						mirror_pivot = pivot
					key["value"] = ClipSpec.negate_axes(value, axes, mirror_pivot)
					changed += 1
				elif kind == "float" and axes.contains(sub):
					key["value"] = -float(value)
					changed += 1
			elif include_scale and _PROPERTY_SCALE.has(base):
				if kind == "vector2" or kind == "vector3":
					key["value"] = ClipSpec.negate_axes(value, axes)
					changed += 1
				elif kind == "float":
					key["value"] = -float(value)
					changed += 1
	return {"spec": out, "changed": changed}


## Drop keys that share a time with the previous key (wrapping a loop can land
## the first and last key of a seam on the same time).
static func _dedupe_times(track: Dictionary) -> void:
	var keys: Array = track.get("keys", [])
	var kept: Array = []
	for key in keys:
		if not kept.is_empty() and is_equal_approx(float(kept[kept.size() - 1].get("time", 0.0)), float(key.get("time", 0.0))):
			continue
		kept.append(key)
	track["keys"] = kept


# --- offset ----------------------------------------------------------------

## Shift every key time by `delta` seconds. With `wrap` the shift happens inside
## the clip length (loop phase rotation); without it times clamp at 0 and the
## length grows to fit the last key.
static func offset(spec: Dictionary, delta: float, wrap: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	if is_zero_approx(delta):
		return out
	var length := float(out.get("length", 0.0))
	if wrap and length > 0.0:
		for track in out.tracks:
			for key in track.keys:
				key["time"] = fposmod(float(key.get("time", 0.0)) + delta, length)
			ClipSpec.sort_keys(track)
			_dedupe_times(track)
		for marker in out.markers:
			marker["time"] = fposmod(float(marker.get("time", 0.0)) + delta, length)
		return out
	for track in out.tracks:
		for key in track.keys:
			key["time"] = maxf(0.0, float(key.get("time", 0.0)) + delta)
	for marker in out.markers:
		marker["time"] = maxf(0.0, float(marker.get("time", 0.0)) + delta)
	return ClipSpec.normalize(out)


# --- easing / interpolation ------------------------------------------------

## Set the per-key transition value on value-ish keys whose time falls in
## [from, to]. Returns `{spec, changed}`.
static func ease_range(spec: Dictionary, from: float, to: float, transition: float) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var changed := 0
	for track in out.tracks:
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		for key in track.keys:
			var time := float(key.get("time", 0.0))
			if time < from or time > to:
				continue
			key["transition"] = transition
			changed += 1
	return {"spec": out, "changed": changed}


## Set the track-level interpolation type on value-ish tracks (optionally only
## the track at `track_path`). Returns `{spec, changed}`.
static func set_interp(spec: Dictionary, interpolation: int, track_path: String) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var changed := 0
	for track in out.tracks:
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		if not track_path.is_empty() and str(track.get("path", "")) != track_path:
			continue
		track["interp"] = interpolation
		changed += 1
	return {"spec": out, "changed": changed}


# --- trim / split / merge --------------------------------------------------

## Value of a value-ish track at `time` (nearest-key fallback outside the key
## range). Honors the left key's per-key transition shape and, for cubic /
## nearest tracks, the engine's own interpolator, so spec math and playback
## agree. Returns null for non-value tracks and empty tracks.
static func sample_track(track: Dictionary, time: float) -> Variant:
	if not ClipSpec.is_value_type(int(track.get("type", -1))):
		return null
	var keys: Array = track.get("keys", [])
	if keys.is_empty():
		return null
	if time <= float(keys[0].get("time", 0.0)):
		return keys[0].get("value")
	var last: Dictionary = keys[keys.size() - 1]
	if time >= float(last.get("time", 0.0)):
		return last.get("value")
	if int(track.get("interp", Animation.INTERPOLATION_LINEAR)) != Animation.INTERPOLATION_LINEAR:
		return sample_track_exact(track, time)
	for i in range(keys.size() - 1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var ta := float(a.get("time", 0.0))
		var tb := float(b.get("time", 0.0))
		if time < ta or time > tb:
			continue
		var span := tb - ta
		if span <= _TIME_EPSILON:
			return b.get("value")
		var va: Variant = a.get("value")
		var vb: Variant = b.get("value")
		if not ClipSpec.can_lerp(va, vb):
			return va
		var c := ease_curve((time - ta) / span, ValueCodec.parse_transition(a.get("transition", 1.0)))
		return ClipSpec.lerp_value(va, vb, c)
	return null


## Exact value of a value-ish track at `time`, sampled through the engine's own
## interpolator: a scratch Animation is built from the track, so per-key
## transitions and cubic interpolation behave exactly as they do at playback.
## Prefer `sample_built_track` when sampling one track many times.
static func sample_track_exact(track: Dictionary, time: float) -> Variant:
	return sample_built_track(build_track_animation(track), time)


## A scratch single-track Animation for engine-side sampling (transitions and
## cubic included). The track is deep-copied, so the input spec is untouched.
static func build_track_animation(track: Dictionary) -> Animation:
	var spec := ClipSpec.make(ClipSpec.last_key_time(track), Animation.LOOP_NONE)
	spec.tracks.append(track.duplicate(true))
	return SpecBuilder.to_animation(spec)


## Value of the first track of a `build_track_animation` result at `time`.
static func sample_built_track(anim: Animation, time: float) -> Variant:
	if anim == null or anim.get_track_count() == 0:
		return null
	match anim.track_get_type(0):
		Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(0, time)
		Animation.TYPE_ROTATION_3D:
			return anim.rotation_track_interpolate(0, time)
		Animation.TYPE_SCALE_3D:
			return anim.scale_track_interpolate(0, time)
		_:
			return anim.value_track_interpolate(0, time)


## Godot's `Math::ease(p_x, p_c)` curve. `transition` is the per-key encoding
## used everywhere else (1.0 linear, 2.0 ease_in, 0.5 ease_out, -2.0
## ease_in_out, 0.0 hold; other positive/negative floats are custom exponents).
static func ease_curve(p_x: float, transition: float) -> float:
	var x := clampf(p_x, 0.0, 1.0)
	if is_zero_approx(transition):
		return 0.0
	if transition > 0.0:
		if transition < 1.0:
			return 1.0 - pow(1.0 - x, 1.0 / transition)
		return pow(x, transition)
	return 0.5 * (
		pow(2.0 * x, -transition) if x < 0.5
		else 2.0 - pow(2.0 - x * 2.0, -transition)
	)


## Keep only [from, to], shifted to start at 0, with the clip length set to
## `to - from`. With `keep_bounds` value-ish tracks get sampled keys at both cut
## edges so the motion at the edges is preserved.
static func trim(spec: Dictionary, from: float, to: float, keep_bounds: bool) -> Dictionary:
	var out := ClipSpec.make(to - from, int(spec.get("loop_mode", Animation.LOOP_NONE)))
	for track in spec.get("tracks", []):
		var new_track: Dictionary = ClipSpec.clone({"t": track}).t
		new_track["keys"] = []
		for key in track.get("keys", []):
			var time := float(key.get("time", 0.0))
			if time < from - _TIME_EPSILON or time > to + _TIME_EPSILON:
				continue
			var kept: Dictionary = key.duplicate(true)
			kept["time"] = clampf(time - from, 0.0, to - from)
			new_track.keys.append(kept)
		if keep_bounds and ClipSpec.is_value_type(int(new_track.get("type", -1))):
			_add_boundary_key(new_track, 0.0, track, from)
			_add_boundary_key(new_track, to - from, track, to)
		if not (new_track.keys as Array).is_empty():
			ClipSpec.sort_keys(new_track)
			out.tracks.append(new_track)
	for marker in spec.get("markers", []):
		var time := float(marker.get("time", 0.0))
		if time < from - _TIME_EPSILON or time > to + _TIME_EPSILON:
			continue
		out.markers.append({
			"name": marker.get("name", ""),
			"time": clampf(time - from, 0.0, to - from),
			"color": marker.get("color", Color(1, 1, 1, 1)),
		})
	return out


## Insert a key at `target_time` (in the trimmed clip) sampled from the original
## track at `sample_time`, unless a key already sits at that time.
static func _add_boundary_key(target: Dictionary, target_time: float, source: Dictionary, sample_time: float) -> void:
	for key in target.get("keys", []):
		if is_equal_approx(float(key.get("time", 0.0)), target_time):
			return
	var sampled: Variant = sample_track(source, sample_time)
	if sampled == null:
		return
	target.keys.append({"time": target_time, "value": sampled, "transition": 1.0})


## Two clips cut at `time`: `{head, tail}`. The tail starts at time 0.
static func split(spec: Dictionary, time: float) -> Dictionary:
	var length := float(spec.get("length", 0.0))
	return {
		"head": trim(spec, 0.0, time, true),
		"tail": trim(spec, time, length, true),
	}


## Concatenate specs end to end, offsetting each by the running length plus
## `gap`. Tracks that share (type, path) are merged into one; the result is
## always LOOP_NONE.
static func merge(specs: Array, gap: float) -> Dictionary:
	var out := ClipSpec.make(0.0, Animation.LOOP_NONE)
	var cursor := 0.0
	for spec in specs:
		for track in spec.get("tracks", []):
			var path := str(track.get("path", ""))
			var type := int(track.get("type", -1))
			var existing := ClipSpec.find_track_index(out, path, type)
			var target: Dictionary
			if existing >= 0:
				target = out.tracks[existing]
			else:
				target = ClipSpec.clone({"t": track}).t
				target["keys"] = []
				out.tracks.append(target)
			for key in track.get("keys", []):
				var shifted: Dictionary = key.duplicate(true)
				shifted["time"] = float(key.get("time", 0.0)) + cursor
				target.keys.append(shifted)
		for marker in spec.get("markers", []):
			out.markers.append({
				"name": marker.get("name", ""),
				"time": float(marker.get("time", 0.0)) + cursor,
				"color": marker.get("color", Color(1, 1, 1, 1)),
			})
		cursor += float(spec.get("length", 0.0)) + gap
	out.length = maxf(0.0, cursor - gap)
	for track in out.tracks:
		ClipSpec.sort_keys(track)
	return out


# --- amplitude -------------------------------------------------------------

## Scale every value-ish key's distance from a baseline by `factor`. The
## baseline is `baseline` when given, else each track's first key value.
static func amplitude(spec: Dictionary, factor: float, baseline: Variant, has_baseline: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	for track in out.tracks:
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		var base: Variant = baseline if has_baseline else ClipSpec.first_key_value(track)
		if base == null:
			continue
		for key in track.keys:
			key["value"] = ClipSpec.scale_delta(key.get("value"), base, factor)
	return out


# --- loop ------------------------------------------------------------------

## Set the loop mode. With `make_seamless` every value-ish track gets a final
## key at the clip length equal to its first key, so a linear loop wraps without
## a jump.
static func set_loop(spec: Dictionary, loop_mode: int, make_seamless: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	out.loop_mode = loop_mode
	if not make_seamless:
		return out
	var length := float(out.get("length", 0.0))
	if length <= 0.0:
		return out
	for track in out.tracks:
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		var keys: Array = track.keys
		if keys.is_empty():
			continue
		var first: Dictionary = keys[0]
		var last: Dictionary = keys[keys.size() - 1]
		if is_equal_approx(float(last.get("time", 0.0)), length):
			last["value"] = first.get("value")
			if first.has("transition"):
				last["transition"] = first.get("transition")
		else:
			keys.append({
				"time": length,
				"value": first.get("value"),
				"transition": first.get("transition", 1.0),
			})
	return out


# --- key_edit --------------------------------------------------------------

## Index of the key nearest `time` within `tolerance`, or -1.
static func nearest_key_index(track: Dictionary, time: float, tolerance: float) -> int:
	var best := -1
	var best_delta := tolerance
	var keys: Array = track.get("keys", [])
	for i in keys.size():
		var delta := absf(float(keys[i].get("time", 0.0)) - time)
		if delta <= best_delta:
			best = i
			best_delta = delta
	return best


## Add / set / remove / move one key on one track. Returns
## `{spec, key_index}`; `key_index` is -1 when nothing matched.
static func key_edit(
	spec: Dictionary, track_index: int, action: String, time: float,
	value: Variant, transition: float, new_time: float, tolerance: float,
) -> Dictionary:
	var out := ClipSpec.clone(spec)
	if track_index < 0 or track_index >= out.tracks.size():
		return {"spec": out, "key_index": -1}
	var track: Dictionary = out.tracks[track_index]
	var is_method := int(track.get("type", -1)) == Animation.TYPE_METHOD
	var index := nearest_key_index(track, time, tolerance)
	match action:
		"add":
			if index >= 0 and is_equal_approx(float(track.keys[index].get("time", 0.0)), time):
				if is_method:
					track.keys[index]["method"] = str(value)
				else:
					track.keys[index]["value"] = value
					track.keys[index]["transition"] = transition
				return {"spec": out, "key_index": index}
			var key: Dictionary
			if is_method:
				key = {"time": time, "method": str(value), "args": []}
			else:
				key = {"time": time, "value": value, "transition": transition}
			track.keys.append(key)
			ClipSpec.sort_keys(track)
			return {"spec": out, "key_index": nearest_key_index(track, time, tolerance)}
		"set":
			if index < 0:
				return {"spec": out, "key_index": -1}
			if is_method:
				track.keys[index]["method"] = str(value)
			else:
				track.keys[index]["value"] = value
				track.keys[index]["transition"] = transition
			return {"spec": out, "key_index": index}
		"remove":
			if index < 0:
				return {"spec": out, "key_index": -1}
			track.keys.remove_at(index)
			return {"spec": out, "key_index": index}
		"move":
			if index < 0:
				return {"spec": out, "key_index": -1}
			track.keys[index]["time"] = new_time
			ClipSpec.sort_keys(track)
			return {"spec": out, "key_index": nearest_key_index(track, new_time, tolerance)}
	return {"spec": out, "key_index": -1}


# --- cleanup ---------------------------------------------------------------

## Drop redundant keys: consecutive keys with equal values (and transition) are
## collapsed to the last one, keys closer than `min_gap` to the previous kept
## key are dropped, and empty tracks are removed. The clip length is preserved.
## Returns `{spec, removed}`.
static func cleanup(spec: Dictionary, tolerance: float, min_gap: float, drop_empty: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var removed := 0
	var kept_tracks: Array = []
	for track in out.tracks:
		var kept: Array = []
		var is_method := int(track.get("type", -1)) == Animation.TYPE_METHOD
		for key in track.get("keys", []):
			if kept.is_empty():
				kept.append(key)
				continue
			var prev: Dictionary = kept[kept.size() - 1]
			var duplicate := false
			if is_method:
				duplicate = str(prev.get("method", "")) == str(key.get("method", ""))
			else:
				duplicate = (
					ClipSpec.values_equal(prev.get("value"), key.get("value"), tolerance)
					and absf(float(prev.get("transition", 1.0)) - float(key.get("transition", 1.0))) <= tolerance
				)
			if duplicate:
				kept[kept.size() - 1] = key
				removed += 1
				continue
			if min_gap > 0.0 and float(key.get("time", 0.0)) - float(prev.get("time", 0.0)) < min_gap:
				removed += 1
				continue
			kept.append(key)
		track["keys"] = kept
		if kept.is_empty() and drop_empty:
			removed += 1
			continue
		kept_tracks.append(track)
	out.tracks = kept_tracks
	return {"spec": out, "removed": removed}
