extends SceneTree

## Independent one-shot playback and joins to separately saved approved clips.
## No production motion sampler, IK, or bone-pose writes are used here.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _poses(rig: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in rig.get_bone_count(): result.append(rig.get_bone_global_pose(i))
	return result

func _rotation(a: Transform3D, b: Transform3D) -> Vector3:
	var q := a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()
	if q.w < 0.0: q = -q
	var axis := Vector3(q.x, q.y, q.z)
	return axis.normalized() * (2.0 * atan2(axis.length(), absf(q.w))) if axis.length() > 0.00000001 else Vector3.ZERO

func _difference(a: Array[Transform3D], b: Array[Transform3D]) -> Vector2:
	var worst := Vector2.ZERO
	if a.size() != b.size(): return Vector2(INF, INF)
	for i in a.size():
		worst.x = maxf(worst.x, a[i].origin.distance_to(b[i].origin))
		worst.y = maxf(worst.y, _rotation(a[i], b[i]).length())
	return worst

func _tree(v: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return v.player
	v.player.active = false
	var tree := AnimationTree.new()
	v.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(v.player)
	tree.root_node = tree.get_path_to(v.player.get_node(v.player.root_node))
	tree.root_motion_track = v.player.root_motion_track
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = v.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _find(manifest: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in manifest.cases:
		if row.id == id: return row
	return {}

func _join(v: Dictionary, other_row: Dictionary, edge: float, phase: float, entering: bool, dt: float) -> Dictionary:
	var reference := Native.load_case(other_row, root)
	var at: float = phase * reference.clip.length
	reference.player.seek(at, true)
	var center := _poses(reference.rig)
	v.player.seek(edge, true)
	var here := _poses(v.rig)
	var endpoint := _difference(here, center)
	var before: Array[Transform3D]
	var after: Array[Transform3D]
	if entering:
		reference.player.seek(fposmod(at - dt, reference.clip.length), true)
		before = _poses(reference.rig)
		v.player.seek(edge + dt, true)
		after = _poses(v.rig)
	else:
		v.player.seek(edge - dt, true)
		before = _poses(v.rig)
		reference.player.seek(fposmod(at + dt, reference.clip.length), true)
		after = _poses(reference.rig)
	var worst := Vector2.ZERO
	var bones: Array = []
	for i in here.size():
		var incoming := here[i].origin - before[i].origin
		var outgoing := after[i].origin - here[i].origin
		var position_jump := incoming.distance_to(outgoing)
		var angular_jump := _rotation(before[i], here[i]).distance_to(_rotation(here[i], after[i]))
		worst.x = maxf(worst.x, position_jump)
		worst.y = maxf(worst.y, angular_jump)
		bones.append({"bone": v.rig.get_bone_name(i), "position_step_jump_m": position_jump,
			"rotation_step_jump_rad": angular_jump, "position_velocity_jump_m_s": position_jump / dt,
			"rotation_velocity_jump_rad_s": angular_jump / dt})
	reference.scene.free()
	return {"reference_scene": other_row.scene, "reference_scene_sha256": other_row.scene_sha256,
		"reference_phase": phase, "reference_time_s": at, "endpoint_position_error_m": endpoint.x,
		"endpoint_rotation_error_rad": endpoint.y, "max_position_step_jump_m": worst.x,
		"max_rotation_step_jump_rad": worst.y, "spacing_s": dt, "bones": bones}

func _check(row: Dictionary, pair: Dictionary, walk: Dictionary, idle: Dictionary, fps: int, mode: String, baseline: bool) -> Dictionary:
	var v := Native.load_case(row, root)
	v.animation_name = row.params.animation_name
	var clip: Animation = v.clip
	var leg: float = v.leg
	var dt := 1.0 / fps
	# The existing commit path appends a stationary extraction tail. Joins use
	# the authored action boundary, not the later storage/finishing boundary.
	var action_duration := float(row.write.get("capture_duration", clip.length))
	var stopping: bool = row.params.op == "walk_stop"
	var phase := float(row.write.get("phase", row.params.get("phase", 0.0)))
	var gait_join := _join(v, walk, 0.0 if stopping else action_duration, phase, stopping, dt)
	var idle_join := _join(v, idle, action_duration if stopping else 0.0, 0.0, not stopping, dt)
	v.player.stop()
	v.player.play(v.animation_name, 0.0, 1.0)
	v.player.advance(0.0)
	var reference := Native.load_case(row, root)
	var extracted: bool = row.params.root_motion
	var driver: Node3D = null
	var paired: Dictionary = {}
	var paired_track := -1
	var actor_schedule_known: bool = row.write.has("actor_translation_keys")
	if not extracted:
		driver = Node3D.new()
		root.add_child(driver)
		v.scene.reparent(driver, true)
		v.body = driver
		v.initial_body = driver.global_position
		# Baseline diagnostics explicitly use the paired extracted clip's engine
		# track. This assumption is NOT caller documentation or an acceptance.
		paired = Native.load_case(pair, root)
		paired_track = paired.clip.find_track(paired.player.root_motion_track, Animation.TYPE_POSITION_3D)
	var mixer := _tree(v, mode)
	var errors: Array[String] = []
	var key_count := 0
	var path_errors: Array[String] = []
	var active_mixers := 0
	for active in v.scene.find_children("*", "AnimationMixer", true, false):
		if active.active: active_mixers += 1
	if active_mixers != 1: errors.append("Expected exactly one active mixer")
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null: path_errors.append("Unresolved path " + str(path))
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]: path_errors.append("Unexpected track type")
		if target is Skeleton3D and (path.get_subname_count() != 1 or target.find_bone(str(path.get_subname(0))) < 0): path_errors.append("Unresolved bone " + str(path))
		if not extracted and not target is Skeleton3D: path_errors.append("In-place clip writes actor transform")
		key_count += clip.track_get_key_count(track)
	if not path_errors.is_empty(): errors.append("Invalid track paths/types")
	if key_count != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count): errors.append("Reported track/key counts differ")
	if clip.loop_mode != Animation.LOOP_NONE: errors.append("Transition must preserve one-shot endpoints")
	if absf(clip.length - float(row.write.length)) > 0.000001: errors.append("Reported duration differs")
	if not clip.has_marker("settled") or absf(clip.get_marker_time("settled") - action_duration) > 0.000001: errors.append("Reported action boundary differs from settled marker")
	var root_track := clip.find_track(mixer.root_motion_track, Animation.TYPE_POSITION_3D)
	if extracted and root_track < 0: errors.append("Extracted root track missing")
	if not extracted and root_track >= 0: errors.append("In-place clip owns extracted translation")
	var expected_root := Vector3.ZERO
	if root_track >= 0: expected_root = clip.position_track_interpolate(root_track, clip.length) - clip.position_track_interpolate(root_track, 0.0)
	if not extracted and paired_track >= 0: expected_root = paired.clip.position_track_interpolate(paired_track, paired.clip.length) - paired.clip.position_track_interpolate(paired_track, 0.0)
	var feet := {}
	for side in ["l", "r"]:
		feet[side] = {"active": false, "anchor": Vector3.ZERO, "slide": 0.0, "penetration": 0.0,
			"normal": Vector3.ZERO, "flips": 0, "frames": 0, "windows": 0}
	var previous := _poses(v.rig)
	var terminal: Array[Transform3D] = []
	var max_reference := Vector2.ZERO
	var hold_error := Vector2.ZERO
	var max_step := Vector2.ZERO
	var endpoint_step := Vector2.ZERO
	var nonfinite := 0
	var root_hold_error := 0.0
	var hold_root := Vector3.ZERO
	var backward := 0.0
	var in_place_root := 0.0
	var frames := ceili((clip.length + 0.5) * fps)
	var trace: Array = []
	for frame in frames + 1:
		if frame > 0:
			mixer.advance(dt)
			var delta := mixer.get_root_motion_position()
			if extracted: v.body.position += v.body.quaternion * delta
			else:
				in_place_root = maxf(in_place_root, delta.length())
				if paired_track >= 0:
					var at := minf(float(frame) / fps, clip.length)
					var before := minf(float(frame - 1) / fps, clip.length)
					v.body.global_position += paired.clip.position_track_interpolate(paired_track, at) - paired.clip.position_track_interpolate(paired_track, before)
			backward = maxf(backward, -delta.dot(v.forward))
		v.time = float(frame) / fps
		reference.player.seek(minf(v.time, clip.length), true)
		var poses := _poses(v.rig)
		var difference := _difference(poses, _poses(reference.rig))
		max_reference.x = maxf(max_reference.x, difference.x)
		max_reference.y = maxf(max_reference.y, difference.y)
		if v.time >= clip.length - 0.000001:
			if terminal.is_empty():
				terminal = poses
				hold_root = v.body.global_position
			else:
				var held := _difference(terminal, poses)
				hold_error.x = maxf(hold_error.x, held.x)
				hold_error.y = maxf(hold_error.y, held.y)
				root_hold_error = maxf(root_hold_error, hold_root.distance_to(v.body.global_position))
		var sample := {"time": v.time, "root": Native.values(v.body.global_position), "feet": {}}
		for side: String in feet:
			var foot := Native.point(v, "foot_" + side)
			var height: float = foot.dot(v.up) - v.ground
			var f: Dictionary = feet[side]
			var on := absf(height) <= 0.01 * leg
			if on and not f.active:
				f.anchor = foot
				f.windows += 1
			if on:
				f.frames += 1
				f.slide = maxf(f.slide, Native.flat(foot - f.anchor, v.up).length())
			f.active = on
			f.penetration = maxf(f.penetration, -height)
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > 0.005 * leg:
				var normal := pole.normalized()
				if (f.normal as Vector3).length_squared() > 0.5 and normal.dot(f.normal) < 0.0: f.flips += 1
				f.normal = normal
			sample.feet[side] = {"p": Native.values(foot), "height_from_rest_ankle_plane": height, "observed_contact_band": on}
		for i in poses.size():
			if not poses[i].origin.is_finite() or not poses[i].basis.is_finite(): nonfinite += 1
			var step := _difference([poses[i]], [previous[i]])
			max_step.x = maxf(max_step.x, step.x)
			max_step.y = maxf(max_step.y, step.y)
			if v.time >= clip.length - dt and v.time <= clip.length + dt:
				endpoint_step.x = maxf(endpoint_step.x, step.x)
				endpoint_step.y = maxf(endpoint_step.y, step.y)
		previous = poses
		trace.append(sample)
	var travel: Vector3 = v.body.global_position - v.initial_body
	var root_error := travel.distance_to(expected_root)
	if root_error > 0.0001 or root_hold_error > 0.00001: errors.append("Root travel/terminal hold mismatch")
	if backward > 0.00001: errors.append("Backward root travel")
	if in_place_root > 0.000001: errors.append("In-place extraction output")
	if max_reference.x > 0.001 * leg or max_reference.y > 0.0001: errors.append("Sequential mixer differs from independent engine seek")
	if hold_error.x > 0.00001 or hold_error.y > 0.0001: errors.append("Terminal pose does not hold")
	if nonfinite > 0 or max_step.x < 0.000001: errors.append("Nonfinite/inert skeletal playback")
	var clamp_known: bool = row.write.has("clamped")
	if clamp_known and bool(row.write.clamped): errors.append("Generation reach clamp")
	if not baseline and not clamp_known: errors.append("Generation clamp metadata unavailable")
	if not baseline and not extracted and not actor_schedule_known: errors.append("In-place actor schedule unavailable")
	for join: Dictionary in [gait_join, idle_join]:
		if join.endpoint_position_error_m > 0.00001 or join.endpoint_rotation_error_rad > 0.0001: errors.append("Accepted pose endpoint differs")
		if join.max_position_step_jump_m > 0.005 or join.max_rotation_step_jump_rad > 0.75 * max_step.y + 0.002: errors.append("Played join velocity discontinuity")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide > minf(0.02 * leg, 0.03) or f.penetration > 0.01 * leg or f.flips > 0 or f.frames == 0: errors.append(side + " contact/slide/penetration/knee failure")
		metrics[side] = {"max_observed_contact_slide_m": f.slide, "max_rest_ankle_plane_penetration_m": f.penetration,
			"knee_pole_flips": f.flips, "observed_contact_frames": f.frames, "observed_contact_windows": f.windows}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "frames": frames + 1, "duration_s": clip.length,
		"action_duration_s": action_duration, "reported_terminal_hold_s": row.write.get("root_motion_terminal_hold", null),
		"root_mode": "extracted" if extracted else "in_place", "phase": phase, "leg_length_m": leg,
		"generation_clamp_metadata_known": clamp_known, "generation_reach_clamped": row.write.get("clamped", null),
		"actor_schedule_known": actor_schedule_known, "actor_schedule_source": "extracted root track" if extracted else "paired extracted saved clip: diagnostic assumption",
		"active_mixers": active_mixers, "root_distance_m": travel.length(), "expected_root_distance_m": expected_root.length(),
		"root_error_m": root_error, "root_hold_error_m": root_hold_error, "backward_root_step_m": backward,
		"max_in_place_root_delta_m": in_place_root, "max_reference_position_error_m": max_reference.x,
		"max_reference_rotation_error_rad": max_reference.y, "max_pose_step_m": max_step.x, "max_rotation_step_rad": max_step.y,
		"endpoint_step_m": endpoint_step.x, "endpoint_rotation_step_rad": endpoint_step.y, "nonfinite": nonfinite,
		"hold_position_error_m": hold_error.x, "hold_rotation_error_rad": hold_error.y, "gait_join": gait_join,
		"idle_join": idle_join, "feet": metrics, "trace": trace, "path_errors": path_errors,
		"failures": errors, "thresholds_pass": errors.is_empty()}
	v.scene.free()
	if driver != null: driver.free()
	reference.scene.free()
	if not paired.is_empty(): paired.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		quit(1)
		return
	var inputs: Array[Dictionary] = []
	for i in 4: inputs.append(JSON.parse_string(FileAccess.get_file_as_string(args[i])))
	var results: Array = []
	var failures: Array = []
	for row: Dictionary in inputs[0].cases:
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var result := _check(row, _find(inputs[1], row.id), _find(inputs[2], row.id), _find(inputs[3], row.id), fps, mode, inputs[0].phase == "baseline")
				results.append(result)
				if not result.thresholds_pass: failures.append("%s/%s/%s: %s" % [row.id, fps, mode, str(result.failures)])
	var report := {"source_head": inputs[0].source_head, "revision": inputs[0].revision, "runs": results,
		"failures": failures, "engine_errors": logger.errors, "passed": results.size() == 24 and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Played world-space rest-ankle contact band, not sole collision; independent saved accepted gait/idle joins; one-shot terminal hold; paired in-place driver is baseline diagnostic assumption. Numerical checks do not approve visual quality."}
	FileAccess.open(args[4], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("START_STOP_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
