extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
var views: Array[Dictionary] = []
var title: Label
var status: Label
var diagnostic := false
var output := ""

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m
func _box(parent: Node, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	node.mesh = mesh
	parent.add_child(node)
	return node
func _sphere(parent: Node, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = 2.0 * radius
	mesh.material = _mat(color)
	node.mesh = mesh
	parent.add_child(node)
	return node
func _rod(parent: Node, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.material = _mat(color)
	node.mesh = mesh
	parent.add_child(node)
	return node
func _line(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	node.visible = direction.length() > 0.00001
	if node.visible:
		node.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())) * Basis.from_scale(Vector3(1, direction.length(), 1)), (from + to) / 2.0)
func _label(text_value: String, position_value: Vector2, size_value: int) -> Label:
	var l := Label.new()
	l.text = text_value
	l.position = position_value
	l.add_theme_font_size_override("font_size", size_value)
	root.add_child(l)
	return l
func _viewport(index: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(952, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var texture := TextureRect.new()
	texture.texture = viewport.get_texture()
	texture.position = Vector2(4 + index * 960, 125)
	texture.size = Vector2(952, 900)
	root.add_child(texture)
	return viewport
func _setup(row: Dictionary, viewport: SubViewport, index: int) -> Dictionary:
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.035, 0.055, 0.075)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.35
	world.add_child(env)
	for i in 2:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45 if i == 0 else -25, -35 if i == 0 else 130, 0)
		light.light_energy = 0.85 if i == 0 else 0.3
		light.shadow_enabled = i == 0
		world.add_child(light)
	var group := Node3D.new()
	world.add_child(group)
	var v := Native.load_case(row, group)
	# Presentation normalization rotates the entire scene, never an individual bone.
	# Native root extraction remains inside the original rig coordinate convention.
	group.basis = Basis(v.right, v.up, -v.forward).inverse()
	var leg: float = v.leg
	var ankle := minf(Native.rest(v.rig, v.roles, "foot_l").y, Native.rest(v.rig, v.roles, "foot_r").y)
	var floor_y := ankle - 0.035 * leg
	if not bool(row.synthetic):
		floor_y = INF
		for mesh: MeshInstance3D in v.scene.find_children("*", "MeshInstance3D", true, false):
			var aabb := mesh.get_aabb()
			for corner in 8: floor_y = minf(floor_y, (mesh.global_transform * aabb.get_endpoint(corner)).y)
	group.position.y -= floor_y
	v.up = Vector3.UP
	v.forward = Vector3.FORWARD
	v.right = Vector3.RIGHT
	v.ground = ankle - floor_y
	v.initial_body = v.body.global_position
	v.world = world
	v.group = group
	v.height = Native.rest(v.rig, v.roles, "head").y + 0.25 * leg
	v.segments = []
	v.joints = []
	v.hand_shapes = []
	if bool(row.synthetic):
		for pair in [["hips", "spine", 0.13], ["spine", "chest", 0.13], ["chest", "head", 0.10], ["arm_l", "arm_r", 0.10], ["thigh_l", "thigh_r", 0.10], ["thigh_l", "shin_l", 0.065], ["thigh_r", "shin_r", 0.065], ["shin_l", "foot_l", 0.055], ["shin_r", "foot_r", 0.055], ["arm_l", "forearm_l", 0.045], ["arm_r", "forearm_r", 0.045], ["forearm_l", "hand_l", 0.04], ["forearm_r", "hand_r", 0.04], ["foot_l", "toe_l", 0.035], ["foot_r", "toe_r", 0.035]]:
			v.segments.append({"node": _rod(world, leg * float(pair[2]), Color(0.13, 0.55, 0.7)), "a": pair[0], "b": pair[1]})
		for role in ["hips", "shin_l", "shin_r", "arm_l", "arm_r", "forearm_l", "forearm_r", "hand_l", "hand_r", "foot_l", "foot_r"]:
			v.joints.append({"node": _sphere(world, leg * (0.04 if role.begins_with("hand") else 0.065), Color(0.22, 0.67, 0.78)), "role": role})
		v.joints.append({"node": _sphere(world, leg * 0.135, Color(0.34, 0.73, 0.83)), "role": "head"})
		for side in ["l", "r"]:
			var hand_index: int = v.indices["hand_" + side]
			var fore_index: int = v.indices["forearm_" + side]
			var hand_rest: Transform3D = v.rig.get_bone_global_rest(hand_index)
			var rest_direction: Vector3 = hand_rest.origin - v.rig.get_bone_global_rest(fore_index).origin
			v.hand_shapes.append({"node": _rod(world, leg * 0.035, Color(0.55, 0.8, 0.88)),
				"role": "hand_" + side, "index": hand_index,
				"local_direction": hand_rest.basis.inverse() * rest_direction.normalized(), "length": 0.14 * leg})
	# This floor is a visual rest-sole alignment, not a collision measurement.
	var floor := _box(world, Vector3(40, 0.02, 40), Color(0.14, 0.19, 0.23))
	floor.position.y = -0.015
	for n in range(-40, 41):
		var major := n % 4 == 0
		var color := Color(0.32, 0.39, 0.44) if major else Color(0.21, 0.27, 0.32)
		var width := 0.008 if major else 0.003
		var x := _box(world, Vector3(width, 0.002, 40), color)
		x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		x.position = Vector3(float(n) * 0.25, 0, 0)
		var z := _box(world, Vector3(40, 0.002, width), color)
		z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z.position = Vector3(0, 0, float(n) * 0.25)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(v.height) * 1.45
	camera.near = 0.02
	world.add_child(camera)
	v.camera = camera
	v.camera_offset = (Vector3(0, 0.27, -4.0) if index == 0 else Vector3(4.0, 0.27, 0.0)) * float(v.height)
	v.center_offset = Vector3(0, float(v.height) * 0.46, 0) - v.initial_body
	v.diag = {}
	if diagnostic:
		v.diag.hip = _sphere(world, leg * 0.03, Color(1.0, 0.4, 0.95))
		v.diag.hip_line = _rod(world, leg * 0.007, Color(1.0, 0.4, 0.95))
		v.diag.support = _rod(world, leg * 0.012, Color(0.3, 1, 0.4))
		v.diag.root_travel = _rod(world, leg * 0.006, Color(0.25, 0.7, 1))
		for side in ["l", "r"]: v.diag[side] = _sphere(world, leg * 0.045, Color.GREEN)
	_update(v)
	return v
func _update(v: Dictionary) -> void:
	for segment: Dictionary in v.segments: _line(segment.node, Native.point(v, segment.a), Native.point(v, segment.b))
	for joint: Dictionary in v.joints: joint.node.global_position = Native.point(v, joint.role)
	for hand: Dictionary in v.hand_shapes:
		var pose: Transform3D = v.rig.global_transform * v.rig.get_bone_global_pose(hand.index)
		_line(hand.node, pose.origin, pose.origin + pose.basis * hand.local_direction * float(hand.length))
	var center: Vector3 = v.body.global_position + v.center_offset
	v.camera.position = center + v.camera_offset
	v.camera.look_at(center, Vector3.UP)
	if not diagnostic: return
	var hip := Native.point(v, "hips")
	var hip_projected := Vector3(hip.x, 0.025, hip.z)
	v.diag.hip.global_position = hip_projected
	_line(v.diag.hip_line, hip_projected, hip)
	var supporting: Array[Vector3] = []
	for side in ["l", "r"]:
		var foot := Native.point(v, "foot_" + side)
		var on := Native.contact(v, side)
		v.diag[side].global_position = foot
		v.diag[side].mesh.material.albedo_color = Color(0.2, 1, 0.4) if on else Color(1, 0.65, 0.15)
		if on: supporting.append(Vector3(foot.x, 0.02, foot.z))
	if supporting.size() == 2: _line(v.diag.support, supporting[0], supporting[1])
	else: v.diag.support.visible = false
	var here: Vector3 = v.body.global_position
	var start: Vector3 = v.initial_body
	_line(v.diag.root_travel, Vector3(start.x, 0.015, start.z), Vector3(here.x, 0.015, here.z))
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]
	diagnostic = args[2] == "diagnostic"
	var preview_frames := int(args[3]) if args.size() > 3 else 360
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color(0.018, 0.029, 0.044)
	background.size = Vector2(1920, 1080)
	root.add_child(background)
	title = _label("", Vector2(24, 10), 30)
	status = _label("", Vector2(24, 50), 23)
	_label("FRONT", Vector2(24, 92), 23)
	_label("SIDE", Vector2(984, 92), 23)
	_label("Green: declared contact   Amber: swing   Magenta: hip projection (not COM)   Blue: root travel" if diagnostic else "Native saved-scene playback | cameras follow translation only | stationary 25 cm grid | no motion tuning changes", Vector2(24, 1035), 21)
	var ports := [_viewport(0), _viewport(1)]
	var frames := 0
	var rows: Array = []
	for row: Dictionary in manifest.cases:
		title.text = "WALK BASELINE r001 | %s | current tuning | Godot 4.7.2 | %s" % [row.label, str(manifest.source_head).left(7)]
		views = [_setup(row, ports[0], 0), _setup(row, ports[1], 1)]
		await process_frame
		for frame in preview_frames:
			if frame > 0:
				for v: Dictionary in views:
					Native.advance(v, 1.0 / 60.0)
					_update(v)
			var v: Dictionary = views[0]
			var contacts := ("L " if Native.contact(v, "l") else "") + ("R" if Native.contact(v, "r") else "")
			status.text = "%s | rig time %05.2f s | travel %.2f m | declared support %s" % ["DIAGNOSTIC" if diagnostic else "CLEAN", float(frame) / 60.0, v.body.global_position.distance_to(v.initial_body), contacts]
			await process_frame
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(output.path_join("%06d.png" % frames))
			if error != OK: push_error("Frame save failed: " + str(error))
			frames += 1
		rows.append({"id": row.id, "frames": preview_frames, "start_s": float(frames - preview_frames) / 60, "duration_s": float(preview_frames) / 60, "height_m": views[0].height, "visual_floor_rest_ankle_offset_m": views[0].ground})
		for v: Dictionary in views: v.world.free()
		views.clear()
		print("Captured " + str(row.id) + ": " + str(preview_frames) + " frames")
	var report := {"revision": manifest.revision, "source_head": manifest.source_head, "fps": 60, "size": [1920, 1080], "frames": frames, "mode": args[2], "cases": rows, "errors": logger.errors, "root_consumers_per_view": 1}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("CHARACTER_QUALITY_RENDER=" + JSON.stringify(report))
	quit(0 if logger.errors.is_empty() and rows.size() == 4 else 1)
