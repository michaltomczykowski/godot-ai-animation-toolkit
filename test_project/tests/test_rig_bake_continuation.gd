@tool
extends McpTestSuite

const Graph := preload("res://tests/test_rig_bake_graph.gd")
var helper := Graph.new()
class FinalPose extends SkeletonModifier3D:
	var poses: Array = []
	func _process_modification_with_delta(_delta: float) -> void:
		poses.clear()
		for i in get_skeleton().get_bone_count(): poses.append(get_skeleton().get_bone_pose(i))
func suite_name() -> String: return "rig_bake_continuation"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _fixture(name: String, kind: String) -> Dictionary:
	var f := helper._fixture(name, "state" if kind == "clip" else kind)
	for i in [1, 2]:
		f.skeleton.add_bone("middle" if i == 1 else "end")
		f.skeleton.set_bone_parent(i, i - 1)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		f.skeleton.set_bone_rest(i, rest)
		f.skeleton.set_bone_pose(i, rest)
	helper.helper._spring(f)
	if kind == "clip":
		f.tree.free()
		f.erase("tree")
		f.player.play("input")
		f.player.advance(0)
	else:
		helper._begin(f)
		if kind == "state":
			f.tree.advance(0.04)
			f.tree.get("parameters/playback").travel("Action")
			f.tree.advance(0.02)
			f.tree.get("parameters/playback").travel("Idle")
		elif kind == "state_inactive": f.tree.active = false
	var witness := FinalPose.new()
	f.skeleton.add_child(witness)
	f.witness = witness
	f.phase = 0
	return f
func _trace(f: Dictionary, fps: int) -> Array:
	var values: Array = []
	for frame in 8:
		f.root.position.x = 0.3 * sin(float(f.phase) / fps * TAU)
		f.phase += 1
		if f.has("tree"):
			if f.tree.active: f.tree.advance(1.0 / fps)
		elif f.player.is_playing(): f.player.advance(1.0 / fps)
		f.skeleton.advance(1.0 / fps)
		f.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		values.append(f.witness.poses.duplicate(true))
	return values
func _compare(subject: Dictionary, control: Dictionary, fps: int, label: String) -> void:
	var a := _trace(subject, fps)
	var b := _trace(control, fps)
	assert_eq(a.size(), 8, label + " eight continued samples")
	var worst := 0.0
	for frame in 8:
		assert_eq(a[frame].size(), 3, label + " all continued bones")
		for bone in 3:
			var x: Transform3D = a[frame][bone]
			var y: Transform3D = b[frame][bone]
			var q := x.basis.get_rotation_quaternion().inverse() * y.basis.get_rotation_quaternion()
			worst = maxf(worst, 2 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
			assert_true(x.origin.distance_to(y.origin) < 0.0001 and x.basis.get_scale().distance_to(y.basis.get_scale()) < 0.0001, label + " continued position/scale")
	assert_true(worst < 0.001, label + " continued spring/graph rotation error=" + str(worst))
	print("BAKE_CONTINUATION kind=%s fps=%d phase=%s rotation_error=%.9f" % [subject.kind, fps, label, worst])
func _case(kind: String, fps: int) -> void:
	var subject := _fixture("BakeContinuedSubject", kind)
	var control := _fixture("BakeContinuedControl", kind)
	subject.kind = kind
	_compare(subject, control, fps, "warmup")
	var errors := helper.helper._logger.errors.size()
	var params := helper.helper._params(subject).merged({"duration": 0.205, "fps": fps}, true)
	if subject.has("tree"):
		params.erase("source_animation")
		params.merge({"source_tree_path": str(subject.tree.get_path()), "tree_parameters": subject.initial, "tree_starts": subject.starts, "tree_events": subject.events}, true)
	# The witness itself is a scripted modifier; it is an oracle on the live
	# fixtures and must be removed while the public baker validates native stacks.
	subject.witness.active = false
	var dry := helper._call(params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", kind + " continued dry " + str(dry.get("error", {})))
	subject.witness.active = true
	_compare(subject, control, fps, "dry")
	subject.witness.active = false
	var written := helper._call(params)
	assert_has_key(written, "data", kind + " continued write " + str(written.get("error", {})))
	subject.witness.active = true
	_compare(subject, control, fps, "write")
	if written.has("data"):
		# Automatic storage uses a fresh name each time; explicitly select the
		# first destination to test an overwrite refusal before sampling.
		var refused := helper._call(params.merged({"output_player_path": written.data.player_path}, true)) if subject.has("tree") else helper._call(params)
		assert_has_key(refused.get("error", {}), "code", kind + " overwrite refusal")
		_compare(subject, control, fps, "refusal")
		assert_true(helper.helper._history().undo(), kind + " continued Undo")
		_compare(subject, control, fps, "undo")
		assert_true(helper.helper._history().redo(), kind + " continued Redo")
		_compare(subject, control, fps, "redo")
		assert_true(helper.helper._history().undo(), kind + " final Undo")
	assert_eq(helper.helper._logger.errors.size(), errors, "zero continuation engine errors")
	subject.root.free()
	control.root.free()
func test_clip_spring_continuation() -> void:
	for fps in [30, 60, 120]: _case("clip", fps)
func test_graph_spring_continuation() -> void:
	for kind in ["state", "blend1d", "blend2d", "additive", "oneshot", "state_nested", "state_grouped", "state_inactive"]:
		for fps in [30, 60, 120]: _case(kind, fps)
