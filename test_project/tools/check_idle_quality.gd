extends SceneTree

## Independent saved-scene standing playback. No generator or bone-pose writes.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _angle(q: Quaternion) -> float:
	return 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))

func _rotation_step(a: Transform3D, b: Transform3D) -> Vector3:
	var q := a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()
	if q.w < 0.0: q = -q
	var axis := Vector3(q.x, q.y, q.z)
	return axis.normalized() * _angle(q) if axis.length() > 0.00000001 else Vector3.ZERO

func _poses(rig: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index in rig.get_bone_count(): result.append(rig.get_bone_global_pose(index))
	return result

func _pose_error(a: Skeleton3D, b: Skeleton3D) -> Vector2:
	var worst := Vector2.ZERO
	for index in a.get_bone_count():
		var other := b.find_bone(a.get_bone_name(index))
		if other < 0: return Vector2(INF, INF)
		var left := a.get_bone_global_pose(index)
		var right := b.get_bone_global_pose(other)
		worst.x = maxf(worst.x, left.origin.distance_to(right.origin))
		worst.y = maxf(worst.y, _angle(left.basis.get_rotation_quaternion().inverse() * right.basis.get_rotation_quaternion()))
	return worst

func _tree(view: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return view.player
	view.player.active = false
	var tree := AnimationTree.new()
	view.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(view.player)
	tree.root_node = tree.get_path_to(view.player.get_node(view.player.root_node))
	tree.root_motion_track = view.player.root_motion_track
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = view.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _seam_probe(view: Dictionary) -> Dictionary:
	# Fixed fractional spacing probes actual engine interpolation independently
	# of frame rate, including direction changes at the seam.
	var clip: Animation = view.clip
	var step := clip.length / 120.0
	view.player.seek(clip.length - step, true)
	var before := _poses(view.rig)
	view.player.seek(0.0, true)
	var center := _poses(view.rig)
	view.player.seek(step, true)
	var after := _poses(view.rig)
	var fast_position: Array[float] = []
	var fast_rotation: Array[float] = []
	fast_position.resize(center.size())
	fast_rotation.resize(center.size())
	var previous := after
	for sample in range(2, 120):
		view.player.seek(step * sample, true)
		var here := _poses(view.rig)
		for index in here.size():
			fast_position[index] = maxf(fast_position[index], here[index].origin.distance_to(previous[index].origin))
			fast_rotation[index] = maxf(fast_rotation[index], _rotation_step(previous[index], here[index]).length())
		previous = here
	var rows: Array = []
	var failures: Array[String] = []
	for index in center.size():
		var incoming := center[index].origin - before[index].origin
		var outgoing := after[index].origin - center[index].origin
		var rotation_in := _rotation_step(before[index], center[index])
		var rotation_out := _rotation_step(center[index], after[index])
		var position_jump := incoming.distance_to(outgoing)
		var rotation_jump := rotation_in.distance_to(rotation_out)
		# Keep the established 5 mm positional step and relative angular step
		# gates; these are played global poses, rather than copied key values.
		var angular_limit := 0.75 * fast_rotation[index] + 0.002
		if position_jump > 0.005 or rotation_jump > angular_limit:
			failures.append(view.rig.get_bone_name(index))
		rows.append({"bone": view.rig.get_bone_name(index), "position_velocity_jump_m_s": position_jump / step,
			"rotation_velocity_jump_rad_s": rotation_jump / step, "position_step_jump_m": position_jump,
			"rotation_step_jump_rad": rotation_jump, "position_step_jump_limit_m": 0.005,
			"rotation_step_jump_limit_rad": angular_limit, "fastest_interior_position_step_m": fast_position[index],
			"fastest_interior_rotation_step_rad": fast_rotation[index]})
	view.player.seek(0.0, true)
	return {"spacing_s": step, "bones": rows, "failures": failures}

func _check(row: Dictionary, fps: int, mode: String, baseline: bool, negative: bool) -> Dictionary:
	var v := Native.load_case(row, root)
	if v.has("error"): return {"thresholds_pass": false, "failures": [v.error]}
	v.animation_name = row.params.animation_name
	var reference := Native.load_case(row, root)
	if reference.has("error"):
		v.scene.free()
		return {"thresholds_pass": false, "failures": [reference.error]}
	var mixer := _tree(v, mode)
	var clip: Animation = v.clip
	var leg: float = v.leg
	var errors: Array[String] = []
	var path_errors: Array[String] = []
	var keys := 0
	var active_mixers := 0
	for active in v.scene.find_children("*", "AnimationMixer", true, false):
		if active.active: active_mixers += 1
	if active_mixers != 1: errors.append("Expected exactly one active mixer")
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null: path_errors.append("Unresolved path " + str(path))
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			path_errors.append("Unexpected type " + str(path))
		if target is Skeleton3D and (path.get_subname_count() != 1 or target.find_bone(str(path.get_subname(0))) < 0):
			path_errors.append("Unresolved bone " + str(path))
		if not target is Skeleton3D: path_errors.append("Stationary idle writes an actor transform")
		keys += clip.track_get_key_count(track)
	if keys != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count): errors.append("Reported track/key counts differ")
	if clip.loop_mode != Animation.LOOP_LINEAR: errors.append("Idle must loop continuously")
	if absf(float(row.write.length) - clip.length) > 0.000001: errors.append("Reported period differs")
	var root_track_present := not mixer.root_motion_track.is_empty() and clip.find_track(mixer.root_motion_track, Animation.TYPE_POSITION_3D) >= 0
	if root_track_present: errors.append("Stationary clip owns extraction translation")
	var clamp_known: bool = row.write.has("clamped")
	if clamp_known and bool(row.write.clamped): errors.append("Generation reach clamp")
	if not baseline and not clamp_known: errors.append("Generation clamp metadata unavailable")
	if not baseline and not bool(row.write.get("reach_evaluated", false)): errors.append("Standing reach was not evaluated")
	var seam_probe := _seam_probe(reference)
	if not seam_probe.failures.is_empty(): errors.append("Played loop velocity discontinuity")
	var feet := {}
	var arms := {}
	for side in ["l", "r"]:
		feet[side] = {"anchor": Native.rest(v.rig, v.roles, "foot_" + side), "slide": 0.0,
			"penetration": 0.0, "height": 0.0, "normal": Vector3.ZERO, "flips": 0, "observed_frames": 0}
		arms[side] = {"max_upper_up_dot": -1.0, "min_elbow_deg": 180.0, "max_elbow_deg": 0.0,
			"wrist_initial": v.rig.get_bone_pose_rotation(v.indices["hand_" + side]), "wrist_excursion_rad": 0.0}
	var duration := maxf(6.0, 3.0 * clip.length)
	var frame_count := ceili(duration * fps)
	var max_reference := Vector2.ZERO
	var root_distance := 0.0
	var max_root_delta := 0.0
	var nonfinite := 0
	var seams := 0
	var max_step := Vector2.ZERO
	var seam_step := Vector2.ZERO
	var interior_step := Vector2.ZERO
	var previous := _poses(v.rig)
	var trace: Array = []
	var negative_parent: Node3D = null
	if negative:
		negative_parent = Node3D.new()
		root.add_child(negative_parent)
		v.scene.reparent(negative_parent, true)
	for frame in frame_count + 1:
		var crossed := false
		if frame > 0:
			mixer.advance(1.0 / fps)
			max_root_delta = maxf(max_root_delta, mixer.get_root_motion_position().length())
			if negative: negative_parent.global_position += v.right * (0.05 * leg / fps)
			var previous_time: float = v.time
			v.time = float(frame) / fps
			crossed = floori(v.time / clip.length) > floori(previous_time / clip.length)
			if crossed: seams += 1
		reference.player.seek(fposmod(v.time, clip.length), true)
		var difference := _pose_error(v.rig, reference.rig)
		max_reference.x = maxf(max_reference.x, difference.x)
		max_reference.y = maxf(max_reference.y, difference.y)
		root_distance = maxf(root_distance, v.body.global_position.distance_to(v.initial_body))
		var sample := {"time": v.time, "root": Native.values(v.body.global_position), "feet": {}}
		for side: String in feet:
			var f: Dictionary = feet[side]
			var foot := Native.point(v, "foot_" + side)
			var offset: Vector3 = foot - f.anchor
			var height := offset.dot(v.up)
			f.slide = maxf(f.slide, Native.flat(offset, v.up).length())
			f.height = maxf(f.height, absf(height))
			f.penetration = maxf(f.penetration, -height)
			var observed := absf(height) <= 0.01 * leg
			if observed: f.observed_frames += 1
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > 0.005 * leg:
				var normal := pole.normalized()
				if (f.normal as Vector3).length_squared() > 0.5 and normal.dot(f.normal) < 0.0: f.flips += 1
				f.normal = normal
			sample.feet[side] = {"p": Native.values(foot), "height_from_rest_ankle_target": height,
				"expected_standing_support": true, "observed_contact_band": observed}
		for index in v.rig.get_bone_count():
			var pose: Transform3D = v.rig.get_bone_global_pose(index)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
			if frame > 0:
				var step := Vector2(pose.origin.distance_to(previous[index].origin), _rotation_step(previous[index], pose).length())
				max_step.x = maxf(max_step.x, step.x)
				max_step.y = maxf(max_step.y, step.y)
				if crossed:
					seam_step.x = maxf(seam_step.x, step.x)
					seam_step.y = maxf(seam_step.y, step.y)
				else:
					interior_step.x = maxf(interior_step.x, step.x)
					interior_step.y = maxf(interior_step.y, step.y)
			previous[index] = pose
		for side: String in arms:
			var upper := (Native.point(v, "forearm_" + side) - Native.point(v, "arm_" + side)).normalized()
			var fore := (Native.point(v, "hand_" + side) - Native.point(v, "forearm_" + side)).normalized()
			var a: Dictionary = arms[side]
			a.max_upper_up_dot = maxf(a.max_upper_up_dot, upper.dot(v.up))
			var bend := rad_to_deg(acos(clampf(upper.dot(fore), -1.0, 1.0)))
			a.min_elbow_deg = minf(a.min_elbow_deg, bend)
			a.max_elbow_deg = maxf(a.max_elbow_deg, bend)
			a.wrist_excursion_rad = maxf(a.wrist_excursion_rad, _angle((a.wrist_initial as Quaternion).inverse() * v.rig.get_bone_pose_rotation(v.indices["hand_" + side])))
		trace.append(sample)
	var slide_limit := minf(0.02 * leg, 0.03)
	if not path_errors.is_empty(): errors.append("Invalid track paths/types")
	if nonfinite > 0: errors.append("Nonfinite played poses")
	if root_distance > 0.0001 or max_root_delta > 0.0001: errors.append("Stationary root/actor drift")
	if seams < 2: errors.append("Insufficient crossed loop seam coverage")
	if max_reference.x > 0.001 * leg or max_reference.y > 0.0001: errors.append("Repeated engine pose differs at fractional phase")
	if max_step.x <= 0.000001 and max_step.y <= 0.000001: errors.append("Inert ordinary skeletal playback")
	if seam_step.x > 1.5 * interior_step.x + 0.001 * leg or seam_step.y > 1.5 * interior_step.y + 0.002:
		errors.append("Crossed loop seam pose discontinuity")
	var foot_metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide > slide_limit or f.penetration > 0.01 * leg or f.height > 0.01 * leg or f.flips > 0:
			errors.append(side + " standing contact/slide/penetration/knee failure")
		foot_metrics[side] = {"max_standing_slide_m": f.slide, "max_rest_ankle_target_penetration_m": f.penetration,
			"max_standing_height_error_m": f.height, "knee_pole_flips": f.flips,
			"expected_standing_frames": frame_count + 1, "observed_contact_band_frames": f.observed_frames}
	for side in arms: arms[side].erase("wrist_initial")
	var result := {"id": row.id, "fps": fps, "mixer": mode, "requested_root_motion": row.params.root_motion,
		"reported_root_motion": row.write.root_motion, "active_root_position_track": root_track_present,
		"root_translation_owner": "none; stationary standing clip", "frames": frame_count + 1, "dt": 1.0 / fps,
		"duration_s": float(frame_count) / fps, "leg_length_m": leg, "period_s": clip.length,
		"source_world_up": Native.values(v.up), "slide_limit_m": slide_limit, "penetration_limit_m": 0.01 * leg,
		"max_actor_distance_m": root_distance, "max_extracted_root_delta_m": max_root_delta,
		"max_reference_position_error_m": max_reference.x, "max_reference_rotation_error_rad": max_reference.y,
		"crossed_loop_seams": seams, "max_pose_step_m": max_step.x, "max_rotation_step_rad": max_step.y,
		"max_seam_step_m": seam_step.x, "max_seam_rotation_step_rad": seam_step.y, "seam_velocity_probe": seam_probe,
		"nonfinite": nonfinite, "generation_clamp_metadata_known": clamp_known,
		"generation_reach_clamped": row.write.get("clamped", null), "active_mixers": active_mixers,
		"feet": foot_metrics, "arms": arms, "trace": trace, "path_errors": path_errors,
		"failures": errors, "thresholds_pass": errors.is_empty(),
		"candidate_quality_pass": errors.is_empty() and clamp_known, "negative_actor_drift": negative}
	v.scene.free()
	if negative_parent != null: negative_parent.free()
	reference.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var baseline := args.size() > 2 and args[2] == "baseline"
	var negative := args.size() > 3 and args[3] == "negative_actor_drift"
	var modes: Array = ["player"] if baseline else ["player", "tree"]
	var results: Array = []
	var failures: Array = []
	for row: Dictionary in manifest.cases:
		if not row.get("passed", false):
			failures.append(str(row.id) + ": invalid public route")
			continue
		for fps in [30, 60, 120]:
			for mode: String in modes:
				var result := _check(row, fps, mode, baseline, negative)
				results.append(result)
				if not result.get("thresholds_pass", false): failures.append("%s/%s/%s: %s" % [row.id, fps, mode, str(result.get("failures", ["Invalid check result"]))])
	var report := {"source_head": manifest.source_head, "revision": manifest.revision, "baseline": baseline,
		"runs": results, "failures": failures, "engine_errors": logger.errors,
		"passed": results.size() == 4 * 3 * modes.size() and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Independent saved engine playback; bilateral expected standing support and measured world-space rest-ankle contact. No gait markers or actor translation consumer. Missing generation clamp metadata stays unknown and prevents candidate approval. Rest ankle targets are not skinned sole collision; numerical checks do not approve visual quality."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("IDLE_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
