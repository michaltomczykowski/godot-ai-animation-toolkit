extends SceneTree

## Render saved public-tool output. No toolkit handlers or test helpers.
## Only authored input/target stimuli change; native modifiers supply output.
class Witness extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void: pass

const CASES := ["local_ik_setup_dummy", "local_look_at_setup_dummy", "local_twist_setup_dummy", "local_spring_setup_dummy", "local_retarget_setup_dummy", "stack_2_1.0", "stack_4_0.5"]
const TITLES := ["Two-bone IK / bundled dummy", "Look-at / false secondary default", "Twist distribution / bundled dummy", "Spring / world-center collision", "Retarget / authored receiver", "Ordered IK > look-at > twist", "Ordered IK > spring / final influence 0.5"]
var views: Array[Dictionary] = []
var heading: Label
var output := "user://modifier_history_preview"

func _initialize() -> void: _run.call_deferred()
func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
func _sphere(parent: Node, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.material = _material(color)
	node.mesh = mesh
	parent.add_child(node)
	return node
func _rod(parent: Node, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.material = _material(color)
	node.mesh = mesh
	parent.add_child(node)
	return node
func _line(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	node.visible = direction.length() > 0.00001
	if not node.visible: return
	var basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	node.global_transform = Transform3D(basis.scaled(Vector3(1, direction.length(), 1)), (from + to) / 2)
func _poses(source: Skeleton3D) -> Array:
	var poses: Array = []
	for i in source.get_bone_count(): poses.append(source.get_bone_pose(i))
	return poses
func _restore(source: Skeleton3D, poses: Array) -> void:
	for i in poses.size(): source.set_bone_pose(i, poses[i])
func _overlay(source: Skeleton3D, world: Node3D) -> Dictionary:
	var bones: Array = []
	var axes: Array = []
	for i in source.get_bone_count():
		bones.append(_rod(world, 0.008, Color(0.2, 0.85, 0.9)))
		axes.append([_rod(world, 0.004, Color(1, 0.3, 0.3)), _rod(world, 0.004, Color(0.35, 0.5, 1))])
	return {"source": source, "bones": bones, "axes": axes}
func _draw_rig(rig: Dictionary) -> void:
	var source: Skeleton3D = rig.source
	for i in source.get_bone_count():
		var pose := source.global_transform * source.get_bone_global_pose(i)
		var parent := source.get_bone_parent(i)
		if parent >= 0: _line(rig.bones[i], (source.global_transform * source.get_bone_global_pose(parent)).origin, pose.origin)
		else: rig.bones[i].visible = false
		var axis_size := 0.06 if source.get_bone_count() > 10 else 0.15
		_line(rig.axes[i][0], pose.origin, pose.origin + pose.basis.x.normalized() * axis_size)
		_line(rig.axes[i][1], pose.origin, pose.origin + pose.basis.z.normalized() * axis_size)
func _view(index: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 610)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var texture := TextureRect.new()
	texture.texture = viewport.get_texture()
	texture.position = Vector2(index * 640, 100)
	texture.size = Vector2(640, 610)
	root.add_child(texture)
	var world := Node3D.new()
	world.name = "PreviewWorld"
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.025, 0.045, 0.075)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.0
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(3.8, 2.4, 5.5)
	camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	camera.current = true
	return viewport
func _load(row: Dictionary, viewport: SubViewport, enabled: bool) -> Dictionary:
	var scene := (ResourceLoader.load(row.states.do, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var world := viewport.get_node("PreviewWorld") as Node3D
	var group := Node3D.new()
	world.add_child(group)
	# These saved test scenes have a Node2D root. Reparent their 3D fixture roots
	# together, preserving every modifier-relative path and local transform.
	for child in scene.get_children():
		if child.name in ["ModifierHistory", "Receiver", "MH_LastSibling"]: child.reparent(group, false)
	scene.free()
	var source := group.get_node(row.source) as Skeleton3D
	group.position -= source.global_position
	var peer := group.get_node(row.peer) as Skeleton3D
	peer.visible = false
	peer.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	# Hide peer mesh ancestors too, while leaving the configured source visible.
	group.get_node("ModifierHistory/Peer").visible = false
	var observed: Skeleton3D = group.get_node(row.receiver) if row.op == "retarget_setup" else source
	if row.op == "retarget_setup":
		for mesh in source.find_children("*", "MeshInstance3D", true, false): mesh.visible = false
		observed.global_position = source.global_position + Vector3(0.6, 0, 0)
		group.position.x -= 0.3
	var modifiers: Array[SkeletonModifier3D] = []
	if row.op == "stack":
		for stage in row.stack: modifiers.append(group.get_node(stage.modifier))
	else: modifiers.append(group.get_node(row.modifier))
	for i in modifiers.size():
		modifiers[i].active = enabled
		modifiers[i].influence = float(row.get("last_influence", 1.0)) if i == modifiers.size() - 1 else 1.0
		if modifiers[i] is SpringBoneSimulator3D:
			modifiers[i].external_force = Vector3(0.7, 0, 0.4)
	source.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	observed.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var witness := Witness.new()
	source.add_child(witness)
	var rig := _overlay(observed, world)
	witness.modification_processed.connect(func(): _draw_rig(rig))
	var markers: Array = []
	for modifier in modifiers:
		if modifier is TwoBoneIK3D or modifier is LookAtModifier3D: markers.append(_sphere(world, 0.045, Color(1, 0.85, 0.2)))
		else: markers.append(null)
	return {"group": group, "source": source, "observed": observed, "modifiers": modifiers, "input": _poses(source), "rig": rig, "markers": markers}
func _step(view: Dictionary, time: float) -> void:
	var source: Skeleton3D = view.source
	_restore(source, view.input)
	for i in view.modifiers.size():
		var modifier: SkeletonModifier3D = view.modifiers[i]
		if modifier is TwoBoneIK3D:
			var start := source.global_transform * source.get_bone_global_pose(modifier.get_root_bone(0)).origin
			var end := source.global_transform * source.get_bone_global_pose(modifier.get_end_bone(0)).origin
			var side := (end - start).normalized().cross(Vector3.FORWARD).normalized()
			if side.length() < 0.1: side = Vector3.RIGHT
			var target := modifier.get_node(modifier.get_target_node(0)) as Node3D
			target.global_position = start + (end - start) * (0.72 + 0.08 * sin(time * TAU / 3)) + side * (end - start).length() * 0.16
			view.markers[i].global_position = target.global_position
		if modifier is LookAtModifier3D:
			var origin := source.global_transform * source.get_bone_global_pose(modifier.bone).origin
			if modifier.origin_from == LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE:
				var origin_node := modifier.get_node(modifier.origin_external_node) as Node3D
				origin_node.global_position = origin
			var target := modifier.get_node(modifier.target_node) as Node3D
			target.global_position = origin + source.global_basis * Vector3(0.5 * sin(time * TAU / 3), 0.2, 0.9)
			view.markers[i].global_position = target.global_position
		if modifier is BoneTwistDisperser3D:
			var end: int = modifier.get_end_bone(0)
			if not modifier.is_end_bone_extended(0): end = source.get_bone_parent(end)
			source.set_bone_pose_rotation(end, view.input[end].basis.get_rotation_quaternion() * Quaternion(Vector3.UP, 0.65 * sin(time * TAU / 3)))
		if modifier is SpringBoneSimulator3D:
			source.set_bone_pose_rotation(0, view.input[0].basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.12 * sin(time * TAU / 2)))
		if modifier is RetargetModifier3D:
			var bone := source.find_bone("B-upperArm.L")
			source.set_bone_pose_rotation(bone, view.input[bone].basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.6 * sin(time * TAU / 3)))
	source.advance(1.0 / 30)
	source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 27)
	heading.position = Vector2(24, 12)
	root.add_child(heading)
	for index in 2:
		var label := Label.new()
		label.text = "Authored input / modifier inactive" if index == 0 else "Godot AI configured output / native playback"
		label.position = Vector2(24 + index * 640, 60)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
	var viewports := [_view(0), _view(1)]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://rig_modifier_history.json"))
	for case_index in CASES.size():
		var matches: Array = manifest.cases.filter(func(row): return row.id == CASES[case_index])
		if matches.size() != 1:
			push_error("Required preview case missing: " + CASES[case_index])
			quit(1)
			return
		var row: Dictionary = matches[0]
		heading.text = TITLES[case_index] + " | Godot 4.7.2 | 30 FPS"
		views = [_load(row, viewports[0], false), _load(row, viewports[1], true)]
		await process_frame
		await process_frame
		for view in views:
			for modifier in view.modifiers:
				if modifier is SpringBoneSimulator3D:
					var source: Skeleton3D = view.source
					if modifier.get_child_count() > 0:
						var collider := modifier.get_child(0) as SpringBoneCollisionSphere3D
						var child: int = modifier.get_joint_bone(0, 1)
						var tail := source.global_transform * source.get_bone_global_pose(child).origin
						var start := source.global_transform * source.get_bone_global_pose(modifier.get_joint_bone(0, 0)).origin
						var side := (tail - start).normalized().cross(Vector3.FORWARD).normalized()
						if side.length() < 0.1: side = Vector3.UP
						collider.radius = source.get_bone_rest(child).origin.length() * 0.25
						collider.global_position = tail + side * (collider.radius + modifier.get_joint_radius(0, 0)) * 1.05
						modifier.external_force = side * 0.7
						_sphere(collider, collider.radius, Color(0.9, 0.45, 0.1))
					modifier.reset()
		for frame in 120:
			for view in views: _step(view, float(frame) / 30)
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png(output.path_join("%02d_%03d.png" % [case_index, frame]))
			if result != OK:
				push_error("Preview image save failed")
				quit(1)
				return
			await process_frame
		for view in views:
			view.group.free()
			for rod in view.rig.bones: rod.free()
			for axes in view.rig.axes:
				for rod in axes: rod.free()
			for marker in view.markers:
				if marker != null: marker.free()
		views.clear()
	print("MODIFIER_HISTORY_PREVIEW=" + JSON.stringify({"cases": CASES, "frames": 840, "fps": 30, "output": output, "comparison": "inactive authored input vs configured output; not prior-addon footage"}))
	quit()
