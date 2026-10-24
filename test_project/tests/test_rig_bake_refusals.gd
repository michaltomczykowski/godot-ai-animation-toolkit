@tool
extends McpTestSuite
const Helpers := preload("res://tests/test_rig_bake_restoration.gd")
var helper := Helpers.new()
class ScriptedClip extends Animation:
	static var constructed := 0
	func _init() -> void: constructed += 1
func suite_name() -> String: return "rig_bake_refusals"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _check_refusal(f: Dictionary, label: String, params: Dictionary = {}) -> void:
	var history := helper._history().get_version()
	var orphans := Node.get_orphan_node_ids()
	var errors := helper._logger.errors.size()
	var poses: Array = []
	for i in f.skeleton.get_bone_count(): poses.append(f.skeleton.get_bone_pose(i))
	for dry in [false, true]:
		var result := helper._call(helper._params(f).merged(params, true).merged({"dry_run": dry}, true))
		assert_eq(result.get("error", {}).get("code"), "OPERATION_UNAVAILABLE", label + " typed unavailable " + str(result))
		assert_eq(helper._history().get_version(), history, label + " no history")
		assert_eq(Node.get_orphan_node_ids(), orphans, label + " exact orphan IDs")
		assert_false(f.player.has_animation("baked"), label + " no inert clip")
		for i in poses.size(): assert_eq(f.skeleton.get_bone_pose(i), poses[i], label + " source pose untouched")
	assert_eq(helper._logger.errors.size(), errors, label + " zero engine errors")
func test_track_semantics() -> void:
	for kind in ["unknown_bone", "unknown_property", "empty", "nonfinite"]:
		var f := helper._fixture("BakeRefuseTrack")
		if kind == "unknown_bone": f.animation.track_set_path(0, "Skeleton:missing")
		elif kind == "unknown_property":
			var track: int = f.animation.add_track(Animation.TYPE_VALUE)
			f.animation.track_set_path(track, "Skeleton:missing")
			f.animation.track_insert_key(track, 0, 1)
		elif kind == "empty": f.animation.track_remove_key(0, 1); f.animation.track_remove_key(0, 0)
		else: f.animation.track_set_key_value(0, 0, Quaternion(INF, 0, 0, 1))
		_check_refusal(f, kind)
		f.root.free()
func test_animated_scripted_modifier_refusal() -> void:
	var f := helper._fixture("BakeRefuseActivation")
	var scripted := Helpers.Witness.new()
	scripted.name = "Unsupported"
	scripted.active = false
	f.skeleton.add_child(scripted)
	var track: int = f.animation.add_track(Animation.TYPE_VALUE)
	f.animation.track_set_path(track, "Skeleton/Unsupported:active")
	f.animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	f.animation.track_insert_key(track, 0, false)
	f.animation.track_insert_key(track, 0.1, true)
	_check_refusal(f, "late animated unsupported modifier")
	assert_false(scripted.active, "original scripted modifier remains inactive")
	f.root.free()
func test_scripted_resource_refused_before_duplication() -> void:
	var f := helper._fixture("BakeRefuseScriptedResource")
	var clip := ScriptedClip.new()
	var count := ScriptedClip.constructed
	var library: AnimationLibrary = f.player.get_animation_library("")
	library.remove_animation("input")
	library.add_animation("input", clip)
	_check_refusal(f, "scripted resource")
	assert_eq(ScriptedClip.constructed, count, "scripted resource constructor never duplicated")
	f.root.free()
func test_short_final_spacing_refusal() -> void:
	var f := helper._fixture("BakeRefuseSpacing")
	_check_refusal(f, "short final sample", {"duration": 0.200001})
	f.root.free()
