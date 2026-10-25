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
static func admit(row: Dictionary, control: String = "", diagnostics: Dictionary = {}) -> Array[String]:
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
	if control in ["inert_player", "assigned_player", "autoplay_player", "playing_player"]:
		var foreign := AnimationPlayer.new()
		foreign.name = "AdmissionControlPlayer"
		foreign.active = true
		scene.add_child(foreign)
		if control != "inert_player":
			for library_name in player.get_animation_library_list(): foreign.add_animation_library(library_name,player.get_animation_library(library_name))
			if control == "assigned_player": foreign.assigned_animation = row.params.animation_name
			if control == "autoplay_player": foreign.autoplay = row.params.animation_name
			if control == "playing_player": foreign.play(row.params.animation_name)
	if control == "wrong_root_track": player.root_motion_track = NodePath("Missing:position")
	diagnostics["mixers"] = []
	for node in all_nodes(scene):
		var mixer := node as AnimationMixer
		if mixer == null: continue
		var other_player := mixer as AnimationPlayer
		var state := {"path":str(scene.get_path_to(mixer)),"class":mixer.get_class(),"active":mixer.active,"selected":mixer==player,"scripted":mixer.get_script()!=null,"root_node":str(mixer.root_node)}
		if other_player != null:
			state.merge({"assigned":str(other_player.assigned_animation),"autoplay":str(other_player.autoplay),"playing":other_player.is_playing(),"animations":Array(other_player.get_animation_list())})
		var inert := other_player != null and mixer.get_script() == null and other_player.assigned_animation.is_empty() and other_player.autoplay.is_empty() and not other_player.is_playing()
		state["inert_unassigned_native_player"] = inert
		diagnostics.mixers.append(state)
		if mixer != player and mixer.active and not inert: errors.append("Foreign active mixer before normalization")
	for node in all_nodes(scene):
		var modifier := node as SkeletonModifier3D
		if modifier == null or not modifier.active: continue
		var simulator := modifier as PhysicalBoneSimulator3D
		if simulator != null and modifier.get_parent() != null and not modifier.get_parent().get_children().has(modifier) and modifier.get_script() == null and modifier.get_child_count(true) == 0 and not simulator.is_simulating_physics(): continue
		errors.append("Active modifier before normalization")
	for role in row.roles:
		if rig.find_bone(row.roles[role]) < 0: errors.append("Saved bone role missing")
	var clip := player.get_animation(row.params.animation_name) if player.has_animation(row.params.animation_name) else null
	if clip == null: errors.append("Saved clip missing")
	var owner := player.get_node_or_null(player.root_node)
	if control == "dormant_binding" and owner != null:
		var carrier := Node3D.new()
		carrier.name = "AdmissionDormantCarrier"
		owner.add_child(carrier)
		player.root_motion_track = NodePath("AdmissionDormantCarrier:position")
	if control == "selected_track_binding" and clip != null and not bool(row.params.root_motion):
		for index in clip.get_track_count():
			if clip.track_is_enabled(index) and clip.track_get_type(index) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				player.root_motion_track = clip.track_get_path(index)
				break
	var root_path := player.root_motion_track
	var resolved := root_path.is_empty() or (owner != null and owner.get_node_or_null(NodePath(root_path.get_concatenated_names())) != null)
	var matching: Array = []
	var enabled := 0
	var keyed := 0
	if clip != null and not root_path.is_empty():
		for index in clip.get_track_count():
			if clip.track_get_path(index) == root_path and clip.track_get_type(index) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				matching.append({"index":index,"type":clip.track_get_type(index),"path":str(clip.track_get_path(index)),"enabled":clip.track_is_enabled(index),"keys":clip.track_get_key_count(index)})
				if clip.track_is_enabled(index):
					enabled += 1
					if clip.track_get_key_count(index) > 0: keyed += 1
	diagnostics["root_binding"] = {"property":str(root_path),"node_resolved":resolved,"matching_tracks":matching,"enabled_matches":enabled,"enabled_keyed_matches":keyed,"requested_extraction":bool(row.params.root_motion)}
	if not resolved: errors.append("Saved root-motion property node does not resolve")
	if bool(row.params.root_motion):
		if root_path.is_empty() or keyed == 0: errors.append("Extracted clip lacks an enabled selected root track")
	elif enabled > 0: errors.append("Unextracted clip has an enabled selected root track")
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
			for shape in mesh.get_blend_shape_count():
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

