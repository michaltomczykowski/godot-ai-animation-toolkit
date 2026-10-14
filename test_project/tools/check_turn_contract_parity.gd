extends "res://tools/check_transition_preview_parity.gd"
## Same independent played comparison, with exact interpolation and marker parity.

func _same_channels(a: Animation, b: Animation) -> bool:
	if a.length != b.length or a.loop_mode != b.loop_mode or a.step != b.step or a.get_track_count() != b.get_track_count(): return false
	if a.get_marker_names() != b.get_marker_names(): return false
	for marker in a.get_marker_names():
		if a.get_marker_time(marker) != b.get_marker_time(marker) or a.get_marker_color(marker) != b.get_marker_color(marker): return false
	for track in a.get_track_count():
		if a.track_get_path(track) != b.track_get_path(track) or a.track_get_type(track) != b.track_get_type(track): return false
		if a.track_get_interpolation_type(track) != b.track_get_interpolation_type(track) or a.track_get_interpolation_loop_wrap(track) != b.track_get_interpolation_loop_wrap(track): return false
		if a.track_is_enabled(track) != b.track_is_enabled(track) or a.track_get_key_count(track) != b.track_get_key_count(track): return false
		for key in a.track_get_key_count(track):
			if a.track_get_key_time(track, key) != b.track_get_key_time(track, key) or a.track_get_key_value(track, key) != b.track_get_key_value(track, key) or a.track_get_key_transition(track, key) != b.track_get_key_transition(track, key): return false
	return true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var fresh: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var rows: Array = []
	for row: Dictionary in fresh.cases:
		var previous: Dictionary = {}
		for item: Dictionary in old.cases:
			if item.id == row.id: previous = item
		assert(not previous.is_empty())
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var a := Native.load_case(previous, root)
				var b := Native.load_case(row, root)
				var exact := _same_channels(a.clip, b.clip)
				var am: AnimationMixer = _mixer(a, mode)
				var bm: AnimationMixer = _mixer(b, mode)
				var worst := Vector2.ZERO
				var root_error := 0.0
				for frame in ceili((a.clip.length + 0.3) * fps) + 1:
					if frame > 0:
						am.advance(1.0 / fps)
						bm.advance(1.0 / fps)
					root_error = maxf(root_error, (a.body.global_position - a.initial_body).distance_to(b.body.global_position - b.initial_body))
					for bone in a.rig.get_bone_count():
						var ap: Transform3D = a.rig.get_bone_global_pose(bone)
						var bp: Transform3D = b.rig.get_bone_global_pose(bone)
						worst.x = maxf(worst.x, ap.origin.distance_to(bp.origin))
						worst.y = maxf(worst.y, _angle(ap.basis, bp.basis))
				rows.append({"id": row.id, "fps": fps, "mode": mode, "channels_interpolation_markers_exact": exact,
					"position_error_m": worst.x, "rotation_error_rad": worst.y, "root_error_m": root_error,
					"passed": exact and worst.x < 0.000001 and worst.y < 0.000001 and root_error < 0.000001})
				a.scene.free()
				b.scene.free()
	var passed := rows.size() == 24 and logger.errors.is_empty()
	for row: Dictionary in rows: passed = passed and row.passed
	var report := {"passed": passed, "runs": rows, "engine_errors": logger.errors,
		"reference_source": old.source_head, "fresh_source": fresh.source_head}
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("TURN_CONTRACT_PARITY=" + JSON.stringify({"passed": passed, "runs": rows.size(), "errors": logger.errors}))
	quit(0 if passed else 1)
