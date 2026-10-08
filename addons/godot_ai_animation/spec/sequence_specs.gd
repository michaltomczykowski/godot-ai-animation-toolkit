@tool
extends RefCounted

## Sample several authored clips or poses into one AnimationPlayer-owned clip.
## Segment times are on the output timeline; source times are on each input.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")


static func compose(segments: Array, length: float, fps: int, root_motion_path: String = "", initial_values: Dictionary = {}) -> Dictionary:
	if segments.is_empty() or not is_finite(length) or length <= 0.0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "compose needs segments and a positive duration")
	if fps < 4 or fps > 120 or length * fps > 1200.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "compose needs 4-120 fps and at most 1200 samples")
	var ordered := segments.duplicate(true)
	for segment in ordered:
		if not segment is Dictionary or not segment.has("start") or not (segment.start is int or segment.start is float) or not is_finite(float(segment.start)):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Every segment needs a finite start time")
	ordered.sort_custom(func(a, b): return float(a.start) < float(b.start))
	var previous_start := -1.0
	var tracks := {}
	var markers: Array = []
	for index in ordered.size():
		var segment: Dictionary = ordered[index]
		var start := float(segment.get("start", -1.0))
		var span := float(segment.get("duration", 0.0))
		var fade := float(segment.get("fade_in", 0.0))
		var source_start := float(segment.get("source_start", 0.0))
		var source_end := float(segment.get("source_end", 0.0))
		if not (is_finite(start) and is_finite(span) and is_finite(fade)
				and is_finite(source_start) and is_finite(source_end)) \
				or start < 0.0 or span <= 0.0 or fade < 0.0 or fade > span \
				or start + span > length + 0.00001 or source_end <= source_start \
				or start <= previous_start:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"segments[%d] has invalid timing or duplicates a start time" % index)
		if index == 0 and start > 0.000001:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"the first segment must start at time 0")
		if index > 0 and start < float(ordered[index - 1].start) + float(ordered[index - 1].get("fade_in", 0.0)):
			return ErrorCodes.make(ErrorCodes.OPERATION_UNAVAILABLE, "A new segment cannot start before the preceding fade finishes")
		previous_start = start
		var spec: Dictionary = segment.get("spec", {})
		if not segment.has("_native_animation"):
			segment["_native_animation"] = SpecBuilder.to_animation(spec)
			segment._native_animation.loop_mode = Animation.LOOP_NONE
		for track in spec.get("tracks", []):
			var kind := int(track.get("type", -1))
			if not [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
					Animation.TYPE_SCALE_3D].has(kind):
				return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
					"compose accepts 3D position, rotation and scale tracks only")
			var key := "%d|%s" % [kind, str(track.get("path", ""))]
			tracks[key] = {"type": kind, "path": str(track.path)}
		for marker in spec.get("markers", []):
			var source_time := float(marker.get("time", -1.0))
			if source_time >= source_start and source_time <= source_end:
				markers.append({"name": str(marker.get("name", "")),
					"time": start + span * (source_time - source_start) / (source_end - source_start),
					"color": marker.get("color", Color.WHITE)})
		var contacts: Variant = segment.get("contacts", [])
		if not contacts is Array: return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "contacts must be an array")
		for contact in contacts:
			if not contact is Dictionary or not (contact.get("time") is float or contact.get("time") is int): return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "contact needs a numeric time")
			var contact_time := float(contact.get("time", -1.0))
			var contact_name := str(contact.get("name", ""))
			if not is_finite(contact_time) or contact_time < 0.0 or contact_time > span or contact_name.is_empty():
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"segments[%d] has an invalid contact marker" % index)
			markers.append({"name": "contact_" + contact_name,
				"time": start + contact_time, "color": Color(0.2, 0.9, 0.3)})
	if tracks.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "compose sources have no 3D tracks")
	for label in tracks:
		if not initial_values.has(label): initial_values[label] = Vector3.ZERO if tracks[label].type == Animation.TYPE_POSITION_3D else Vector3.ONE if tracks[label].type == Animation.TYPE_SCALE_3D else Quaternion.IDENTITY
	for segment in ordered: segment["_initial_values"] = initial_values
	# Each source root track is local to its own clip. Carry its displacement
	# into the next segment, including overlaps, so the composed character does
	# not jump back to the origin when a walk or approach clip changes.
	var root_label := "%d|%s" % [Animation.TYPE_POSITION_3D, root_motion_path]
	if not root_motion_path.is_empty() and tracks.has(root_label):
		for index in ordered.size():
			var segment: Dictionary = ordered[index]
			var origin: Vector3 = _sample(segment, root_label, float(segment.start)) if index == 0 and _sample(segment, root_label, float(segment.start)) is Vector3 else initial_values[root_label]
			if index > 0:
				var preceding = _value_at(ordered.slice(0, index), root_label,
					float(segment.start))
				if preceding is Vector3:
					origin = preceding
			var source_start_value = _sample(segment, root_label, float(segment.start))
			if source_start_value is Vector3:
				segment["_root_label"] = root_label
				segment["_root_origin"] = origin
				segment["_root_start"] = source_start_value
	var times: Array = [0.0, length]
	var jumps := {}
	for step in range(1, ceili(length * float(fps))):
		times.append(minf(float(step) / float(fps), length))
	for segment in ordered:
		times.append(float(segment.start))
		times.append(float(segment.start) + float(segment.duration))
		times.append(minf(float(segment.start) + float(segment.get("fade_in", 0.0)), length))
		if segment.start > 0.0 and segment.get("fade_in", 0.0) == 0.0: jumps[float(segment.start)] = true
		var animation: Animation = segment._native_animation
		for track in animation.get_track_count():
			if not animation.track_is_enabled(track): continue
			for key in animation.track_get_key_count(track):
				var source_time := animation.track_get_key_time(track, key)
				if source_time < float(segment.source_start) or source_time > float(segment.source_end): continue
				var at := float(segment.start) + float(segment.duration) * (source_time - float(segment.source_start)) / (float(segment.source_end) - float(segment.source_start))
				times.append(at)
				if key > 0 and (animation.track_get_interpolation_type(track) == Animation.INTERPOLATION_NEAREST or animation.track_get_key_transition(track, key - 1) == 0.0): jumps[at] = true
	times.sort()
	var unique_times: Array = []
	for at in times:
		if unique_times.is_empty() or absf(float(at) - float(unique_times.back())) > 0.000001:
			unique_times.append(at)
	var bridge_times := {}
	for raw_at in jumps:
		var at: float = raw_at
		if at <= 0.0: continue
		# Native transform key times are floats. A mapped key can differ from
		# the grid by nanoseconds; use its already-deduplicated boundary.
		for time in unique_times:
			if absf(float(time) - at) <= 0.000001:
				at = float(time)
				break
		var previous := 0.0
		for time in unique_times:
			if time < at: previous = maxf(previous, time)
		var before: float = at - minf(0.00004 * maxf(1.0, absf(at)), (at - previous) * 0.5)
		unique_times.append(before)
		bridge_times[before] = true
	unique_times.sort()
	for index in unique_times.size() - 1:
		if float(unique_times[index + 1]) - float(unique_times[index]) <= 0.00002 * maxf(1.0, absf(unique_times[index + 1])):
			return ErrorCodes.make(ErrorCodes.OPERATION_UNAVAILABLE, "Sequence boundaries are too close for native key lookup; adjust timing or samples")
	if unique_times.size() > 1200:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"compose would exceed 1200 output keys per track")
	var out := ClipSpec.make(length)
	for label in tracks:
		var info: Dictionary = tracks[label]
		var keys: Array = []
		for at in unique_times:
			var value = _value_at(ordered, label, float(at))
			if value != null:
				keys.append({"time": at, "value": value, "transition": 0.0 if bridge_times.has(at) else 1.0})
		if not keys.is_empty():
			ClipSpec.add_value_track(out, info.path, keys,
				Animation.INTERPOLATION_LINEAR, int(info.type))
	var used_names := {}
	for marker in markers:
		if str(marker.name).is_empty():
			continue
		var marker_name := str(marker.name)
		var candidate := marker_name
		var count := 0
		while used_names.has(candidate):
			count += 1
			candidate = "%s_%d" % [marker_name, count]
		used_names[candidate] = true
		ClipSpec.add_marker(out, candidate,
			float(marker.time), marker.color)
	return {"spec": out, "sample_count": unique_times.size()}


static func _value_at(segments: Array, label: String, time: float) -> Variant:
	var current := 0
	for index in segments.size():
		if time + 0.000001 >= float(segments[index].start):
			current = index
	var now: Dictionary = segments[current]
	var value = _sample(now, label, time)
	if current > 0:
		var fade := float(now.get("fade_in", 0.0))
		if fade > 0.0 and time < float(now.start) + fade:
			var before = _sample(segments[current - 1], label, time)
			if before == null:
				before = _held_before(segments, current - 1, label, time)
			if before != null and value != null and ClipSpec.can_lerp(before, value):
				return ClipSpec.lerp_value(before, value,
					clampf((time - float(now.start)) / fade, 0.0, 1.0))
	if value != null:
		return value
	return _held_before(segments, current - 1, label, time)

static func _held_before(segments: Array, current: int, label: String, time: float) -> Variant:
	for index in range(current, -1, -1):
		var held_at := minf(time, float(segments[index + 1].start)) if index + 1 < segments.size() else time
		var value = _sample(segments[index], label, held_at)
		if value != null: return value
	return segments[0].get("_initial_values", {}).get(label)


static func _sample(segment: Dictionary, label: String, time: float) -> Variant:
	var source_time := lerpf(float(segment.source_start), float(segment.source_end),
		clampf((time - float(segment.start)) / float(segment.duration), 0.0, 1.0))
	for track in (segment.spec as Dictionary).get("tracks", []):
		if "%d|%s" % [int(track.type), str(track.path)] == label:
			var animation: Animation = segment._native_animation
			var index := animation.find_track(NodePath(track.path), int(track.type))
			var value: Variant = animation.position_track_interpolate(index, source_time) if int(track.type) == Animation.TYPE_POSITION_3D else animation.rotation_track_interpolate(index, source_time) if int(track.type) == Animation.TYPE_ROTATION_3D else animation.scale_track_interpolate(index, source_time)
			if label == str(segment.get("_root_label", "")) and value is Vector3:
				return (segment._root_origin as Vector3) + value - (segment._root_start as Vector3)
			return value
	return null
