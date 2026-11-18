extends RefCounted

## Independently configure native nodes from requests. No toolkit/test imports,
## and no copying the saved modifier's numeric settings into the reference.
static func replace(row: Dictionary, source: Skeleton3D, old: SkeletonModifier3D, class_override: String = "") -> SkeletonModifier3D:
	var p: Dictionary = row.params
	var links := {}
	if old is IKModifier3D:
		links.target = old.get_node(old.get_path_3d(0) if old is SplineIK3D else old.get_target_node(0))
		if old is TwoBoneIK3D: links.pole = old.get_node(old.get_pole_node(0))
	if old is LookAtModifier3D:
		links.target = old.get_node(old.target_node)
		if p.get("origin_from", "self") == "external_node": links.origin = old.get_node(old.origin_external_node)
	if old is SpringBoneSimulator3D:
		links.centers = []
		for i in p.springs.size():
			var path: NodePath = old.get_center_node(i)
			links.centers.append(old.get_node_or_null(path) if not path.is_empty() else null)
	var children := old.get_children()
	var child_poses := {}
	for child in children:
		if child is Skeleton3D:
			var poses: Array = []
			for b in child.get_bone_count(): poses.append(child.get_bone_pose(b))
			child_poses[child] = poses
	var native: SkeletonModifier3D = ClassDB.instantiate(old.get_class() if class_override.is_empty() else class_override)
	var name_before := old.name
	old.name = "ReplacedNativeSource"
	native.name = name_before
	native.active = false
	var index := old.get_index()
	source.add_child(native)
	source.move_child(native, index)
	for child in children: child.reparent(native, true)
	source.remove_child(old)
	match row.op:
		"ik_setup":
			native.set_setting_count(1)
			native.set_root_bone_name(0, p.chain[0])
			if native is TwoBoneIK3D:
				native.set_middle_bone_name(0, p.chain[1])
				if p.get("use_virtual_end", false):
					native.set_use_virtual_end(0, true)
					native.set_extend_end_bone(0, true)
					native.set_end_bone_length(0, float(p.get("end_bone_length", 0.1)))
				else: native.set_end_bone_name(0, p.chain[2])
				native.set_pole_node(0, native.get_path_to(links.pole))
				if not p.has("pole_path"):
					var middle := source.get_bone_global_rest(source.find_bone(p.chain[1]))
					var pole_direction: Vector3 = (middle.basis.inverse() * (source.global_transform.affine_inverse() * links.pole.global_position - middle.origin)).normalized()
					native.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
					native.set_pole_direction_vector(0, pole_direction)
			else: native.set_end_bone_name(0, p.chain[-1])
			if native is SplineIK3D: native.set_path_3d(0, native.get_path_to(links.target))
			else: native.set_target_node(0, native.get_path_to(links.target))
		"look_at_setup":
			native.bone_name = p.bone
			native.target_node = native.get_path_to(links.target)
			native.forward_axis = {"+x": SkeletonModifier3D.BONE_AXIS_PLUS_X, "-x": SkeletonModifier3D.BONE_AXIS_MINUS_X, "+y": SkeletonModifier3D.BONE_AXIS_PLUS_Y, "-y": SkeletonModifier3D.BONE_AXIS_MINUS_Y, "+z": SkeletonModifier3D.BONE_AXIS_PLUS_Z, "-z": SkeletonModifier3D.BONE_AXIS_MINUS_Z}[p.get("forward_axis", "+z")]
			native.primary_rotation_axis = {"x": 0, "y": 1, "z": 2}[p.get("primary_axis", "y")]
			native.origin_from = {"self": LookAtModifier3D.ORIGIN_FROM_SELF, "bone": LookAtModifier3D.ORIGIN_FROM_SPECIFIC_BONE, "external_node": LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE}[p.get("origin_from", "self")]
			if p.has("origin_bone"): native.origin_bone_name = p.origin_bone
			if links.has("origin"): native.origin_external_node = native.get_path_to(links.origin)
			native.use_secondary_rotation = bool(p.get("use_secondary_rotation", false))
			native.use_angle_limitation = bool(p.get("use_angle_limitation", false))
			if p.has("primary_limit_angle"): native.primary_limit_angle = deg_to_rad(float(p.primary_limit_angle))
			if p.has("secondary_limit_angle"): native.secondary_limit_angle = deg_to_rad(float(p.secondary_limit_angle))
			native.relative = bool(p.get("relative", false))
			native.duration = float(p.get("duration", 0.0))
		"twist_setup":
			var spec: Dictionary = p.disperse
			native.set_setting_count(1)
			var names: Array = p.get("spine_chain", [])
			var first: String = spec.get("root_bone", names[0] if not names.is_empty() else "")
			var last: String = spec.get("end_bone", names[-1] if not names.is_empty() else "")
			native.set_root_bone_name(0, first)
			native.set_end_bone_name(0, last)
			var count := 1
			var bone := source.find_bone(last)
			while bone >= 0 and source.get_bone_name(bone) != first:
				count += 1
				bone = source.get_bone_parent(bone)
			native.set_extend_end_bone(0, bool(spec.get("extend_end_bone", count < 3)))
			native.set_disperse_mode(0, BoneTwistDisperser3D.DISPERSE_MODE_EVEN if spec.get("mode", "even") == "even" else BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED)
			if spec.has("weight_position"): native.set_weight_position(0, clampf(float(spec.weight_position), 0, 1))
			native.set_twist_from_rest(0, bool(spec.get("twist_from_rest", true)))
			if spec.has("twist_from"):
				var q: Dictionary = spec.twist_from
				native.set_twist_from(0, Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))))
			if p.has("mutable_bone_axes"): native.mutable_bone_axes = bool(p.mutable_bone_axes)
			native.influence = clampf(float(p.get("influence", 1.0)), 0, 1)
		"spring_setup":
			native.set_setting_count(p.springs.size())
			if p.has("mutable_bone_axes"): native.mutable_bone_axes = bool(p.mutable_bone_axes)
			for i in p.springs.size():
				var spec: Dictionary = p.springs[i]
				native.set_root_bone_name(i, spec.root_bone)
				native.set_end_bone_name(i, spec.end_bone)
				for field in ["stiffness", "drag", "gravity", "radius"]:
					if spec.has(field): native.call("set_" + field, i, float(spec[field]))
				native.set_center_from(i, {"world_origin": SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN, "node": SpringBoneSimulator3D.CENTER_FROM_NODE, "bone": SpringBoneSimulator3D.CENTER_FROM_BONE}[spec.get("center_from", "world_origin")])
				if spec.has("center_bone"): native.set_center_bone_name(i, spec.center_bone)
				if links.centers[i] != null: native.set_center_node(i, native.get_path_to(links.centers[i]))
				native.set_enable_all_child_collisions(i, bool(spec.get("enable_all_child_collisions", true)))
				for selector in ["collisions", "exclude_collisions"]:
					var selected: Array = spec.get(selector, [])
					var prefix := "exclude_collision" if selector == "exclude_collisions" else "collision"
					native.call("set_" + prefix + "_count", i, selected.size())
					for c in selected.size():
						# Collider reparenting uses caller names plus a numeric suffix.
						var basename := str(selected[c]).get_file()
						var occurrence := 0
						for preceding in selected.slice(0, c):
							if str(preceding).get_file() == basename: occurrence += 1
						var collider_name := basename if occurrence == 0 else basename + str(occurrence + 1)
						if selector == "exclude_collisions" and basename == "Collider" and children.size() == 2: collider_name = "Collider2"
						native.call("set_" + prefix + "_path", i, c, NodePath(collider_name))
			native.reset()
		"retarget_setup":
			var target: Skeleton3D = children.filter(func(child): return child is Skeleton3D)[0]
			var profile := SkeletonProfile.new()
			var names: Array[String] = []
			for b in source.get_bone_count():
				if target.find_bone(source.get_bone_name(b)) >= 0: names.append(source.get_bone_name(b))
			profile.set_bone_size(names.size())
			for i in names.size():
				profile.set_bone_name(i, names[i])
				var parent := source.get_bone_parent(source.find_bone(names[i]))
				if parent >= 0 and names.has(source.get_bone_name(parent)): profile.set_bone_parent(i, source.get_bone_name(parent))
			native.profile = profile
			var flags := 0
			if p.get("position", false): flags |= RetargetModifier3D.TRANSFORM_FLAG_POSITION
			if p.get("rotation", true): flags |= RetargetModifier3D.TRANSFORM_FLAG_ROTATION
			if p.get("scale", false): flags |= RetargetModifier3D.TRANSFORM_FLAG_SCALE
			native.set_enable_flags(flags)
			native.use_global_pose = bool(p.get("use_global_pose", false))
	for child in child_poses:
		for i in child_poses[child].size(): child.set_bone_pose(i, child_poses[child][i])
	native.set_meta("native_authored_children", child_poses)
	native.active = bool(p.get("active", false))
	old.free()
	return native

static func finish(modifier: SkeletonModifier3D) -> void:
	# Author the native reference's child inputs after the engine's deferred
	# cache refresh. This is independent of the toolkit's serialized helper.
	var poses: Dictionary = modifier.get_meta("native_authored_children", {})
	for child in poses:
		for i in poses[child].size(): child.set_bone_pose(i, poses[child][i])
	modifier.remove_meta("native_authored_children")
