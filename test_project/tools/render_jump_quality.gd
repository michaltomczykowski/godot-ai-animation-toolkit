extends "res://tools/render_character_quality.gd"
const CaptureGuard := preload("res://tools/motion_capture_guard.gd")

func _setup(row: Dictionary, viewport: SubViewport, index: int) -> Dictionary:
	var v := super._setup(row, viewport, index)
	var displacement: Vector3 = v.forward * float(row.write.distance)
	v.fixed_center = v.initial_body + v.center_offset + displacement * 0.5 + Vector3.UP * float(row.write.height) * 0.3
	v.fixed_camera = v.fixed_center + v.camera_offset
	var horizontal := Vector3.RIGHT if index == 0 else Vector3.FORWARD
	v.camera.size = maxf(float(v.height) * 1.65 + float(row.write.height), absf(displacement.dot(horizontal)) * 1.2 + float(v.height) * 1.5)
	_update(v)
	return v

func _update(v: Dictionary) -> void:
	super._update(v)
	if v.has("fixed_center"):
		v.camera.position = v.fixed_camera
		v.camera.look_at(v.fixed_center, Vector3.UP)

func _contact(v: Dictionary, _side: String) -> bool:
	var takeoff: float = v.clip.get_marker_time("takeoff")
	var landing: float = v.clip.get_marker_time("land")
	return v.time <= takeoff or v.time >= landing

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [3, 4, 5]:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var guarded := args.size() >= 4
	var probe := args.size() == 5 and args[4] == "probe"
	var trace: Array = []
	var png_frames := 0
	var capture_control := ""
	if guarded:
		var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		capture_control = str(binding.get("framing_control", ""))
		if FileAccess.get_sha256(args[0]) != str(binding.route_sha256): push_error("Capture route identity changed")
		for file: Dictionary in binding.files:
			if FileAccess.get_sha256(file.path) != str(file.sha256): push_error("Capture dependency changed: "+str(file.path))
		if not logger.errors.is_empty(): quit(1); return
	output = args[1]
	diagnostic = args[2] == "diagnostic"
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 29)
	status = _label("", Vector2(24, 50), 22)
	_label("FIXED FRONT", Vector2(24, 92), 22)
	_label("FIXED SIDE", Vector2(984, 92), 22)
	_label("Saved one-shot | two reset-separated complete takes | one movement owner | human review waived", Vector2(24, 1035), 20)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in manifest.cases:
		if guarded:
			for error in CaptureGuard.admit(row): push_error(error)
			if not logger.errors.is_empty(): quit(1); return
		title.text = "JUMP %.2fm | %s | %s | %s | %s" % [float(row.write.distance), manifest.profile, manifest.root_mode, row.label, str(manifest.source_head).left(7)]
		for take in 2:
			views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
			if guarded:
				for view: Dictionary in views:
					CaptureGuard.attach(view)
					if capture_control == "cropped_camera": view.camera.size *= 0.01
			await process_frame
			for frame in 180:
				if frame > 0:
					for v: Dictionary in views:
						Native.advance(v, 1.0 / 60.0)
						_update(v)
				status.text = "Godot 4.7.2 | take %d/2 | %.2fs | %s" % [take + 1, float(frame) / 60.0, "extracted actor travel" if row.params.root_motion else "skeletal travel; no controller displacement"]
				await process_frame
				await RenderingServer.frame_post_draw
				if guarded:
					for view_index in views.size():
						var observation := CaptureGuard.frame(views[view_index])
						observation.merge({"frame":frames,"rig":row.id,"view":view_index,"take":take+1})
						trace.append(observation)
				var image := root.get_texture().get_image()
				if image.get_size() != Vector2i(1920,1080): push_error("Actual root PNG size is not1920x1080")
				if not logger.errors.is_empty():
					FileAccess.open(output.path_join("guard-failure.json"),FileAccess.WRITE).store_string(JSON.stringify({"errors":logger.errors,"last_frame":frames,"trace":trace}))
					quit(1)
					return
				if not probe or frame in [0,90,179]:
					if image.save_png(output.path_join("%06d.png" % frames)) != OK: push_error("Capture frame save failed")
					png_frames += 1
				frames += 1
			for v: Dictionary in views: v.world.free()
			views.clear()
		rows.append({"id": row.id, "frames": 360, "start_s": float(frames - 360) / 60.0, "duration_s": 6.0,
			"scene": row.scene, "scene_sha256": row.scene_sha256, "takes": 2, "camera_views": ["FRONT", "SIDE"]})
		print("Captured jump %s: 360 frames" % row.id)
	var report := {"revision": manifest.revision, "operation": manifest.operation, "profile": manifest.profile,
		"source_head": manifest.source_head, "fps": 60, "size": [1920, 1080], "frames": frames,
		"mode": args[2], "cases": rows, "errors": logger.errors, "root_consumers_per_view": 1,
		"layout": "simultaneous_fixed_front_side", "human_review": "waived", "visual_approval": false, "guarded":guarded, "probe":probe, "png_frames":png_frames, "trace":trace, "capture_binding_sha256":FileAccess.get_sha256(args[3]) if guarded else ""}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if frames == 1440 and logger.errors.is_empty() else 1)
