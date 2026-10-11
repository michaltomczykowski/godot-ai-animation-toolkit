extends "res://tools/check_start_stop_quality.gd"

## Play the saved public composition; independent sources remain saved clips.
func _contacts(row: Dictionary, segment: Dictionary, clock: float, side: String, source: Dictionary) -> bool:
	var op: String = segment.source_animation
	if op == "idle_cycle": return true
	if op == "walk_cycle":
		source.time = clock
		return Native.contact(source, side)
	for contact: Dictionary in row.sources[op].declared_contacts:
		if contact.side == side and clock >= float(contact.start) - 0.000001 and clock <= float(contact.end) + 0.000001: return true
	return false

func _sequence_check(row: Dictionary, fps: int, mode: String) -> Dictionary:
	var v := Native.load_case(row, root)
	v.animation_name = row.params.animation_name
	var segments: Array = row.params.segments
	var sources := {}
	for op in row.sources:
		var source_row: Dictionary = row.duplicate(true)
		source_row.params.animation_name = op
		sources[op] = Native.load_case(source_row, root)
	var expected_travel := Vector3.ZERO
	for segment: Dictionary in segments:
		var source: Dictionary = sources[segment.source_animation]
		var track: int = source.clip.find_track(source.player.root_motion_track, Animation.TYPE_POSITION_3D)
		if track >= 0:
			expected_travel += source.clip.position_track_interpolate(track, segment.source_end) - source.clip.position_track_interpolate(track, segment.source_start)
	var mixer := _tree(v, mode)
	var failures: Array[String] = []
	var active := 0
	for node in v.scene.find_children("*", "AnimationMixer", true, false):
		if node.active: active += 1
	if active != 1: failures.append("Exactly one mixer must own the character")
	if v.clip.loop_mode != Animation.LOOP_NONE: failures.append("Sequence must be a one-shot")
	if v.clip.get_marker_names().size() != int(row.write.contact_markers): failures.append("Marker report differs from saved resource")
	for segment: Dictionary in segments:
		for contact: Dictionary in segment.contacts:
			var found := false
			for label in v.clip.get_marker_names():
				if str(label).split("+").has("contact_" + str(contact.name)) and absf(v.clip.get_marker_time(label) - float(segment.start) - float(contact.time)) < 0.00001: found = true
			if not found: failures.append("Scheduled contact annotation missing")
	var feet := {}
	for side in ["l", "r"]: feet[side] = {"active": false, "anchor": Vector3.ZERO, "slide": 0.0, "penetration": 0.0, "frames": 0, "normal": Vector3.ZERO, "flips": 0}
	var worst := Vector2.ZERO
	var compared := 0
	var backward := 0.0
	var previous_root: Vector3 = v.body.global_position
	var action_duration: float = row.write.capture_duration
	var frames := ceili((action_duration + float(row.write.root_motion_terminal_hold) + 0.5) * fps)
	for frame in frames + 1:
		var time := float(frame) / fps
		if frame > 0:
			mixer.advance(1.0 / fps)
			v.body.position += v.body.quaternion * mixer.get_root_motion_position()
		var delta: Vector3 = v.body.global_position - previous_root
		backward = maxf(backward, -delta.dot(v.forward))
		previous_root = v.body.global_position
		var index := 0
		for i in segments.size():
			if time >= float(segments[i].start) - 0.000001: index = i
		var segment: Dictionary = segments[index]
		var clock := lerpf(float(segment.source_start), float(segment.source_end), clampf((time - float(segment.start)) / float(segment.duration), 0.0, 1.0))
		var source: Dictionary = sources[segment.source_animation]
		# The sequence's timed blends are covered by native composition suites;
		# compare every complete played source pose outside those brief intervals.
		if time >= float(segment.start) + float(segment.fade_in) - 0.000001:
			source.player.seek(clock, true)
			var diff := _difference(_poses(v.rig), _poses(source.rig))
			worst.x = maxf(worst.x, diff.x)
			worst.y = maxf(worst.y, diff.y)
			compared += 1
		for side in ["l", "r"]:
			var f: Dictionary = feet[side]
			var foot := Native.point(v, "foot_" + side)
			var on := _contacts(row, segment, clock, side, source)
			if on:
				if not f.active: f.anchor = foot
				f.slide = maxf(f.slide, Native.flat(foot - f.anchor, v.up).length())
				f.frames += 1
			f.active = on
			f.penetration = maxf(f.penetration, float(v.ground) - foot.dot(v.up))
			var thigh := Native.point(v, "thigh_" + side)
			var shin := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var bend := shin - thigh - axis * (shin - thigh).dot(axis)
			if bend.length() > 0.001 * float(v.leg):
				var normal := bend.normalized()
				if f.normal.length_squared() > 0.5 and normal.dot(f.normal) < -0.5: f.flips += 1
				f.normal = normal
			for i in v.rig.get_bone_count():
				if not v.rig.get_bone_global_pose(i).is_finite(): failures.append("Nonfinite played pose")
	if worst.x > 0.00001 or worst.y > 0.0001: failures.append("Played sequence differs from independent complete source pose")
	var root_error: float = (v.body.global_position - v.initial_body).distance_to(expected_travel)
	if root_error > 0.00001 or backward > 0.00001: failures.append("Root travel/ownership failed")
	var metrics := {}
	for side in feet:
		var f: Dictionary = feet[side]
		if f.frames == 0 or f.slide > minf(0.02 * float(v.leg), 0.03) or f.penetration > 0.01 * float(v.leg) or f.flips > 0: failures.append("World contact or pole limit failed: " + str(side))
		metrics[side] = {"stance_slide_m": f.slide, "penetration_m": f.penetration, "contact_frames": f.frames, "knee_flips": f.flips}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "active_mixers": active, "frames": frames + 1,
		"source_pose_samples": compared, "max_position_error_m": worst.x, "max_rotation_error_rad": worst.y,
		"root_error_m": root_error, "backward_root_step_m": backward, "feet": metrics, "failures": failures, "passed": failures.is_empty()}
	for source in sources.values(): source.scene.free()
	v.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var results: Array = []
	var passed: bool = route.passed and route.cases.size() == 4
	for row: Dictionary in route.cases:
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var result := _sequence_check(row, fps, mode)
				results.append(result)
				if not result.passed: passed = false
	passed = passed and results.size() == 24 and logger.errors.is_empty()
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify({"passed": passed, "source_head": route.source_head,
		"runs": results, "engine_errors": logger.errors, "visual_approval": false}))
	OS.remove_logger(logger)
	print("TRANSITION_SEQUENCE_CHECK=" + JSON.stringify({"passed": passed, "runs": results.size(), "engine_errors": logger.errors}))
	quit(0 if passed else 1)
