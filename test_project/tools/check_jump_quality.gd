extends "res://tools/check_run_quality.gd"

## One-shot saved playback. An unextracted forward jump owns skeletal travel,
## so it must not also receive controller translation.
func _check(row: Dictionary, fps: int, mode: String) -> Dictionary:
	var v := Native.load_case(row, root)
	if v.has("error"): return {"thresholds_pass": false, "failures": [v.error]}
	v.animation_name = row.params.animation_name
	var mixer := _tree(v, mode)
	var clip: Animation = v.clip
	var errors: Array[String] = []
	var action := float(row.write.get("capture_duration", clip.length))
	var leg := float(v.leg)
	var extracted := bool(row.params.root_motion) and absf(float(row.write.distance)) > 0.000001
	var first_hip := Native.point(v, "hips")
	var takeoff := clip.get_marker_time("takeoff") if clip.has_marker("takeoff") else -1.0
	var landing := clip.get_marker_time("land") if clip.has_marker("land") else -1.0
	if takeoff < 0.0 or landing <= takeoff: errors.append("Missing or unordered jump event markers")
	if clip.loop_mode != Animation.LOOP_NONE: errors.append("Jump unexpectedly loops")
	if not bool(row.write.get("reach_evaluated", false)): errors.append("Missing evaluated reach metadata")
	if bool(row.write.get("clamped", false)): errors.append("Generation reach clamp")
	var feet := {}
	for side in ["l", "r"]:
		feet[side] = {"active": false, "anchor": Vector3.ZERO, "slide": 0.0, "penetration": 0.0,
			"contact_height": 0.0, "pole": Vector3.ZERO, "flips": 0, "max_lift": 0.0, "frames": 0}
	var initial: Array[Vector3] = []
	for i in v.rig.get_bone_count(): initial.append(v.rig.get_bone_global_pose(i).origin)
	var previous := initial.duplicate()
	var max_step := 0.0
	var max_motion := 0.0
	var nonfinite := 0
	var air_frames := 0
	var ground_root_motion := 0.0
	var zero_extraction := 0.0
	var trace: Array = []
	var frames := ceili((clip.length + 0.25) * fps) + 1
	for frame in frames:
		var time := float(frame) / fps
		if frame > 0:
			mixer.advance(1.0 / fps)
			var delta := mixer.get_root_motion_position()
			if extracted:
				v.body.position += v.body.quaternion * delta
				if time <= takeoff or time >= landing + 1.0 / fps: ground_root_motion = maxf(ground_root_motion, delta.length())
			else: zero_extraction = maxf(zero_extraction, delta.length())
		var contact := time <= takeoff + 0.000001 or time >= landing - 0.000001
		var airborne := true
		var sample := {"time": time, "root": Native.values(v.body.global_position), "feet": {}}
		for side: String in feet:
			var foot := Native.point(v, "foot_" + side)
			var height: float = foot.dot(v.up) - v.ground
			var f: Dictionary = feet[side]
			if contact and not f.active: f.anchor = foot
			if contact:
				f.slide = maxf(f.slide, Native.flat(foot - f.anchor, v.up).length())
				f.contact_height = maxf(f.contact_height, absf(height))
				f.frames += 1
			f.active = contact
			f.penetration = maxf(f.penetration, -height)
			f.max_lift = maxf(f.max_lift, height)
			airborne = airborne and height > 0.01 * leg
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > 0.005 * leg:
				var normal := pole.normalized()
				if (f.pole as Vector3).length_squared() > 0.5 and normal.dot(f.pole) < 0.0: f.flips += 1
				f.pole = normal
			sample.feet[side] = {"p": Native.values(foot), "height": height, "declared_contact": contact}
		if airborne: air_frames += 1
		for i in v.rig.get_bone_count():
			var pose: Transform3D = v.rig.get_bone_global_pose(i)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
			max_step = maxf(max_step, pose.origin.distance_to(previous[i]))
			max_motion = maxf(max_motion, pose.origin.distance_to(initial[i]))
			previous[i] = pose.origin
		trace.append(sample)
	var travel: Vector3 = v.body.global_position - v.initial_body if extracted else Native.point(v, "hips") - first_hip
	var expected: Vector3 = v.forward * float(row.write.distance)
	var root_error := Native.flat(travel - expected, v.up).length()
	var slide_limit := minf(0.02 * leg, 0.03)
	if root_error > 0.0001: errors.append("Authored travel ownership/endpoint mismatch")
	if ground_root_motion > 0.000001: errors.append("Actor travels during declared grounded phase")
	if zero_extraction > 0.000001: errors.append("Nonextracted jump has competing extraction")
	if nonfinite > 0 or max_motion <= 0.000001: errors.append("Nonfinite or inert skeletal playback")
	if max_step > maxf(0.12 * leg, 10.0 * leg / fps): errors.append("Played jump discontinuity")
	if air_frames <= 0: errors.append("No simultaneous observed flight")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide > slide_limit or f.penetration > 0.01 * leg or f.contact_height > 0.01 * leg or f.flips > 0:
			errors.append(side + " contact/slide/penetration/knee failure")
		metrics[side] = {"slide_m": f.slide, "penetration_m": f.penetration, "contact_height_m": f.contact_height,
			"knee_flips": f.flips, "maximum_lift_m": f.max_lift, "contact_frames": f.frames}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "frames": frames, "leg_length_m": leg,
		"actor_translation_owner": "extracted carrier" if extracted else "skeletal clip only; no controller translation",
		"root_error_m": root_error, "grounded_root_delta_m": ground_root_motion, "unexpected_extraction_m": zero_extraction,
		"observed_flight_frames": air_frames, "nonfinite": nonfinite, "max_pose_step_m": max_step,
		"feet": metrics, "trace": trace, "failures": errors, "thresholds_pass": errors.is_empty()}
	v.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var runs: Array = []
	var failures: Array = []
	for row: Dictionary in manifest.cases:
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var result := _check(row, fps, mode)
				runs.append(result)
				if not result.thresholds_pass: failures.append("%s/%d/%s: %s" % [row.id, fps, mode, str(result.failures)])
	var report := {"source_head": manifest.source_head, "revision": manifest.revision, "runs": runs,
		"route_sha256": FileAccess.get_sha256(args[0]), "checker_sha256": FileAccess.get_sha256("res://tools/check_jump_quality.gd"),
		"native_helper_sha256": FileAccess.get_sha256("res://tools/character_quality_native.gd"),
		"base_checker_sha256": FileAccess.get_sha256("res://tools/check_run_quality.gd"),
		"failures": failures, "engine_errors": logger.errors, "passed": runs.size() == 24 and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Saved Player/Tree one-shot at actual FPS. World ankle-plane contact/flight, marker timing and single translation owner; no synthesized poses. Not sole collision or visual approval."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("JUMP_QUALITY_CHECK=" + JSON.stringify({"runs": runs.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
