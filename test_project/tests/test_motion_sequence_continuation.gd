@tool
extends McpTestSuite
const Matrix := preload("res://tests/test_motion_sequence_history.gd")
const Capture := preload("res://tests/test_rig_bake_continuation.gd")
var helper := Matrix.new()
func suite_name() -> String: return "motion_sequence_continuation"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _fixture(name: String, tree_driven: bool, group: String) -> Dictionary:
	var f := helper._fixture()
	f.name = name
	helper._prepare_inputs(f, group, "single" if group == "secondary" else "partial")
	var rig := f.get_node("Character/Skeleton") as Skeleton3D
	rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var controller := f.get_node("Playback/OtherPlayer") as AnimationPlayer
	var destination := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	controller.get_animation_library("source").remove_animation("input")
	controller.get_animation_library("source").add_animation("input", destination.get_animation("source/input").duplicate(true))
	controller.speed_scale = 1.0
	controller.active = true
	controller.playback_auto_capture = false
	var result := {"root": f, "rig": rig, "controller": controller, "phase": 0}
	if tree_driven:
		var tree := AnimationTree.new()
		tree.name = "SourceTree"
		f.add_child(tree)
		tree.anim_player = tree.get_path_to(controller)
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var graph := AnimationNodeStateMachine.new()
		for state in ["Idle", "Action"]:
			var clip := AnimationNodeAnimation.new()
			clip.animation = "source/input"
			graph.add_node(state, clip)
		var transition := AnimationNodeStateMachineTransition.new()
		transition.xfade_time = 0.3
		graph.add_transition("Idle", "Action", transition)
		tree.tree_root = graph
		tree.active = true
		tree.get("parameters/playback").start("Idle")
		tree.advance(0.03)
		tree.get("parameters/playback").travel("Action")
		result.tree = tree
	else:
		controller.play("source/input")
		controller.advance(0)
	var spring := SpringBoneSimulator3D.new()
	rig.add_child(spring)
	spring.set_setting_count(1)
	spring.set_root_bone_name(0, "arm_L")
	spring.set_end_bone_name(0, "hand_L")
	spring.set_stiffness(0, 0.2)
	spring.set_drag(0, 0.1)
	spring.set_gravity(0, 0.8)
	spring.external_force = Vector3(0.7, 0.2, 0.4)
	spring.active = true
	spring.reset()
	var witness := Capture.FinalPose.new()
	rig.add_child(witness)
	result.witness = witness
	return result
func _trace(f: Dictionary, fps: int) -> Array:
	var samples: Array = []
	for frame in 8:
		f.root.position.x = 0.3 * sin(float(f.phase) / fps * TAU)
		f.phase += 1
		if f.has("tree"): f.tree.advance(1.0 / fps)
		else: f.controller.advance(1.0 / fps)
		f.rig.advance(1.0 / fps)
		f.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		samples.append(f.witness.poses.duplicate(true))
	return samples
func _compare(subject: Dictionary, control: Dictionary, fps: int, label: String) -> void:
	var a := _trace(subject, fps)
	var b := _trace(control, fps)
	var worst := 0.0
	assert_eq(a.size(), 8, label + " eight samples")
	for frame in 8:
		assert_eq(a[frame].size(), subject.rig.get_bone_count(), label + " all bones captured")
		for bone in subject.rig.get_bone_count():
			var x: Transform3D = a[frame][bone]
			var y: Transform3D = b[frame][bone]
			var q := x.basis.get_rotation_quaternion().inverse() * y.basis.get_rotation_quaternion()
			worst = maxf(worst, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
			assert_true(x.origin.distance_to(y.origin) < 0.0001 and x.basis.get_scale().distance_to(y.basis.get_scale()) < 0.0001, label + " position/scale continued")
	assert_true(worst < 0.001, label + " rotation continued " + str(worst))
func _case(group: String, tree_driven: bool, fps: int) -> void:
	var subject := _fixture("MotionContinuedSubject", tree_driven, group)
	var control := _fixture("MotionContinuedControl", tree_driven, group)
	var label := "%s tree=%s fps=%d" % [group, tree_driven, fps]
	var errors := helper._logger.errors.size()
	var variant := "walk_cycle" if group == "motion" else "single" if group == "secondary" else "partial"
	var params := helper._case_params(subject.root, group, variant, "local", fps)
	var family := "animation_sequence" if group == "sequence" else "animation_motion"
	_compare(subject, control, fps, label + " warm")
	assert_has_key(helper._call(family, params.merged({"dry_run": true}, true)), "data", label + " dry")
	_compare(subject, control, fps, label + " dry")
	var made := helper._call(family, params)
	assert_has_key(made, "data", label + " write " + str(made))
	_compare(subject, control, fps, label + " write")
	assert_has_key(helper._call(family, params.merged({"player_path": "/Missing"}, true)).get("error", {}), "code", label + " refusal")
	_compare(subject, control, fps, label + " refused")
	if made.has("data"):
		var history: UndoRedo = helper._undo.get_history_undo_redo(helper._undo.get_object_history_id(EditorInterface.get_edited_scene_root()))
		assert_true(history.undo(), label + " undo")
		_compare(subject, control, fps, label + " undo")
		assert_true(history.redo(), label + " redo")
		_compare(subject, control, fps, label + " redo")
	assert_eq(helper._logger.errors.size(), errors, label + " zero engine errors")
	subject.root.free()
	control.root.free()
func test_clip_spring_continuation() -> void:
	for group in ["motion", "secondary", "sequence"]:
		for fps in [30, 60, 120]: _case(group, false, fps)
func test_tree_spring_continuation() -> void:
	for group in ["motion", "secondary", "sequence"]:
		for fps in [30, 60, 120]: _case(group, true, fps)
