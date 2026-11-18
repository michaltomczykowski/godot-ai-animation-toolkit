extends SceneTree

## Compare saved engine playback, never the procedural sampler or an applied pose.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var runs: Array = []
	var failures: Array = []
	for row: Dictionary in after.cases:
		var old: Dictionary = {}
		for entry: Dictionary in before.cases:
			if entry.id == row.id: old = entry
		assert(not old.is_empty())
		var a := Native.load_case(old, root)
		var b := Native.load_case(row, root)
		var peaks := {}
		var endpoint := Vector2.ZERO
		var root_error := 0.0
		var window := float(row.write.reference_window_s)
		var length := float(row.write.capture_duration)
		for frame in ceili(length * 60.0) + 1:
			var time := minf(float(frame) / 60.0, length)
			if frame > 0:
				Native.advance(a, time - float(a.time))
				Native.advance(b, time - float(b.time))
			root_error = maxf(root_error, (a.body.global_position - a.initial_body).distance_to(b.body.global_position - b.initial_body))
			for role in ["hips", "chest", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "hand_l", "hand_r"]:
				if not a.indices.has(role) or not b.indices.has(role): continue
				var ap: Transform3D = a.rig.global_transform * a.rig.get_bone_global_pose(a.indices[role])
				var bp: Transform3D = b.rig.global_transform * b.rig.get_bone_global_pose(b.indices[role])
				var position: float = (ap.origin - a.body.global_position).distance_to(bp.origin - b.body.global_position)
				var delta := ap.basis.get_rotation_quaternion().inverse() * bp.basis.get_rotation_quaternion()
				var angle := 2.0 * atan2(Vector3(delta.x, delta.y, delta.z).length(), absf(delta.w))
				var peak: Dictionary = peaks.get(role, {"position_m": 0.0, "rotation_deg": 0.0})
				peak.position_m = maxf(float(peak.position_m), position)
				peak.rotation_deg = maxf(float(peak.rotation_deg), rad_to_deg(angle))
				peaks[role] = peak
				if time <= window + 0.000001 or time >= length - window - 0.000001:
					endpoint.x = maxf(endpoint.x, position)
					endpoint.y = maxf(endpoint.y, angle)
		var errors: Array = []
		if root_error > 0.000001: errors.append("actor travel changed")
		if endpoint.x > 0.00001 or endpoint.y > 0.0001: errors.append("protected reference window changed")
		for role in peaks:
			if float(peaks[role].rotation_deg) < 0.5: errors.append(role + " reaction is inert")
		if float(peaks.hips.position_m) < 0.005 * float(b.leg): errors.append("pelvis transfer is inert")
		if not errors.is_empty(): failures.append({"id": row.id, "errors": errors})
		runs.append({"id": row.id, "fps": 60, "mixer": "AnimationPlayer", "played_peaks_vs_r001": peaks,
			"reference_window_position_error_m": endpoint.x, "reference_window_rotation_error_rad": endpoint.y,
			"actor_travel_difference_m": root_error, "failures": errors, "passed": errors.is_empty()})
		a.scene.free()
		b.scene.free()
	var report := {"runs": runs, "failures": failures, "engine_errors": logger.errors,
		"source_head": after.source_head, "baseline_source_head": before.source_head,
		"passed": runs.size() == 4 and failures.is_empty() and logger.errors.is_empty(),
		"visual_approval": false, "contract": "Actual saved engine playback at 60 FPS. Actor-relative world-space bone displacement and global orientation differences; reference windows and extraction unchanged. Magnitude is not visual approval."}
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("TRANSITION_BODY_RESPONSE=" + JSON.stringify({"passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
