extends "res://tools/render_start_stop_comparison.gd"

func _contact(v: Dictionary, side: String) -> bool:
	var row: Dictionary = v.review_row
	var segment: Dictionary = row.params.segments[0]
	for item: Dictionary in row.params.segments:
		if v.time >= float(item.start): segment = item
	var clock := clampf(v.time - float(segment.start), 0.0, float(segment.duration))
	var intended := false
	if segment.source_animation == "idle_cycle": intended = true
	elif segment.source_animation == "walk_cycle":
		intended = Native.contact({"clip": v.player.get_animation("walk_cycle"), "time": clock}, side)
	else:
		for contact: Dictionary in row.sources[segment.source_animation].declared_contacts:
			if contact.side == side and clock >= float(contact.start) and clock <= float(contact.end): intended = true
	return intended and _observed(v, side)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]
	diagnostic = args[2] == "diagnostic"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 30)
	status = _label("", Vector2(24, 50), 21)
	_label("FRONT | single saved character clip", Vector2(24, 92), 23)
	_label("SIDE | same clip, independent view", Vector2(984, 92), 23)
	_label("Green: intended stance within ankle band | magenta: hip projection | blue: root" if diagnostic else "Public animation_sequence | idle → start → walk → stop → idle | one mixer and root consumer per character | review pending", Vector2(24, 1035), 18)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var cases: Array = []
	for row: Dictionary in route.cases:
		title.text = "SAVED START/STOP SEQUENCE | %s | Godot 4.7.2 | %s" % [row.label, str(route.source_head).left(7)]
		var count := ceili((float(row.write.capture_duration) + 1.0) * 60)
		var beginning := frames
		for take in 2:
			views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
			await process_frame
			for frame in count:
				if frame > 0:
					for v: Dictionary in views:
						Native.advance(v, 1.0 / 60)
						_update(v)
				var segment: Dictionary = row.params.segments[0]
				for item: Dictionary in row.params.segments:
					if float(frame) / 60 >= float(item.start): segment = item
				status.text = "take %d/2 | %.2fs | %s | action %.3fs, storage %.3fs | extracted once | travel %.3fm" % [take + 1, float(frame) / 60, segment.source_animation, row.write.capture_duration, views[0].clip.length, views[0].body.global_position.distance_to(views[0].initial_body)]
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames)) != OK: push_error("Sequence frame save failed")
				frames += 1
			for v: Dictionary in views: v.world.free()
			views.clear()
		cases.append({"id": row.id, "frames": count * 2, "start_s": float(beginning) / 60, "duration_s": float(count * 2) / 60, "scene": row.scene, "camera_views": ["FRONT", "SIDE"], "takes": 2, "reset_between_takes": true})
		print("Captured continuous sequence: " + str(row.id))
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify({"operation": "animation_sequence", "revision": route.revision,
		"source_head": route.source_head, "frames": frames, "fps": 60, "size": [1920, 1080], "mode": args[2],
		"cases": cases, "errors": logger.errors, "root_consumers_per_view": 1, "visual_approval": false}))
	OS.remove_logger(logger)
	quit(0 if logger.errors.is_empty() and cases.size() == 4 else 1)
