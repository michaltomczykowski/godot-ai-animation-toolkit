@tool
extends McpTestSuite

const Graph := preload("res://tests/test_rig_bake_graph.gd")
const Saved := preload("res://tests/bake_saved_matrix.gd")
var helper := Graph.new()
class FinalPose extends SkeletonModifier3D:
	var value: Transform3D
	func _process_modification_with_delta(_delta: float) -> void: value = get_skeleton().get_bone_pose(0)
func suite_name() -> String: return "rig_bake_root_motion"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _fixture(label: String, graph: bool, local: bool, looping: bool) -> Dictionary:
	var f := helper._fixture(label, "blend1d")
	var root := EditorInterface.get_edited_scene_root()
	var parent := Node3D.new()
	parent.name = label + "Parent"
	parent.position = Vector3(3, 0, 2)
	parent.rotation.y = -0.3
	parent.scale = Vector3.ONE * 1.1
	root.add_child(parent)
	f.root.reparent(parent, false)
	f.root.position = Vector3(0.2, 0.1, 0.3)
	f.root.rotation.y = 0.7
	f.root.scale = Vector3.ONE * 1.2
	var target := Node3D.new()
	target.name = label + "Target"
	target.position = Vector3(3.2, 1.0, 4.0)
	root.add_child(target)
	var look := LookAtModifier3D.new()
	f.skeleton.add_child(look)
	look.bone_name = "arm"
	look.target_node = look.get_path_to(target)
	look.use_secondary_rotation = false
	look.influence = 0.5
	look.active = true
	var mixer: AnimationMixer = f.tree if graph else f.player
	f.tree.active = graph
	for name in f.player.get_animation_list():
		var clip: Animation = f.player.get_animation(name)
		clip.length = 0.25
		clip.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
		var rotation_track := clip.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
		clip.track_set_key_time(rotation_track, 1, 0.25)
		clip.track_set_key_value(rotation_track, 1, Quaternion(Vector3.UP, 0.4 if name == "input" else 0.7))
		for channel in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			var track := clip.add_track(channel)
			clip.track_set_path(track, "Skeleton:arm")
			clip.track_insert_key(track, 0, Vector3.ZERO if channel == Animation.TYPE_POSITION_3D else Vector3.ONE)
			clip.track_insert_key(track, 0.25, Vector3(0.4, 0, 0.2) if channel == Animation.TYPE_POSITION_3D else Vector3.ONE * 1.03)
	mixer.root_motion_track = "Skeleton:arm"
	mixer.root_motion_local = local
	f.parent = parent
	f.target = target
	f.mixer = mixer
	f.graph = graph
	f.scale_initial = f.root.scale
	f.scale_accum = Vector3.ONE
	helper.helper._own(parent, root)
	helper.helper._own(target, root)
	return f
func _begin(f: Dictionary) -> void:
	if f.graph: helper._begin(f)
	else:
		f.player.active = true
		f.player.play("input")
		f.player.advance(0)
func _delta(mixer: AnimationMixer) -> Dictionary:
	return {"p": mixer.get_root_motion_position(), "q": mixer.get_root_motion_rotation(), "s": mixer.get_root_motion_scale(), "a": mixer.get_root_motion_rotation_accumulator()}
func _consume(f: Dictionary, delta: Dictionary, local: bool) -> void:
	f.root.quaternion = (f.root.quaternion * delta.q).normalized()
	var frame: Quaternion = f.root.quaternion if local else delta.a.inverse() * f.root.quaternion
	f.root.position += frame * delta.p
	f.scale_accum += delta.s
	f.root.scale = f.scale_initial * f.scale_accum
func _public(f: Dictionary) -> Dictionary:
	return {"body": f.root.transform, "global": f.root.global_transform,
		"root_track": f.mixer.root_motion_track, "root_local": f.mixer.root_motion_local,
		"motion": _delta(f.mixer), "position_accumulator": f.mixer.get_root_motion_position_accumulator(), "scale_accumulator": f.mixer.get_root_motion_scale_accumulator(),
		"graph": helper._public(f.tree), "library": f.player.get_animation_library(""), "target": f.target.transform}
func _case(graph: bool, local: bool, looping: bool, mode: String, fps: int) -> void:
	var subject := _fixture("BakeRootSubject", graph, local, looping)
	var reference := _fixture("BakeRootReference", graph, local, looping)
	_begin(subject)
	subject.mixer.advance(0.03)
	var before := _public(subject)
	var initial: Transform3D = subject.root.transform
	var params := helper.helper._params(subject)
	params.merge({"root_motion_mode": mode, "root_motion_target_path": str(subject.root.get_path()), "duration": 0.605, "fps": fps, "scales": true}, true)
	if graph:
		params.erase("source_animation")
		params.merge({"source_tree_path": str(subject.tree.get_path()), "tree_parameters": subject.initial, "tree_events": subject.events}, true)
	var saved := Saved.begin(subject, params, "root_%s_%s_%s_%s_%d" % [mode, graph, local, looping, fps])
	var errors := helper.helper._logger.errors.size()
	var version := helper.helper._history().get_version()
	var dry := helper._call(params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", "root dry " + str(dry.get("error", {})))
	assert_eq(_public(subject), before, "dry source exact")
	assert_eq(helper.helper._history().get_version(), version, "dry history exact")
	var result := helper._call(params)
	assert_has_key(result, "data", "root write " + str(result.get("error", {})))
	if not result.has("data"):
		subject.parent.free()
		subject.target.free()
		reference.parent.free()
		reference.target.free()
		return
	assert_eq(_public(subject), before, "write source exact")
	assert_eq(result.data.player_path, dry.data.player_path, "root dry output path")
	var scene_root := EditorInterface.get_edited_scene_root()
	var source_output: AnimationPlayer = scene_root.get_node(NodePath(str(result.data.player_path).trim_prefix("/Main/")))
	var baked := source_output.get_animation("baked")
	# Independent native playback copy, with one writer and no source modifiers.
	var replay: Node3D = subject.parent.duplicate(0)
	for node in replay.find_children("*", "AnimationMixer", true, false): node.active = false
	for node in replay.find_children("*", "SkeletonModifier3D", true, false): node.active = false
	scene_root.add_child(replay)
	var played_body: Node3D = replay.get_node(NodePath(str(subject.root.name)))
	played_body.transform = initial
	var played_skeleton: Skeleton3D = played_body.get_node("Skeleton")
	var output: AnimationPlayer = played_body.get_node(NodePath(str(source_output.name)))
	output.active = true
	output.play("baked")
	output.advance(0)
	var witness := FinalPose.new()
	reference.skeleton.add_child(witness)
	_begin(reference)
	var previous := 0.0
	var cursor: int = reference.cursor if graph else 0
	var played_scale := played_body.scale
	var played_accum := Vector3.ONE
	var track := baked.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
	var worst_position := 0.0
	var worst_rotation := 0.0
	for i in baked.track_get_key_count(track):
		var time := baked.track_get_key_time(track, i)
		var delta: Dictionary = {"p": Vector3.ZERO, "q": Quaternion.IDENTITY, "s": Vector3.ZERO, "a": Quaternion.IDENTITY}
		if time > previous:
			if graph or reference.player.is_playing():
				reference.mixer.advance(time - previous)
				delta = _delta(reference.mixer)
		if graph:
			var changed := false
			while cursor < reference.events.size() and reference.events[cursor].time <= time + 0.00000001:
				var event: Dictionary = reference.events[cursor]
				reference.tree.set(event.path, helper._decode(event.value))
				cursor += 1
				changed = true
			if changed: reference.tree.advance(0)
		if mode != "pose_only": _consume(reference, delta, local)
		reference.skeleton.advance(time - previous)
		reference.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		if time > previous:
			output.advance(time - previous)
			if mode == "preserve":
				played_body.quaternion = (played_body.quaternion * output.get_root_motion_rotation()).normalized()
				played_body.position += played_body.quaternion * output.get_root_motion_position()
				played_accum += output.get_root_motion_scale()
				played_body.scale = played_scale * played_accum
		var expected: Transform3D = reference.root.transform
		worst_position = maxf(worst_position, played_body.position.distance_to(expected.origin))
		var difference := played_body.quaternion.inverse() * expected.basis.get_rotation_quaternion()
		worst_rotation = maxf(worst_rotation, 2 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w)))
		assert_true(played_body.scale.distance_to(expected.basis.get_scale()) < 0.0001, "native movement scale")
		assert_true(played_skeleton.get_bone_pose_position(0).distance_to(witness.value.origin) < 0.0001, "native final bone position")
		var bone_difference := played_skeleton.get_bone_pose_rotation(0).inverse() * witness.value.basis.get_rotation_quaternion()
		assert_true(2 * atan2(Vector3(bone_difference.x, bone_difference.y, bone_difference.z).length(), absf(bone_difference.w)) < 0.001, "native final weighted bone rotation")
		previous = time
	assert_true(worst_position < 0.0001, "native movement position error=%.6f" % worst_position)
	assert_true(worst_rotation < 0.001, "native movement rotation error=%.6f" % worst_rotation)
	assert_true(reference.root.position.distance_to(initial.origin) > 0.2 if mode != "pose_only" else reference.root.transform.is_equal_approx(initial), "movement is effective or explicitly omitted")
	assert_eq(result.data.travel_omitted, mode == "pose_only", "travel omission reported")
	assert_eq(helper.helper._history().get_version(), version + 1, "root one action")
	Saved.state(saved, source_output, "do")
	assert_true(helper.helper._history().undo(), "root undo")
	Saved.state(saved, source_output, "undo")
	assert_false(source_output.is_inside_tree(), "undo removes output and carrier")
	assert_eq(_public(subject), before, "undo source exact")
	assert_true(helper.helper._history().redo(), "root redo")
	Saved.state(saved, source_output, "redo")
	Saved.finish(saved)
	assert_true(source_output.is_inside_tree(), "redo restores output")
	assert_eq(_public(subject), before, "redo source exact")
	assert_true(helper.helper._history().undo(), "root final undo")
	assert_eq(helper.helper._logger.errors.size(), errors, "zero root bake engine errors")
	print("BAKE_ROOT_CASE mode=%s graph=%s local=%s looping=%s fps=%d position_error=%.9f rotation_error=%.9f" % [mode, graph, local, looping, fps, worst_position, worst_rotation])
	replay.free()
	subject.parent.free()
	subject.target.free()
	reference.parent.free()
	reference.target.free()
func _matrix(mode: String) -> void:
	for fps in [30, 60, 120]:
		for graph in [false, true]:
			for local in [false, true]:
				for looping in [false, true]: _case(graph, local, looping, mode, fps)
func test_preserve() -> void: _matrix("preserve")
func test_pose_only() -> void: _matrix("pose_only")
func test_apply() -> void: _matrix("apply")

func test_explicit_output_carrier_history() -> void:
	var f := _fixture("BakeExplicitRoot", true, true, true)
	_begin(f)
	var output := AnimationPlayer.new()
	output.name = "ExplicitOutput"
	output.active = false
	output.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.root.add_child(output)
	helper.helper._own(f.parent, EditorInterface.get_edited_scene_root())
	var params := helper.helper._params(f)
	params.erase("source_animation")
	params.merge({"source_tree_path": str(f.tree.get_path()), "tree_parameters": f.initial,
		"output_player_path": str(output.get_path()), "root_motion_mode": "preserve",
		"root_motion_target_path": str(f.root.get_path())}, true)
	var state := _public(f)
	var orphans := Node.get_orphan_node_ids()
	var errors := helper.helper._logger.errors.size()
	var version := helper.helper._history().get_version()
	var result := helper._call(params)
	assert_has_key(result, "data", "explicit preserved write " + str(result.get("error", {})))
	if result.has("data"):
		var carrier: Skeleton3D = output.get_node("RootMotionCarrier")
		var clip := output.get_animation("baked")
		assert_eq(output.get_children().size(), 1, "one carrier")
		assert_eq(helper.helper._history().get_version(), version + 1, "explicit output one action")
		assert_eq(_public(f), state, "explicit write source exact")
		assert_true(helper.helper._history().undo(), "explicit undo")
		assert_false(output.has_animation_library(""), "undo removes new library")
		assert_false(carrier.is_inside_tree(), "undo removes carrier")
		assert_eq(output.root_motion_track, NodePath(), "undo restores extraction")
		assert_true(helper.helper._history().redo(), "explicit redo")
		assert_true(output.get_animation("baked") == clip, "redo clip identity")
		assert_true(carrier.is_inside_tree(), "redo carrier")
		var overwrite := helper._call(params.merged({"overwrite": true}, true))
		assert_has_key(overwrite, "data", "overwrite preserved clip")
		assert_eq(output.get_children().size(), 1, "overwrite reuses compatible carrier")
		assert_true(helper.helper._history().undo(), "overwrite undo")
		assert_true(output.get_animation("baked") == clip, "overwrite restores exact prior clip")
		var expected_orphans := Node.get_orphan_node_ids()
		var pending: Array[Node] = [carrier]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			expected_orphans.append(node.get_instance_id())
			pending.append_array(node.get_children(true))
		assert_true(helper.helper._history().undo(), "explicit final undo")
		expected_orphans.sort()
		var actual_orphans := Node.get_orphan_node_ids()
		actual_orphans.sort()
		assert_eq(actual_orphans, expected_orphans, "only history-owned carrier hierarchy retained")
		assert_eq(_public(f), state, "all history source exact")
	assert_eq(helper.helper._logger.errors.size(), errors, "zero explicit output errors")
	f.parent.free()
	f.target.free()

func test_root_preflight_is_atomic() -> void:
	var f := _fixture("BakeRootRefusals", true, true, true)
	_begin(f)
	var params := helper.helper._params(f)
	params.erase("source_animation")
	params.source_tree_path = str(f.tree.get_path())
	var state := _public(f)
	var version := helper.helper._history().get_version()
	var orphans := Node.get_orphan_node_ids()
	var errors := helper.helper._logger.errors.size()
	for invalid in [{}, {"root_motion_mode": "wrong"}, {"root_motion_mode": false},
		{"root_motion_mode": "apply", "root_motion_target_path": str(f.target.get_path())},
		{"root_motion_mode": "preserve", "root_motion_target_path": "missing"}]:
		var result := helper._call(params.merged(invalid, true))
		assert_has_key(result.get("error", {}), "code", "typed root refusal")
		assert_eq(_public(f), state, "root refused source exact")
		assert_eq(helper.helper._history().get_version(), version, "root refused history exact")
		assert_eq(Node.get_orphan_node_ids(), orphans, "root refused no orphan nodes")
	assert_eq(helper.helper._logger.errors.size(), errors, "zero root preflight errors")
	f.parent.free()
	f.target.free()
