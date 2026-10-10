extends "res://tools/render_modifier_history.gd"

## Fixed-camera native source versus saved public-route bake. Geometry helpers
## only visualize played bones; no pose is generated or hand-applied here.
const REVIEW_IDS := ["graph_state_60", "graph_oneshot_60", "modifier_spring_1_60", "modifier_ordered_spring_look_1_60", "modifier_retarget_1_60", "root_preserve_true_true_true_60", "root_pose_only_true_true_true_60", "root_apply_true_true_true_60"]
func _decode(value: Variant) -> Variant:
	return Vector2(value.x, value.y) if value is Dictionary else value
func _load(row: Dictionary, viewport: SubViewport, source_view: bool) -> Dictionary:
	var path: String = row.source if source_view else row.states.redo
	var scene := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
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
	for rig in group.find_children("*", "Skeleton3D", true, false): rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var source := group.get_node(row.skeleton) as Skeleton3D
	var body := group.get_node(row.movement_owner) as Node3D
	var player := group.get_node(row.source_player if source_view else row.output) as AnimationPlayer
	var tree := group.get_node(row.tree) as AnimationTree if source_view and not str(row.tree).is_empty() else null
	var mixer: AnimationMixer = tree if tree != null else player
	if not source_view:
		for modifier in group.find_children("*", "SkeletonModifier3D", true, false): modifier.active = false
	player.speed_scale = 1
	player.playback_auto_capture = false
	if tree != null:
		for entry in tree.get_property_list():
			var key := str(entry.name)
			if key.ends_with("/request"): tree.set(key, 0)
			elif key.ends_with("/seek_request"): tree.set(key, -1.0)
			elif key.ends_with("/transition_request"): tree.set(key, "")
		for key in row.params.get("tree_parameters", {}): tree.set(key, _decode(row.params.tree_parameters[key]))
		for start in row.params.get("tree_starts", []): tree.get(start.playback_path).start(start.state, true)
		tree.active = true
	else:
		player.active = true
		player.play(str(row.params.get("source_animation", "input")) if source_view else row.params.animation_name)
	var required: Array = []
	for rig in group.find_children("*", "Skeleton3D", true, false):
		if rig == source or rig.is_ancestor_of(source) or source.is_ancestor_of(rig): required.append(rig)
	var overlay := _overlay(source, world, [])
	for rod in overlay.bones:
		rod.mesh.top_radius = 0.012
		rod.mesh.bottom_radius = 0.012
	for pair in overlay.axes:
		for rod in pair:
			rod.mesh.top_radius = 0.008
			rod.mesh.bottom_radius = 0.008
	var witness := Witness.new()
	source.add_child(witness)
	witness.modification_processed.connect(func(): _draw_rig(overlay))
	var camera: Camera3D = world.find_children("*", "Camera3D", false, false)[0]
	var focus := source.global_position + (Vector3(0.35, 0, 0.15) if source.get_bone_count() == 1 else Vector3(0, 0.8, 0))
	if source.get_bone_count() == 1: camera.size = 1.8
	camera.position = focus + Vector3(3.8, 1.4, 5.5)
	camera.look_at(focus, Vector3.UP)
	var view := {"group": group, "source": source, "body": body, "mixer": mixer, "player": player, "tree": tree, "source_view": source_view, "row": row, "required": required, "cursor": 0, "previous": 0.0, "initial_scale": body.scale, "accum": Vector3.ONE, "rig": overlay}
	_step(view, 0)
	return view
func _step(view: Dictionary, time: float) -> void:
	var delta: float = time - view.previous
	if delta > 0 and (view.tree != null or view.player.is_playing()):
		view.mixer.advance(delta)
		if not view.mixer.root_motion_track.is_empty() and (not view.source_view or view.row.params.get("root_motion_mode", "preserve") != "pose_only"):
			view.body.quaternion = (view.body.quaternion * view.mixer.get_root_motion_rotation()).normalized()
			var frame: Quaternion = view.body.quaternion if view.mixer.root_motion_local else view.mixer.get_root_motion_rotation_accumulator().inverse() * view.body.quaternion
			view.body.position += frame * view.mixer.get_root_motion_position()
			view.accum += view.mixer.get_root_motion_scale()
			view.body.scale = view.initial_scale * view.accum
	var changed := false
	var events: Array = view.row.params.get("tree_events", []) if view.source_view else []
	while view.cursor < events.size() and float(events[view.cursor].time) <= time + 0.00000001:
		var event: Dictionary = events[view.cursor]
		if event.action == "set": view.tree.set(event.path, _decode(event.value))
		elif event.action == "start": view.tree.get(event.path).start(event.state, true)
		else: view.tree.get(event.path).travel(event.state, true)
		view.cursor += 1
		changed = true
	if time == 0 or changed: view.mixer.advance(0)
	if time == 0:
		for rig in view.required:
			for modifier in rig.get_children():
				if modifier is SpringBoneSimulator3D and modifier.active: modifier.reset()
	for rig in view.required:
		rig.advance(delta)
		rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	view.previous = time
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 25)
	heading.position = Vector2(24, 12)
	root.add_child(heading)
	for i in 2:
		var label := Label.new()
		label.text = "Native source replay" if i == 0 else "Saved Godot AI bake / native playback"
		label.position = Vector2(24 + i * 640, 60)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
	var viewports := [_view(0), _view(1)]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://rig_bake_saved_matrix.json"))
	var frames := 0
	for case_index in REVIEW_IDS.size():
		var matches: Array = manifest.cases.filter(func(row): return row.id == REVIEW_IDS[case_index])
		if matches.size() != 1:
			push_error("Missing/duplicate bake preview case " + REVIEW_IDS[case_index])
			quit(1)
			return
		var row: Dictionary = matches[0]
		heading.text = row.id + " | Godot 4.7.2 | played bones and local axes"
		views = [_load(row, viewports[0], true), _load(row, viewports[1], false)]
		await process_frame
		for frame in 61:
			var time := minf(float(frame) / 60, float(row.params.duration))
			for view in views:
				# Include each event endpoint before this rendered frame.
				if view.source_view:
					for event in row.params.get("tree_events", []):
						if float(event.time) > view.previous and float(event.time) < time: _step(view, float(event.time))
				if time > view.previous: _step(view, time)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%02d_%03d.png" % [case_index, frame]))
			frames += 1
		for view in views:
			view.group.free()
			for rod in view.rig.bones: rod.free()
			for pair in view.rig.axes:
				for rod in pair: rod.free()
	OS.remove_logger(logger)
	print("BAKE_PREVIEW=" + JSON.stringify({"cases": REVIEW_IDS, "frames": frames, "errors": logger.errors, "output": output}))
	quit(0 if logger.errors.is_empty() and frames == 488 else 1)
