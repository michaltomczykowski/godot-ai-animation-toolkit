@tool
extends McpTestSuite

const History := preload("res://tests/test_rig_modifier_history.gd")
const Bake := preload("res://tests/test_rig_bake_restoration.gd")
const Native := preload("res://tools/modifier_native_reference.gd")
const Saved := preload("res://tests/bake_saved_matrix.gd")
var fixtures := History.new()
var baker := Bake.new()
class FinalPose extends SkeletonModifier3D:
	var poses: Array = []
	func _process_modification_with_delta(_delta: float) -> void:
		poses.clear()
		for i in get_skeleton().get_bone_count(): poses.append(get_skeleton().get_bone_pose(i))
func suite_name() -> String: return "rig_bake_modifiers"
func suite_setup(ctx: Dictionary) -> void:
	fixtures.suite_setup(ctx)
	baker.suite_setup(ctx)
func suite_teardown() -> void:
	fixtures.suite_teardown()
	baker.suite_teardown()
func _case(kind: String, weight_index: int, fps: int) -> void:
	var label := "modifier_%s_%d_%d" % [kind, weight_index, fps]
	var f := fixtures._fixture(label, "local")
	# This matrix owns local source nodes. Instance/peer isolation remains in
	# the separate clip/modifier history gates; do not turn a peer's inherited
	# children into local overrides by recursively changing their owners.
	f.peer.free()
	var scene := EditorInterface.get_edited_scene_root()
	var source: Skeleton3D = f.source
	var selected := source
	var configurations: Array = []
	var ops: Array = ["ik_setup"] if kind in ["two_bone", "ccdik", "fabrik", "spline"] else [{"look": "look_at_setup", "twist": "twist_setup", "spring": "spring_setup", "retarget": "retarget_setup"}.get(kind, "look_at_setup")]
	if kind.begins_with("ordered"): ops = ["look_at_setup", "spring_setup"] if kind == "ordered_look_spring" else ["spring_setup", "look_at_setup"]
	var errors := baker._logger.errors.size()
	for op in ops:
		var p := fixtures._params(op, f).merged({"active": true, "name": "Bake" + str(configurations.size())}, true)
		if op == "ik_setup":
			p.kind = kind
			if kind == "spline": p.target_path = str(f.wrapper.get_node("SharedPath").get_path())
		var result := fixtures._call(p)
		assert_has_key(result, "data", label + " public modifier setup " + str(result.get("error", {})))
		if not result.has("data"):
			_cleanup(f)
			return
		var modifier: SkeletonModifier3D = source.get_node(NodePath(p.name))
		modifier.influence = float(weight_index) / 2
		p.influence = modifier.influence
		configurations.append({"op": op, "params": p, "path": str(scene.get_path_to(modifier))})
		if op == "retarget_setup": selected = f.receiver
	if kind == "retarget":
		var look := LookAtModifier3D.new()
		look.name = "ChildLook"
		selected.add_child(look)
		look.bone_name = "head"
		look.target_node = look.get_path_to(f.caller.get_node("Target"))
		look.use_secondary_rotation = false
		look.influence = 0.5
		look.active = true
		configurations.append({"op": "look_at_setup", "params": {"bone": "head", "active": true, "influence": 0.5}, "path": str(scene.get_path_to(look))})
	var player := AnimationPlayer.new()
	player.name = "BakeInput"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.wrapper.add_child(player)
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 1
	for i in source.get_bone_count():
		var path := str(f.wrapper.get_path_to(source)) + ":" + source.get_bone_name(i)
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, path)
		clip.track_insert_key(track, 0, source.get_bone_pose_rotation(i))
		clip.track_insert_key(track, 1, source.get_bone_pose_rotation(i) * Quaternion(Vector3.UP, 0.5))
	library.add_animation("input", clip)
	player.add_animation_library("", library)
	fixtures._pose._checks._own(f.container, scene)
	fixtures._pose._checks._own(f.caller, scene)
	var params := {"op": "bake_pose_sequence", "player_path": str(player.get_path()), "skeleton_path": str(selected.get_path()), "source_animation": "input", "animation_name": "baked", "duration": 0.205, "fps": fps, "positions": true, "scales": true}
	var saved := Saved.begin({"root": f.wrapper, "player": player, "skeleton": selected}, params, label)
	saved.modifiers = configurations
	var before := fixtures._snapshot(f.container)
	var identity := fixtures._identities(f.container, {})
	var version := baker._history().get_version()
	var dry := baker._call(params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", label + " dry " + str(dry.get("error", {})))
	assert_eq(fixtures._snapshot(f.container), before, label + " dry exact scene")
	assert_eq(baker._history().get_version(), version, label + " dry history")
	var result := baker._call(params)
	assert_has_key(result, "data", label + " write " + str(result.get("error", {})))
	if result.has("data"):
		assert_eq(baker._history().get_version(), version + 1, label + " one bake action")
		assert_eq(fixtures._identities(f.container, {}), identity, label + " original node identities")
		Saved.state(saved, player, "do")
		assert_true(baker._history().undo(), label + " Undo")
		Saved.state(saved, player, "undo")
		assert_eq(fixtures._snapshot(f.container), before, label + " exact Undo scene")
		assert_true(baker._history().redo(), label + " Redo")
		Saved.state(saved, player, "redo")
		Saved.finish(saved)
		assert_true(baker._history().undo(), label + " final Undo")
	assert_eq(baker._logger.errors.size(), errors, label + " zero engine errors")
	_cleanup(f)
func _cleanup(f: Dictionary) -> void:
	for node in [f.container, f.caller, f.receiver]:
		if is_instance_valid(node) and not node.is_queued_for_deletion(): node.free()
	var sentinel := EditorInterface.get_edited_scene_root().get_node_or_null("MH_LastSibling")
	if sentinel != null: sentinel.free()
func test_all_native_modifiers() -> void:
	for kind in ["two_bone", "ccdik", "fabrik", "spline", "look", "twist", "spring", "retarget"]:
		for weight in 3:
			for fps in [30, 60, 120]: _case(kind, weight, fps)
func test_reordered_fractional_stacks() -> void:
	for kind in ["ordered_look_spring", "ordered_spring_look"]:
		for weight in 3:
			for fps in [30, 60, 120]: _case(kind, weight, fps)
