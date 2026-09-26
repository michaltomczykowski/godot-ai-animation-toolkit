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
## return the global pose of `bone`. Nearest-key sampling: dense samples make it
## exact, sparse keys (jump/turn) land on the closest pose.
func _pose_of(rig: Dictionary, anim: Animation, time: float, bone: String) -> Transform3D:
	var skeleton: Skeleton3D = rig.skeleton
	skeleton.reset_bone_poses()
	for track in anim.get_track_count():
		var bone_name := str(anim.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var key := _nearest_key_index(anim, track, time)
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


## World yaw (radians) of a rotation track's nearest key, as a bone basis.
func _yaw_of(rig: Dictionary, anim: Animation, track: int, time: float) -> float:
	var skeleton: Skeleton3D = rig.skeleton
	skeleton.reset_bone_poses()
	var key := _nearest_key_index(anim, track, time)
	if key < 0:
		return 0.0
	var path := str(anim.track_get_path(track))
	var index := skeleton.find_bone(path.get_slice(":", 1))
	if index < 0:
		return 0.0
	var value: Quaternion = anim.track_get_key_value(track, key)
	skeleton.set_bone_pose_rotation(index, value)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	return skeleton.get_bone_global_pose(index).basis.get_euler().y


func _nearest_key_index(anim: Animation, track: int, time: float) -> int:
	var best := -1
	var best_distance := INF
	for index in anim.track_get_key_count(track):
		var distance := absf(anim.track_get_key_time(track, index) - time)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


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


## Largest rotation angle any key reaches from the first key of a rotation track.
func _spread(anim: Animation, track: int) -> float:
	var first: Quaternion = anim.track_get_key_value(track, 0)
	var spread := 0.0
	for key in anim.track_get_key_count(track):
		spread = maxf(spread, first.angle_to(anim.track_get_key_value(track, key)))
	return spread


## Per-bone rotation spread along a bone chain, keyed by bone name. Bones the
## recipe left alone are reported as 0.0 so the caller can compare the chain.
func _chain_spreads(anim: Animation, bones: Array) -> Dictionary:
	var out := {}
	for bone in bones:
		var track := _track_index(anim, ":%s" % str(bone), Animation.TYPE_ROTATION_3D)
		out[str(bone)] = 0.0 if track < 0 else _spread(anim, track)
	return out


# --- motion pack ------------------------------------------------------------

func test_speed_driven_gait_and_warning() -> void:
	var rig := _rig("MotionSpeed")
	if rig.has("error"):
		skip(rig.error)
		return
	var slow := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_slow",
		"duration": 1.0, "loop_mode": "linear", "speed": 0.7,
	}, null)
	var fast := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_fast",
		"duration": 1.0, "loop_mode": "linear", "speed": 1.6,
	}, null)
	assert_true(slow.has("data") and fast.has("data"), "both speeds build")
	assert_true(absf(float(slow.data.speed) - 0.7) < 0.05, "the requested speed is achieved (%s)" % slow.data.speed)
	assert_true(absf(float(fast.data.speed) - 1.6) < 0.1, "the fast walk matches its speed (%s)" % fast.data.speed)
	assert_gt(float(fast.data.stride_used), float(slow.data.stride_used), "a faster walk uses a wider stride")
	assert_gt(float(fast.data.cadence), 0.0, "cadence is reported")
	var too_fast := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_impossible",
		"duration": 0.4, "loop_mode": "linear", "speed": 8.0,
	}, null)
	assert_true(too_fast.has("data"), "an unreachable speed still builds (clamped)")
	assert_has_key(too_fast.data, "warnings")
	assert_contains(str(too_fast.data.warnings), "duration")
	_teardown(rig)


func test_jump_arc_and_markers() -> void:
	var rig := _rig("MotionJump")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "jump", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "jump",
		"duration": 1.2, "height": 0.55, "crouch": 0.25,
	}, null)
	assert_true(result.has("data"), "jump builds: %s" % str(result))
	var anim: Animation = rig.player.get_animation("jump")
	var hips := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	var rest_y: float = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-hips")).origin.y
	assert_gt(_range_of(anim, hips, 1), 0.4, "the hips rise through the jump")
	var apex_y := -INF
	for key in anim.track_get_key_count(hips):
		apex_y = maxf(apex_y, (anim.track_get_key_value(hips, key) as Vector3).y)
	assert_true(absf((apex_y - rest_y) - 0.55) < 0.06, "the apex reaches the requested height (%s)" % (apex_y - rest_y))
	var names := anim.get_marker_names()
	assert_true(names.has("takeoff") and names.has("apex") and names.has("land"), "jump phase markers exist")
	var roles := MotionHandler._resolve_roles({}, rig.skeleton)
	var forward := MotionHandler._forward_dir(rig.skeleton, roles)
	var foot_rest: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.L")).origin
	var foot_start := _pose_of(rig, anim, 0.0, "B-foot.L").origin
	var foot_apex := _pose_of(rig, anim, 0.55, "B-foot.L").origin
	assert_gt((foot_apex - foot_start).dot(Vector3.UP), 0.1,
		"the feet leave the ground in the air (start=%s apex=%s)" % [foot_start, foot_apex])
	var foot_end := _pose_of(rig, anim, 1.0, "B-foot.L").origin
	assert_true(absf((foot_end - foot_rest).dot(Vector3.UP)) < 0.05, "the feet land back on the ground")
	assert_true(forward.length() > 0.0, "facing is resolvable")
	_teardown(rig)


func test_one_shot_recipes_keep_their_endpoint_when_looping() -> void:
	var rig := _rig("MotionOneShot")
	if rig.has("error"):
		skip(rig.error)
		return
	# loop_mode=linear on a one-shot used to run the loop-closing pass, which
	# overwrote the last key with the first and threw the endpoint away. A jump
	# returns to the same height, so the observable case is a transition that
	# ends somewhere else: it starts at rest and ends in a gait pose.
	var start := _handler.run({
		"op": "walk_start", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "start_looped",
		"duration": 0.4, "phase": 0.5, "loop_mode": "linear",
	}, null)
	assert_true(start.has("data"), "walk_start builds: %s" % str(start))
	var start_anim: Animation = rig.player.get_animation("start_looped")
	var start_thigh := _track_index(start_anim, ":B-thigh.L", Animation.TYPE_ROTATION_3D)
	var start_first: Quaternion = start_anim.track_get_key_value(start_thigh, 0)
	var start_last: Quaternion = start_anim.track_get_key_value(start_thigh,
		start_anim.track_get_key_count(start_thigh) - 1)
	assert_true(rad_to_deg(start_first.angle_to(start_last)) > 3.0,
		"the transition keeps its gait endpoint (%.1f deg)" % rad_to_deg(start_first.angle_to(start_last)))
	var turn := _handler.run({
		"op": "turn_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "turn_looped",
		"duration": 0.6, "angle": 90, "loop_mode": "linear",
	}, null)
	assert_true(turn.has("data"), "turn builds: %s" % str(turn))
	var turn_anim: Animation = rig.player.get_animation("turn_looped")
	var turn_hips := _track_index(turn_anim, ":B-hips", Animation.TYPE_ROTATION_3D)
	var turn_first: Quaternion = turn_anim.track_get_key_value(turn_hips, 0)
	var turn_last: Quaternion = turn_anim.track_get_key_value(turn_hips,
		turn_anim.track_get_key_count(turn_hips) - 1)
	assert_true(rad_to_deg(turn_first.angle_to(turn_last)) > 45.0,
		"the turn still ends turned (%.1f deg)" % rad_to_deg(turn_first.angle_to(turn_last)))
	# A cyclic recipe is unaffected: its first and last keys still match.
	var walk := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_looped",
		"duration": 0.8, "loop_mode": "linear",
	}, null)
	assert_true(walk.has("data"), "walk builds: %s" % str(walk))
	var walk_anim: Animation = rig.player.get_animation("walk_looped")
	var walk_hips := _track_index(walk_anim, ":B-hips", Animation.TYPE_POSITION_3D)
	assert_true((walk_anim.track_get_key_value(walk_hips, 0) as Vector3).is_equal_approx(
			walk_anim.track_get_key_value(walk_hips, walk_anim.track_get_key_count(walk_hips) - 1) as Vector3),
		"a looping cycle still closes on itself")
	_teardown(rig)


func test_motion_rejects_non_finite_parameters() -> void:
	var rig := _rig("MotionFinite")
	if rig.has("error"):
		skip(rig.error)
		return
	var bad_duration := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_nan",
		"duration": NAN,
	}, null)
	assert_is_error(bad_duration, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(bad_duration.get("error", {}).get("message", ""), "finite")
	var bad_override := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_inf",
		"overrides": {"lean": INF},
	}, null)
	assert_is_error(bad_override, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(bad_override.get("error", {}).get("message", ""), "overrides.lean")
	var good := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_ok", "duration": 0.8,
	}, null)
	assert_true(good.has("data"), "a normal call still builds: %s" % str(good))
	_teardown(rig)


func test_motion_honours_an_explicit_spine_chain() -> void:
	var rig := _rig("MotionChain")
	if rig.has("error"):
		skip(rig.error)
		return
	# An explicit chain used to be validated and then replaced by the
	# role-derived one, so a named intermediate never got a track.
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "chain_walk",
		"duration": 0.8, "spine_chain": ["B-hips", "B-spine", "B-chest"],
	}, null)
	assert_true(result.has("data"), "walk builds: %s" % str(result))
	assert_eq((result.data.spine_chain as Array).size(), 3, "the explicit chain is used as given")
	var anim: Animation = rig.player.get_animation("chain_walk")
	for bone in ["B-spine", "B-chest"]:
		var index := _track_index(anim, ":" + str(bone), Animation.TYPE_ROTATION_3D)
		assert_true(index >= 0, "%s is keyed on the explicit chain" % str(bone))
	# The neck is not one of the scalar roles, so keying it proves the explicit
	# chain was used instead of the role-derived one.
	var upper := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "chain_idle",
		"duration": 2.0, "spine_chain": ["B-chest", "B-neck", "B-head"],
	}, null)
	assert_true(upper.has("data"), "an intermediate bone can be named: %s" % str(upper))
	assert_eq((upper.data.spine_chain as Array).size(), 3, "the explicit chain is used as given")
	var upper_anim: Animation = rig.player.get_animation("chain_idle")
	assert_true(_track_index(upper_anim, ":B-neck", Animation.TYPE_ROTATION_3D) >= 0,
		"the named intermediate is keyed")
	_teardown(rig)


func test_turn_cycle_rotates_and_settles() -> void:
	var rig := _rig("MotionTurn")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "turn_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "turn_left",
		"duration": 0.7, "angle": 90, "direction": "left",
	}, null)
	assert_true(result.has("data"), "turn builds: %s" % str(result))
	var anim: Animation = rig.player.get_animation("turn_left")
	var hips := _track_index(anim, ":B-hips", Animation.TYPE_ROTATION_3D)
	var first: Quaternion = anim.track_get_key_value(hips, 0)
	var last: Quaternion = anim.track_get_key_value(hips, anim.track_get_key_count(hips) - 1)
	assert_true(absf(rad_to_deg(first.angle_to(last)) - 90.0) < 2.0,
		"the turn ends at the requested angle (%s deg)" % rad_to_deg(first.angle_to(last)))
	var foot_rest: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.R")).origin
	var foot_end := _pose_of(rig, anim, 1.0, "B-foot.R").origin
	assert_true(absf((foot_end - foot_rest).dot(Vector3.UP)) < 0.05, "the feet are back on the ground")
	assert_true(anim.get_marker_names().has("anticipate"), "turn phase markers exist")
	_teardown(rig)


## `steps: 2` splits a 180-degree turn into two pivots with the opposite foot
## lifting in each, so it reads as weight shifts instead of one spin.
func test_turn_cycle_splits_into_pivot_steps() -> void:
	var rig := _rig("MotionTurnSteps")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "turn_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "turn_back",
		"duration": 1.4, "angle": 180, "direction": "left", "steps": 2,
	}, null)
	assert_true(result.has("data"), "the stepped turn builds: %s" % str(result))
	assert_eq(int(result.data.steps), 2, "the result reports two pivot steps")
	var anim: Animation = rig.player.get_animation("turn_back")
	assert_true(anim != null, "the clip exists")
	var hips := _track_index(anim, ":B-hips", Animation.TYPE_ROTATION_3D)
	assert_true(hips >= 0, "the hips are keyed")
	assert_eq(anim.track_get_key_count(hips), 9,
		"two steps key five phases, sharing the boundary settle (got %d)"
			% anim.track_get_key_count(hips))
	var first: Quaternion = anim.track_get_key_value(hips, 0)
	var middle: Quaternion = anim.track_get_key_value(hips, 4)
	var last: Quaternion = anim.track_get_key_value(hips, 8)
	assert_true(absf(anim.track_get_key_time(hips, 4) - 0.7) < 0.01,
		"the first step settles at the halfway time (%f)" % anim.track_get_key_time(hips, 4))
	assert_true(absf(rad_to_deg(first.angle_to(middle)) - 90.0) < 2.0,
		"the first pivot settles at half the turn (%s deg)" % rad_to_deg(first.angle_to(middle)))
	assert_true(absf(rad_to_deg(first.angle_to(last)) - 180.0) < 2.0,
		"the full turn still lands on 180 degrees (%s deg)" % rad_to_deg(first.angle_to(last)))
	var names := anim.get_marker_names()
	assert_true(names.has("anticipate") and names.has("anticipate_2"),
		"each step gets its own markers (%s)" % str(names))
	# The chest leads each step by a bounded amount. Scaling the running total
	# instead corkscrewed the spine: at the end of step two the chest used to be
	# a full extra turn past the hips.
	var chest := _track_index(anim, ":B-chest", Animation.TYPE_ROTATION_3D)
	var head := _track_index(anim, ":B-head", Animation.TYPE_ROTATION_3D)
	assert_true(chest >= 0 and head >= 0, "the chest and head are keyed")
	var worst_lead := 0.0
	var worst_lag := 0.0
	for index in 21:
		var time := float(index) / 20.0 * 1.4
		var hips_yaw := _yaw_of(rig, anim, hips, time)
		var chest_yaw := _yaw_of(rig, anim, chest, time)
		var head_yaw := _yaw_of(rig, anim, head, time)
		# Euler yaw wraps at +/-180, so compare through the shortest arc.
		var lead := wrapf(rad_to_deg(chest_yaw - hips_yaw), -180.0, 180.0)
		var lag := wrapf(rad_to_deg(head_yaw - hips_yaw), -180.0, 180.0)
		worst_lead = maxf(worst_lead, lead)
		worst_lag = maxf(worst_lag, -lag)
	assert_true(worst_lead < 45.0,
		"the chest never leads the hips by more than 45 degrees (worst %.1f)" % worst_lead)
	assert_true(worst_lag < 45.0,
		"the head never trails the hips by more than 45 degrees (worst %.1f)" % worst_lag)
	# The first step lifts the right foot, the second the left one.
	var right_lift := 0.0
	var left_lift := 0.0
	for index in 20:
		var time := float(index) / 19.0 * 1.4
		right_lift = maxf(right_lift, _pose_of(rig, anim, time, "B-foot.R").origin.y)
		left_lift = maxf(left_lift, _pose_of(rig, anim, time, "B-foot.L").origin.y)
	var right_rest: float = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.R")).origin.y
	var left_rest: float = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.L")).origin.y
	assert_true(right_lift > right_rest + 0.02, "the right foot steps in the first pivot")
	assert_true(left_lift > left_rest + 0.02, "the left foot steps in the second pivot")
	_teardown(rig)


func test_strafe_moves_laterally_and_loops() -> void:
	var rig := _rig("MotionStrafe")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "strafe_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "strafe_left",
		"duration": 0.9, "direction": "left", "speed": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "strafe builds: %s" % str(result))
	assert_true(absf(float(result.data.speed) - 1.0) < 0.1, "the strafe matches its speed")
	var anim: Animation = rig.player.get_animation("strafe_left")
	var roles := MotionHandler._resolve_roles({}, rig.skeleton)
	var left_rest: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-thigh.L")).origin
	var right_rest: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-thigh.R")).origin
	var lateral: Vector3 = left_rest - right_rest
	lateral.y = 0.0
	lateral = lateral.normalized()
	var foot_rest: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.L")).origin
	var lo := INF
	var hi := -INF
	for index in 10:
		var foot := _pose_of(rig, anim, float(index) / 9.0 * 0.9, "B-foot.L").origin
		var offset := (foot - foot_rest).dot(lateral)
		lo = minf(lo, offset)
		hi = maxf(hi, offset)
	assert_gt(hi - lo, 0.05, "the strafe foot travels sideways (%s m)" % (hi - lo))
	assert_gt(float(result.data.markers), 0.0, "the strafe emits phase markers")
	_teardown(rig)


func test_walk_transitions_match_the_cycle() -> void:
	var rig := _rig("MotionTransition")
	if rig.has("error"):
		skip(rig.error)
		return
	var walk := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	var start := _handler.run({
		"op": "walk_start", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_start",
		"duration": 0.35, "phase": 0.0,
	}, null)
	var stop := _handler.run({
		"op": "walk_stop", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_stop",
		"duration": 0.35, "phase": 0.0,
	}, null)
	assert_true(walk.has("data") and start.has("data") and stop.has("data"), "walk and both transitions build")
	var walk_anim: Animation = rig.player.get_animation("walk")
	var start_anim: Animation = rig.player.get_animation("walk_start")
	var stop_anim: Animation = rig.player.get_animation("walk_stop")
	var walk_contact := _pose_of(rig, walk_anim, 0.0, "B-foot.L").origin
	var start_end := _pose_of(rig, start_anim, 0.35, "B-foot.L").origin
	var stop_begin := _pose_of(rig, stop_anim, 0.0, "B-foot.L").origin
	assert_true(walk_contact.distance_to(start_end) < 0.05,
		"walk_start ends on the cycle's contact pose (%s m off)" % walk_contact.distance_to(start_end))
	assert_true(walk_contact.distance_to(stop_begin) < 0.05,
		"walk_stop starts on the cycle's contact pose (%s m off)" % walk_contact.distance_to(stop_begin))
	var stop_end := _pose_of(rig, stop_anim, 0.35, "B-foot.L").origin
	var rest_ankle: Vector3 = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone("B-foot.L")).origin
	assert_true(stop_end.distance_to(rest_ankle) < 0.05, "walk_stop settles back to rest")
	_teardown(rig)


func test_walk_transition_meets_the_cycle_mid_phase() -> void:
	var rig := _rig("MotionPhase")
	if rig.has("error"):
		skip(rig.error)
		return
	# Sparse sampling puts the phase target between two gait keys, which is where
	# the old nearest-key lookup snapped to the phase-0 key instead of
	# interpolating: the transition used to land on the WRONG point of the cycle.
	var sparse := 4.0
	var cycle := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "cycle",
		"duration": 0.4, "loop_mode": "linear", "samples": sparse,
	}, null)
	var start := _handler.run({
		"op": "walk_start", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "start",
		"duration": 0.4, "phase": 0.5, "samples": sparse,
	}, null)
	assert_true(cycle.has("data") and start.has("data"),
		"the sparse cycle and its transition build (%s)" % str([cycle, start]))
	var cycle_anim: Animation = rig.player.get_animation("cycle")
	var start_anim: Animation = rig.player.get_animation("start")
	# A transition at phase p samples the cycle at p * its own length.
	var target := 0.5 * 0.4
	for bone in ["B-foot.L", "B-thigh.R", "B-spine"]:
		var expected := _pose_of(rig, cycle_anim, target, bone)
		var reached := _pose_of(rig, start_anim, 0.4, bone)
		var rest: Transform3D = rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(bone))
		var wanted_distance := expected.origin.distance_to(rest.origin)
		assert_true(reached.origin.distance_to(expected.origin) < maxf(0.02, wanted_distance * 0.25),
			"walk_start lands on the cycle at %s (%.3f m from it, wanted %.3f)"
			% [bone, reached.origin.distance_to(expected.origin), wanted_distance])
	_teardown(rig)


func test_dry_run_creates_no_clip_no_tree_and_no_undo_action() -> void:
	var rig := _rig("MotionDry")
	if rig.has("error"):
		skip(rig.error)
		return
	var before_nodes := _node_paths(EditorInterface.get_edited_scene_root())
	var before_clips := _clip_names(rig.player)
	var before_version := _undo_version()
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "dry_walk",
		"duration": 0.8, "loop_mode": "linear", "root_motion": true, "dry_run": true,
	}, null)
	assert_true(result.has("data"), "walk_cycle dry_run reports a result (%s)" % str(result.get("error", result)))
	assert_true(bool(result.data.dry_run), "dry_run is reported")
	assert_eq(_node_paths(EditorInterface.get_edited_scene_root()), before_nodes,
		"dry_run adds no AnimationTree and no player")
	assert_eq(_clip_names(rig.player), before_clips, "dry_run writes no clip")
	assert_eq(_undo_version(), before_version, "dry_run commits no undo action")
	_teardown(rig)


func _node_paths(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append("%s:%s" % [str(node.get_path()), node.get_class()])
		for child in node.get_children():
			stack.append(child)
	out.sort()
	return out


func _clip_names(player: AnimationPlayer) -> Array:
	var out: Array = []
	for name in player.get_animation_list():
		var anim: Animation = player.get_animation(str(name))
		out.append("%s:%.4f:%d" % [str(name), anim.length, anim.get_track_count()])
	out.sort()
	return out


func _undo_version() -> int:
	var undo := EditorInterface.get_editor_undo_redo()
	var id := undo.get_object_history_id(EditorInterface.get_edited_scene_root())
	if id < 0:
		return -1
	return int(undo.get_history_undo_redo(id).get_version())


func test_root_motion_wires_and_undoes() -> void:
	var rig := _rig("MotionRootWiring")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_root",
		"duration": 1.0, "loop_mode": "linear", "root_motion": true,
	}, null)
	assert_true(result.has("data"), "rooted walk builds: %s" % str(result))
	assert_true(str(rig.player.root_motion_track).ends_with(":B-hips"),
		"the player's root_motion_track is wired (%s)" % rig.player.root_motion_track)
	assert_true(editor_undo(_undo_redo), "undo should succeed")
	assert_true(str(rig.player.root_motion_track).is_empty(), "one undo restores the root motion track")
	_teardown(rig)


func test_foot_roll_and_markers_in_walk() -> void:
	var rig := _rig("MotionFootRoll")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "walk builds: %s" % str(result))
	var anim: Animation = rig.player.get_animation("walk")
	assert_true(_track_index(anim, ":B-toe.L", Animation.TYPE_ROTATION_3D) >= 0, "the toe bone is animated")
	var names := anim.get_marker_names()
	for marker in ["contact.L", "contact.R", "toe_off.L", "toe_off.R"]:
		assert_true(names.has(marker), "the walk emits %s" % marker)
	assert_eq(int(result.data.markers), 6, "six phase markers are reported")
	_teardown(rig)


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


func test_walk_arms_swing_forward_with_forward_elbow() -> void:
	var rig := _rig("MotionArms")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "the walk builds, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("walk")
	var roles := MotionHandler._resolve_roles({}, rig.skeleton)
	var forward := MotionHandler._forward_dir(rig.skeleton, roles)
	# The left arm is fully forward at t=0.5. The hand must lead the elbow: the
	# old rest-frame elbow conversion curled the forearm across the body instead.
	var elbow := _pose_of(rig, anim, 0.5, "B-forearm.L")
	var hand := _pose_of(rig, anim, 0.5, "B-hand.L")
	assert_gt((hand.origin - elbow.origin).dot(forward), 0.02,
		"the hand leads the elbow at the front of the swing")
	var hand_back := _pose_of(rig, anim, 0.0, "B-hand.L")
	assert_gt((hand.origin - hand_back.origin).dot(forward), 0.05,
		"the hand travels forward between the back and front of the swing")
	var arm_down := _handler._default_arm_down(rig.skeleton, roles)
	assert_gt(arm_down, 0.0, "the T-pose rest is detected and the arms lowered")
	_teardown(rig)


# --- idle -------------------------------------------------------------------

func test_idle_twist_is_shared_over_the_spine_chain() -> void:
	var rig := _rig("MotionTwist")
	if rig.has("error"):
		skip(rig.error)
		return
	var chain := ["B-hips", "B-spine", "B-chest", "B-neck", "B-head"]
	var result := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_twist",
		"duration": 3.0, "loop_mode": "linear", "overrides": {"twist": 40.0},
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("idle_twist")
	assert_true(anim != null, "the clip exists")
	var spreads := _chain_spreads(anim, chain)
	for bone in chain:
		assert_gt(float(spreads[bone]), 0.0, "%s takes part in the twist" % bone)
	# 40 degrees of twist is shared: a sine channel swings twice its amplitude, so
	# the old per-bone multipliers (chest alone: 1.0 + 0.3 of 40 degrees) reached
	# more than a full turn of spread on one bone. Now the biggest torso bone is
	# the upper chest at a ~27 degree peak-to-peak.
	for bone in ["B-hips", "B-spine", "B-chest", "B-neck"]:
		assert_true(float(spreads[bone]) < deg_to_rad(40.0),
			"%s stays inside the shared twist (%s rad)" % [bone, str(spreads[bone])])
	assert_true(float(spreads["B-chest"]) < deg_to_rad(30.0),
		"the chest takes a share, not the whole twist (%s rad)" % str(spreads["B-chest"]))
	var tight := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_tight",
		"duration": 3.0, "loop_mode": "linear",
		"overrides": {"twist": 40.0, "twist_spread": 0.0},
	}, null)
	assert_true(tight.has("data"), "twist_spread is an accepted override, got: %s" % str(tight))
	var tight_anim: Animation = rig.player.get_animation("idle_tight")
	var tight_spreads := _chain_spreads(tight_anim, chain)
	assert_true(float(tight_spreads["B-chest"]) < float(spreads["B-chest"]) * 0.5,
		"twist_spread 0 keeps the movement out of the chest (%s rad)" % str(tight_spreads["B-chest"]))
	assert_true(float(tight_spreads["B-hips"]) > float(spreads["B-hips"]),
		"twist_spread 0 hands the twist to the hips (%s rad)" % str(tight_spreads["B-hips"]))
	var explicit := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_chain",
		"duration": 3.0, "loop_mode": "linear",
		"spine_chain": ["B-hips", "B-spine", "B-chest"],
	}, null)
	assert_true(explicit.has("data"), "an explicit spine_chain is accepted, got: %s" % str(explicit))
	var chain_anim: Animation = rig.player.get_animation("idle_chain")
	assert_eq(_track_index(chain_anim, ":B-head", Animation.TYPE_ROTATION_3D), -1,
		"a headless chain leaves the head out of the torso twist")
	var broken := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_bad", "duration": 3.0,
		"spine_chain": ["B-chest", "B-hips"],
	}, null)
	assert_is_error(broken, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


func test_idle_keeps_its_feet_planted() -> void:
	# The pelvis breathes, sways and twists; if the legs are not re-solved, both
	# feet travel with it and the character skates in place. `planted` (the
	# default) solves them against their rest ankles, and `planted: false` keeps
	# the old pelvis-only clip.
	var rig := _rig("MotionIdlePlant")
	if rig.has("error"):
		skip(rig.error)
		return
	var planted := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_planted",
		"duration": 3.0, "loop_mode": "linear", "planted": true,
	}, null)
	assert_true(planted.has("data"), "planted idle builds (%s)" % str(planted.get("error", planted)))
	var loose := _handler.run({
		"op": "idle_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle_loose",
		"duration": 3.0, "loop_mode": "linear", "planted": false,
	}, null)
	assert_true(loose.has("data"), "pelvis-only idle builds (%s)" % str(loose.get("error", loose)))
	var anim: Animation = rig.player.get_animation("idle_planted")
	var pelvis_only: Animation = rig.player.get_animation("idle_loose")
	for side in [".L", ".R"]:
		var bone := "B-foot" + str(side)
		var foot := _track_index(anim, ":" + bone, Animation.TYPE_ROTATION_3D)
		var shin := _track_index(anim, ":B-shin" + str(side), Animation.TYPE_ROTATION_3D)
		assert_true(foot >= 0, "B-foot%s is keyed when planted" % str(side))
		assert_true(shin >= 0, "B-shin%s is keyed when planted" % str(side))
		# "Planted" is a claim about the WORLD: the ankle must not travel with the
		# pelvis. The local foot delta is not the measure (a foot pinned to its
		# world orientation still rotates locally as the shin moves under it), so
		# measure the foot bone's world position across the clip instead.
		var rest_ankle: Vector3 = rig.skeleton.get_bone_global_rest(
			rig.skeleton.find_bone(bone)).origin
		var travel := 0.0
		var furthest := 0.0
		for step in 13:
			var pose := _pose_of(rig, anim, 3.0 * float(step) / 12.0, bone)
			travel = maxf(travel, pose.origin.distance_to(rest_ankle))
			furthest = maxf(furthest, pose.origin.y - rest_ankle.y)
		assert_true(travel < 0.02,
			"the planted %s stays on its rest spot (%.3f m of travel)" % [bone, travel])
		assert_true(furthest < 0.01,
			"and never lifts off the floor (%.3f m up)" % furthest)
		# The shin has to do the work, or the foot is static for the wrong reason.
		assert_gt(_spread(anim, shin), 0.005,
			"the shin%s absorbs the weight shift" % str(side))
		# The pelvis-only clip keys no legs at all, which is what `planted: false`
		# documents.
		assert_true(_track_index(pelvis_only, ":B-shin" + str(side), Animation.TYPE_ROTATION_3D) < 0,
			"planted: false leaves B-shin%s alone" % str(side))
	_teardown(rig)


func test_default_distances_scale_with_the_rig() -> void:
	# Bob, foot lift, crouch and jump height defaulted to FIXED metres, so a
	# 1.2 m character got the same five centimetres of lift as a 2.4 m one. They
	# are now fractions of the measured leg, while an explicit value stays metres.
	var rig := _rig("MotionScale")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var normal := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "scale_1x",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(normal.has("data"), "the walk builds (%s)" % str(normal.get("error", normal)))
	# A doubled rig: the same skeleton instance scaled 2x, which is the only way
	# to measure "half the height" without a second model in the repo.
	var parent := Node3D.new()
	parent.name = "MotionScaleDouble"
	scene_root.add_child(parent)
	var packed = load(DUMMY) as PackedScene
	if packed == null:
		skip("the dummy asset is missing")
		return
	var doubled := packed.instantiate()
	doubled.name = "Dummy2x"
	parent.add_child(doubled)
	for child in doubled.get_children():
		child.owner = scene_root
	doubled.owner = scene_root
	var skeleton_2x := _find_of_type(doubled, "Skeleton3D") as Skeleton3D
	var player_2x := _find_of_type(doubled, "AnimationPlayer") as AnimationPlayer
	assert_true(skeleton_2x != null and player_2x != null, "the doubled rig has a skeleton and a player")
	if skeleton_2x == null or player_2x == null:
		_remove_node("/" + str(scene_root.name) + "/MotionScaleDouble")
		_teardown(rig)
		return
	# Bone rest poses are read in SKELETON space, and `get_bone_global_rest` is
	# explicitly unaffected by the node's scale, so the rig is made taller the way
	# a real one would be: every bone's rest position pushed out along the chain.
	# That doubles the measured leg without touching the proportions.
	for index in skeleton_2x.get_bone_count():
		var bone_rest := skeleton_2x.get_bone_rest(index)
		bone_rest.origin *= 2.0
		skeleton_2x.set_bone_rest(index, bone_rest)
	var big := _handler.run({
		"op": "walk_cycle", "skeleton_path": "/" + str(scene_root.name) + "/MotionScaleDouble/Dummy2x/" + str(skeleton_2x.name),
		"player_path": "/" + str(scene_root.name) + "/MotionScaleDouble/Dummy2x/" + str(player_2x.name),
		"animation_name": "scale_2x", "duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(big.has("data"), "the doubled walk builds (%s)" % str(big.get("error", big)))
	var small_lift := _hip_bob(rig.player.get_animation("scale_1x"))
	var big_lift := _hip_bob(player_2x.get_animation("scale_2x"))
	assert_gt(small_lift, 0.0005, "the reference rig bobs (%.4f m)" % small_lift)
	# Doubling the rig must roughly double the vertical motion, not leave it at
	# the same five centimetres. (The upper bound allows for the bob channel
	# being halved inside the gait.)
	assert_true(big_lift > small_lift * 1.6,
		"a doubled rig bobs further (%.4f m vs %.4f m)" % [big_lift, small_lift])
	assert_true(big_lift < small_lift * 4.0,
		"and not absurdly further (%.4f m vs %.4f m)" % [big_lift, small_lift])
	# An explicit value is metres and is left alone.
	var explicit := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "scale_explicit",
		"duration": 1.0, "loop_mode": "linear", "overrides": {"bob": 0.5},
	}, null)
	assert_true(explicit.has("data"), "the explicit walk builds (%s)" % str(explicit.get("error", explicit)))
	var explicit_bob := _hip_bob(rig.player.get_animation("scale_explicit"))
	assert_true(explicit_bob > small_lift * 2.0,
		"an explicit bob is taken in metres (%.4f m vs the default %.4f m)"
		% [explicit_bob, small_lift])
	_remove_node("/" + str(scene_root.name) + "/MotionScaleDouble")
	_teardown(rig)


func test_generator_contract_key_times_speeds_and_determinism() -> void:
	# The generator had no direct contract tests: everything was asserted through
	# one pose at a time. These are the promises every recipe makes - the key
	# times, the marker times, the numbers it reports, that nothing is NaN, that
	# the loop closes in value AND velocity, and that the same call twice is
	# byte-identical.
	var rig := _rig("MotionContract")
	if rig.has("error"):
		skip(rig.error)
		return
	var duration := 1.6
	var rate := 12.0
	var recipes := [
		{"op": "walk_cycle", "animation_name": "c_walk", "root_motion": true, "rooted": true, "looped": true},
		{"op": "run_cycle", "animation_name": "c_run", "looped": true},
		{"op": "idle_cycle", "animation_name": "c_idle", "looped": true},
		{"op": "strafe_cycle", "animation_name": "c_strafe", "direction": "left", "looped": true},
		{"op": "jump", "animation_name": "c_jump"},
		{"op": "turn_cycle", "animation_name": "c_turn"},
	]
	# Only the LOOPING recipes have to close at the seam. A one-shot (jump, turn)
	# starts and ends at rest by design, and its recovery segment is deliberately
	# not the mirror of its anticipation.
	for recipe in recipes:
		var name := str((recipe as Dictionary)["animation_name"])
		var params: Dictionary = {
			"skeleton_path": rig.skeleton_path, "player_path": rig.player_path,
			"duration": duration, "samples": rate, "loop_mode": "linear",
		}
		for key in (recipe as Dictionary):
			if str(key) != "animation_name":
				params[str(key)] = (recipe as Dictionary)[key]
		var result := _handler.run(params, null)
		assert_true(result.has("data"), "%s builds (%s)" % [str((recipe as Dictionary)["op"]), str(result.get("error", result))])
		if not result.has("data"):
			continue
		# The clip is looked up by the name the reply reports, not the one asked
		# for: a root-motion walk names its travel clip itself.
		var clip_name := str(result.data.get("animation_name", name))
		var anim: Animation = rig.player.get_animation(clip_name)
		assert_true(anim != null, "%s produced a clip called '%s'" % [name, clip_name])
		if anim == null:
			continue
		# Key times: ascending and inside the clip. NOT every track starts at 0 -
		# a bone that only moves from the second phase of a recipe (the jump's
		# shoulder) legitimately starts later.
		for track in anim.get_track_count():
			var path := str(anim.track_get_path(track))
			var count: int = anim.track_get_key_count(track)
			if count == 0:
				continue
			var previous := -1.0
			for index in count:
				var at: float = anim.track_get_key_time(track, index)
				assert_true(at >= previous - 0.0001,
					"%s: %s key times ascend (%.4f after %.4f)" % [name, path, at, previous])
				previous = at
			assert_true(previous <= anim.length + 0.001,
				"%s: %s ends inside the clip (%.4f <= %.4f)" % [name, path, previous, anim.length])
		# Every keyed value is finite: a NaN silently poisons playback.
		for track in anim.get_track_count():
			for index in anim.track_get_key_count(track):
				var value = anim.track_get_key_value(track, index)
				var text := str(value)
				if text.contains("nan") or text.contains("inf"):
					assert_true(false, "%s: %s key %d is not finite (%s)"
						% [name, str(anim.track_get_path(track)), index, text])
					break
		# Reported numbers.
		if result.data.has("duration"):
			assert_true(float(result.data.duration) > 0.0, "%s reports its duration" % name)
		if result.data.has("speed"):
			assert_true(float(result.data.speed) >= 0.0, "%s reports a speed" % name)
		if result.data.has("stride_used"):
			assert_true(float(result.data.stride_used) > 0.0, "%s reports the stride it used" % name)
		# Markers: the reply reports a COUNT, so the times are checked on the clip
		# that was actually committed - inside the clip, in order, and the count
		# matching.
		assert_true(int(result.data.get("markers", 0)) >= 0, "%s reports its marker count" % name)
		var committed_markers: PackedStringArray = anim.get_marker_names()
		assert_eq(committed_markers.size(), int(result.data.get("markers", 0)),
			"%s: the committed markers match the reported count" % name)
		var previous_marker := -1.0
		for marker_name in committed_markers:
			var at: float = anim.get_marker_time(marker_name)
			assert_true(at >= -0.0001 and at <= anim.length + 0.0001,
				"%s: marker '%s' at %.4f is inside the clip" % [name, str(marker_name), at])
			assert_true(at >= previous_marker - 0.0001,
				"%s: marker '%s' is in order" % [name, str(marker_name)])
			previous_marker = at
		# The loop closes in VALUE and in VELOCITY: a clip whose ends match but
		# whose slopes differ pops at the seam.
		for track in anim.get_track_count():
			if anim.track_get_key_count(track) < 3:
				continue
			var last_index: int = anim.track_get_key_count(track) - 1
			var first_value = anim.track_get_key_value(track, 0)
			var last_value = anim.track_get_key_value(track, last_index)
			if first_value is Quaternion:
				var a: Quaternion = first_value
				var b: Quaternion = last_value
				# Only a looping recipe has to come back to where it started. A
				# one-shot keeps its own endpoint (`_mark_one_shot`), so its ends
				# differing is the contract, not a defect.
				if not bool((recipe as Dictionary).get("looped", false)):
					continue
				assert_true(absf(a.angle_to(b)) < 0.02,
					"%s: %s closes in value (%.4f rad apart)" % [name, str(anim.track_get_path(track)), a.angle_to(b)])
				# Velocity has to close too on an in-place loop, or the clip pops at
				# the seam. A ROOTED clip is exempt: the leg reaches a different
				# world point each cycle, so its seam velocity is legitimately
				# different - the travel is the point.
				if not bool((recipe as Dictionary).get("looped", false)) \
						or bool((recipe as Dictionary).get("rooted", false)):
					continue
				var a2: Quaternion = anim.track_get_key_value(track, 1)
				var b2: Quaternion = anim.track_get_key_value(track, last_index - 1)
				var v_first := a2.angle_to(a)
				var v_last := b.angle_to(b2)
				# Judged against the track's own motion rather than an absolute
				# number: a seam step is a pop when it is out of scale with the
				# fastest step inside the clip.
				var fastest := 0.0
				for index in range(1, last_index - 1):
					var here: Quaternion = anim.track_get_key_value(track, index)
					var next: Quaternion = anim.track_get_key_value(track, index + 1)
					fastest = maxf(fastest, here.angle_to(next))
				# A seam where the track arrives early and holds (a planted foot, which
				# is genuinely the same value at both ends) is a shape, not a pop, so
				# only a mismatch between two MOVING ends is one.
				if v_last < 0.0005 or v_first < 0.0005:
					continue
				assert_true(absf(v_first - v_last) <= 0.75 * fastest + 0.002,
					"%s: %s closes in velocity (%.4f vs %.4f, fastest interior step %.4f)"
					% [name, str(anim.track_get_path(track)), v_first, v_last, fastest])
			elif first_value is Vector3:
				var a: Vector3 = first_value
				var b: Vector3 = last_value
				# A ROOTED clip (root motion) must NOT close: the hips travel a stride
				# forward and that travel IS the root motion. Closing it would cancel
				# the movement the caller asked for. Everything else still has to.
				var travels: bool = bool((recipe as Dictionary).get("rooted", false)) \
					and str(anim.track_get_path(track)).ends_with(":B-hips")
				if travels:
					assert_true(a.distance_to(b) > 0.01,
						"%s: %s keeps its travel instead of closing (%.4f m)"
						% [name, str(anim.track_get_path(track)), a.distance_to(b)])
					continue
				if not bool((recipe as Dictionary).get("looped", false)):
					continue
				assert_true(a.distance_to(b) < 0.005,
					"%s: %s closes in value (%.4f m apart)" % [name, str(anim.track_get_path(track)), a.distance_to(b)])
				var a2: Vector3 = anim.track_get_key_value(track, 1)
				var b2: Vector3 = anim.track_get_key_value(track, last_index - 1)
				var step_first := a.distance_to(a2)
				var step_last := b.distance_to(b2)
				assert_true(absf(step_first - step_last) < 0.005,
					"%s: %s closes in step size (%.4f vs %.4f)"
					% [name, str(anim.track_get_path(track)), step_first, step_last])
		# Determinism: the SAME call again, as its own clip, must be identical. This
		# is the "generate twice" contract - not the overwrite-in-place path, which
		# is a different question about the existing clip.
		var twice_params: Dictionary = params.duplicate()
		twice_params["animation_name"] = clip_name + "_twice"
		var twice := _handler.run(twice_params, null)
		assert_true(twice.has("data"), "%s rebuilds (%s)" % [name, str(twice.get("error", twice))])
		if not twice.has("data"):
			continue
		var rebuilt: Animation = rig.player.get_animation(clip_name + "_twice")
		assert_true(rebuilt != null, "%s produced a second clip" % name)
		if rebuilt == null:
			continue
		assert_eq(rebuilt.get_track_count(), anim.get_track_count(),
			"%s: the same call produces the same track count" % name)
		for track in mini(rebuilt.get_track_count(), anim.get_track_count()):
			assert_eq(rebuilt.track_get_key_count(track), anim.track_get_key_count(track),
				"%s: %s rebuilds with the same key count" % [name, str(anim.track_get_path(track))])
			for index in mini(rebuilt.track_get_key_count(track), anim.track_get_key_count(track)):
				var before = anim.track_get_key_value(track, index)
				var after = rebuilt.track_get_key_value(track, index)
				if before is Quaternion:
					# Not bit-exact: the solve chain is float end to end, and the
					# observed drift between two builds is ~1e-4 rad. A real
					# non-determinism (an unseeded noise channel, a stateful input)
					# would be orders of magnitude larger than this.
					var gap := (before as Quaternion).angle_to(after as Quaternion)
					assert_true(gap < 0.001,
						"%s: %s key %d (t=%.4f) matches on a rebuild (%.6f rad apart)"
						% [name, str(anim.track_get_path(track)), index,
							anim.track_get_key_time(track, index), gap])
				elif before is Vector3:
					var gap_m := (before as Vector3).distance_to(after as Vector3)
					assert_true(gap_m < 0.0001,
						"%s: %s key %d (t=%.4f) matches on a rebuild (%.6f m apart)"
						% [name, str(anim.track_get_path(track)), index,
							anim.track_get_key_time(track, index), gap_m])
	_teardown(rig)


func test_real_playback_interpolates_wraps_and_matches_the_data() -> void:
	# Every other test in this suite applies the NEAREST key to the skeleton by
	# hand, so nothing has ever checked what the engine actually plays: the
	# interpolation between keys, the wrap at the end of a looping clip, or that
	# the pose on screen is the pose the data describes. This one lets the real
	# AnimationPlayer do the work.
	var rig := _rig("MotionPlayback")
	if rig.has("error"):
		skip(rig.error)
		return
	var player: AnimationPlayer = rig.player
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "play_walk",
		"duration": 1.0, "loop_mode": "linear", "samples": 8.0,
	}, null)
	assert_true(built.has("data"), "the walk builds (%s)" % str(built.get("error", built)))
	var anim: Animation = player.get_animation("play_walk")
	assert_true(anim != null and anim.get_track_count() > 0, "the clip has tracks")
	if anim == null:
		_teardown(rig)
		return
	var bone := "B-thigh.L"
	var track := _track_index(anim, ":" + bone, Animation.TYPE_ROTATION_3D)
	assert_true(track >= 0, "%s has a rotation track" % bone)
	if track < 0:
		_teardown(rig)
		return
	# play() + seek(update=true) + advance(0) is the documented way to make the
	# player evaluate a time immediately, without waiting for a frame. The blend
	# time goes to zero first: with the default blend, the first evaluations are a
	# partial weight and the pose is not yet the clip's.
	var blend: float = player.playback_default_blend_time
	player.playback_default_blend_time = 0.0
	player.play("play_walk")
	player.seek(0.0, true)
	player.advance(0.0)
	# 1. Mid-key sampling is INTERPOLATED, not snapped: the played value at a time
	# between two keys differs from both of them. Under the nearest-key helper this
	# was impossible to see.
	var a: Quaternion = anim.track_get_key_value(track, 0)
	var b: Quaternion = anim.track_get_key_value(track, 1)
	if absf(a.angle_to(b)) > 0.01:
		var mid_time: float = (anim.track_get_key_time(track, 0) + anim.track_get_key_time(track, 1)) * 0.5
		player.seek(mid_time, true)
		player.advance(0.0)
		var index: int = rig.skeleton.find_bone(bone)
		var played: Quaternion = rig.skeleton.get_bone_pose_rotation(index)
		var expected: Quaternion = anim.rotation_track_interpolate(track, mid_time)
		# Not bit-exact, and it cannot be: the played value comes back through the
		# skeleton's pose application, which normalises the local rotation against
		# the bone chain. The measured gap is ~7e-4 rad, so 2e-3 is the engine's
		# real guarantee - well under a hundredth of a degree.
		assert_true(played.angle_to(expected) < 0.002,
			"the played %s at t=%.4f is the clip's own interpolation (%.5f rad apart)"
			% [bone, mid_time, played.angle_to(expected)])
		var from_first := played.angle_to(a)
		var from_second := played.angle_to(b)
		var span := a.angle_to(b)
		assert_true(from_first < span * 0.98 and from_second < span * 0.98,
			"the mid-key value is BETWEEN its keys, not snapped to one (%.4f / %.4f of %.4f)"
			% [from_first, from_second, span])
	# 2. What plays is what the data says, at several times across the clip.
	for step in 9:
		var at: float = anim.length * float(step) / 8.0
		player.seek(at, true)
		player.advance(0.0)
		var index: int = rig.skeleton.find_bone(bone)
		var played: Quaternion = rig.skeleton.get_bone_pose_rotation(index)
		var expected: Quaternion = anim.rotation_track_interpolate(track, at)
		assert_true(played.angle_to(expected) < 0.002,
			"t=%.4f: the played %s matches the clip (%.5f rad apart)" % [at, bone, played.angle_to(expected)])
	# 3. A looping clip WRAPS rather than clamping: past the end, playback is back
	# at the start of the cycle.
	player.seek(anim.length + 0.05, true)
	player.advance(0.0)
	var wrapped: Quaternion = rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(bone))
	player.seek(0.05, true)
	player.advance(0.0)
	var wrapped_again: Quaternion = rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(bone))
	assert_true(wrapped.angle_to(wrapped_again) < 0.001,
		"seeking past the end wraps into the cycle (%.5f rad apart)" % wrapped.angle_to(wrapped_again))
	# 4. The seam is continuous under real playback: the step across the wrap is no
	# bigger than the biggest step inside the clip (a pop would dwarf it).
	player.seek(anim.length - 0.001, true)
	player.advance(0.0)
	var before_wrap: Quaternion = rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone(bone))
	var seam := before_wrap.angle_to(wrapped)
	var biggest := 0.0
	for index in range(1, anim.track_get_key_count(track)):
		var first: Quaternion = anim.track_get_key_value(track, index - 1)
		var second: Quaternion = anim.track_get_key_value(track, index)
		biggest = maxf(biggest, first.angle_to(second))
	assert_true(seam <= biggest * 1.35 + 0.01,
		"the loop seam is no bigger than the motion inside the clip (%.4f vs %.4f)" % [seam, biggest])
	player.stop()
	player.playback_default_blend_time = blend
	player.seek(0.0, true)
	player.advance(0.0)
	_teardown(rig)


func test_chain_bones_outside_the_roles_use_their_own_rest_pose() -> void:
	# The rest map covered the ROLE bones only, so a bone the spine detector found
	# but no role names - a neck, an upper chest - was keyed against an IDENTITY
	# rest pose. That turns a small rest-relative delta into a rotation by the
	# bone's whole rest orientation, which is tens of degrees. Any keyed bone that
	# is not a role has to stay small.
	var rig := _rig("MotionRestMap")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "rest_map_walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the walk builds (%s)" % str(built.get("error", built)))
	var anim: Animation = rig.player.get_animation("rest_map_walk")
	assert_true(anim != null, "the clip exists")
	if anim == null:
		_teardown(rig)
		return
	# The dummy's role bones (named the same way the rest of this suite names
	# them). Anything else the clip keys came from the spine detector.
	var driven := [
		"B-hips", "B-thigh.L", "B-shin.L", "B-foot.L", "B-toe.L",
		"B-thigh.R", "B-shin.R", "B-foot.R", "B-toe.R",
		"B-spine", "B-chest", "B-head", "B-jaw",
		"B-upperArm.L", "B-forearm.L", "B-hand.L",
		"B-upperArm.R", "B-forearm.R", "B-hand.R",
	]
	var checked: Array = []
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(anim.track_get_path(track)).get_slice(":", 1)
		if driven.has(bone) or bone.is_empty():
			continue
		# A chain bone outside the roles: its swing must be a motion, not the
		# bone's rest orientation applied as a delta.
		var spread := _spread(anim, track)
		checked.append(bone)
		assert_true(spread < 0.6,
			"%s is keyed and moves %.3f rad - an identity rest fallback would be far more"
			% [bone, spread])
	assert_gt(checked.size(), 0,
		"the clip keys at least one chain bone outside the roles (%s)" % ", ".join(checked))
	_teardown(rig)


func test_the_walk_matches_its_golden() -> void:
	# The golden is a quantized digest of one walk clip, committed, so a change to
	# the generator shows up as a NUMBER instead of "it looks a bit different".
	# Quantizing is what gives the comparison an explicit tolerance: one step is
	# 1/2048 of the unit, so float noise cannot fail it and a real change cannot
	# hide. Missing file means "record it" - that is how the fixture was created.
	var rig := _rig("MotionGolden")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "golden_walk",
		"duration": 1.0, "loop_mode": "linear", "samples": 8.0,
	}, null)
	assert_true(built.has("data"), "the walk builds (%s)" % str(built.get("error", built)))
	var anim: Animation = rig.player.get_animation("golden_walk")
	assert_true(anim != null and anim.get_track_count() > 0, "the clip has tracks")
	if anim == null:
		_teardown(rig)
		return
	var digest := _clip_digest(anim)
	var path := "res://tests/fixtures/golden_walk.json"
	if not FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert_true(file != null, "the golden could be created (%s)" % str(FileAccess.get_open_error()))
		if file != null:
			file.store_string(JSON.stringify(digest, "  "))
			file.close()
			print("  recorded %s (%d tracks)" % [path, (digest.tracks as Array).size()])
		_teardown(rig)
		return
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(golden is Dictionary and golden.has("tracks"), "the golden parses")
	if not (golden is Dictionary) or not golden.has("tracks"):
		_teardown(rig)
		return
	assert_eq(float(golden.length), snappedf(anim.length, 0.0001),
		"the golden's clip length still matches")
	var golden_tracks: Array = golden.tracks
	var fresh_tracks: Array = digest.tracks
	assert_eq(fresh_tracks.size(), golden_tracks.size(),
		"the walk keys the same number of tracks (%d vs %d)"
		% [fresh_tracks.size(), golden_tracks.size()])
	if fresh_tracks.size() == golden_tracks.size():
		var worst := 0
		var worst_where := ""
		for index in fresh_tracks.size():
			var fresh: Dictionary = fresh_tracks[index]
			var old: Dictionary = golden_tracks[index]
			if str(fresh.bone) != str(old.bone):
				assert_true(false, "track %d is %s, the golden says %s" % [index, str(fresh.bone), str(old.bone)])
				continue
			var fresh_keys: Array = fresh.keys
			var old_keys: Array = old.keys
			if fresh_keys.size() != old_keys.size():
				assert_true(false, "%s has %d keys, the golden has %d"
					% [str(fresh.bone), fresh_keys.size(), old_keys.size()])
				continue
			for key_index in fresh_keys.size():
				# An integer step of difference is one quantization unit per
				# component, so 1 means "as close as this digest can see".
				var gap: int = 0
				for component in (fresh_keys[key_index] as Array).size():
					gap = maxi(gap, absi(int((fresh_keys[key_index] as Array)[component])
						- int((old_keys[key_index] as Array)[component])))
				if gap > worst:
					worst = gap
					worst_where = "%s key %d" % [str(fresh.bone), key_index]
		assert_true(worst <= 2,
			"the walk still matches its golden (worst drift %d units at %s; 1 unit = 1/2048)"
			% [worst, worst_where])
	_teardown(rig)


## A quantized, comparable digest of a clip: sorted tracks, and every key as
## integers (quaternions scaled by 2048, vectors the same). Quaternion sign is
## normalised first, because q and -q are the same rotation and the engine is
## free to store either.
func _clip_digest(anim: Animation) -> Dictionary:
	const SCALE := 2048
	var tracks: Array = []
	for track in anim.get_track_count():
		var kind := anim.track_get_type(track)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var path := str(anim.track_get_path(track))
		var bone := path.get_slice(":", 1)
		if bone.is_empty():
			continue
		var values: Array = []
		for index in anim.track_get_key_count(track):
			var value = anim.track_get_key_value(track, index)
			if value is Quaternion:
				var q: Quaternion = value
				if q.w < 0.0:
					q = Quaternion(-q.x, -q.y, -q.z, -q.w)
				values.append([q.x, q.y, q.z, q.w].map(
					func(v: float) -> int: return roundi(v * SCALE)))
			else:
				var v3: Vector3 = value
				values.append([v3.x, v3.y, v3.z].map(
					func(v: float) -> int: return roundi(v * SCALE)))
		tracks.append({"bone": bone, "type": kind, "keys": values})
	tracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.bone) < str(b.bone))
	return {"length": snappedf(anim.length, 0.0001), "scale": SCALE, "tracks": tracks}


## Peak travel of the hips track measured along one axis, in metres.
func _hip_travel(anim: Animation, axis: Vector3) -> float:
	var track := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	if track < 0:
		return 0.0
	var lowest := INF
	var highest := -INF
	for index in anim.track_get_key_count(track):
		var value: Vector3 = anim.track_get_key_value(track, index)
		var along: float = value.dot(axis)
		lowest = minf(lowest, along)
		highest = maxf(highest, along)
	return highest - lowest


## Peak vertical travel of the hips track, in metres: the bob.
func _hip_bob(anim: Animation) -> float:
	var track := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	if track < 0:
		return 0.0
	var lowest := INF
	var highest := -INF
	for index in anim.track_get_key_count(track):
		var value: Vector3 = anim.track_get_key_value(track, index)
		lowest = minf(lowest, value.y)
		highest = maxf(highest, value.y)
	return highest - lowest


func test_lean_is_shared_over_the_spine_not_repeated_per_bone() -> void:
	# Every torso bone used to take the FULL lean, so a long spine folded N times
	# as much as a short one and `lean` meant something different on every rig.
	# Measuring the DIFFERENCE against a lean-less clip isolates the lean from the
	# sway/twist channels that share the same bones.
	var rig := _rig("MotionLean")
	if rig.has("error"):
		skip(rig.error)
		return
	for lean_degrees in [9.0, 18.0]:
		var with_lean := _handler.run({
			"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
			"player_path": rig.player_path, "animation_name": "lean_%d" % int(lean_degrees),
			"duration": 1.0, "loop_mode": "linear", "lean": lean_degrees,
		}, null)
		assert_true(with_lean.has("data"), "the walk builds (%s)" % str(with_lean.get("error", with_lean)))
	var flat := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "lean_flat",
		"duration": 1.0, "loop_mode": "linear", "lean": 0.0,
	}, null)
	assert_true(flat.has("data"), "the lean-less walk builds (%s)" % str(flat.get("error", flat)))
	var baseline: Animation = rig.player.get_animation("lean_flat")
	var results: Array = []
	for lean_degrees in [9.0, 18.0]:
		var anim: Animation = rig.player.get_animation("lean_%d" % int(lean_degrees))
		var torso := 0.0
		var counted: Array = []
		for bone in ["B-spine", "B-chest", "B-upperChest", "B-neck"]:
			var index := _track_index(anim, ":" + str(bone), Animation.TYPE_ROTATION_3D)
			if index < 0:
				continue
			counted.append(str(bone))
			torso += _lateral_delta(anim, index, baseline)
		assert_true(counted.size() >= 2,
			"a few torso bones carry the lean (%s)" % ", ".join(counted))
		# The total across the torso is the requested lean - not the lean times the
		# number of bones.
		var want := deg_to_rad(lean_degrees)
		assert_true(absf(torso - want) < want * 0.35,
			"a %d degree lean folds %.2f degrees across the torso (%.2f wanted)"
			% [int(lean_degrees), rad_to_deg(torso), lean_degrees])
		results.append(torso)
	if results.size() == 2:
		# Twice the lean, twice the fold: a per-bone copy would have doubled per
		# bone and quadrupled on a two-bone chain... it must scale linearly.
		assert_true(absf((results[1] as float) - 2.0 * (results[0] as float)) < 0.02,
			"the fold scales linearly with the request (%.3f vs %.3f)"
			% [results[1] as float, 2.0 * (results[0] as float)])
	_teardown(rig)


## How far `lean` tilted one bone sideways, as a difference against the same
## clip built with no lean at all (both at their first key, where the lean is a
## constant offset).
func _lateral_delta(anim: Animation, track: int, baseline: Animation) -> float:
	var path := anim.track_get_path(track)
	var reference := -1
	for index in baseline.get_track_count():
		if baseline.track_get_path(index) == path \
				and baseline.track_get_type(index) == Animation.TYPE_ROTATION_3D:
			reference = index
			break
	if reference < 0:
		return 0.0
	var here: Quaternion = anim.track_get_key_value(track, 0)
	var there: Quaternion = baseline.track_get_key_value(reference, 0)
	return absf(_lateral_angle(here * there.inverse()))


## The signed angle of `delta` about the world lateral axis, in radians.
func _lateral_angle(delta: Quaternion) -> float:
	if absf(delta.w) >= 0.999999:
		return 0.0
	var axis := Vector3(delta.x, delta.y, delta.z)
	if axis.length_squared() <= 0.000001:
		return 0.0
	return 2.0 * acos(clampf(delta.w, -1.0, 1.0)) \
		* signf(axis.normalized().dot(Vector3(1, 0, 0)))


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
	assert_true(chest >= 0, "the chest twists")
	var chest_spread := _spread(anim, chest)
	assert_gt(chest_spread, 0.15, "the torso twist is pronounced (%s rad)" % chest_spread)
	assert_true(chest_spread < 0.6, "the twist stays a twist (%s rad)" % chest_spread)
	var head := _track_index(anim, ":B-head", Animation.TYPE_ROTATION_3D)
	assert_true(head >= 0, "the head looks around")
	var head_spread := _spread(anim, head)
	assert_gt(head_spread, 0.25, "the look-around is pronounced (%s rad)" % head_spread)
	assert_true(head_spread < 1.0, "the head does not spin (%s rad)" % head_spread)
	assert_true(_track_index(anim, ":B-jaw", Animation.TYPE_ROTATION_3D) < 0, "the idle never touches the jaw")
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


# --- character setup --------------------------------------------------------

func test_character_setup_builds_clips_and_tree() -> void:
	var rig := _rig("Setup")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "character_setup", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"speed": 1.4, "run_speed": 4.0, "include_jump": true, "include_turn": true,
	}, null)
	assert_true(result.has("data"), "character_setup: %s" % str(result))
	for clip in ["idle", "walk", "run", "jump", "turn_left"]:
		assert_true(rig.player.has_animation(clip), "the %s clip exists" % clip)
	assert_eq(str(result.data.speed_parameter), "parameters/Base/blend_position",
		"the speed parameter points into the wrapped blend space")
	assert_eq(str(result.data.jump_request_parameter), "parameters/OneShot/request",
		"the jump request parameter is reported")
	assert_true(float(result.data.speed_values.walk) == 1.4 and float(result.data.speed_values.run) == 4.0,
		"the blend space positions are the clip speeds")
	assert_true(str(rig.player.root_motion_track).ends_with(":B-hips"), "root motion is wired")
	var scene_root := EditorInterface.get_edited_scene_root()
	var tree := _find_of_type(rig.player.get_parent(), "AnimationTree") as AnimationTree
	assert_true(tree != null, "an AnimationTree is created next to the player")
	if tree != null:
		assert_true(tree.tree_root is AnimationNodeBlendTree, "the jump layer wraps the blend space")
		assert_true(tree.get_node_or_null(tree.anim_player) == rig.player, "the tree is wired to the player")
		assert_true(str(tree.root_motion_track).ends_with(":B-hips"), "the tree carries the root motion track")
	assert_true(str(result.data.apply_snippet).contains("blend_position"), "a game-side snippet is returned")
	# One undo removes the clips, the root motion track and the tree together.
	assert_true(editor_undo(_undo_redo), "undo should succeed")
	for clip in ["idle", "walk", "run", "jump", "turn_left"]:
		assert_true(rig.player.get_animation(clip) == null, "undo removed the %s clip" % clip)
	assert_true(str(rig.player.root_motion_track).is_empty(), "undo cleared the root motion track")
	assert_true(_find_of_type(rig.player.get_parent(), "AnimationTree") == null,
		"undo removed the created tree")
	_teardown(rig)


func test_character_setup_defaults_and_validation() -> void:
	var rig := _rig("SetupPlain")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "character_setup", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
	}, null)
	assert_true(result.has("data"), "character_setup with defaults: %s" % str(result))
	assert_eq(str(result.data.speed_parameter), "parameters/blend_position",
		"without jump the blend space is the tree root (got %s)" % str(result.data.speed_parameter))
	assert_eq(str(result.data.jump_request_parameter), "", "no jump layer means no request parameter")
	var tree := _find_of_type(rig.player.get_parent(), "AnimationTree") as AnimationTree
	assert_true(tree != null and tree.tree_root is AnimationNodeBlendSpace1D,
		"the default tree root is the blend space")
	assert_true(rig.player.get_animation("jump") == null, "jump is opt-in")
	assert_true(rig.player.get_animation("turn_left") == null, "turn is opt-in")
	var bad_speeds := _handler.run({
		"op": "character_setup", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"speed": 4.0, "run_speed": 2.0,
	}, null)
	assert_is_error(bad_speeds, ErrorCodes.VALUE_OUT_OF_RANGE)
	_teardown(rig)
