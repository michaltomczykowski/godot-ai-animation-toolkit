extends "res://tools/check_saved_bake_capture.gd"
## Draw the shared evaluator's final witnesses without yielding a process tick.
## Overlay transforms only: no authored pose, key, modifier or hierarchy edits.
var capture: Dictionary
var capture_output: String
var ports: Array = []
var cameras: Array = []
var overlay: Node3D
var meshes: Dictionary = {}
var images: Array = []
var sample_index := 0

func _initialize() -> void:
	OS.add_logger(logger)
	_start.call_deferred()

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("manifest, native report, render report and exclusive frame folder required")
		quit(1); return
	capture = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	capture_output = args[3]
	if capture.get("kind") != "saved_bake_capture_binding" or DirAccess.dir_exists_absolute(capture_output):
		push_error("new bound capture output required"); quit(1); return
	for file: Dictionary in capture.files:
		_check(FileAccess.get_sha256(file.path) == file.sha256, "capture dependency " + str(file.path))
	DirAccess.make_dir_recursive_absolute(capture_output)
	root.content_scale_size = Vector2i(960, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.size = Vector2i(960, 1080)
	for index in 2:
		var port := SubViewport.new()
		port.size = Vector2i(960, 540)
		port.world_3d = World3D.new() if index == 0 else ports[0].world_3d
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(port)
		ports.append(port)
		var texture := TextureRect.new()
		texture.texture = port.get_texture()
		texture.position = Vector2(0, index * 540)
		texture.size = Vector2(960, 540)
		root.add_child(texture)
		var camera := Camera3D.new()
		port.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.cull_mask = 1 << 19
		camera.current = true
		cameras.append(camera)
	overlay = Node3D.new()
	ports[0].add_child(overlay)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.04, 0.065)
	overlay.add_child(environment)
	await process_frame
	await super._run()

func _open_scene(path: String):
	var scene: Node = _load(path)
	if scene != null: scene.reparent(ports[0], false)
	return scene

func _rod(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.008; mesh.bottom_radius = 0.008; mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	node.mesh = mesh; node.layers = 1 << 19
	overlay.add_child(node)
	return node

func _line(node: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var offset := end - start
	node.visible = offset.length() > 0.000001
	if node.visible:
		node.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, offset.normalized())).scaled(Vector3(1, offset.length(), 1)), (start + end) * 0.5)
		node.force_update_transform()

func _capture_begin(view: Dictionary):
	sample_index = 0
	meshes.clear()
	var configs: Array = capture.cameras[view.row.id]
	for index in 2:
		var config: Dictionary = configs[index]
		var camera: Camera3D = cameras[index]
		camera.position = Vector3(config.position[0], config.position[1], config.position[2])
		camera.look_at(Vector3(config.center[0], config.center[1], config.center[2]), Vector3.UP)
		camera.size = config.size; camera.near = config.near; camera.far = config.far
		camera.force_update_transform()
	for rig: Skeleton3D in view.required:
		var rods: Array = []
		for bone in rig.get_bone_count():
			rods.append([_rod(Color(0.2, 0.85, 0.95)), _rod(Color(1, 0.3, 0.3)), _rod(Color(0.35, 0.55, 1))])
		meshes[str(view.scene.get_path_to(rig))] = rods
	# No yield after witness attachment/player start: even a zero-delta deferred
	# skeleton notification would change the native witness and solver schedule.

func _snapshot(view: Dictionary) -> String:
	var state: Array = [_body(view.body), _tree_clock(view.mixer if view.mixer is AnimationTree else null)]
	for rig: Skeleton3D in view.required:
		var counts: Array = []
		for child in rig.get_children():
			if child is FinalPose: counts.append(child.count)
		state.append([_observation(rig), counts])
	return var_to_str(state)

func _capture_sample(view: Dictionary, sample: Dictionary):
	var points: Array[Vector3] = []
	for rig: Skeleton3D in view.required:
		var key := str(view.scene.get_path_to(rig))
		var world: Array = sample.required[key].pose.world
		for bone in world.size():
			var pose: Transform3D = world[bone]
			var parent := rig.get_bone_parent(bone)
			var rods: Array = meshes[key][bone]
			if parent >= 0: _line(rods[0], world[parent].origin, pose.origin)
			else: rods[0].visible = false
			_line(rods[1], pose.origin, pose.origin + pose.basis.x.normalized() * 0.15)
			_line(rods[2], pose.origin, pose.origin + pose.basis.z.normalized() * 0.15)
			points.append(pose.origin)
			points.append(pose.origin + pose.basis.x.normalized() * 0.15)
			points.append(pose.origin + pose.basis.z.normalized() * 0.15)
	var bounds: Array = []
	for camera: Camera3D in cameras:
		var low := Vector2(INF, INF); var high := Vector2(-INF, -INF)
		for point: Vector3 in points:
			var depth := -(camera.global_transform.affine_inverse() * point).z
			_check(depth > camera.near + 0.01 and depth < camera.far - 0.01, "capture depth")
			var pixel := camera.unproject_position(point)
			low = low.min(pixel); high = high.max(pixel)
		_check(low.x >= 12 and low.y >= 12 and high.x <= 948 and high.y <= 528, "capture conservative bounds")
		bounds.append([low.x, low.y, high.x, high.y])
	var before := _snapshot(view)
	var process_before := Engine.get_process_frames()
	var physics_before := Engine.get_physics_frames()
	# No process-frame yield: deferred Spring reset must not run between samples.
	RenderingServer.force_draw(false, 0.0)
	RenderingServer.force_sync()
	var image := root.get_texture().get_image()
	_check(image.get_size() == Vector2i(960, 1080), "actual capture dimensions")
	_check(before == _snapshot(view), "draw changed original evaluator state")
	_check(process_before == Engine.get_process_frames() and physics_before == Engine.get_physics_frames(), "draw advanced engine simulation")
	var name := "%s-%s-%d-%03d.png" % [view.row.id, view.side, view.take, sample_index]
	_check(not FileAccess.file_exists(capture_output.path_join(name)), "exclusive capture PNG")
	_check(image.save_png(capture_output.path_join(name)) == OK, "capture PNG write")
	images.append({"id": view.row.id, "side": view.side, "take": view.take, "sample": sample_index, "time": sample.time, "delta": sample.delta, "name": name, "sha256": FileAccess.get_sha256(capture_output.path_join(name)), "bounds": bounds, "no_simulation_advance": before == _snapshot(view) and process_before == Engine.get_process_frames() and physics_before == Engine.get_physics_frames()})
	sample_index += 1

func _capture_end(_view: Dictionary):
	for rods: Array in meshes.values():
		for set_of_rods: Array in rods:
			for rod: MeshInstance3D in set_of_rods: rod.free()
	meshes.clear()
	var report := {"kind": "saved_bake_capture_images", "binding_sha256": FileAccess.get_sha256(OS.get_cmdline_user_args()[2]), "size": [960, 1080], "images": images, "failures": failures, "engine_errors": logger.values, "passed": failures.is_empty() and logger.values.is_empty(), "scope": "Unskinned final joint/axis witnesses, two fixed cameras. Presentation repetition is encoded separately, never simulated."}
	FileAccess.open(capture_output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
