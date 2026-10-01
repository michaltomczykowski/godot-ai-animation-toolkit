@tool
extends RefCounted

## Sample several authored clips or poses into one AnimationPlayer-owned clip.
## Segment times are on the output timeline; source times are on each input.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")


static func compose(segments: Array, length: float, fps: int, root_motion_path: String = "") -> Dictionary:
	if segments.is_empty() or not is_finite(length) or length <= 0.0:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "compose needs segments and a positive duration")
	if fps < 4 or fps > 120 or length * fps > 1200.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "compose needs 4-120 fps and at most 1200 samples")
	var ordered := segments.duplicate(true)
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
		previous_start = start
		var spec: Dictionary = segment.get("spec", {})
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
		for contact in segment.get("contacts", []):
			var contact_time := float(contact.get("time", -1.0))
			var contact_name := str(contact.get("name", ""))
			if contact_time < 0.0 or contact_time > span or contact_name.is_empty():
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"segments[%d] has an invalid contact marker" % index)
			markers.append({"name": "contact_" + contact_name,
				"time": start + contact_time, "color": Color(0.2, 0.9, 0.3)})
	if tracks.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "compose sources have no 3D tracks")
	# Each source root track is local to its own clip. Carry its displacement
	# into the next segment, including overlaps, so the composed character does
	# not jump back to the origin when a walk or approach clip changes.
	var root_label := "%d|%s" % [Animation.TYPE_POSITION_3D, root_motion_path]
	if not root_motion_path.is_empty() and tracks.has(root_label):
		for index in ordered.size():
			var segment: Dictionary = ordered[index]
			var origin := Vector3.ZERO
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
	for step in range(1, ceili(length * float(fps))):
		times.append(minf(float(step) / float(fps), length))
	for segment in ordered:
		times.append(float(segment.start))
		times.append(minf(float(segment.start) + float(segment.get("fade_in", 0.0)), length))
	times.sort()
	var unique_times: Array = []
	for at in times:
		if unique_times.is_empty() or absf(float(at) - float(unique_times.back())) > 0.000001:
			unique_times.append(at)
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
				keys.append({"time": at, "value": value, "transition": 1.0})
		if not keys.is_empty():
			ClipSpec.add_value_track(out, info.path, keys,
				Animation.INTERPOLATION_LINEAR, int(info.type))
	var used_names := {}
	for marker in markers:
		if str(marker.name).is_empty():
			continue
		var marker_name := str(marker.name)
		var count := int(used_names.get(marker_name, 0))
		used_names[marker_name] = count + 1
		ClipSpec.add_marker(out, marker_name if count == 0 else "%s_%d" % [marker_name, count],
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
			if before != null and value != null and ClipSpec.can_lerp(before, value):
				return ClipSpec.lerp_value(before, value,
					clampf((time - float(now.start)) / fade, 0.0, 1.0))
	if value != null:
		return value
	for index in range(current - 1, -1, -1):
		value = _sample(segments[index], label, time)
		if value != null:
			return value
	return null


static func _sample(segment: Dictionary, label: String, time: float) -> Variant:
	var source_time := lerpf(float(segment.source_start), float(segment.source_end),
		clampf((time - float(segment.start)) / float(segment.duration), 0.0, 1.0))
	for track in (segment.spec as Dictionary).get("tracks", []):
		if "%d|%s" % [int(track.type), str(track.path)] == label:
			var value = SpecModifiers.sample_track(track, source_time)
			if label == str(segment.get("_root_label", "")) and value is Vector3:
				return (segment._root_origin as Vector3) + value - (segment._root_start as Vector3)
			return value
	return null
