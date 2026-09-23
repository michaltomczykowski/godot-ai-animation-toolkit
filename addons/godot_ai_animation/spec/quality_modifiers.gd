@tool
extends RefCounted

## Clip-quality passes for the edit tool, on top of the spec engine: smoothing,
## engine-exact resampling, seeded micro-noise, per-track overlap (follow-
## through) and additive/mix clip layering. Pure spec -> spec functions, so the
## whole surface is tier-1 testable.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const MotionDrivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")

const _EPSILON := 0.000001


## Tracks a pass applies to: `track_path` empty means every value-ish track;
## otherwise an exact track path, a node path, or a node path prefix.
static func _select_tracks(spec: Dictionary, track_path: String) -> Array:
	var selected: Array = []
	for track in spec.get("tracks", []):
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		if track_path.is_empty() or _matches(track, track_path):
			selected.append(track)
	return selected


static func _matches(track: Dictionary, track_path: String) -> bool:
	var path := str(track.get("path", ""))
	if path == track_path:
		return true
	var node := ClipSpec.node_path_of(path)
	return node == track_path or node.begins_with(track_path + "/")


# --- smooth -----------------------------------------------------------------

## Soften key values in place: each key lerps toward the midpoint of its
## neighbours, `passes` times. Looping clips wrap so the seam stays smooth.
## Returns `{spec, changed}`.
static func smooth(spec: Dictionary, strength: float, passes: int, track_path: String = "") -> Dictionary:
	var out := ClipSpec.clone(spec)
	var amount := clampf(strength, 0.0, 1.0)
	var loops := int(out.get("loop_mode", Animation.LOOP_NONE)) != Animation.LOOP_NONE
	var changed := 0
	for track in _select_tracks(out, track_path):
		var keys: Array = track.get("keys", [])
		if keys.size() < 3 or amount <= 0.0 or passes <= 0:
			continue
		for _pass in maxi(1, passes):
			var previous_values: Array = []
			for key in keys:
				previous_values.append(key.get("value"))
			for index in keys.size():
				var neighbour := _neighbour_average(
					previous_values[index - 1] if index > 0 else (previous_values[keys.size() - 1] if loops else previous_values[index]),
					previous_values[index + 1] if index < keys.size() - 1 else (previous_values[0] if loops else previous_values[index]),
					previous_values[index])
				if neighbour == null:
					continue
				keys[index]["value"] = ClipSpec.lerp_value(previous_values[index], neighbour, amount)
				changed += 1
	return {"spec": out, "changed": changed}


## Midpoint of two values on the same hemisphere as `reference`.
static func _neighbour_average(a: Variant, b: Variant, reference: Variant) -> Variant:
	if not ClipSpec.can_lerp(a, b) or typeof(a) != typeof(reference):
		return null
	if typeof(a) == TYPE_QUATERNION:
		var qa := a as Quaternion
		var qb := b as Quaternion
		var ref := reference as Quaternion
		if qa.dot(ref) < 0.0:
			qa = -qa
		if qb.dot(ref) < 0.0:
			qb = -qb
		return qa.slerp(qb, 0.5)
	return ClipSpec.lerp_value(a, b, 0.5)


# --- resample ---------------------------------------------------------------

## Rebuild value-ish tracks at a fixed sample rate using the engine's own
## interpolator (per-key transitions and cubic included), so any clip can be
## densified or simplified without changing its shape. Returns `{spec, changed}`.
static func resample(spec: Dictionary, fps: float, interpolation: int, track_path: String = "") -> Dictionary:
	var out := ClipSpec.make(float(spec.get("length", 0.0)), int(spec.get("loop_mode", Animation.LOOP_NONE)))
	out["markers"] = (spec.get("markers", []) as Array).duplicate(true)
	var rate := maxf(fps, 0.5)
	var changed := 0
	for track in spec.get("tracks", []):
		if not ClipSpec.is_value_type(int(track.get("type", -1))) or not (track_path.is_empty() or _matches(track, track_path)):
			out.tracks.append(ClipSpec.clone({"t": track}).t)
			continue
		var times := _sample_times(float(spec.get("length", 0.0)), rate)
		var anim := SpecModifiers.build_track_animation(track)
		var keys: Array = []
		for time in times:
			var value = SpecModifiers.sample_built_track(anim, time)
			if value == null:
				continue
			keys.append({"time": time, "value": value, "transition": 1.0})
		if keys.is_empty():
			continue
		var rebuilt: Dictionary = ClipSpec.clone({"t": track}).t
		rebuilt["keys"] = keys
		rebuilt["interp"] = interpolation
		out.tracks.append(rebuilt)
		changed += keys.size()
	return {"spec": out, "changed": changed}


static func _sample_times(length: float, fps: float) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	if length <= 0.0:
		times.append(0.0)
		return times
	var step := 1.0 / fps
	var count := int(floor(length * fps + _EPSILON))
	for index in count + 1:
		var time := minf(float(index) * step, length)
		times.append(time)
	if times[times.size() - 1] < length - _EPSILON:
		times.append(length)
	return times


# --- add_noise --------------------------------------------------------------

## Add deterministic, smooth micro-motion to value-ish keys. `amount` is degrees
## for rotation tracks (a small rotation about a seeded axis) and units for
## vectors; `frequency` is how many noise cycles fit across the track.
## Returns `{spec, changed}`.
static func add_noise(spec: Dictionary, amount: float, frequency: float, seed_value: int, track_path: String = "") -> Dictionary:
	var out := ClipSpec.clone(spec)
	var changed := 0
	for track in _select_tracks(out, track_path):
		var keys: Array = track.get("keys", [])
		var type := int(track.get("type", -1))
		var property := ClipSpec.property_of(str(track.get("path", "")))
		var track_seed := seed_value + str(track.get("path", "")).hash()
		for index in keys.size():
			var x := frequency * float(index) / maxf(float(keys.size() - 1), 1.0)
			var value: Variant = keys[index].get("value")
			if typeof(value) == TYPE_QUATERNION or type == Animation.TYPE_ROTATION_3D:
				var axis := _seeded_axis(track_seed + index)
				var degrees := MotionDrivers.signal_value("noise", x, track_seed, 3) * amount
				keys[index]["value"] = (value as Quaternion * Quaternion(axis, deg_to_rad(degrees))).normalized()
			elif typeof(value) == TYPE_VECTOR3:
				var offset := Vector3(
					MotionDrivers.signal_value("noise", x, track_seed, 3),
					MotionDrivers.signal_value("noise", x, track_seed + 1, 3),
					MotionDrivers.signal_value("noise", x, track_seed + 2, 3)) * amount
				if type == Animation.TYPE_SCALE_3D or property == "scale":
					keys[index]["value"] = (value as Vector3) * (Vector3.ONE + offset)
				else:
					keys[index]["value"] = (value as Vector3) + offset
			elif typeof(value) == TYPE_VECTOR2:
				var offset2 := Vector2(
					MotionDrivers.signal_value("noise", x, track_seed, 3),
					MotionDrivers.signal_value("noise", x, track_seed + 1, 3)) * amount
				if property == "scale":
					keys[index]["value"] = (value as Vector2) * (Vector2.ONE + offset2)
				else:
					keys[index]["value"] = (value as Vector2) + offset2
			elif typeof(value) == TYPE_COLOR:
				var offsetc := MotionDrivers.signal_value("noise", x, track_seed, 3) * amount
				var source := value as Color
				keys[index]["value"] = Color(source.r + offsetc, source.g + offsetc, source.b + offsetc, source.a)
			elif typeof(value) == TYPE_FLOAT:
				keys[index]["value"] = float(value) + MotionDrivers.signal_value("noise", x, track_seed, 3) * amount
			else:
				continue
			changed += 1
	return {"spec": out, "changed": changed}


static func _seeded_axis(seed_value: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.length_squared() < _EPSILON:
		return Vector3.UP
	return axis.normalized()


# --- overlap ----------------------------------------------------------------

## Delay the selected tracks by `delay` seconds, leaving the rest alone - the
## one-call way to give a limb or a prop follow-through. With `wrap` the shift
## folds inside the clip length. Returns `{spec, changed}`.
static func overlap(spec: Dictionary, track_path: String, delay: float, wrap: bool) -> Dictionary:
	var out := ClipSpec.clone(spec)
	var length := float(out.get("length", 0.0))
	var changed := 0
	for track in _select_tracks(out, track_path):
		var keys: Array = track.get("keys", [])
		for key in keys:
			var time := float(key.get("time", 0.0)) + delay
			if wrap and length > 0.0:
				time = fposmod(time, length)
			else:
				time = maxf(time, 0.0)
			key["time"] = time
		ClipSpec.sort_keys(track)
		_dedupe_times(track)
		changed += keys.size()
		if not wrap:
			out["length"] = maxf(float(out.get("length", 0.0)), ClipSpec.last_key_time(track))
	return {"spec": out, "changed": changed}


static func _dedupe_times(track: Dictionary) -> void:
	var keys: Array = track.get("keys", [])
	var kept: Array = []
	for key in keys:
		var time := float(key.get("time", 0.0))
		if not kept.is_empty() and is_equal_approx(float((kept[kept.size() - 1] as Dictionary).get("time", 0.0)), time):
			kept[kept.size() - 1] = key
			continue
		kept.append(key)
	track["keys"] = kept


# --- motion report ----------------------------------------------------------

## Per-track motion metrics: key density, peak speed/acceleration, loop-seam gap
## and speed mismatch, quaternion hemisphere flips and constant tracks. Pure and
## read-only; `motion_report` turns the metrics into findings with fix hints.
static func analyze_track(spec: Dictionary, track: Dictionary) -> Dictionary:
	var keys: Array = track.get("keys", [])
	var path := str(track.get("path", ""))
	if keys.size() < 2:
		return {
			"path": path, "keys": keys.size(), "keys_per_second": 0.0,
			"speed_peak": 0.0, "acceleration_peak": 0.0,
			"seam_gap": 0.0, "seam_ratio": 0.0, "flips": 0, "constant": true,
		}
	var length := maxf(float(spec.get("length", 0.0)), 0.0001)
	var flips := 0
	var speed_peak := 0.0
	var acceleration_peak := 0.0
	var previous_speed := -1.0
	for index in range(keys.size() - 1):
		var a: Dictionary = keys[index]
		var b: Dictionary = keys[index + 1]
		var span := maxf(float(b.get("time", 0.0)) - float(a.get("time", 0.0)), 0.000001)
		var speed := _value_distance(a.get("value"), b.get("value")) / span
		if previous_speed >= 0.0:
			acceleration_peak = maxf(acceleration_peak, absf(speed - previous_speed) / span)
		speed_peak = maxf(speed_peak, speed)
		previous_speed = speed
		if typeof(a.get("value")) == TYPE_QUATERNION \
				and (a.value as Quaternion).dot(b.value as Quaternion) < 0.0:
			flips += 1
	var seam_gap := _value_distance(keys[0].get("value"), keys[keys.size() - 1].get("value"))
	var seam_ratio := 0.0
	if int(spec.get("loop_mode", Animation.LOOP_NONE)) != Animation.LOOP_NONE and keys.size() >= 3:
		var first_speed := _segment_speed(keys[0], keys[1])
		var last_speed := _segment_speed(keys[keys.size() - 2], keys[keys.size() - 1])
		if maxf(first_speed, last_speed) > 0.05:
			seam_ratio = maxf(first_speed, last_speed) / maxf(minf(first_speed, last_speed), 0.0001)
	return {
		"path": path,
		"keys": keys.size(),
		"keys_per_second": float(keys.size()) / length,
		"speed_peak": speed_peak,
		"acceleration_peak": acceleration_peak,
		"seam_gap": seam_gap,
		"seam_ratio": seam_ratio,
		"flips": flips,
		"constant": speed_peak <= 0.000001,
	}


## Motion-quality report over every value track: metrics plus findings whose
## `fix` names the op that resolves them. Read-only.
static func motion_report(spec: Dictionary, max_tracks: int = 20) -> Dictionary:
	var tracks: Array = []
	var findings: Array = []
	var flipped := 0
	var worst_seam := 0.0
	var loops := int(spec.get("loop_mode", Animation.LOOP_NONE)) != Animation.LOOP_NONE
	for track in spec.get("tracks", []):
		if not ClipSpec.is_value_type(int(track.get("type", -1))):
			continue
		var metrics := analyze_track(spec, track)
		tracks.append(metrics)
		flipped += int(metrics.flips)
		worst_seam = maxf(worst_seam, float(metrics.seam_gap))
		var path := str(metrics.path)
		if int(metrics.keys) < 2:
			continue
		if loops and float(metrics.seam_gap) > 0.001:
			findings.append(_report_finding("warning", "loop_seam", path,
				"The first and last keys differ by %s - the loop pops." % snappedf(float(metrics.seam_gap), 0.0001),
				"animation_edit loop make_seamless"))
		if loops and float(metrics.seam_ratio) > 4.0:
			findings.append(_report_finding("warning", "seam_speed", path,
				"The wrap segment is %.1fx faster than the first segment." % float(metrics.seam_ratio),
				"animation_edit resample"))
		if int(metrics.flips) > 0:
			findings.append(_report_finding("warning", "hemisphere_flip", path,
				"%d consecutive rotation keys are on opposite hemispheres." % int(metrics.flips),
				"animation_edit resample"))
		if float(metrics.keys_per_second) < 4.0:
			findings.append(_report_finding("info", "sparse_keys", path,
				"Only %s keys/s - fast motion will read as linear." % snappedf(float(metrics.keys_per_second), 0.01),
				"animation_edit resample"))
		if bool(metrics.constant):
			findings.append(_report_finding("info", "constant_track", path,
				"Every key holds the same value.", "animation_edit cleanup"))
	var limited: Array = tracks.slice(0, maxi(max_tracks, 1))
	return {
		"tracks": limited,
		"track_count": tracks.size(),
		"findings": findings,
		"flipped_quaternions": flipped,
		"worst_seam_gap": worst_seam,
		"healthy": findings.is_empty(),
	}


static func _report_finding(severity: String, code: String, path: String, message: String, fix: String) -> Dictionary:
	return {"severity": severity, "code": code, "track": path, "message": message, "fix": fix}


static func _segment_speed(a: Dictionary, b: Dictionary) -> float:
	var span := maxf(float(b.get("time", 0.0)) - float(a.get("time", 0.0)), 0.000001)
	return _value_distance(a.get("value"), b.get("value")) / span


static func _value_distance(a: Variant, b: Variant) -> float:
	if typeof(a) != typeof(b):
		return 0.0
	match typeof(a):
		TYPE_FLOAT, TYPE_INT:
			return absf(float(a) - float(b))
		TYPE_VECTOR2:
			return (a as Vector2).distance_to(b as Vector2)
		TYPE_VECTOR3:
			return (a as Vector3).distance_to(b as Vector3)
		TYPE_COLOR:
			var ca := a as Color
			var cb := b as Color
			return maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), maxf(absf(ca.b - cb.b), absf(ca.a - cb.a)))
		TYPE_QUATERNION:
			return rad_to_deg((a as Quaternion).angle_to(b as Quaternion))
	return 0.0


# --- layer ------------------------------------------------------------------

## Combine an overlay clip onto a base clip. In "mix" mode each overlay key
## blends the base value toward it by `weight`; in "add" mode the overlay's
## delta from its own first key is applied on top (rotation multiply, vector
## add). `remap_node` rewrites the overlay's node part before matching.
## Returns `{spec, changed, tracks_created}`.
static func layer(base: Dictionary, overlay: Dictionary, weight: float, mode: String, remap_node: String = "") -> Dictionary:
	var out := ClipSpec.clone(base)
	var blend := clampf(weight, 0.0, 1.0)
	var changed := 0
	var created := 0
	for source in overlay.get("tracks", []):
		var type := int(source.get("type", -1))
		if not ClipSpec.is_value_type(type):
			continue
		var path := str(source.get("path", ""))
		if not remap_node.is_empty():
			path = remap_node + path.substr(ClipSpec.node_path_of(path).length())
		var index := ClipSpec.find_track_index(out, path, type)
		var target: Dictionary
		if index < 0:
			target = ClipSpec.clone({"t": source}).t
			target["keys"] = []
			target["path"] = path
			out.tracks.append(target)
			created += 1
		else:
			target = out.tracks[index]
		var base_anim := SpecModifiers.build_track_animation(target) if not (target.get("keys", []) as Array).is_empty() else null
		var source_keys: Array = source.get("keys", [])
		var neutral: Variant = (source_keys[0] as Dictionary).get("value") if not source_keys.is_empty() else null
		for key in source_keys:
			var time := float(key.get("time", 0.0))
			var overlay_value: Variant = key.get("value")
			var blended: Variant
			if mode == "add":
				blended = _add_values(
					SpecModifiers.sample_built_track(base_anim, time) if base_anim != null else null,
					overlay_value, neutral, blend, typeof(overlay_value))
			else:
				var base_value: Variant = (
					SpecModifiers.sample_built_track(base_anim, time) if base_anim != null else overlay_value)
				blended = ClipSpec.lerp_value(base_value, overlay_value, blend) if ClipSpec.can_lerp(base_value, overlay_value) else overlay_value
			if blended == null:
				continue
			_put_key(target, time, blended)
			changed += 1
	out["length"] = maxf(float(out.get("length", 0.0)), float(overlay.get("length", 0.0)))
	return {"spec": out, "changed": changed, "tracks_created": created}


static func _add_values(base: Variant, overlay: Variant, neutral: Variant, weight: float, type: int) -> Variant:
	if typeof(overlay) == TYPE_QUATERNION:
		var q: Quaternion = overlay as Quaternion
		var n := Quaternion.IDENTITY
		if typeof(neutral) == TYPE_QUATERNION:
			n = neutral as Quaternion
		var delta: Quaternion = n.inverse() * q
		var scaled: Quaternion = Quaternion.IDENTITY.slerp(delta, weight)
		if base == null:
			return scaled
		return (base as Quaternion * scaled).normalized()
	if typeof(overlay) == TYPE_VECTOR3:
		var delta3: Vector3 = (overlay as Vector3) - (neutral as Vector3) if typeof(neutral) == TYPE_VECTOR3 else overlay as Vector3
		if base == null:
			return delta3 * weight
		return (base as Vector3) + delta3 * weight
	if typeof(overlay) == TYPE_FLOAT:
		var deltaf: float = float(overlay) - float(neutral) if neutral != null else float(overlay)
		if base == null:
			return deltaf * weight
		return float(base) + deltaf * weight
	return null


static func _put_key(track: Dictionary, time: float, value: Variant) -> void:
	var keys: Array = track.get("keys", [])
	for key in keys:
		if is_equal_approx(float(key.get("time", 0.0)), time):
			key["value"] = value
			return
	keys.append({"time": time, "value": value, "transition": 1.0})
	ClipSpec.sort_keys(track)
