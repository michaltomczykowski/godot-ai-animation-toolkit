extends RefCounted
## Observation/admission only. Never changes a saved pose, key, helper or graph.
static func digest(path: String) -> String:
	return FileAccess.get_sha256(path)
static func all_nodes(node: Node) -> Array[Node]:
	var nodes: Array[Node] = [node]
	var offset := 0
	while offset < nodes.size():
		for child in nodes[offset].get_children(true): nodes.append(child)
		offset += 1
	return nodes
static func admit(row: Dictionary, control: String = "") -> Array[String]:
	var errors: Array[String] = []
	if digest(row.scene) != row.scene_sha256: errors.append("Saved scene digest changed")
	var packed := load(row.scene) as PackedScene
	if packed == null: return ["Saved scene missing"]
	var scene := packed.instantiate()
	var player := scene.get_node_or_null(row.player) as AnimationPlayer
	var rig := scene.get_node_or_null(row.skeleton) as Skeleton3D
	if player == null or rig == null:
		scene.free()
		return ["Saved Player/Skeleton missing"]
	if control == "foreign_tree":
		var foreign := AnimationTree.new()
		foreign.active = true
		scene.add_child(foreign)
	if control == "active_modifier":
		var foreign := SkeletonModifier3D.new()
		foreign.active = true
		rig.add_child(foreign)
	if control == "wrong_root_track": player.root_motion_track = NodePath("Missing:position")
	for node in all_nodes(scene):
		var mixer := node as AnimationMixer
		if mixer != null and mixer != player and mixer.active: errors.append("Foreign active mixer before normalization")
	for node in all_nodes(scene):
		var modifier := node as SkeletonModifier3D
		if modifier == null or not modifier.active: continue
		var simulator := modifier as PhysicalBoneSimulator3D
		if simulator != null and modifier.get_parent() != null and not modifier.get_parent().get_children().has(modifier) and modifier.get_script() == null and modifier.get_child_count(true) == 0 and not simulator.is_simulating_physics(): continue
		errors.append("Active modifier before normalization")
	for role in row.roles:
		if rig.find_bone(row.roles[role]) < 0: errors.append("Saved bone role missing")
	if not player.has_animation(row.params.animation_name): errors.append("Saved clip missing")
	if bool(row.params.root_motion):
		var owner := player.get_node_or_null(player.root_node)
		var path := NodePath(player.root_motion_track.get_concatenated_names())
		if player.root_motion_track.is_empty() or owner == null or owner.get_node_or_null(path) == null: errors.append("Saved extraction binding missing")
	elif not player.root_motion_track.is_empty(): errors.append("Unextracted clip has extraction owner")
	scene.free()
	return errors
static func attach(v: Dictionary) -> void:
	v.capture_skin_count = 0
	v.capture_previous_skin = 0
	v.rig.skeleton_updated.connect(func(): v.capture_skin_count += 1)
static func frame(v: Dictionary) -> Dictionary:
	var camera: Camera3D = v.camera
	var nodes: Array = v.scene.find_children("*", "MeshInstance3D", true, false)
	for key in ["segments", "joints", "hand_shapes", "finger_segments"]:
		for item in v[key]: nodes.append(item.node)
	for item in v.diag.values():
		if item is MeshInstance3D: nodes.append(item)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var count := 0
	var clipped := 0
	var finite := true
	for item in nodes:
		var mesh := item as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var bounds := mesh.get_aabb()
		if mesh.skin != null or mesh.get_skin_reference() != null:
			if mesh.get_skin_reference() == null:
				push_error("Declared skin has no registered native skeleton")
				continue
			for shape in mesh.mesh.get_blend_shape_count():
				if not is_zero_approx(mesh.get_blend_shape_value(shape)):
					push_error("Bounds snapshot does not support nonzero blend shapes")
			var snapshot := mesh.bake_mesh_from_current_skeleton_pose()
			if snapshot == null:
				push_error("Actual skinned bounds snapshot missing")
				continue
			bounds = snapshot.get_aabb()
		for corner in 8:
			var point: Vector3 = mesh.global_transform * bounds.get_endpoint(corner)
			var depth := -(camera.global_transform.affine_inverse() * point).z
			if camera.is_position_behind(point) or depth < camera.near or depth > camera.far: clipped += 1
			var screen := camera.unproject_position(point)
			finite = finite and point.is_finite() and screen.is_finite()
			minimum = minimum.min(screen); maximum = maximum.max(screen)
			count += 1
	var fits := count > 0 and finite and clipped == 0 and minimum.x >= 8 and minimum.y >= 8 and maximum.x <= 944 and maximum.y <= 892
	var fresh: bool = v.capture_skin_count > v.capture_previous_skin
	var poses := {}
	for role in ["hips", "head", "hand_l", "hand_r", "foot_l", "foot_r"]:
		var pose: Transform3D = v.rig.global_transform * v.rig.get_bone_global_pose(v.indices[role])
		if not pose.origin.is_finite() or not pose.basis.is_finite(): push_error("Nonfinite capture pose")
		poses[role] = [pose.origin.x,pose.origin.y,pose.origin.z]
	var actor: Vector3 = v.body.global_position
	var delta: Vector3 = v.player.get_root_motion_position()
	var result := {"poses_world":poses,"actor_world":[actor.x,actor.y,actor.z],"root_delta_owner_parent":[delta.x,delta.y,delta.z],"points":count,"bounds":[minimum.x,minimum.y,maximum.x,maximum.y],"fits":fits,"depth_clipped":clipped,"skin_before":v.capture_previous_skin,"skin_after":v.capture_skin_count,"skin_fresh":fresh,"native_time":v.time}
	v.capture_previous_skin = v.capture_skin_count
	if not fits: push_error("Displayed character geometry is outside fixed panel margin")
	if not fresh: push_error("No fresh native skin update for accepted frame")
	if not v.player.active or v.player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL: push_error("Capture manual Player ownership changed")
	return result
