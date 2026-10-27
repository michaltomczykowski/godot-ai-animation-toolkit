extends "res://tools/render_start_stop_comparison.gd"

## One saved clip, simultaneous matched front/side cameras, fresh reset per take.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]
	diagnostic = args[2] == "diagnostic"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 30)
	status = _label("", Vector2(24, 50), 23)
	_label("FRONT", Vector2(24, 92), 23)
	_label("SIDE", Vector2(984, 92), 23)
	_label("Green: intended stance within ankle band | Magenta: hip projection (not COM) | Blue: actor travel" if diagnostic
		else "Original saved clip | two complete reset-separated takes | one root consumer | human review pending", Vector2(24, 1035), 21)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in manifest.cases:
		title.text = "%s | %s | %s | Godot 4.7.2 | %s" % [manifest.operation.to_upper(), manifest.profile, row.label, str(manifest.source_head).left(7)]
		var start_frame := frames
		for take in 2:
			views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
			await process_frame
			for frame in 180:
				if frame > 0:
					for v: Dictionary in views:
						Native.advance(v, 1.0 / 60.0)
						_update(v)
				status.text = "take %d/2 | %.2fs | action %.3fs | storage %.3fs | phase %.3f | extracted once | travel %.3fm" % [take + 1, float(frame) / 60.0, row.write.capture_duration, views[0].clip.length, row.write.phase, views[0].body.global_position.distance_to(views[0].initial_body)]
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames)) != OK: push_error("Candidate one-shot frame save failed")
				frames += 1
			for v: Dictionary in views: v.world.free()
			views.clear()
		rows.append({"id": row.id, "scene": row.scene, "camera_views": ["FRONT", "SIDE"],
			"frames": 360, "start_s": float(start_frame) / 60.0, "duration_s": 6.0,
			"takes": 2, "reset_between_takes": true})
		print("Captured complete candidate takes: " + str(row.id))
	var report := {"revision": manifest.revision, "operation": manifest.operation, "profile": manifest.profile,
		"source_head": manifest.source_head, "fps": 60, "size": [1920, 1080], "frames": frames,
		"mode": args[2], "cases": rows, "errors": logger.errors, "root_consumers_per_view": 1,
		"visual_approval": false, "layout": "simultaneous_front_side"}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if logger.errors.is_empty() and rows.size() == 4 and frames == 1440 else 1)
