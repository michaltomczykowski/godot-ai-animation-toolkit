extends SceneTree

## Read saved modifier wiring and a simple live IK/look-at response.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("RIG_MODIFIER_RUNTIME_FAIL: scene and op required")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("RIG_MODIFIER_RUNTIME_FAIL: scene cannot load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var skeleton := fixture.get_node("Dummy/Skeleton3D") as Skeleton3D
	var modifiers: Array[SkeletonModifier3D] = []
	for child in skeleton.get_children():
		if child is SkeletonModifier3D:
			modifiers.append(child)
	var failures: Array[String] = []
	if modifiers.size() != 1:
		failures.append("expected exactly one modifier")
		print("RIG_MODIFIER_RUNTIME=" + JSON.stringify({"op": args[1], "failures": failures}))
		quit(1)
		return
	var modifier := modifiers[0]
	if modifier.active:
		failures.append("saved modifier should be inactive by request")
	var target_resolved := false
	var response := 0.0
	match args[1]:
		"spring_setup":
			var spring := modifier as SpringBoneSimulator3D
			if spring == null or spring.get_setting_count() != 1:
				failures.append("spring setting missing")
			else:
				var leaf := spring.get_root_bone_name(0) == spring.get_end_bone_name(0)
				if leaf:
					if not spring.is_end_bone_extended(0) or spring.get_end_bone_length(0) <= 0.0:
						failures.append("single leaf spring has no usable virtual tail")
				elif spring.get_root_bone_name(0) != "B-forearm.L" or spring.get_end_bone_name(0) != "B-hand.L":
					failures.append("saved spring chain names changed")
				var bone := skeleton.find_bone(spring.get_root_bone_name(0))
				var before := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
				var observed := {"max": 0.0, "count": 0}
				spring.modification_processed.connect(func() -> void:
					observed.count += 1
					observed.max = maxf(float(observed.max), before.angle_to(
						skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())))
				spring.external_force = Vector3(0.0, 0.0, 1.0) if leaf else Vector3(1.0, 0.0, 0.0)
				spring.active = true
				for _i in 24:
					skeleton.advance(1.0 / 60.0)
					await process_frame
				response = float(observed.max)
				if response < 0.001:
					failures.append("active spring did not move the root bone (processed %d times)" % int(observed.count))
		"ik_setup":
			var ik := modifier as TwoBoneIK3D
			if ik == null:
				failures.append("wrong IK class")
			else:
				var target := ik.get_node_or_null(ik.get_target_node(0)) as Node3D
				var pole := ik.get_node_or_null(ik.get_pole_node(0)) as Node3D
				target_resolved = target != null and pole != null
				if not target_resolved:
					failures.append("IK target or pole path does not resolve")
				else:
					var bone := skeleton.find_bone("B-upperArm.L")
					var before := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
					var observed := {"max": 0.0, "count": 0}
					ik.modification_processed.connect(func() -> void:
						observed.count += 1
						observed.max = maxf(float(observed.max), before.angle_to(
							skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())))
					target.global_position += Vector3(0.5, 0.3, 0.2)
					ik.active = true
					for _i in 6:
						skeleton.advance(0.1)
						await process_frame
					response = float(observed.max)
					if response < 0.001:
						failures.append("active IK did not move the arm (processed %d times)" % int(observed.count))
		"look_at_setup":
			var look := modifier as LookAtModifier3D
			if look == null:
				failures.append("wrong look-at class")
			else:
				var target := look.get_node_or_null(look.get_target_node()) as Node3D
				target_resolved = target != null
				if not target_resolved:
					failures.append("look-at target path does not resolve")
				else:
					var bone := skeleton.find_bone("B-head")
					var before := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
					var observed := {"max": 0.0, "count": 0}
					look.modification_processed.connect(func() -> void:
						observed.count += 1
						observed.max = maxf(float(observed.max), before.angle_to(
							skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion())))
					target.global_position += Vector3(0.4, 0.2, 0.4)
					look.active = true
					for _i in 6:
						skeleton.advance(0.1)
						await process_frame
					response = float(observed.max)
					if response < 0.001:
						failures.append("active look-at did not move the head (processed %d times)" % int(observed.count))
		"twist_setup":
			var twist := modifier as BoneTwistDisperser3D
			if twist == null or twist.get_setting_count() != 1:
				failures.append("twist setting missing")
			else:
				if twist.get_root_bone_name(0) != "B-hips" or twist.get_end_bone_name(0) != "B-chest":
					failures.append("twist chain names changed")
				var chest := skeleton.find_bone("B-chest")
				var spine := skeleton.find_bone("B-spine")
				var hips := skeleton.find_bone("B-hips")
				var axis := (skeleton.get_bone_global_rest(chest).origin -
					skeleton.get_bone_global_rest(spine).origin).normalized()
				var local_axis := (skeleton.get_bone_global_rest(spine).basis.inverse() * axis).normalized()
				skeleton.set_bone_pose_rotation(spine, Quaternion(local_axis, PI * 0.25))
				var before := skeleton.get_bone_global_pose(hips).basis.get_rotation_quaternion()
				var observed := {"max": 0.0, "count": 0}
				twist.modification_processed.connect(func() -> void:
					observed.count += 1
					observed.max = maxf(float(observed.max), before.angle_to(
						skeleton.get_bone_global_pose(hips).basis.get_rotation_quaternion())))
				twist.active = true
				for _i in 6:
					skeleton.advance(0.1)
					await process_frame
				response = float(observed.max)
				if response < 0.001:
					failures.append("active twist did not distribute to hips (processed %d times)" % int(observed.count))
		_:
			failures.append("unknown operation")
	print("RIG_MODIFIER_RUNTIME=" + JSON.stringify({"op": args[1],
		"modifier_class": modifier.get_class(), "target_resolved": target_resolved,
		"response": response, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
