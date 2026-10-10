extends RefCounted

## Engine-only reference: no toolkit handlers, spec codecs or spring helpers.
static func _value(animation: Animation, index: int, time: float) -> Variant:
	match animation.track_get_type(index):
		Animation.TYPE_POSITION_3D: return animation.position_track_interpolate(index, time)
		Animation.TYPE_ROTATION_3D: return animation.rotation_track_interpolate(index, time)
		Animation.TYPE_SCALE_3D: return animation.scale_track_interpolate(index, time)
	return null
static func _mix(a: Variant, b: Variant, weight: float) -> Variant:
	return a.slerp(b, weight).normalized() if a is Quaternion else a.lerp(b, weight)
static func _baseline(fixture: Node, path: NodePath, kind: int) -> Variant:
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var target: Node = player.get_node(player.root_node).get_node(NodePath(path.get_concatenated_names()))
	if target is Skeleton3D:
		var index: int = target.find_bone(str(path.get_subname(0)))
		return target.get_bone_pose_position(index) if kind == Animation.TYPE_POSITION_3D else target.get_bone_pose_rotation(index) if kind == Animation.TYPE_ROTATION_3D else target.get_bone_pose_scale(index)
	return target.position if kind == Animation.TYPE_POSITION_3D else target.quaternion if kind == Animation.TYPE_ROTATION_3D else target.scale
static func _pose(fixture: Node, raw: Dictionary) -> Animation:
	var skeleton := fixture.get_node("Character/Skeleton") as Skeleton3D
	var clip := Animation.new()
	clip.length = 1.0
	for name in raw.bones:
		var rest := skeleton.get_bone_rest(skeleton.find_bone(name))
		var values: Dictionary = raw.bones[name]
		var rq: Dictionary = values.get("rotation", {})
		var rp: Dictionary = values.get("position", {})
		var rs: Dictionary = values.get("scale", {})
		var q := Quaternion(float(rq.get("x", 0)), float(rq.get("y", 0)), float(rq.get("z", 0)), float(rq.get("w", 1))).normalized()
		var p := Vector3(float(rp.get("x", 0)), float(rp.get("y", 0)), float(rp.get("z", 0)))
		var s := Vector3(float(rs.get("x", 1)), float(rs.get("y", 1)), float(rs.get("z", 1)))
		for record in [[Animation.TYPE_POSITION_3D, rest.origin + p], [Animation.TYPE_ROTATION_3D, (rest.basis.get_rotation_quaternion() * q).normalized()], [Animation.TYPE_SCALE_3D, s]]:
			var track := clip.add_track(record[0])
			clip.track_set_path(track, NodePath("Skeleton:" + name))
			clip.track_insert_key(track, 0.0, record[1])
			clip.track_insert_key(track, 1.0, record[1])
	return clip
static func _segments(fixture: Node, params: Dictionary, pose_json: Dictionary) -> Array:
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var segments: Array = []
	for raw in params.segments:
		var clip := player.get_animation(raw.source_animation).duplicate(true) as Animation if raw.has("source_animation") else _pose(fixture, raw.get("pose", pose_json))
		clip.loop_mode = Animation.LOOP_NONE
		segments.append({"start": float(raw.start), "span": float(raw.duration), "fade": float(raw.get("fade_in", 0)), "from": float(raw.get("source_start", 0)) if raw.has("source_animation") else 0.0, "to": float(raw.get("source_end", clip.length)) if raw.has("source_animation") else 1.0, "clip": clip, "offset": Vector3.ZERO})
	segments.sort_custom(func(a, b): return a.start < b.start)
	return segments
static func _source(segment: Dictionary, path: NodePath, kind: int, time: float) -> Variant:
	var index := (segment.clip as Animation).find_track(path, kind)
	if index < 0 or not segment.clip.track_is_enabled(index): return null
	var phase := clampf((time - segment.start) / segment.span, 0.0, 1.0)
	var value: Variant = _value(segment.clip, index, segment.from + (segment.to - segment.from) * phase)
	if kind == Animation.TYPE_POSITION_3D: value += segment.offset if segment.get("root", NodePath()) == path else Vector3.ZERO
	return value
static func _timeline(segments: Array, path: NodePath, kind: int, time: float, authored: Variant) -> Variant:
	var current := 0
	for index in segments.size():
		if segments[index].start <= time + 0.000001: current = index
	var now: Dictionary = segments[current]
	var value: Variant = _source(now, path, kind, time)
	if value == null:
		for index in range(current - 1, -1, -1):
			value = _source(segments[index], path, kind, minf(time, segments[index + 1].start))
			if value != null: break
		return authored if value == null else value
	if current > 0 and now.fade > 0.0 and time < now.start + now.fade:
		var before: Variant = _source(segments[current - 1], path, kind, time)
		if before == null: before = _timeline(segments.slice(0, current), path, kind, minf(time, now.start), authored)
		return _mix(before, value, clampf((time - now.start) / now.fade, 0.0, 1.0))
	return value
static func prepared_sequence(fixture: Node, params: Dictionary, pose_json: Dictionary) -> Array:
	var segments := _segments(fixture, params, pose_json)
	var root_path: NodePath = fixture.get_node("Playback/AnimationPlayer").root_motion_track
	for index in segments.size():
		var segment: Dictionary = segments[index]
		if root_path.is_empty(): break
		var own: Variant = _source(segment, root_path, Animation.TYPE_POSITION_3D, segment.start)
		if own == null: continue
		var origin: Variant = own if index == 0 else _timeline(segments.slice(0, index), root_path, Animation.TYPE_POSITION_3D, segment.start, _baseline(fixture, root_path, Animation.TYPE_POSITION_3D))
		segment.root = root_path
		segment.offset = origin - own
	return segments
static func _sequence(fixture: Node, params: Dictionary, pose_json: Dictionary, output: Animation) -> Animation:
	var segments := prepared_sequence(fixture, params, pose_json)
	var reference := Animation.new()
	reference.length = output.length
	for i in output.get_track_count():
		var path := output.track_get_path(i)
		var kind := output.track_get_type(i)
		var authored: Variant = _baseline(fixture, path, kind)
		var track := reference.add_track(kind)
		reference.track_set_path(track, path)
		for key in output.track_get_key_count(i):
			var time := output.track_get_key_time(i, key)
			reference.track_insert_key(track, time, _timeline(segments, path, kind, time, authored), output.track_get_key_transition(i, key))
	return reference
static func _secondary(fixture: Node, params: Dictionary, output: Animation, sample_times: Array = []) -> Animation:
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var rig := fixture.get_node("Character/Skeleton") as Skeleton3D
	var reference := player.get_animation(params.animation_name).duplicate(true) as Animation
	var times: Array = []
	var new_track := output.find_track(NodePath("Skeleton:" + str(params.bones[0])), Animation.TYPE_ROTATION_3D)
	for key in output.track_get_key_count(new_track): times.append(output.track_get_key_time(new_track, key))
	if not sample_times.is_empty(): times = sample_times
	var authored := {}
	var parent_curves := {}
	for name in params.bones:
		authored[name] = rig.get_bone_pose_rotation(rig.find_bone(name))
		parent_curves[name] = []
	player.speed_scale = 1.0
	player.active = true
	player.root_motion_track = NodePath()
	player.playback_auto_capture = false
	player.stop()
	player.play(params.animation_name, 0.0, 1.0)
	player.advance(0.0)
	for step in times.size():
		if step > 0: player.advance(times[step] - times[step - 1])
		for name in params.bones:
			parent_curves[name].append(rig.get_bone_global_pose(rig.get_bone_parent(rig.find_bone(name))).basis.orthonormalized())
	for name in params.bones:
		var parents: Array = parent_curves[name]
		var state: Quaternion = (parents[0] * Basis(authored[name])).get_rotation_quaternion().normalized()
		var velocity := Vector3.ZERO
		var track := reference.add_track(Animation.TYPE_ROTATION_3D)
		reference.track_set_path(track, NodePath("Skeleton:" + str(name)))
		for step in times.size():
			var target: Quaternion = (parents[step] * Basis(authored[name])).get_rotation_quaternion().normalized()
			if step > 0:
				var dt: float = (times[step] - times[step - 1]) * 0.5
				for _half in 2:
					var difference: Quaternion = target * state.inverse()
					if difference.w < 0: difference = -difference
					var axis := Vector3(difference.x, difference.y, difference.z)
					var radians := 2.0 * atan2(axis.length(), absf(difference.w))
					var displacement := axis.normalized() * radians if radians > 0.000001 else Vector3.ZERO
					velocity += (float(params.get("stiffness", 120)) * displacement - float(params.get("damping", 12)) * velocity) * dt
					if velocity.length() * dt > 0.000001: state = (Quaternion(velocity.normalized(), velocity.length() * dt) * state).normalized()
			var local: Quaternion = (parents[step].inverse() * Basis(state)).get_rotation_quaternion().normalized()
			reference.track_insert_key(track, times[step], local)
		if reference.loop_mode != Animation.LOOP_NONE: reference.track_set_key_value(track, reference.track_get_key_count(track) - 1, reference.track_get_key_value(track, 0))
	return reference
static func build(fixture: Node, params: Dictionary, group: String, pose_json: Dictionary, output: Animation) -> Animation:
	if group == "sequence": return _sequence(fixture, params, pose_json, output)
	if group == "secondary": return _secondary(fixture, params, output)
	return output.duplicate(true)
