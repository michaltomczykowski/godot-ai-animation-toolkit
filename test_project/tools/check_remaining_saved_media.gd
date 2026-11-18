extends "res://tools/render_saved_bake_capture.gd"
## Three immutable saved cases. No production handler, reference generation,
## bone pose setter, solver or animation key write is used by this evaluator.
var remaining_manifest: Dictionary
var remaining_runs: Array = []
var remaining_render := false

func _initialize() -> void:
	OS.add_logger(logger)
	_start.call_deferred()

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("manifest, report, binding, frame folder (or - for native) required")
		quit(1); return
	remaining_manifest = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	capture = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	capture_output = args[3]
	remaining_render = capture_output != "-"
	_check(capture.get("kind") == "remaining_saved_capture_binding", "fixed binding kind")
	_check(capture.manifest_sha256 == FileAccess.get_sha256(args[0]), "bound manifest")
	for file: Dictionary in capture.files:
		_check(FileAccess.get_sha256(file.path) == file.sha256, "bound input " + str(file.path))
	if remaining_render:
		_check(not DirAccess.dir_exists_absolute(capture_output), "exclusive frames")
		if not failures.is_empty(): quit(1); return
		DirAccess.make_dir_recursive_absolute(capture_output)
		_setup_remaining_views()
		await process_frame
	for row: Dictionary in remaining_manifest.cases:
		for take in 2:
			if row.id == "secondary_branches_local_60":
				for fps in ([60] if remaining_render else [30, 60, 120]):
					for side in ["reference", "redo"]:
						_remaining_secondary(row, side, take, fps)
			else:
				for side in ["before", "after"]: _remaining_static(row, side, take)
	var report := {"kind": "remaining_saved_native", "manifest_sha256": FileAccess.get_sha256(args[0]), "binding_sha256": FileAccess.get_sha256(args[2]), "rendered": remaining_render, "runs": remaining_runs, "failures": failures, "engine_errors": logger.values, "passed": failures.is_empty() and logger.values.is_empty(), "clock_contract": "Secondary: one manual player, complete finite clip. Static: zero simulation advances. Encoded display holds are separate."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	if remaining_render:
		var image_report := {"kind": "remaining_saved_images", "binding_sha256": report.binding_sha256, "size": [960, 1080], "images": images, "failures": failures, "engine_errors": logger.values, "passed": report.passed}
		FileAccess.open(capture_output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(image_report))
	print("REMAINING_SAVED=" + JSON.stringify({"passed": report.passed, "runs": remaining_runs.size(), "images": images.size()}))
	OS.remove_logger(logger)
	quit(0 if report.passed else 1)

func _setup_remaining_views() -> void:
	root.content_scale_size = Vector2i(960, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(960, 1080)
	for index in 2:
		var port := SubViewport.new()
		port.size = Vector2i(960, 540)
		port.world_3d = World3D.new() if index == 0 else ports[0].world_3d
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(port); ports.append(port)
		var texture := TextureRect.new()
		texture.texture = port.get_texture(); texture.position = Vector2(0, index * 540); texture.size = Vector2(960, 540)
		root.add_child(texture)
		var camera := Camera3D.new()
		port.add_child(camera); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.cull_mask = 1 << 19; camera.current = true; cameras.append(camera)
	overlay = Node3D.new(); ports[0].add_child(overlay)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.04, 0.065)
	overlay.add_child(environment)

func _remaining_load(path: String) -> Node:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(packed != null, "saved scene loads " + path)
	if packed == null: return null
	var scene := packed.instantiate()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	for mixer in scene.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
		mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_check(scene.find_children("*", "SkeletonModifier3D", true, false).is_empty(), "no saved solver")
	# Move the entire original root under the viewport. Relative player/owner
	# paths and all original sibling roots remain together and unchanged.
	(ports[0] if remaining_render else root).add_child(scene)
	return scene

func _legacy(value: Variant) -> Variant:
	if value is Vector3: return {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
	if value is Basis: return {"type": "Basis", "x": _legacy(value.x), "y": _legacy(value.y), "z": _legacy(value.z)}
	if value is Transform3D: return {"type": "Transform3D", "origin": _legacy(value.origin), "basis": _legacy(value.basis)}
	if value is Transform2D: return {"x": [value.x.x, value.x.y], "y": [value.y.x, value.y.y], "origin": [value.origin.x, value.origin.y]}
	return value

func _remaining_snapshot(node: Node, top: bool = true, origin: Node = null) -> Dictionary:
	if origin == null: origin = node
	var result := {"type": node.get_class(), "children": {}}
	if not top: result.owner = "" if node.owner == null else str(origin.get_path_to(node.owner)) if origin == node.owner or origin.is_ancestor_of(node.owner) else "[scene]"
	if node is Node3D: result.transform = _legacy(node.transform)
	if node is Node2D: result.transform = _legacy(node.transform)
	if node is Skeleton3D:
		var bones: Array = []
		for i in node.get_bone_count():
			var meta := {}
			for key in node.get_bone_meta_list(i): meta[str(key)] = node.get_bone_meta(i, key)
			bones.append({"name": node.get_bone_name(i), "parent": node.get_bone_parent(i), "rest": _legacy(node.get_bone_rest(i)), "pose": _legacy(node.get_bone_pose(i)), "enabled": node.is_bone_enabled(i), "meta": meta})
		result.bones = bones
	for child in node.get_children(): result.children[str(child.name)] = _remaining_snapshot(child, false, origin)
	return result

func _remaining_state(scene: Node) -> Dictionary:
	var rigs := {}; var clocks := {}
	for rig: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		var components: Array = []
		for i in rig.get_bone_count(): components.append({"position": _stable(rig.get_bone_pose_position(i)), "rotation": _stable(rig.get_bone_pose_rotation(i)), "scale": _stable(rig.get_bone_pose_scale(i))})
		rigs[str(scene.get_path_to(rig))] = {"snapshot": _remaining_snapshot(rig), "components": components, "pose": _stable(_observation(rig))}
	for mixer in scene.find_children("*", "AnimationMixer", true, false):
		clocks[str(scene.get_path_to(mixer))] = {"active": mixer.active, "manual": mixer.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "position": mixer.current_animation_position if mixer is AnimationPlayer and not mixer.assigned_animation.is_empty() else 0.0, "playing": mixer.is_playing() if mixer is AnimationPlayer else false, "assigned": str(mixer.assigned_animation) if mixer is AnimationPlayer else "", "speed": mixer.speed_scale}
	return {"rigs": rigs, "clocks": clocks, "tree": _remaining_snapshot(scene)}

func _snapshot(view: Dictionary) -> String:
	return var_to_str(_remaining_state(view.scene))

func _remaining_view(row: Dictionary, scene: Node, side: String, take: int) -> Dictionary:
	return {"row": row, "scene": scene, "side": side, "take": take, "required": scene.find_children("*", "Skeleton3D", true, false)}

func _remaining_sample(view: Dictionary, time: float, delta: float) -> Dictionary:
	var required := {}
	for rig: Skeleton3D in view.required: required[str(view.scene.get_path_to(rig))] = {"pose": _observation(rig)}
	var sample := {"time": time, "delta": delta, "required": required, "state": _remaining_state(view.scene)}
	if remaining_render: _capture_sample(view, sample)
	return _stable(sample)

func _remaining_end(view: Dictionary) -> void:
	if remaining_render:
		for rods: Array in meshes.values():
			for set_of_rods: Array in rods:
				for rod: MeshInstance3D in set_of_rods: rod.free()
		meshes.clear()
	view.scene.free()

func _remaining_static(row: Dictionary, side: String, take: int) -> void:
	var before := failures.size()
	var scene := _remaining_load(row.files[side].path)
	if scene == null: return
	var view := _remaining_view(row, scene, side, take)
	var fixture := scene.get_node("RigChainHistory")
	var snapshot := _remaining_snapshot(fixture)
	for mixer in scene.find_children("*", "AnimationMixer", true, false): _check(not mixer.active, "static has no active writer")
	if remaining_render: _capture_begin(view)
	var initial := _remaining_sample(view, 0.0, 0.0)
	var final := _remaining_state(scene)
	_check(initial.state == final, "static draw leaves complete original state unchanged")
	remaining_runs.append({"id": row.id, "side": side, "take": take, "fps": 0, "scene_sha256": FileAccess.get_sha256(row.files[side].path), "snapshot": snapshot, "simulation_advances": 0, "trace": [initial], "after_draw": final, "failures": failures.slice(before)})
	_remaining_end(view)

func _remaining_value(animation: Animation, track: int, time: float) -> Variant:
	var kind := animation.track_get_type(track)
	if kind == Animation.TYPE_ROTATION_3D: return animation.rotation_track_interpolate(track, time)
	if kind == Animation.TYPE_POSITION_3D: return animation.position_track_interpolate(track, time)
	return animation.scale_track_interpolate(track, time)

func _remaining_tracks(animation: Animation) -> Array:
	var rows: Array = []
	for i in animation.get_track_count():
		var keys: Array = []
		for k in animation.track_get_key_count(i): keys.append({"time": animation.track_get_key_time(i, k), "transition": animation.track_get_key_transition(i, k), "value": _stable(animation.track_get_key_value(i, k))})
		rows.append({"path": str(animation.track_get_path(i)), "type": animation.track_get_type(i), "enabled": animation.track_is_enabled(i), "interpolation": animation.track_get_interpolation_type(i), "loop_wrap": animation.track_get_interpolation_loop_wrap(i), "keys": keys})
	return rows

func _remaining_times(animation: Animation, fps: int) -> Array:
	var times: Array = [0.0, animation.length]
	for i in range(1, ceili(animation.length * fps)):
		var at := float(i) / fps
		if not times.has(at): times.append(at)
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			var at := animation.track_get_key_time(track, key)
			if not times.has(at): times.append(at)
			if key > 0:
				var midpoint := (at + animation.track_get_key_time(track, key - 1)) * 0.5
				if not times.has(midpoint): times.append(midpoint)
	times.sort()
	return times

func _remaining_secondary(row: Dictionary, side: String, take: int, fps: int) -> void:
	var before := failures.size()
	var scene := _remaining_load(row.files.source.path if side == "reference" else row.files.redo.path)
	if scene == null: return
	var player := scene.get_node("MotionSequenceHistory/Playback/AnimationPlayer") as AnimationPlayer
	var name: String = row.params.animation_name
	var reference := ResourceLoader.load(row.files.reference.path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	_check(reference != null, "persisted diagnostic reference loads")
	if reference == null: scene.free(); return
	# The sole diagnostic substitution is this exact persisted Animation. No
	# reference builder, solver, resampling or key generation is called.
	if side == "reference":
		var library := player.get_animation_library("")
		if library.has_animation(name): library.remove_animation(name)
		library.add_animation(name, reference)
	var animation := player.get_animation(name)
	_check(animation != null and animation.loop_mode == Animation.LOOP_NONE and absf(animation.length - 1.0) < 0.000001, "complete finite one-second clip")
	if animation == null: scene.free(); return
	var actual_tracks := _remaining_tracks(animation)
	var reference_tracks := _remaining_tracks(reference)
	_check(actual_tracks.size() == reference_tracks.size() and actual_tracks.size() == 5, "all five persisted tracks")
	for i in mini(actual_tracks.size(), reference_tracks.size()):
		var a: Dictionary = actual_tracks[i]; var b: Dictionary = reference_tracks[i]
		for field in ["path", "type", "enabled", "interpolation", "loop_wrap"]: _check(a[field] == b[field], "track contract " + field)
		_check(a["keys"].size() == b["keys"].size(), "complete key count")
		for key in mini(a["keys"].size(), b["keys"].size()):
			_check(absf(a["keys"][key].time - b["keys"][key].time) < 0.0000001 and a["keys"][key].transition == b["keys"][key].transition, "key time/transition")
	var markers := {}
	for marker in animation.get_marker_names(): markers[str(marker)] = {"time": animation.get_marker_time(marker), "color": str(animation.get_marker_color(marker))}
	var wanted_markers := {}
	for marker in reference.get_marker_names(): wanted_markers[str(marker)] = {"time": reference.get_marker_time(marker), "color": str(reference.get_marker_color(marker))}
	_check(markers == wanted_markers, "persisted markers")
	var saved_speed := player.speed_scale
	player.speed_scale = 1.0; player.playback_auto_capture = false
	player.active = true; player.play(name, 0.0, 1.0); player.advance(0.0)
	var view := _remaining_view(row, scene, side, take)
	if remaining_render: _capture_begin(view)
	var trace: Array = []; var previous := 0.0
	var base := player.get_node(player.root_node)
	for time: float in _remaining_times(reference, fps):
		var delta := time - previous
		if delta > 0.0: player.advance(delta)
		var observed: Array = []; var expected: Array = []
		for i in animation.get_track_count():
			var path := animation.track_get_path(i); var kind := animation.track_get_type(i)
			var rig := base.get_node(NodePath(path.get_concatenated_names())) as Skeleton3D
			var bone := rig.find_bone(str(path.get_subname(0)))
			_check(bone >= 0 and animation.track_is_enabled(i), "valid enabled bone target")
			var actual: Variant = rig.get_bone_pose_rotation(bone) if kind == Animation.TYPE_ROTATION_3D else rig.get_bone_pose_position(bone) if kind == Animation.TYPE_POSITION_3D else rig.get_bone_pose_scale(bone)
			var wanted: Variant = _remaining_value(reference, i, time)
			var error := 0.0
			if actual is Quaternion:
				var difference: Quaternion = actual.inverse() * wanted
				error = 2.0 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w))
			else: error = actual.distance_to(wanted)
			_check(actual.is_finite() and wanted.is_finite() and error <= (0.001 if kind == Animation.TYPE_ROTATION_3D else 0.0001), "native track interpolation " + str(path) + " at " + str(time))
			observed.append(_stable(actual)); expected.append(_stable(wanted))
		var sample := _remaining_sample(view, time, delta)
		sample.actual = observed; sample.reference = expected
		sample.root_delta = _stable(player.get_root_motion_position())
		var owners := 0
		for clock: Dictionary in sample.state.clocks.values():
			if clock.active: owners += 1
		_check(owners == 1 and player.root_motion_track.is_empty(), "single writer and no root consumer")
		sample.owners = owners
		trace.append(sample); previous = time
	var endpoint := _remaining_state(scene)
	# Display holds never call advance, seek, process_frame or a solver.
	_check(previous == animation.length, "finite endpoint evaluated")
	remaining_runs.append({"id": row.id, "side": side, "take": take, "fps": fps, "scene_sha256": FileAccess.get_sha256(row.files.source.path if side == "reference" else row.files.redo.path), "reference_sha256": FileAccess.get_sha256(row.files.reference.path), "saved_speed_scale": saved_speed, "evaluation_speed_scale": player.speed_scale, "length": animation.length, "loop_mode": animation.loop_mode, "tracks": actual_tracks, "reference_tracks": reference_tracks, "markers": markers, "trace": trace, "held_endpoint": endpoint, "hold_simulation_advances": 0, "failures": failures.slice(before)})
	_remaining_end(view)
