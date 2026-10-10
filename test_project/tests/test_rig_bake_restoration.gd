@tool
extends McpTestSuite

## Actual public dispatcher; a native witness supplies the independent oracle.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const Sampler := preload("res://addons/godot_ai_animation/utils/pose_bake_sampler.gd")
class Witness extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void: pass
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: Capture.ErrorCapture
func suite_name() -> String: return "rig_bake_restoration"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "bake-restoration", "command": "custom_tool:animation_rig", "params": params})
func _own(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children(): _own(child, root)
func _fixture(label: String, spring: bool = false) -> Dictionary:
	var container := Node3D.new()
	container.name = label
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	container.add_child(skeleton)
	for i in (3 if spring else 1):
		skeleton.add_bone(["arm", "middle", "end"][i])
		if i > 0: skeleton.set_bone_parent(i, i - 1)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0, 0.5 if i > 0 else 0.0, 0))
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose(i, rest)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	container.add_child(player)
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, "Skeleton:arm")
	animation.track_insert_key(track, 0, Quaternion.IDENTITY)
	animation.track_insert_key(track, 1, Quaternion(Vector3.FORWARD, 0.2) if spring else Quaternion.IDENTITY)
	var library := AnimationLibrary.new()
	library.add_animation("input", animation)
	player.add_animation_library("", library)
	var root := EditorInterface.get_edited_scene_root()
	root.add_child(container)
	_own(container, root)
	return {"root": container, "skeleton": skeleton, "player": player, "animation": animation, "phase": 0}
func _params(f: Dictionary) -> Dictionary:
	return {"op": "bake_pose_sequence", "player_path": str(f.player.get_path()),
		"skeleton_path": str(f.skeleton.get_path()), "source_animation": "input",
		"animation_name": "baked", "duration": 0.2, "fps": 30}
func _history() -> UndoRedo:
	return _undo.get_history_undo_redo(_undo.get_object_history_id(EditorInterface.get_edited_scene_root()))
func test_fractional_final_influence() -> void:
	var f := _fixture("BakeFractional")
	var skeleton: Skeleton3D = f.skeleton
	var target := Node3D.new()
	target.name = "Target"
	target.position = Vector3(2, 0, 3)
	f.root.add_child(target)
	var look := LookAtModifier3D.new()
	look.name = "Look"
	skeleton.add_child(look)
	look.bone_name = "arm"
	look.target_node = look.get_path_to(target)
	look.use_secondary_rotation = false
	look.influence = 0.5
	look.active = true
	_own(f.root, EditorInterface.get_edited_scene_root())
	var witness := Witness.new()
	skeleton.add_child(witness)
	var measured := {"raw": Quaternion.IDENTITY, "final": Quaternion.IDENTITY}
	look.modification_processed.connect(func(): measured.raw = skeleton.get_bone_pose_rotation(0))
	witness.modification_processed.connect(func(): measured.final = skeleton.get_bone_pose_rotation(0))
	skeleton.advance(0)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	assert_true(measured.raw.angle_to(measured.final) > 0.1, "native oracle distinguishes raw and weighted pose")
	witness.free()
	var errors := _logger.errors.size()
	var result := _call(_params(f))
	assert_has_key(result, "data", "public bake succeeded")
	if result.has("data"):
		var baked: Animation = f.player.get_animation("baked")
		var track := baked.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
		assert_true(track >= 0, "rotation track present")
		if track >= 0:
			var actual: Quaternion = baked.track_get_key_value(track, 0)
			assert_true(actual.angle_to(measured.final) < 0.001, "bake keys the final native weighted pose")
		assert_true(_history().undo(), "undo baked clip")
	assert_eq(_logger.errors.size(), errors, "zero bake engine errors")
	f.root.free()
func _spring(f: Dictionary) -> SpringBoneSimulator3D:
	var spring := SpringBoneSimulator3D.new()
	f.skeleton.add_child(spring)
	spring.set_setting_count(1)
	spring.set_root_bone_name(0, "arm")
	spring.set_end_bone_name(0, "end")
	spring.set_stiffness(0, 0.2)
	spring.set_drag(0, 0.1)
	spring.set_gravity(0, 0.8)
	spring.set_individual_config(0, true)
	spring.mutable_bone_axes = false
	for i in spring.get_joint_count(0):
		spring.set_joint_stiffness(0, i, 0.2)
		spring.set_joint_drag(0, i, 0.1)
		spring.set_joint_gravity(0, i, 0.8)
	spring.external_force = Vector3(0.7, 0.2, 0.4)
	spring.active = true
	spring.reset()
	f.spring = spring
	return spring
func _trace(f: Dictionary, frames: int, fps: int) -> Array:
	var skeleton: Skeleton3D = f.skeleton
	var result: Array = []
	var capture := func():
		var poses: Array = []
		for i in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(i))
		result.append(poses)
	f.spring.modification_processed.connect(capture)
	for frame in frames:
		f.root.position = Vector3(0.4 * sin(float(f.phase) / fps * TAU), 0, 0)
		for i in skeleton.get_bone_count(): skeleton.set_bone_pose(i, skeleton.get_bone_rest(i))
		skeleton.set_bone_pose_rotation(0, Quaternion(Vector3.FORWARD, 0.35 * sin(float(f.phase) / fps * TAU)))
		f.phase += 1
		skeleton.advance(1.0 / fps)
		skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	f.spring.modification_processed.disconnect(capture)
	return result
func test_dry_bake_preserves_live_spring_momentum() -> void:
	for fps in [30, 60, 120]:
		var subject := _fixture("BakeMomentum", true)
		var control := _fixture("BakeMomentumControl", true)
		_spring(subject)
		_spring(control)
		var before := _trace(subject, fps / 4, fps)
		_trace(control, fps / 4, fps)
		assert_true(before[0][0].basis.get_rotation_quaternion().angle_to(before[-1][0].basis.get_rotation_quaternion()) > 0.01, "native excitation is effective")
		var version := _history().get_version()
		var errors := _logger.errors.size()
		var orphans := Node.get_orphan_node_ids()
		var result := _call(_params(subject).merged({"fps": fps, "dry_run": true}, true))
		assert_has_key(result, "data", "spring dry bake")
		assert_eq(_history().get_version(), version, "dry history unchanged")
		assert_eq(Node.get_orphan_node_ids(), orphans, "dry no orphan nodes")
		var actual := _trace(subject, 8, fps)
		var expected := _trace(control, 8, fps)
		assert_eq(actual.size(), 8, "all continued subject samples")
		assert_eq(expected.size(), 8, "all continued native samples")
		var worst := 0.0
		for frame in mini(actual.size(), expected.size()):
			for i in actual[frame].size():
				worst = maxf(worst, actual[frame][i].basis.get_rotation_quaternion().angle_to(expected[frame][i].basis.get_rotation_quaternion()))
		print("BAKE_MOMENTUM_CONTINUATION fps=%d max_rotation_error=%f" % [fps, worst])
		assert_true(worst < 0.001, "continued native spring momentum fps=%d error=%f" % [fps, worst])
		assert_eq(_logger.errors.size(), errors, "zero bake engine errors")
		subject.root.free()
		control.root.free()

func test_animated_target_and_short_final_interval() -> void:
	var subject := _fixture("BakeAnimatedTarget", true)
	var reference := _fixture("BakeAnimatedReference", true)
	for f in [subject, reference]:
		_spring(f)
		var target := Node3D.new()
		target.name = "Target"
		target.position = Vector3(2, 1, 3)
		f.root.add_child(target)
		var track: int = f.animation.add_track(Animation.TYPE_POSITION_3D)
		f.animation.track_set_path(track, "Target")
		f.animation.track_insert_key(track, 0, Vector3(2, 1, 3))
		f.animation.track_insert_key(track, 1, Vector3(3, 2, 4))
		_own(f.root, EditorInterface.get_edited_scene_root())
	var before: Transform3D = subject.root.get_node("Target").transform
	var result := _call(_params(subject).merged({"duration": 0.205}, true))
	assert_has_key(result, "data", "non-grid duration bake")
	if result.has("data"):
		var baked: Animation = subject.player.get_animation("baked")
		var witness := Witness.new()
		reference.skeleton.add_child(witness)
		var captured := {"poses": []}
		witness.modification_processed.connect(func():
			captured.poses.clear()
			for i in reference.skeleton.get_bone_count(): captured.poses.append(reference.skeleton.get_bone_pose_rotation(i)))
		reference.player.play("input")
		reference.player.advance(0)
		reference.spring.reset()
		var previous := 0.0
		for sample in 8:
			var time := minf(sample / 30.0, 0.205)
			if time > previous: reference.player.advance(time - previous)
			reference.skeleton.advance(time - previous)
			reference.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			for bone in reference.skeleton.get_bone_count():
				var index := baked.find_track("Skeleton:" + str(reference.skeleton.get_bone_name(bone)), Animation.TYPE_ROTATION_3D)
				var actual: Quaternion = baked.track_get_key_value(index, sample)
				var difference: Quaternion = actual.inverse() * captured.poses[bone]
				var error := 2.0 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w))
				assert_true(error < 0.001, "native final key sample=%d bone=%d error=%.6f actual=%s reference=%s" % [sample, bone, error, actual, captured.poses[bone]])
			previous = time
		assert_true(_history().undo(), "short bake undo")
	assert_eq(subject.root.get_node("Target").transform, before, "animated outside-rig property untouched")
	subject.root.free()
	reference.root.free()

func test_late_failure_frees_private_evaluation() -> void:
	var f := _fixture("BakeLateFailure")
	var orphans := Node.get_orphan_node_ids()
	var version := _history().get_version()
	var evaluator := Sampler.new()
	assert_has_key(evaluator.open(EditorInterface.get_edited_scene_root(), f.skeleton, f.player, "input"), "ok", "private evaluator opens")
	assert_has_key(evaluator.sample(0, 0), "poses", "first capture")
	evaluator._test_fail_at = 0.1
	var result := evaluator.sample(0.1, 0.1)
	assert_eq(result.get("error", {}).get("code"), "OPERATION_UNAVAILABLE", "late failure typed")
	assert_true(result.get("error", {}).get("message", "").contains("t=0.100000"), "late failure identifies sample")
	assert_eq(Node.get_orphan_node_ids(), orphans, "late failure frees all temporary nodes")
	assert_eq(_history().get_version(), version, "late failure history unchanged")
	f.root.free()
