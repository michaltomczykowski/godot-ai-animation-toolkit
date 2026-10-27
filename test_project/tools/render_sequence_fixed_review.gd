extends "res://tools/render_transition_sequence_review.gd"
const CaptureGuard := preload("res://tools/motion_capture_guard.gd")

func _setup(row: Dictionary, viewport: SubViewport, index: int) -> Dictionary:
	var v := super._setup(row, viewport, index)
	var track: int = v.clip.find_track(v.player.root_motion_track, Animation.TYPE_POSITION_3D)
	assert(track >= 0, "Saved extracted position carrier required")
	var travel: Vector3 = v.clip.position_track_interpolate(track, v.clip.length) - v.clip.position_track_interpolate(track, 0.0)
	if v.body.get_parent() is Node3D: travel = v.body.get_parent().global_basis * travel
	v.fixed_center = v.initial_body + v.center_offset + travel * 0.5
	v.fixed_camera = v.fixed_center + v.camera_offset
	var horizontal := Vector3.RIGHT if index == 0 else Vector3.FORWARD
	v.camera.size = maxf(float(v.height) * 1.8, absf(travel.dot(horizontal)) * 1.25 + float(v.height) * 1.5)
	_update(v)
	return v

func _update(v: Dictionary) -> void:
	super._update(v)
	if v.has("fixed_center"):
		v.camera.position = v.fixed_camera
		v.camera.look_at(v.fixed_center, Vector3.UP)

func _camera_state(v: Dictionary) -> Array:
	var p: Vector3 = v.camera.global_position
	var q: Quaternion = v.camera.global_basis.get_rotation_quaternion()
	return [p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.camera.size, v.camera.near, v.camera.far]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4: push_error("Original route, exclusive output, binding and probe/full required"); quit(1); return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var probe := args[3] == "probe"
	if args[3] not in ["probe", "full"] or FileAccess.get_sha256(args[0]) != binding.route_sha256 or DirAccess.dir_exists_absolute(args[1]):
		push_error("New bound capture required"); quit(1); return
	for file: Dictionary in binding.files:
		if FileAccess.get_sha256(file.path) != file.sha256: push_error("Changed capture input: " + str(file.path))
	var selected: Array = route.cases.filter(func(row): return row.id == "dummy")
	if selected.size() != 1 or not logger.errors.is_empty(): quit(1); return
	var row: Dictionary = selected[0]
	# compose requests have no locomotion root_motion Boolean. This capture
	# explicitly requires the saved extracted carrier; never edit the route.
	var admission_row: Dictionary = row.duplicate(true)
	admission_row.params["root_motion"] = true
	for error in CaptureGuard.admit(admission_row): push_error(error)
	if not logger.errors.is_empty(): quit(1); return
	output = args[1]; diagnostic = false
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044); background.size = Vector2(1920, 1080); root.add_child(background)
	title = _label("SAVED SEQUENCE | bundled dummy | fixed cameras | Godot4.7.2", Vector2(24, 10), 29)
	status = _label("", Vector2(24, 50), 21)
	_label("FIXED FRONT", Vector2(24, 92), 23); _label("FIXED SIDE", Vector2(984, 92), 23)
	_label("Original public composition | idle > start > walk > stop > idle | two fresh takes | no motion changes", Vector2(24, 1035), 19)
	var ports := [_viewport(0), _viewport(1)]
	var trace: Array = []; var cameras: Array = []; var count := 0; var pngs := 0
	var take_frames := ceili((float(row.write.capture_duration) + 1.0) * 60)
	for take in 2:
		views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
		for v: Dictionary in views: CaptureGuard.attach(v)
		var initial := [_camera_state(views[0]), _camera_state(views[1])]
		cameras.append(initial)
		await process_frame
		for frame in take_frames:
			if frame > 0:
				for v: Dictionary in views: Native.advance(v, 1.0 / 60); _update(v)
			status.text = "Take%d/2 | %.3fs | original action %.3fs | displayed hold after saved endpoint" % [take + 1, float(frame) / 60, row.write.capture_duration]
			await process_frame
			await RenderingServer.frame_post_draw
			for index in views.size():
				var observation := CaptureGuard.frame(views[index])
				observation.merge({"frame":count, "rig":"dummy", "view":index, "take":take + 1, "camera":_camera_state(views[index])})
				trace.append(observation)
				if observation.camera != initial[index]: push_error("Fixed camera drift")
			var image := root.get_texture().get_image()
			if image.get_size() != Vector2i(1920, 1080): push_error("Wrong PNG dimensions")
			if not probe or frame in [0, 177, 210, 270, 330, 390, 423, take_frames - 1]:
				if image.save_png(output.path_join("%06d.png" % count)) != OK: push_error("PNG save failed")
				pngs += 1
			count += 1
			if not logger.errors.is_empty(): break
		for v: Dictionary in views: v.world.free()
		views.clear()
		if not logger.errors.is_empty(): break
	var report := {"kind":"saved_sequence_fixed_representative", "source_head":route.source_head, "route_sha256":FileAccess.get_sha256(args[0]), "binding_sha256":FileAccess.get_sha256(args[2]), "frames":count, "take_frames":take_frames, "png_frames":pngs, "fps":60, "size":[1920,1080], "probe":probe, "trace":trace, "cameras":cameras, "errors":logger.errors, "visual_approval":false, "scope":"Selected dummy fixed-camera supplement; historical four-rig movies retain translation-following cameras."}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if logger.errors.is_empty() and count == take_frames * 2 else 1)
