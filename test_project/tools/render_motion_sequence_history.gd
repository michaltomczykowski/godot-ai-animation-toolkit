extends "res://tools/render_modifier_history.gd"
const Reference := preload("res://tools/motion_sequence_native_reference.gd")
func _load_review(row: Dictionary, viewport: SubViewport, reference_view: bool) -> Dictionary:
	var scene := (ResourceLoader.load(row.states.redo, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var world := viewport.get_node("PreviewWorld") as Node3D
	var group := Node3D.new()
	world.add_child(group)
	for child in scene.get_children():
		if child is Node3D:
			_clear_owners(child)
			child.reparent(group, false)
	scene.free()
	for mixer in group.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
		mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for modifier in group.find_children("*", "SkeletonModifier3D", true, false): modifier.active = false
	var f := group.get_node("MotionSequenceHistory")
	var rig := f.get_node("Character/Skeleton") as Skeleton3D
	var body := f.get_node("Character") as Node3D
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var clip := player.get_animation(row.params.animation_name)
	if reference_view:
		var input := (ResourceLoader.load(row.source, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		root.add_child(input)
		var oracle := Reference.build(input.get_node("MotionSequenceHistory"), row.params, row.group, row.pose_json, clip)
		input.free()
		var library := player.get_animation_library("")
		library.remove_animation(row.params.animation_name)
		library.add_animation(row.params.animation_name, oracle)
	player.speed_scale = 1.0
	player.playback_auto_capture = false
	player.active = true
	player.play(row.params.animation_name, 0.0, 1.0)
	player.advance(0.0)
	var focus: Array = []
	for bone in rig.get_bone_count(): focus.append(bone)
	var visuals := Node3D.new()
	world.add_child(visuals)
	var overlay := _overlay(rig, visuals, focus)
	for rod in overlay.bones:
		rod.mesh.top_radius = 0.012
		rod.mesh.bottom_radius = 0.012
	for pair in overlay.axes:
		for rod in pair:
			rod.mesh.top_radius = 0.008
			rod.mesh.bottom_radius = 0.008
	group.position -= rig.global_position
	var camera: Camera3D = world.find_children("*", "Camera3D", false, false)[0]
	camera.size = 3.4
	var center := Vector3(0, 1.0, -0.2)
	camera.position = center + Vector3(4.0, 1.1, 5.5)
	camera.look_at(center, Vector3.UP)
	var floor := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(5, 5)
	mesh.material = _material(Color(0.1, 0.17, 0.24))
	floor.mesh = mesh
	floor.position.y = 0.03
	visuals.add_child(floor)
	_draw_rig(overlay)
	return {"group": group, "visuals": visuals, "body": body, "player": player, "rig": overlay, "previous": 0.0, "length": clip.length}
func _advance_review(view: Dictionary, time: float) -> void:
	var delta: float = time - view.previous
	if delta > 0.0 and view.player.is_playing():
		view.player.advance(delta)
		if not view.player.root_motion_track.is_empty():
			view.body.position += view.body.quaternion * view.player.get_root_motion_position()
	_draw_rig(view.rig)
	view.previous = time
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected review manifest and output directory")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 24)
	heading.position = Vector2(24, 12)
	root.add_child(heading)
	for index in 2:
		var label := Label.new()
		label.text = "Native playback reference" if index == 0 else "Saved Godot AI output"
		label.position = Vector2(24 + 640 * index, 60)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
	var viewports := [_view(0), _view(1)]
	var frames := 0
	var counts: Array = []
	for index in manifest.cases.size():
		var row: Dictionary = manifest.cases[index]
		heading.text = str(row.id) + " | Godot 4.7.2 | fixed camera"
		views = [_load_review(row, viewports[0], true), _load_review(row, viewports[1], false)]
		await process_frame
		var count: int = ceili(float(views[0].length) * 60.0) + 1
		for frame in count:
			var time := minf(float(frame) / 60, float(views[0].length))
			for view in views: _advance_review(view, time)
			await process_frame
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(output.path_join("%02d_%03d.png" % [index, frame]))
			if error != OK: push_error("Frame save failed")
			frames += 1
		counts.append(count)
		for view in views:
			view.visuals.free()
			view.group.free()
		views.clear()
	OS.remove_logger(logger)
	var report := {"cases": manifest.cases.size(), "frames": frames, "counts": counts, "fps": 60, "errors": logger.errors}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	print("MOTION_SEQUENCE_RENDER=" + JSON.stringify(report))
	quit(0 if logger.errors.is_empty() and frames > 240 and manifest.cases.size() == 4 else 1)
