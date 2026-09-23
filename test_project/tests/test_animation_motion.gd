@tool
extends McpTestSuite

## Tests for the animation_motion tool: procedural walk/run/idle cycles with
## planted feet, follow-through, styles and root motion.

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

const MotionHandler := preload("res://addons/godot_ai_animation/handlers/motion.gd")

const DUMMY := "res://models/human_dummy/HumanCharacterDummy_F.fbx"

var _handler: MotionHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_motion"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = MotionHandler.new()


# --- helpers ---------------------------------------------------------------

func _find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owners(child, owner)


func _rig(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	if not ResourceLoader.exists(DUMMY):
		return {"error": "the human dummy asset is missing"}
	var packed = load(DUMMY)
	var root: Node = packed.instantiate()
	root.name = prefix + "Dummy"
	scene_root.add_child(root)
	_assign_owners(root, scene_root)
	var skeleton := _find_of_type(root, "Skeleton3D") as Skeleton3D
	var player := _find_of_type(root, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		_remove_node("/" + scene_root.name + "/" + str(root.name))
		return {"error": "the dummy has no skeleton/player"}
	return {
		"root_path": "/" + scene_root.name + "/" + str(root.name),
		"skeleton_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(skeleton)),
		"player_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(player)),
		"skeleton": skeleton,
		"player": player,
	}


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _teardown(rig: Dictionary) -> void:
	if rig.has("root_path"):
		_remove_node(rig.root_path)


## Apply the clip at `time` to the skeleton (rest + this sample's keys) and
## return the global pose of `bone`. Dense samples make nearest-key sampling
## exact, so this is the pose the engine would show.
func _pose_of(rig: Dictionary, anim: Animation, time: float, bone: String) -> Transform3D:
	var skeleton: Skeleton3D = rig.skeleton
	skeleton.reset_bone_poses()
	for track in anim.get_track_count():
		var bone_name := str(anim.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var key := anim.track_find_key(track, time, Animation.FIND_MODE_NEAREST)
		if key < 0:
			continue
		match anim.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(index, anim.track_get_key_value(track, key))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(index, anim.track_get_key_value(track, key))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(index, anim.track_get_key_value(track, key))
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _track_index(anim: Animation, suffix: String, type: int) -> int:
	for index in anim.get_track_count():
		if anim.track_get_type(index) == type and str(anim.track_get_path(index)).ends_with(suffix):
			return index
	return -1


func _range_of(anim: Animation, track: int, component: int) -> float:
	var values := anim.track_get_key_count(track)
	var lo := INF
	var hi := -INF
	for key in values:
		var v: Vector3 = anim.track_get_key_value(track, key)
		var value: float = v.x if component == 0 else (v.y if component == 1 else v.z)
		lo = minf(lo, value)
		hi = maxf(hi, value)
	return hi - lo


# --- rollup -----------------------------------------------------------------

func test_rollup_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "fly"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "walk_cycle")
	assert_contains(unknown.error.message, "idle_cycle")


# --- walk -------------------------------------------------------------------

func test_walk_dense_curves_planted_feet_and_loop() -> void:
	var rig := _rig("MotionWalk")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear", "samples": 24,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.track_count) >= 10, true, "walk keys the whole body (%s tracks)" % result.data.track_count)
	var anim: Animation = rig.player.get_animation("walk")
	assert_true(anim != null, "the clip exists")
	assert_eq(anim.track_get_key_count(0), 25, "24 samples/s over 1s gives 25 keys")
	assert_gt(float(result.data.speed), 0.2, "the walk has a plausible ground speed")
	# Every track closes its loop exactly.
	for track in anim.get_track_count():
		var first = anim.track_get_key_value(track, 0)
		var last = anim.track_get_key_value(track, anim.track_get_key_count(track) - 1)
		if first is Quaternion:
			assert_true((first as Quaternion).dot(last as Quaternion) > 0.9999,
				"track %s closes its loop" % anim.track_get_path(track))
		else:
			assert_true((first as Vector3).is_equal_approx(last as Vector3),
				"track %s closes its loop" % anim.track_get_path(track))
	# The legs actually swing.
	var thigh := _track_index(anim, ":B-thigh.L", Animation.TYPE_ROTATION_3D)
	assert_true(thigh >= 0, "the left thigh has a rotation track")
	var spread := 0.0
	var first_key: Quaternion = anim.track_get_key_value(thigh, 0)
	for key in anim.track_get_key_count(thigh):
		spread = maxf(spread, first_key.angle_to(anim.track_get_key_value(thigh, key)))
	assert_gt(spread, 0.3, "the thigh swings a real stride")
	# Feet stay on the ground plane, and the stride matches the stride angle.
	var roles := MotionHandler._resolve_roles({}, rig.skeleton)
	var forward := MotionHandler._forward_dir(rig.skeleton, roles)
	var foot_index: int = rig.skeleton.find_bone("B-foot.L")
	var rest_origin: Vector3 = rig.skeleton.get_bone_global_rest(foot_index).origin
	var min_y := INF
	var max_y := -INF
	var min_f := INF
	var max_f := -INF
	for index in 26:
		var foot := _pose_of(rig, anim, float(index) / 25.0, "B-foot.L")
		min_y = minf(min_y, foot.origin.y)
		max_y = maxf(max_y, foot.origin.y)
		var offset := (foot.origin - rest_origin).dot(forward)
		min_f = minf(min_f, offset)
		max_f = maxf(max_f, offset)
	assert_gt(min_y, rest_origin.y - 0.03, "the planted foot never sinks below the ground (min %s)" % min_y)
	assert_true(max_y < rest_origin.y + 0.09, "the swing foot lifts within the lift budget (max %s)" % max_y)
	assert_gt(max_f - min_f, 0.15, "the ankle travels a real stride (%s m)" % (max_f - min_f))
	# One undo removes the clip.
	assert_true(editor_undo(_undo_redo), "undo should succeed")
	assert_true(rig.player.get_animation("walk") == null, "one undo removes the cycle")
	_teardown(rig)


func test_walk_bob_is_visible_and_styles_differ() -> void:
	var rig := _rig("MotionStyles")
	if rig.has("error"):
		skip(rig.error)
		return
	var default_run := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_default",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	var heavy_run := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_heavy",
		"duration": 1.0, "loop_mode": "linear", "style": "heavy",
	}, null)
	assert_true(default_run.has("data") and heavy_run.has("data"),
		"both styles build: %s / %s" % [str(default_run), str(heavy_run)])
	var default_anim: Animation = rig.player.get_animation("walk_default")
	var heavy_anim: Animation = rig.player.get_animation("walk_heavy")
	var default_bob := _range_of(default_anim, _track_index(default_anim, ":B-hips", Animation.TYPE_POSITION_3D), 1)
	var heavy_bob := _range_of(heavy_anim, _track_index(heavy_anim, ":B-hips", Animation.TYPE_POSITION_3D), 1)
	assert_gt(default_bob, 0.02, "the default walk bobs")
	assert_gt(heavy_bob, default_bob * 1.2, "heavy bobs more than default (%s vs %s)" % [heavy_bob, default_bob])
	assert_gt(float(heavy_run.data.speed), 0.0, "heavy reports its speed")
	_teardown(rig)


func test_run_is_faster_and_bigger_than_walk() -> void:
	var rig := _rig("MotionRun")
	if rig.has("error"):
		skip(rig.error)
		return
	var walk := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	var run := _handler.run({
		"op": "run_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "run",
		"duration": 0.6, "loop_mode": "linear",
	}, null)
	assert_true(walk.has("data") and run.has("data"), "both cycles build")
	assert_gt(float(run.data.speed), float(walk.data.speed) * 1.5,
		"the run is much faster (%.2f vs %.2f)" % [float(run.data.speed), float(walk.data.speed)])
	var anim: Animation = rig.player.get_animation("run")
	var thigh := _track_index(anim, ":B-thigh.L", Animation.TYPE_ROTATION_3D)
	var first_key: Quaternion = anim.track_get_key_value(thigh, 0)
	var spread := 0.0
	for key in anim.track_get_key_count(thigh):
		spread = maxf(spread, first_key.angle_to(anim.track_get_key_value(thigh, key)))
	assert_gt(spread, 0.7, "the run swings the legs wide")
	_teardown(rig)


func test_root_motion_keys_travel() -> void:
	var rig := _rig("MotionRoot")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_root",
		"duration": 1.0, "loop_mode": "linear", "root_motion": true,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_true(str(result.data.root_motion_track).ends_with(":B-hips"), "the root motion track names the hips")
	var anim: Animation = rig.player.get_animation("walk_root")
	var hips := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	var first: Vector3 = anim.track_get_key_value(hips, 0)
	var last: Vector3 = anim.track_get_key_value(hips, anim.track_get_key_count(hips) - 1)
	var roles := MotionHandler._resolve_roles({}, rig.skeleton)
	var forward := MotionHandler._forward_dir(rig.skeleton, roles)
	var travel := (last - first).dot(forward)
	assert_true(absf(travel - float(result.data.speed) * 1.0) < 0.05,
		"the hips travel the cycle's ground speed (%s vs %s)" % [travel, float(result.data.speed)])
	_teardown(rig)


# --- idle -------------------------------------------------------------------

func test_idle_cycle_breathing_shift_and_loop() -> void:
	var rig := _rig("MotionIdle")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle",
		"duration": 3.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("idle")
	assert_true(anim != null, "the idle clip exists")
	assert_eq(anim.track_get_key_count(0), 73, "3s at 24 samples/s gives 73 keys")
	var chest := _track_index(anim, ":B-chest", Animation.TYPE_ROTATION_3D)
	assert_true(chest >= 0, "the chest breathes")
	var first_key: Quaternion = anim.track_get_key_value(chest, 0)
	var spread := 0.0
	for key in anim.track_get_key_count(chest):
		spread = maxf(spread, first_key.angle_to(anim.track_get_key_value(chest, key)))
	assert_gt(spread, 0.01, "breathing moves the chest")
	assert_true(spread < 0.15, "breathing stays subtle (%s rad)" % spread)
	var hips := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	assert_true(hips >= 0, "the idle shifts the hips")
	assert_true(_range_of(anim, hips, 0) < 0.1, "the weight shift stays subtle")
	for track in anim.get_track_count():
		var first = anim.track_get_key_value(track, 0)
		var last = anim.track_get_key_value(track, anim.track_get_key_count(track) - 1)
		if first is Quaternion:
			assert_true((first as Quaternion).dot(last as Quaternion) > 0.9999,
				"track %s closes its loop" % anim.track_get_path(track))
		else:
			assert_true((first as Vector3).is_equal_approx(last as Vector3),
				"track %s closes its loop" % anim.track_get_path(track))
	_teardown(rig)


# --- secondary motion -------------------------------------------------------

func test_secondary_motion_bakes_spring_bones() -> void:
	var rig := _rig("MotionSecondary")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source walk builds, got: %s" % str(built))
	var result := _handler.run({
		"op": "secondary_motion", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"bones": ["B-jaw"], "stiffness": 120.0, "damping": 12.0, "samples": 30.0,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("walk")
	var jaw := _track_index(anim, ":B-jaw", Animation.TYPE_ROTATION_3D)
	assert_true(jaw >= 0, "the jaw gained a spring track")
	assert_eq(anim.track_get_key_count(jaw), 31, "1s at 30 samples/s gives 31 keys")
	var first: Quaternion = anim.track_get_key_value(jaw, 0)
	var last: Quaternion = anim.track_get_key_value(jaw, anim.track_get_key_count(jaw) - 1)
	assert_true(first.dot(last) > 0.9999, "the spring track closes its loop")
	var moved := false
	for key in anim.track_get_key_count(jaw):
		var q: Quaternion = anim.track_get_key_value(jaw, key)
		if q.get_angle() > 0.01:
			moved = true
	assert_true(moved, "the spring track actually moves with the head")
	var keyed := _handler.run({
		"op": "secondary_motion", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk", "bones": ["B-thigh.L"],
	}, null)
	assert_is_error(keyed, ErrorCodes.INVALID_PARAMS)
	var not_a_bone := _handler.run({
		"op": "secondary_motion", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk", "bones": ["B-nope"],
	}, null)
	assert_is_error(not_a_bone, ErrorCodes.NODE_NOT_FOUND)
	_teardown(rig)


# --- generic / validation ---------------------------------------------------

func test_cycle_preset_and_validation() -> void:
	var rig := _rig("MotionGeneric")
	if rig.has("error"):
		skip(rig.error)
		return
	var generic := _handler.run({
		"op": "cycle", "preset": "run", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "run_generic",
		"duration": 0.6, "loop_mode": "linear",
	}, null)
	assert_true(generic.has("data"), "cycle builds the preset, got: %s" % str(generic))
	assert_true(rig.player.get_animation("run_generic") != null, "the generic clip exists")
	var bad_preset := _handler.run({
		"op": "cycle", "preset": "swim", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "duration": 1.0,
	}, null)
	assert_is_error(bad_preset, ErrorCodes.VALUE_OUT_OF_RANGE)
	var bad_style := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "duration": 1.0, "style": "dizzy",
	}, null)
	assert_is_error(bad_style, ErrorCodes.VALUE_OUT_OF_RANGE)
	var bad_override := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "duration": 1.0, "overrides": {"moonwalk": 1},
	}, null)
	assert_is_error(bad_override, ErrorCodes.INVALID_PARAMS)
	assert_contains(bad_override.error.message, "stride")
	var bad_roles := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "duration": 1.0,
		"roles": {"thigh_l": "NotABone"},
	}, null)
	assert_is_error(bad_roles, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


func test_override_tunes_the_cycle() -> void:
	var rig := _rig("MotionOverride")
	if rig.has("error"):
		skip(rig.error)
		return
	var small := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_small",
		"duration": 1.0, "loop_mode": "linear", "overrides": {"stride": 8.0, "arm_swing": 4.0},
	}, null)
	var large := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_large",
		"duration": 1.0, "loop_mode": "linear", "overrides": {"stride": 40.0, "arm_swing": 35.0},
	}, null)
	assert_true(small.has("data") and large.has("data"), "both override calls build")
	assert_gt(float(large.data.speed), float(small.data.speed) * 2.0, "a wider stride covers more ground")
	_teardown(rig)
