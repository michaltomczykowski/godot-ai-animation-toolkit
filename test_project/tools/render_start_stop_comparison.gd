extends "res://tools/render_walk_comparison.gd"

## Original saved clips only. Each one-shot plays twice with a fresh scene reset.
func _setup(row: Dictionary, viewport: SubViewport, index: int) -> Dictionary:
	var v := super._setup(row, viewport, index)
	v["review_row"] = row
	return v

func _observed(v: Dictionary, side: String) -> bool:
	return absf(Native.point(v, "foot_" + side).y - float(v.ground)) <= 0.01 * float(v.leg)

func _declared(v: Dictionary, side: String) -> bool:
	for contact: Dictionary in v.get("review_row", {}).get("write", {}).get("declared_contacts", []):
		if str(contact.side) == side and v.time >= float(contact.start) - 0.000001 and v.time <= float(contact.end) + 0.000001: return true
	return false

func _contact(v: Dictionary, side: String) -> bool:
	return _observed(v, side) and (_declared(v, side) if v.get("review_row", {}).get("write", {}).has("declared_contacts") else true)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(1)
		return
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	output = args[2]
	diagnostic = args[3] == "diagnostic"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 30)
	status = _label("", Vector2(24, 50), 21)
	_label("BEFORE | " + str(baseline.source_head).left(7), Vector2(24, 92), 23)
	_label("CANDIDATE | " + str(candidate.source_head).left(7), Vector2(984, 92), 23)
	_label("Green: candidate declared stance within ankle band; baseline observed band | magenta: hip projection | blue: root" if diagnostic else "Saved one-shots | two complete takes with fresh reset | matched cameras follow translation | human review pending", Vector2(24, 1035), 19)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in candidate.cases:
		var reference: Dictionary = {}
		for item: Dictionary in baseline.cases:
			if item.id == row.id: reference = item
		assert(not reference.is_empty(), "Baseline rig must be present")
		assert(bool(row.params.root_motion) and bool(reference.params.root_motion), "This recording uses one extracted-root consumer")
		assert(float(row.write.capture_duration) <= 1.5 and float(reference.write.capture_duration) <= 1.5, "Extend take length before recording longer actions")
		for angle in 2:
			var angle_name := "FRONT" if angle == 0 else "SIDE"
			title.text = "%s | %s | %s | %s | Godot 4.7.2" % [candidate.operation.to_upper(), candidate.profile, row.label, angle_name]
			var start_frame := frames
			for take in 2:
				views = [_setup(reference, ports[0], angle), _setup(row, ports[1], angle)]
				await process_frame
				for frame in 180:
					if frame > 0:
						for v: Dictionary in views:
							Native.advance(v, 1.0 / 60.0)
							_update(v)
					status.text = "take %d/2 | %.2fs | action %.3f / %.3fs | storage %.3f / %.3fs | phase %.3f | extracted once | travel %.3f / %.3fm" % [take + 1, float(frame) / 60.0, reference.write.capture_duration, row.write.capture_duration, views[0].clip.length, views[1].clip.length, row.write.phase, views[0].body.global_position.distance_to(views[0].initial_body), views[1].body.global_position.distance_to(views[1].initial_body)]
					await process_frame
					await RenderingServer.frame_post_draw
					if root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames)) != OK: push_error("One-shot comparison frame save failed")
					frames += 1
				for v: Dictionary in views: v.world.free()
				views.clear()
			rows.append({"id": row.id, "angle": angle_name, "frames": 360, "start_s": float(start_frame) / 60.0,
				"duration_s": 6.0, "takes": 2, "reset_between_takes": true,
				"baseline_scene": reference.scene, "candidate_scene": row.scene})
			print("Captured complete comparison takes: %s/%s" % [row.id, angle_name])
	var report := {"revision": candidate.revision, "operation": candidate.operation, "profile": candidate.profile,
		"source_head": candidate.source_head, "baseline_source_head": baseline.source_head,
		"comparison": true, "fps": 60, "size": [1920, 1080], "frames": frames, "mode": args[3],
		"cases": rows, "errors": logger.errors, "root_consumers_per_view": 1, "visual_approval": false}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if logger.errors.is_empty() and rows.size() == 8 and frames == 2880 else 1)
