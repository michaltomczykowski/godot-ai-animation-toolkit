extends "res://tools/render_start_stop_candidate.gd"
## Saved one-shot heading only. Neither camera follows the character's yaw.
func _contact(v: Dictionary, side: String) -> bool:
	var height := Native.point(v, "foot_" + side).dot(v.up) - float(v.ground)
	return absf(height) <= 0.01 * float(v.leg) and (_declared(v, side) if v.review_row.write.has("declared_contacts") else true)

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
	title = _label("", Vector2(24, 10), 29)
	status = _label("", Vector2(24, 50), 22)
	_label("FIXED FRONT", Vector2(24, 92), 22)
	_label("FIXED SIDE", Vector2(984, 92), 22)
	_label("Green: declared stance/ankle band | Magenta: hip projection, not COM" if diagnostic else "Original saved one-shot | two reset-separated complete takes | one bone writer | human review pending", Vector2(24, 1035), 20)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in manifest.cases:
		title.text = "TURN %s %d degrees / %d steps | %s | %s | %s" % [row.params.direction, int(row.params.get("angle", 90)), int(row.params.get("steps", 1)), manifest.profile, row.label, str(manifest.source_head).left(7)]
		var start_frame := frames
		for take in 2:
			views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
			await process_frame
			for frame in 180:
				if frame > 0:
					for v: Dictionary in views:
						Native.advance(v, 1.0 / 60.0)
						_update(v)
				status.text = "Godot 4.7.2 | take %d/2 | %.2fs | action %.3fs | skeletal heading; no actor yaw consumer" % [take + 1, float(frame) / 60.0, float(row.write.get("capture_duration", views[0].clip.length))]
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames)) != OK: push_error("Turn frame save failed")
				frames += 1
			for v: Dictionary in views: v.world.free()
			views.clear()
		rows.append({"id": row.id, "frames": frames - start_frame, "start_s": float(start_frame) / 60.0,
			"duration_s": 6.0, "scene": row.scene, "scene_sha256": row.scene_sha256,
			"takes": 2, "reset_between_takes": true, "camera_views": ["FRONT", "SIDE"]})
		print("Captured turn %s: %d frames" % [row.id, frames - start_frame])
	var report := {"revision": manifest.revision, "operation": manifest.operation, "profile": manifest.profile,
		"source_head": manifest.source_head, "fps": 60, "size": [1920, 1080], "frames": frames,
		"mode": args[2], "cases": rows, "errors": logger.errors,
		"layout": "simultaneous_front_side", "root_consumers_per_view": 0,
		"bone_writers_per_view": 1, "visual_approval": false}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if frames == 1440 and logger.errors.is_empty() else 1)
