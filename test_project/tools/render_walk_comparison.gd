extends "res://tools/render_character_quality.gd"

## Both sides load their original saved clips. No animation generation here.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		quit(1)
		return
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	output = args[2]
	diagnostic = args[3] == "diagnostic"
	var count := int(args[4]) if args.size() > 4 else 360
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 30)
	status = _label("", Vector2(24, 50), 23)
	_label("PREVIOUS | " + str(baseline.revision), Vector2(24, 92), 23)
	_label(str(candidate.profile).to_upper() + " | " + str(candidate.revision), Vector2(984, 92), 23)
	_label("Green: declared contact | Magenta: hip projection (not COM) | Blue: root travel" if diagnostic else "Original saved clips | matched cameras | actual 60 FPS playback | candidate awaiting human approval", Vector2(24, 1035), 21)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in candidate.cases:
		var reference: Dictionary = {}
		for item: Dictionary in baseline.cases:
			if item.id == row.id: reference = item
		assert(not reference.is_empty(), "Baseline rig must be present")
		for angle in 2:
			var angle_name := "FRONT" if angle == 0 else "SIDE"
			title.text = "WALK UPPER BODY REVIEW | %s | %s | Godot 4.7.2" % [row.label, angle_name]
			views = [_setup(reference, ports[0], angle), _setup(row, ports[1], angle)]
			await process_frame
			for frame in count:
				if frame > 0:
					for v: Dictionary in views:
						Native.advance(v, 1.0 / 60.0)
						_update(v)
				status.text = "%s | time %05.2f s | baseline %.2f m / candidate %.2f m | native ground travel" % ["DIAGNOSTIC" if diagnostic else "CLEAN", float(frame) / 60.0, views[0].body.global_position.distance_to(views[0].initial_body), views[1].body.global_position.distance_to(views[1].initial_body)]
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames)) != OK:
					push_error("Comparison frame save failed")
				frames += 1
			rows.append({"id": row.id, "angle": angle_name, "frames": count, "start_s": float(frames - count) / 60.0, "duration_s": float(count) / 60.0, "baseline_scene": reference.scene, "candidate_scene": row.scene})
			for v: Dictionary in views: v.world.free()
			views.clear()
			print("Captured %s/%s: %d frames" % [row.id, angle_name, count])
	var report := {"revision": candidate.revision, "profile": candidate.profile, "source_head": candidate.source_head, "baseline_source_head": baseline.source_head, "comparison": true, "fps": 60, "size": [1920, 1080], "frames": frames, "mode": args[3], "cases": rows, "errors": logger.errors, "root_consumers_per_view": 1}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("WALK_COMPARISON_RENDER frames=%d errors=%d" % [frames, logger.errors.size()])
	quit(0 if logger.errors.is_empty() and rows.size() == 8 else 1)
