extends "res://tools/check_run_quality.gd"

var control := ""

## One-shot saved playback. An unextracted forward jump owns skeletal travel,
## so it must not also receive controller translation.
func _check(row: Dictionary, fps: int, mode: String) -> Dictionary:
	if not row.get("passed", false): return {"thresholds_pass": false, "failures": ["Invalid public route"]}
	if FileAccess.get_sha256(str(row.scene)) != str(row.get("scene_sha256", "")):
		return {"thresholds_pass": false, "failures": ["Saved scene hash mismatch"]}
	var v := Native.load_case(row, root)
	if v.has("error"): return {"thresholds_pass": false, "failures": [v.error]}
	v.animation_name = row.params.animation_name
	if not control.is_empty(): _inject_control(v)
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
	var previous_rotations: Array[Quaternion] = []
	for i in v.rig.get_bone_count():
		var pose: Transform3D = v.rig.global_transform * v.rig.get_bone_global_pose(i)
		initial.append(pose.origin)
		previous_rotations.append(pose.basis.orthonormalized().get_rotation_quaternion())
	var initial_local: Array[Transform3D] = []
	for i in v.rig.get_bone_count(): initial_local.append(v.rig.get_bone_global_pose(i))
	var peak_height := -INF
	var peak_time := 0.0
	var first_air := -1.0
	var last_air := -1.0
	var previous := initial.duplicate()
	var max_step := 0.0
	var max_angular_velocity := 0.0
	var worst_step := {"bone": "", "time": 0.0, "step_m": 0.0}
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
				var before: Vector3 = v.body.global_position
				v.body.position += delta
				var applied_world: Vector3 = v.body.global_position - before
				if time <= takeoff or time >= landing + 1.0 / fps: ground_root_motion = maxf(ground_root_motion, applied_world.length())
			else:
				var parent := v.body.get_parent() as Node3D
				zero_extraction = maxf(zero_extraction, (parent.global_basis * delta if parent != null else delta).length())
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
		if airborne:
			air_frames += 1
			if first_air < 0.0: first_air = time
			last_air = time
		var hip_height: float = (Native.point(v, "hips") - first_hip).dot(v.up)
		if hip_height > peak_height:
			peak_height = hip_height
			peak_time = time
		for i in v.rig.get_bone_count():
			var pose: Transform3D = v.rig.global_transform * v.rig.get_bone_global_pose(i)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
			var step := pose.origin.distance_to(previous[i])
			if step > max_step:
				max_step = step
				worst_step = {"bone": v.rig.get_bone_name(i), "time": time, "step_m": step}
			max_motion = maxf(max_motion, pose.origin.distance_to(initial[i]))
			previous[i] = pose.origin
			var rotation := pose.basis.orthonormalized().get_rotation_quaternion()
			var q := previous_rotations[i].inverse() * rotation
			max_angular_velocity = maxf(max_angular_velocity, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)) * fps)
			previous_rotations[i] = rotation
		trace.append(sample)
	var travel: Vector3 = v.body.global_position - v.initial_body if extracted else Native.point(v, "hips") - first_hip
	var expected: Vector3 = v.forward * float(row.write.distance)
	var root_error := Native.flat(travel - expected, v.up).length()
	# Compare final skeleton-local global poses: common actor transport must not
	# hide an unrecovered torso/arm. Only the declared skeletal travel is removed.
	var skeletal_travel: Vector3 = Vector3.ZERO if extracted else v.forward * float(row.write.distance)
	var recovery_position := 0.0
	var recovery_rotation := 0.0
	for i in v.rig.get_bone_count():
		var final_pose: Transform3D = v.rig.get_bone_global_pose(i)
		var residual: Vector3 = v.rig.global_basis * (final_pose.origin - initial_local[i].origin) - skeletal_travel
		recovery_position = maxf(recovery_position, residual.length())
		var q := initial_local[i].basis.orthonormalized().get_rotation_quaternion().inverse() * final_pose.basis.orthonormalized().get_rotation_quaternion()
		recovery_rotation = maxf(recovery_rotation, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
	var height := float(row.write.get("height", -1.0))
	var apex := float(row.write.get("apex_time", -1.0))
	# Playback and authored sample interpolation can miss a parabola's summit.
	var authored_dt := action / maxf(1.0, float(row.write.get("effective_samples", row.params.get("samples", 60))))
	var timing_tolerance := 2.0 / fps + authored_dt
	var height_tolerance := maxf(0.002 * leg, 9.81 * pow(1.0 / fps + authored_dt, 2.0))
	var flight_tolerance := timing_tolerance + 0.02 * leg / maxf(0.1, sqrt(maxf(0.0, 2.0 * 9.81 * height)))
	if height <= 0.0 or apex < takeoff or apex > landing: errors.append("Missing physical jump contract")
	elif absf((landing - takeoff) - 2.0 * sqrt(2.0 * height / 9.81)) > 0.0001 or absf(apex - (takeoff + landing) * 0.5) > 0.0001:
		errors.append("Reported flight differs from ballistic height contract")
	if absf(peak_height - height) > height_tolerance: errors.append("Played apex height mismatch")
	if absf(peak_time - apex) > timing_tolerance: errors.append("Played apex timing mismatch")
	if first_air < 0.0 or absf(first_air - takeoff) > flight_tolerance or absf(last_air - landing) > flight_tolerance:
		errors.append("Observed flight window mismatch")
	if recovery_position > minf(0.01 * leg, 0.01) or recovery_rotation > 0.01: errors.append("Final skeletal pose did not recover")
	var slide_limit := minf(0.02 * leg, 0.03)
	if root_error > 0.0001: errors.append("Authored travel ownership/endpoint mismatch")
	if ground_root_motion > 0.000001: errors.append("Actor travels during declared grounded phase")
	if zero_extraction > 0.000001: errors.append("Nonextracted jump has competing extraction")
	if nonfinite > 0 or max_motion <= 0.000001: errors.append("Nonfinite or inert skeletal playback")
	if max_step * fps > 10.0 * leg or max_angular_velocity > 50.0: errors.append("Played jump discontinuity")
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
		"observed_flight_frames": air_frames, "first_observed_air_s": first_air, "last_observed_air_s": last_air,
		"apex_height_m": peak_height, "apex_time_s": peak_time, "expected_apex_height_m": height, "expected_apex_time_s": apex,
		"height_tolerance_m": height_tolerance, "timing_tolerance_s": timing_tolerance, "flight_tolerance_s": flight_tolerance,
		"final_pose_position_error_m": recovery_position, "final_pose_rotation_error_rad": recovery_rotation, "nonfinite": nonfinite, "max_pose_step_m": max_step,
		"max_bone_speed_legs_per_s": max_step * fps / leg, "max_bone_angular_speed_rad_s": max_angular_velocity,
		"worst_pose_step": worst_step, "feet": metrics, "trace": trace, "failures": errors, "thresholds_pass": errors.is_empty()}
	v.scene.free()
	return result

func _inject_control(v: Dictionary) -> void:
	# Replace both library and animation; never mutate the cached saved resource.
	var name := str(v.animation_name)
	var library_name := name.get_slice("/", 0) if name.contains("/") else ""
	var clip_name := name.get_slice("/", 1) if name.contains("/") else name
	var library: AnimationLibrary = v.player.get_animation_library(library_name).duplicate(true)
	v.player.remove_animation_library(library_name)
	v.player.add_animation_library(library_name, library)
	v.clip = library.get_animation(clip_name)
	var clip: Animation = v.clip
	var hips_path := ":" + str(v.roles.hips)
	for track in clip.get_track_count():
		var kind := clip.track_get_type(track)
		var path := str(clip.track_get_path(track))
		if control in ["double_travel", "reverse_travel"] and clip.track_get_path(track) == v.player.root_motion_track and kind == Animation.TYPE_POSITION_3D:
			var first: Vector3 = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track):
				clip.track_set_key_value(track, key, first + ((clip.track_get_key_value(track, key) as Vector3) - first) * (2.0 if control == "double_travel" else -1.0))
		if control == "tiny_hop" and path.ends_with(hips_path) and kind == Animation.TYPE_POSITION_3D:
			var first: Vector3 = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track): clip.track_set_key_value(track, key, first + ((clip.track_get_key_value(track, key) as Vector3) - first) * 0.05)
		if control == "delayed_apex" and kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			# Warp physical poses while leaving the declared event contract unchanged.
			for key in range(clip.track_get_key_count(track) - 1, -1, -1):
				var t := clip.track_get_key_time(track, key)
				clip.track_set_key_time(track, key, clip.length * pow(t / clip.length, 0.65))
		if control == "unrecovered_pose" and kind == Animation.TYPE_ROTATION_3D and not path.ends_with(hips_path):
			var last := clip.track_get_key_count(track) - 1
			var q: Quaternion = clip.track_get_key_value(track, last)
			clip.track_set_key_value(track, last, q * Quaternion(Vector3.RIGHT, 0.35))
		if control == "knee_discontinuity" and kind == Animation.TYPE_ROTATION_3D and path.ends_with(":" + str(v.roles.shin_l)):
			# A common 30 FPS boundary is sampled by all three requested FPS.
			# Preserve the uncorrupted interpolated pose on each flank.
			var center := floorf(clip.length * 0.5 * 30.0) / 30.0
			var left: Quaternion = clip.rotation_track_interpolate(track, center - 1.0 / 120.0)
			var middle: Quaternion = clip.rotation_track_interpolate(track, center)
			var right: Quaternion = clip.rotation_track_interpolate(track, center + 1.0 / 120.0)
			clip.track_insert_key(track, center - 1.0 / 120.0, left)
			clip.track_insert_key(track, center, middle * Quaternion(Vector3.RIGHT, 2.0))
			clip.track_insert_key(track, center + 1.0 / 120.0, right)
	if control == "penetration":
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		var path: NodePath = v.player.get_node(v.player.root_node).get_path_to(v.rig)
		clip.track_set_path(track, NodePath(str(path) + ":" + str(v.roles.foot_l)))
		var bone: int = v.indices.foot_l
		var parent: int = v.rig.get_bone_parent(bone)
		var basis: Basis = v.rig.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
		var shift: Vector3 = basis.inverse() * v.rig.global_basis.inverse() * v.up * float(v.leg) * -0.15
		var rest: Vector3 = v.rig.get_bone_pose_position(bone)
		clip.track_insert_key(track, 0.0, rest)
		clip.track_insert_key(track, clip.length * 0.9, rest + shift)
		clip.track_insert_key(track, clip.length, rest + shift)
	v.player.stop()
	v.player.clear_caches()
	v.player.play(name)
	v.player.advance(0.0)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	control = args[2] if args.size() > 2 else ""
	if control not in ["", "tiny_hop", "delayed_apex", "unrecovered_pose", "double_travel", "reverse_travel", "penetration", "knee_discontinuity"]:
		quit(1)
		return
	var runs: Array = []
	var failures: Array = []
	for row: Dictionary in manifest.cases:
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var result := _check(row, fps, mode)
				runs.append(result)
				if not result.thresholds_pass: failures.append("%s/%d/%s: %s" % [row.id, fps, mode, str(result.failures)])
	# Report sampling convergence without replacing the absolute 10 leg/s gate.
	# A sampled maximum may rise at finer FPS; never average away a failing spike.
	var convergence: Array = []
	for row: Dictionary in manifest.cases:
		for mode in ["player", "tree"]:
			var speeds := {}
			for run: Dictionary in runs:
				if run.get("id") == row.id and run.get("mixer") == mode:
					speeds[str(run.fps)] = run.get("max_bone_speed_legs_per_s", INF)
			if speeds.has("60") and speeds.has("120"):
				convergence.append({"id": row.id, "mixer": mode, "speeds_legs_per_s": speeds,
					"relative_60_120_difference": absf(float(speeds["120"]) - float(speeds["60"])) / maxf(0.001, float(speeds["120"]))})
	var report := {"velocity_sampling_convergence": convergence, "source_head": manifest.source_head, "revision": manifest.revision, "control": control, "runs": runs,
		"route_sha256": FileAccess.get_sha256(args[0]), "checker_sha256": FileAccess.get_sha256(get_script().resource_path),
		"native_helper_sha256": FileAccess.get_sha256("res://tools/character_quality_native.gd"),
		"base_checker_sha256": FileAccess.get_sha256("res://tools/check_run_quality.gd"),
		"failures": failures, "engine_errors": logger.errors, "passed": runs.size() == 24 and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Saved Player/Tree one-shot at actual FPS. World ankle-plane contact/flight, marker timing and single translation owner; no synthesized poses. Not sole collision or visual approval."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("JUMP_QUALITY_CHECK=" + JSON.stringify({"runs": runs.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
