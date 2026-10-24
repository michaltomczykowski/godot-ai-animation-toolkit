## Controlled native regression on four actual public rig fixtures. Rebuilds
## only bone channels; the saved carrier/timeline remain independent inputs.
## Local scenes and private models are never release assets.
extends "res://tools/check_jump_quality.gd"
const Specs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2, "Expected actual public route JSON and fresh local evidence directory")
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	assert(route.cases.size() == 4, "Regression requires all four actual rigs")
	assert(not FileAccess.file_exists(args[1].path_join("regression.json")), "Preserve prior regression output")
	assert(DirAccess.make_dir_recursive_absolute(args[1]) == OK)
	var expected_ids := ["dummy", "xbot", "short", "zup_tall"]
	var seen: Array = []
	var rows: Array = []
	for original: Dictionary in route.cases:
		var row := original.duplicate(true)
		assert(original.id in expected_ids and not original.id in seen)
		seen.append(original.id)
		assert(FileAccess.get_sha256(original.scene) == original.scene_sha256, "Actual fixture source changed")
		var scene := (load(original.scene) as PackedScene).instantiate()
		for mixer in scene.find_children("*", "AnimationMixer", true, false):
			mixer.active = false
			mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for modifier in scene.find_children("*", "SkeletonModifier3D", true, false): modifier.active = false
		root.add_child(scene)
		var rig := scene.get_node(row.skeleton) as Skeleton3D
		rig.reset_bone_poses()
		rig.force_update_all_bone_transforms()
		var player := scene.get_node(row.player) as AnimationPlayer
		var old := player.get_animation(row.params.animation_name)
		var ctx := Specs.context_from_skeleton(rig, row.roles, float(row.write.capture_duration), 120.0, false, 0.85, row.write.spine_chain)
		ctx.config = Specs.jump_config(str(row.write.get("resolved_style", "responsive")))
		ctx.config.jump_height = float(row.write.height) / float(row.write.world_scale)
		ctx.config.jump_crouch = float(row.write.crouch) / float(row.write.world_scale)
		ctx.config.jump_distance = float(row.write.distance) / float(row.write.world_scale)
		ctx.world_scale = float(row.write.world_scale)
		ctx.root_motion = bool(row.params.root_motion)
		ctx.measured_arms = true
		for side in ["l","r"]:
			var arm := str(row.roles["arm_"+side])
			ctx.arm_down[side] = Specs.arm_lower_delta(Specs._rest_basis(ctx, arm), ctx.arm_directions[side], ctx.up, -1.0)
		var generated := Specs.jump_keys(ctx)
		assert(not generated.meta.has("reach_error"), str(generated.meta))
		var clip := old.duplicate(true) as Animation
		var animation_root := player.get_node(player.root_node)
		for index in range(clip.get_track_count()-1,-1,-1):
			var path := clip.track_get_path(index)
			if animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) == rig:
				clip.remove_track(index)
		var bone_path := str(animation_root.get_path_to(rig))
		for bone in generated.keys:
			if bone == "__root_motion__": continue
			var rest := rig.get_bone_rest(rig.find_bone(bone))
			for channel in ["rotation","position"]:
				if not generated.keys[bone].has(channel): continue
				var type := Animation.TYPE_ROTATION_3D if channel == "rotation" else Animation.TYPE_POSITION_3D
				var index := clip.add_track(type)
				clip.track_set_path(index,NodePath(bone_path+":"+bone))
				clip.track_set_interpolation_type(index,Animation.INTERPOLATION_LINEAR)
				for key in generated.keys[bone][channel]:
					var value: Variant = (rest.basis.get_rotation_quaternion()*(key.delta as Quaternion)).normalized() if channel == "rotation" else rest.origin+(key.delta as Vector3)
					clip.track_insert_key(index,key.time,value,1.0)
		var library := player.get_animation_library("")
		library.remove_animation(row.params.animation_name)
		library.add_animation(row.params.animation_name,clip)
		row.write.merge(preload("res://addons/godot_ai_animation/spec/motion_space.gd").world_metrics(generated.meta,ctx.world_scale),true)
		var path: String = args[1].path_join("controlled_"+str(row.id)+".tscn")
		var packed := PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,path)==OK)
		scene.free()
		row.scene = path
		row.scene_sha256 = FileAccess.get_sha256(path)
		for fps in [120]:
			for mode in ["player","tree"]:
				var result := _check(row,fps,mode)
				result.erase("trace")
				result["controlled_scene"] = row.scene
				result["controlled_scene_sha256"] = row.scene_sha256
				rows.append(result)
	var output := {"runs":rows,"engine_errors":logger.errors,"plan_sha256":FileAccess.get_sha256("res://addons/godot_ai_animation/spec/motion_jump_plan.gd")}
	output["scope"] = "Controlled native regeneration from four real public fixtures; not public-generation evidence"
	output["route_sha256"] = FileAccess.get_sha256(args[0])
	output["specs_sha256"] = FileAccess.get_sha256("res://addons/godot_ai_animation/spec/motion_specs.gd")
	output["checker_sha256"] = FileAccess.get_sha256("res://tools/check_jump_quality.gd")
	output["base_checker_sha256"] = FileAccess.get_sha256("res://tools/check_run_quality.gd")
	output["native_helper_sha256"] = FileAccess.get_sha256("res://tools/character_quality_native.gd")
	output["passed"] = rows.size() == 8 and logger.errors.is_empty()
	for result: Dictionary in rows:
		output.passed = output.passed and result.thresholds_pass and float(result.max_bone_speed_legs_per_s) <= 10.0
	FileAccess.open(args[1].path_join("regression.json"),FileAccess.WRITE).store_string(JSON.stringify(output))
	for row in rows:
		if row.fps == 120 and row.mixer == "player": print("SWEEP="+JSON.stringify({"id":row.id,"speed":row.max_bone_speed_legs_per_s,"failures":row.failures,"worst":row.get("worst_pose_step",{})}))
	OS.remove_logger(logger)
	quit(0 if output.passed else 1)

