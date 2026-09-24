@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const RigHandler := preload("res://addons/godot_ai_animation/handlers/rig.gd")

const DUMMY := "res://models/human_dummy/HumanCharacterDummy_F.fbx"
const POSE_FILE := "res://tests/tmp_pose.json"
const POSE_DIR := "res://tests/tmp_poses"
const POSE_DIR_PARAM := {"pose_dir": POSE_DIR}

## Tests for the animation_rig tool (Phase 6a: poses, pose clips, rig dump).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: RigHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_rig"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = RigHandler.new()


func suite_teardown() -> void:
	_cleanup_files()


# --- helpers ---------------------------------------------------------------

func _cleanup_files() -> void:
	if FileAccess.file_exists(POSE_FILE):
		DirAccess.remove_absolute(POSE_FILE)
	var dir := DirAccess.open(POSE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute("%s/%s" % [POSE_DIR, file_name])
			file_name = dir.get_next()
		dir.list_dir_end()


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _scene_root_name() -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	return scene_root.name if scene_root != null else ""


func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owners(child, owner)


func _find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


## Instance the human dummy into the scene and locate its rig.
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


func _teardown(rig: Dictionary) -> void:
	if rig.has("root_path"):
		_remove_node(rig.root_path)
	_cleanup_files()


## Rest-relative rotation angle of a bone (0 = at rest).
func _bone_angle(skeleton: Skeleton3D, bone: String) -> float:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return 0.0
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	return (rest.inverse() * skeleton.get_bone_pose_rotation(index)).get_angle()


## Index of the first track with this bone suffix and type, or -1.
func _track_index(anim: Animation, suffix: String, type: int) -> int:
	for index in anim.get_track_count():
		if anim.track_get_type(index) == type and str(anim.track_get_path(index)).ends_with(suffix):
			return index
	return -1


## Direction of a bone's local Y (skeleton space) for a full local pose value.
func _dir_of(skeleton: Skeleton3D, parent: int, value: Quaternion) -> Vector3:
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		parent_basis = skeleton.get_bone_global_rest(parent).basis
	return (parent_basis * Basis(value) * Vector3.UP).normalized()


## Rotate a bone relative to its rest (so the rest-relative angle equals `angle`).
func _rotate_bone(skeleton: Skeleton3D, bone: String, angle: float) -> void:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(index, (rest * Quaternion(Vector3(0, 1, 0), angle)).normalized())


## A tiny 2D rig: Skeleton2D with two Bone2D children, built detached then added.
func _rig_2d(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	var skeleton := Skeleton2D.new()
	skeleton.name = prefix + "Skeleton2D"
	var upper := Bone2D.new()
	upper.name = "bone_upper"
	upper.rest = Transform2D(0.0, Vector2(0, 0))
	upper.position = Vector2(0, 0)
	upper.set_length(40.0)
	skeleton.add_child(upper)
	var lower := Bone2D.new()
	lower.name = "bone_lower"
	lower.rest = Transform2D(0.0, Vector2(0, 40))
	lower.position = Vector2(0, 40)
	lower.set_length(40.0)
	upper.add_child(lower)
	scene_root.add_child(skeleton)
	skeleton.owner = scene_root
	upper.owner = scene_root
	lower.owner = scene_root
	return {
		"root_path": "/" + scene_root.name + "/" + prefix + "Skeleton2D",
		"skeleton_path": "/" + scene_root.name + "/" + prefix + "Skeleton2D",
		"skeleton": skeleton,
	}


# --- rollup ----------------------------------------------------------------

func test_rollup_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "levitate"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "pose_save")
	assert_contains(unknown.error.message, "rig_get")


# --- pose_save -------------------------------------------------------------

func test_pose_save_captures_rest_and_pose() -> void:
	var rig := _rig("RigSave")
	if rig.has("error"):
		skip(rig.error)
		return
	var rest := _handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path}, null)
	assert_true(rest.has("data"), "expected data, got: %s" % str(rest))
	assert_eq(int(rest.data.bone_count), 56, "the dummy has 56 bones")
	assert_eq(str(rest.data.kind), "3d")
	var hips: Dictionary = rest.data.pose.bones["B-hips"]
	assert_true(absf(float(hips.rotation.w)) > 0.999, "a rest pose has an identity hips delta")
	_rotate_bone(rig.skeleton, "B-upperArm.L", PI / 4.0)
	var posed := _handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path}, null)
	assert_true(posed.has("data"), "expected data, got: %s" % str(posed))
	var arm: Dictionary = posed.data.pose.bones["B-upperArm.L"]
	var delta := Quaternion(arm.rotation.x, arm.rotation.y, arm.rotation.z, arm.rotation.w)
	assert_true(absf(delta.get_angle() - PI / 4.0) < 0.01,
		"the captured delta reflects the posed rotation (%s)" % str(delta.get_angle()))
	_teardown(rig)


func test_pose_save_and_apply_round_trip() -> void:
	var rig := _rig("RigApply")
	if rig.has("error"):
		skip(rig.error)
		return
	_rotate_bone(rig.skeleton, "B-upperArm.L", PI / 3.0)
	var saved := _handler.run({
		"op": "pose_save", "skeleton_path": rig.skeleton_path, "path": POSE_FILE, "overwrite": true,
	}, null)
	assert_true(saved.has("data"), "expected data, got: %s" % str(saved))
	assert_true(FileAccess.file_exists(POSE_FILE), "the pose file is written")
	_rotate_bone(rig.skeleton, "B-upperArm.L", 0.0)
	assert_true(_bone_angle(rig.skeleton, "B-upperArm.L") < 0.001, "the bone is reset before applying")
	var applied := _handler.run({
		"op": "pose_apply", "skeleton_path": rig.skeleton_path, "path": POSE_FILE,
	}, null)
	assert_true(applied.has("data"), "expected data, got: %s" % str(applied))
	assert_eq(int(applied.data.bone_count), 56, "every bone is applied")
	assert_true(absf(_bone_angle(rig.skeleton, "B-upperArm.L") - PI / 3.0) < 0.01,
		"the applied pose restores the rotation (%s)" % _bone_angle(rig.skeleton, "B-upperArm.L"))
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(_bone_angle(rig.skeleton, "B-upperArm.L") < 0.001,
		"one undo restores the previous pose (%s)" % _bone_angle(rig.skeleton, "B-upperArm.L"))
	_teardown(rig)


func test_pose_apply_blend_and_mirror() -> void:
	var rig := _rig("RigBlend")
	if rig.has("error"):
		skip(rig.error)
		return
	_rotate_bone(rig.skeleton, "B-upperArm.L", PI / 2.0)
	_handler.run({
		"op": "pose_save", "skeleton_path": rig.skeleton_path, "path": POSE_FILE, "overwrite": true,
	}, null)
	_rotate_bone(rig.skeleton, "B-upperArm.L", 0.0)
	var half := _handler.run({
		"op": "pose_apply", "skeleton_path": rig.skeleton_path, "path": POSE_FILE, "blend": 0.5,
	}, null)
	assert_true(half.has("data"), "expected data, got: %s" % str(half))
	assert_true(absf(_bone_angle(rig.skeleton, "B-upperArm.L") - PI / 4.0) < 0.02,
		"blend 0.5 lands halfway (%s)" % _bone_angle(rig.skeleton, "B-upperArm.L"))
	var mirrored := _handler.run({
		"op": "pose_apply", "skeleton_path": rig.skeleton_path, "path": POSE_FILE,
		"mirror": true, "reset_first": true,
	}, null)
	assert_true(mirrored.has("data"), "expected data, got: %s" % str(mirrored))
	assert_true(absf(_bone_angle(rig.skeleton, "B-upperArm.R") - PI / 2.0) < 0.02,
		"mirroring moves the rotation to the right arm (%s)" % _bone_angle(rig.skeleton, "B-upperArm.R"))
	assert_true(_bone_angle(rig.skeleton, "B-upperArm.L") < 0.02,
		"the left arm returns to rest (%s)" % _bone_angle(rig.skeleton, "B-upperArm.L"))
	_teardown(rig)


# --- pose_blend ------------------------------------------------------------

func test_pose_blend_op() -> void:
	var rig := _rig("RigMix")
	if rig.has("error"):
		skip(rig.error)
		return
	_rotate_bone(rig.skeleton, "B-upperArm.L", PI / 4.0)
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "up", "overwrite": true}, null)
	_rotate_bone(rig.skeleton, "B-upperArm.L", -PI / 4.0)
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "down", "overwrite": true}, null)
	var mixed := _handler.run({
		"op": "pose_blend", "from": "up", "to": "down", "factor": 0.5, "name": "mid", "pose_dir": POSE_DIR, "overwrite": true,
	}, null)
	assert_true(mixed.has("data"), "expected data, got: %s" % str(mixed))
	assert_eq(int(mixed.data.bone_count), 56)
	var quarter := _handler.run({
		"op": "pose_blend", "from": "up", "to": "down", "factor": 0.25, "pose_dir": POSE_DIR,
	}, null)
	assert_true(quarter.has("data"), "expected data, got: %s" % str(quarter))
	var applied := _handler.run({
		"op": "pose_apply", "skeleton_path": rig.skeleton_path, "name": "mid", "pose_dir": POSE_DIR, "reset_first": true,
	}, null)
	assert_true(applied.has("data"), "expected data, got: %s" % str(applied))
	assert_true(_bone_angle(rig.skeleton, "B-upperArm.L") < 0.02,
		"blending opposites at 0.5 cancels out (%s)" % _bone_angle(rig.skeleton, "B-upperArm.L"))
	var listed := _handler.run({"op": "pose_list", "directory": POSE_DIR}, null)
	assert_true(listed.has("data"), "expected data, got: %s" % str(listed))
	assert_true(int(listed.data.pose_count) >= 3, "saved poses are listed (%d)" % int(listed.data.pose_count))
	var missing := _handler.run({
		"op": "pose_blend", "from": "ghost_pose", "to": "up", "pose_dir": POSE_DIR,
	}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


# --- pose_to_clip ----------------------------------------------------------

func test_pose_to_clip_builds_lean_clip() -> void:
	var rig := _rig("RigClip")
	if rig.has("error"):
		skip(rig.error)
		return
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "rest_pose", "overwrite": true}, null)
	_rotate_bone(rig.skeleton, "B-upperArm.L", PI / 2.0)
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "arm_up", "overwrite": true}, null)
	var result := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": rig.player_path,
		"skeleton_path": rig.skeleton_path,
		"animation_name": "wave",
		"loop_mode": "linear",
		"keys": [
			{"name": "rest_pose", "time": 0.0},
			{"name": "arm_up", "time": 0.5, "transition": "ease_in_out"},
			{"name": "rest_pose", "time": 1.0},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.track_count), 1,
		"only the moving bone gets a track (%d)" % int(result.data.track_count))
	assert_true(is_equal_approx(float(result.data.length), 1.0), "the clip length follows the last key")
	var anim: Animation = rig.player.get_animation("wave")
	assert_true(anim != null, "the clip exists")
	assert_true(str(anim.track_get_path(0)).ends_with(":B-upperArm.L"),
		"the track names the posed bone (%s)" % str(anim.track_get_path(0)))
	assert_eq(anim.track_get_type(0), Animation.TYPE_ROTATION_3D, "bone tracks are rotation tracks")
	assert_eq(anim.track_get_key_count(0), 3)
	var peak: Quaternion = anim.track_get_key_value(0, 1)
	var rest: Quaternion = rig.skeleton.get_bone_rest(rig.skeleton.find_bone("B-upperArm.L")).basis.get_rotation_quaternion()
	var peak_delta: float = (rest.inverse() * peak).get_angle()
	assert_true(absf(peak_delta - PI / 2.0) < 0.02,
		"the keyed rotation matches the pose delta (%s)" % peak_delta)
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(rig.player.get_animation("wave") == null, "one undo removes the pose clip")
	_teardown(rig)


func test_pose_to_clip_positions_and_validation() -> void:
	var rig := _rig("RigClip2")
	if rig.has("error"):
		skip(rig.error)
		return
	var hips: int = rig.skeleton.find_bone("B-hips")
	rig.skeleton.set_bone_pose_position(hips, Vector3(0, 0.4, 0))
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "up_pose", "overwrite": true}, null)
	rig.skeleton.set_bone_pose_position(hips, Vector3.ZERO)
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "down_pose", "overwrite": true}, null)
	var result := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": rig.player_path,
		"skeleton_path": rig.skeleton_path,
		"animation_name": "hop",
		"positions": true,
		"keys": [
			{"name": "down_pose", "time": 0.0},
			{"name": "up_pose", "time": 0.4},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("hop")
	assert_true(anim != null, "the clip exists")
	var types: Array = []
	for index in anim.get_track_count():
		types.append(anim.track_get_type(index))
	assert_true(types.has(Animation.TYPE_POSITION_3D), "a position track is created (%s)" % str(types))
	assert_eq(int(result.data.track_count), 1,
		"a position-only pose produces just the position track (%d)" % int(result.data.track_count))
	var no_keys := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR, "player_path": rig.player_path, "keys": [],
	}, null)
	assert_is_error(no_keys, ErrorCodes.MISSING_REQUIRED_PARAM)
	var bad_pose := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR, "player_path": rig.player_path,
		"keys": [{"name": "ghost_pose", "time": 0.5}],
	}, null)
	assert_is_error(bad_pose, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


## An aim key solves root/mid/end so the end bone's origin lands on a world
## target, keeps that contact through the clip, and leaves the live skeleton
## pose untouched.
func test_pose_to_clip_aim_keys() -> void:
	var rig := _rig("RigAim")
	if rig.has("error"):
		skip(rig.error)
		return
	var skeleton: Skeleton3D = rig.skeleton
	var chain: Array = ["B-upperArm.L", "B-forearm.L", "B-hand.L"]
	var shoulder: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(chain[0])).origin
	var elbow: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(chain[1])).origin
	var wrist: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(chain[2])).origin
	var arm: float = shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var direction := Vector3(0.0, 0.2, 1.0).normalized()
	var first: Vector3 = skeleton.global_transform * (shoulder + direction * (arm * 0.7))
	var second: Vector3 = skeleton.global_transform * (shoulder + direction * (arm * 0.4))
	var result := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": rig.player_path,
		"skeleton_path": rig.skeleton_path,
		"animation_name": "contact",
		"keys": [
			{"time": 0.0, "aim": [{"chain": chain, "target": [first.x, first.y, first.z], "pole": [0, -1, 0]}]},
			{"time": 0.5, "aim": [{"chain": chain, "target": [second.x, second.y, second.z]}]},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("contact")
	assert_true(anim != null, "the clip exists")
	for bone in ["B-upperArm.L", "B-forearm.L"]:
		assert_true(_track_index(anim, ":" + str(bone), Animation.TYPE_ROTATION_3D) >= 0,
			"%s has a rotation track" % str(bone))
	skeleton.reset_bone_poses()
	for key_index in 2:
		for track in anim.get_track_count():
			if anim.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var index := skeleton.find_bone(str(anim.track_get_path(track)).get_slice(":", 1))
			if index >= 0:
				skeleton.set_bone_pose_rotation(index, anim.track_get_key_value(track, key_index))
		skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var hand: int = skeleton.find_bone("B-hand.L")
		var contact: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
		var wanted: Vector3 = first if key_index == 0 else second
		assert_true(contact.distance_to(wanted) < 0.01,
			"key %d holds contact (off by %.4f m)" % [key_index, contact.distance_to(wanted)])
	skeleton.reset_bone_poses()
	var bad_chain := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "bad_aim",
		"keys": [{"time": 0.0, "aim": [{"chain": ["B-upperArm.L", "B-hand.L"], "target": [0, 1, 1]}]}],
	}, null)
	assert_is_error(bad_chain, ErrorCodes.INVALID_PARAMS)
	var ghost_bone := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "ghost_aim",
		"keys": [{"time": 0.0, "aim": [{"chain": ["ghost", "B-forearm.L", "B-hand.L"], "target": [0, 1, 1]}]}],
	}, null)
	assert_is_error(ghost_bone, ErrorCodes.NODE_NOT_FOUND)
	_teardown(rig)


## A player inside a scene instance is saved as an override of the source
## scene, and the editor drops overrides inside a non-editable instance. The
## toolkit turns Editable Children on for those levels and swaps in a
## scene-local library copy so the new clip survives the scene save.
func test_pose_to_clip_inside_a_scene_instance() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null or not ResourceLoader.exists(DUMMY):
		skip("no edited scene or missing dummy")
		return
	var root: Node = (load(DUMMY) as PackedScene).instantiate()
	root.name = "InstDummy"
	scene_root.add_child(root)
	var skeleton := _find_of_type(root, "Skeleton3D") as Skeleton3D
	var player := _find_of_type(root, "AnimationPlayer") as AnimationPlayer
	assert_true(skeleton != null and player != null, "the dummy has a skeleton/player")
	var instance_path := "/" + scene_root.name + "/" + str(root.name)
	assert_true(not scene_root.is_editable_instance(root),
		"a fresh instance starts out non-editable")
	var library_before := player.get_animation_library("")
	_handler.run({"op": "pose_save", "skeleton_path": instance_path + "/Skeleton3D",
		"pose_dir": POSE_DIR, "name": "inst_rest", "overwrite": true}, null)
	_rotate_bone(skeleton, "B-upperArm.L", PI / 3.0)
	_handler.run({"op": "pose_save", "skeleton_path": instance_path + "/Skeleton3D",
		"pose_dir": POSE_DIR, "name": "inst_up", "overwrite": true}, null)
	var result := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR,
		"player_path": instance_path + "/AnimationPlayer",
		"skeleton_path": instance_path + "/Skeleton3D",
		"animation_name": "inst_wave",
		"keys": [
			{"name": "inst_rest", "time": 0.0},
			{"name": "inst_up", "time": 0.5},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_true(scene_root.is_editable_instance(root),
		"the instance was made editable so the clip survives the save")
	var library_after := player.get_animation_library("")
	assert_true(library_after != library_before,
		"the library was swapped for a scene-local copy")
	assert_true(library_after.resource_local_to_scene, "the copy is local to the scene")
	assert_true(library_after.has_animation("inst_wave"), "the clip landed in the copy")
	assert_true(library_after.has_animation("Untitled"), "the imported clips came along")
	_remove_node(instance_path)
	_cleanup_files()


# --- 2D --------------------------------------------------------------------

func test_pose_round_trip_on_a_2d_rig() -> void:
	var rig := _rig_2d("Rig2D")
	if rig.has("error"):
		skip(rig.error)
		return
	var skeleton: Skeleton2D = rig.skeleton
	assert_eq(skeleton.get_bone_count(), 2, "the 2D rig has two bones")
	var rest := _handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path}, null)
	assert_true(rest.has("data"), "expected data, got: %s" % str(rest))
	assert_eq(str(rest.data.kind), "2d")
	assert_eq(int(rest.data.bone_count), 2)
	var lower: Bone2D = skeleton.get_bone(1)
	lower.rotation = 0.6
	var saved := _handler.run({
		"op": "pose_save", "skeleton_path": rig.skeleton_path, "path": POSE_FILE, "overwrite": true,
	}, null)
	assert_true(saved.has("data"), "expected data, got: %s" % str(saved))
	lower.rotation = 0.0
	var applied := _handler.run({
		"op": "pose_apply", "skeleton_path": rig.skeleton_path, "path": POSE_FILE,
	}, null)
	assert_true(applied.has("data"), "expected data, got: %s" % str(applied))
	assert_true(absf(lower.rotation - 0.6) < 0.001, "the 2D rotation is restored (%s)" % lower.rotation)
	_remove_node(rig.root_path)


func test_pose_to_clip_on_a_2d_rig() -> void:
	var rig := _rig_2d("Rig2DClip")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := AnimationPlayer.new()
	player.name = "Rig2DClipPlayer"
	player.add_animation_library("", AnimationLibrary.new())
	scene_root.add_child(player)
	player.owner = scene_root
	var player_path := "/" + scene_root.name + "/Rig2DClipPlayer"
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "flat_rest", "overwrite": true}, null)
	var lower: Bone2D = (rig.skeleton as Skeleton2D).get_bone(1)
	lower.rotation = 0.5
	_handler.run({"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR, "name": "flat_bend", "overwrite": true}, null)
	var result := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR, "player_path": player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "bend", "loop_mode": "linear",
		"keys": [{"name": "flat_rest", "time": 0.0}, {"name": "flat_bend", "time": 0.5}],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = player.get_animation("bend")
	var paths: Array = []
	if anim != null:
		for index in anim.get_track_count():
			paths.append(str(anim.track_get_path(index)))
	assert_eq(int(result.data.track_count), 1,
		"only the bending bone gets a track (got %d: %s)" % [int(result.data.track_count), str(paths)])
	assert_true(anim != null, "the 2D clip exists")
	assert_true(str(anim.track_get_path(0)).ends_with("/bone_lower:rotation"),
		"2D tracks target the bone node's rotation (%s)" % str(anim.track_get_path(0)))
	assert_eq(anim.track_get_type(0), Animation.TYPE_VALUE, "2D bone tracks are value tracks")
	var peak: float = anim.track_get_key_value(0, 1)
	assert_true(absf(peak - 0.5) < 0.001, "the keyed angle matches the pose (%s)" % peak)
	_remove_node(player_path)
	_remove_node(rig.root_path)


# --- rig_get ---------------------------------------------------------------

func test_rig_get_dumps_and_flags_unknown_bones() -> void:
	var rig := _rig("RigGet")
	if rig.has("error"):
		skip(rig.error)
		return
	var dump := _handler.run({"op": "rig_get", "skeleton_path": rig.skeleton_path}, null)
	assert_true(dump.has("data"), "expected data, got: %s" % str(dump))
	assert_eq(str(dump.data.kind), "3d")
	assert_eq(int(dump.data.bone_count), 56)
	var names: Array = []
	for bone in dump.data.bones:
		names.append(str(bone.name))
	assert_true(names.has("B-hips") and names.has("B-thigh.L"), "bone names are listed")
	assert_true((dump.data.issues as Array).is_empty(),
		"the dummy rig has no issues (%s)" % str(dump.data.issues))
	var scene_root := EditorInterface.get_edited_scene_root()
	_handler.run({
		"op": "pose_save", "skeleton_path": rig.skeleton_path, "pose_dir": POSE_DIR,
		"name": "rest_pose", "overwrite": true,
	}, null)
	var bogus := _handler.run({
		"op": "pose_to_clip", "pose_dir": POSE_DIR, "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "bogus",
		"keys": [{"name": "rest_pose", "time": 0.0}, {"name": "rest_pose", "time": 0.5}],
	}, null)
	assert_true(bogus.has("data"), "expected data, got: %s" % str(bogus))
	# Inject a track that names a bone the skeleton does not have.
	var anim: Animation = rig.player.get_animation("bogus")
	var index: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(index, NodePath("Rig/Skeleton3D:B-notABone"))
	anim.rotation_track_insert_key(index, 0.0, Quaternion.IDENTITY)
	var flagged := _handler.run({"op": "rig_get", "skeleton_path": rig.skeleton_path}, null)
	var codes: Array = []
	for issue in flagged.data.issues:
		codes.append(str(issue.code))
	assert_true(codes.has("unknown_bone"), "unknown bone tracks are flagged (%s)" % str(codes))
	_teardown(rig)


func test_rig_get_2d_reports_modification_stack() -> void:
	var rig := _rig_2d("RigGet2D")
	if rig.has("error"):
		skip(rig.error)
		return
	var dump := _handler.run({"op": "rig_get", "skeleton_path": rig.skeleton_path}, null)
	assert_true(dump.has("data"), "expected data, got: %s" % str(dump))
	assert_eq(str(dump.data.kind), "2d")
	assert_eq(int(dump.data.bone_count), 2)
	var names: Array = []
	for bone in dump.data.bones:
		names.append(str(bone.name))
	assert_true(names.has("bone_upper") and names.has("bone_lower"), "2D bone names are listed")
	_remove_node(rig.root_path)


# --- rig_chain -------------------------------------------------------------

func test_rig_chain_builds_3d_bones() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var path := "/" + scene_root.name + "/ChainSkeleton3D"
	var result := _handler.run({
		"op": "rig_chain", "skeleton_path": path, "name": "ChainSkeleton3D",
		"bones": [
			{"name": "spine", "position": [0, 0.2, 0]},
			{"name": "chest", "parent": "spine", "position": [0, 0.3, 0], "rotation": [10, 0, 0]},
			{"name": "head", "parent": "chest", "position": [0, 0.25, 0]},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.bones_created), 3)
	assert_true(bool(result.data.skeleton_created), "the skeleton was created")
	var skeleton := ValueCodec.resolve_scene_path(path, scene_root) as Skeleton3D
	assert_true(skeleton != null, "the skeleton exists")
	assert_eq(skeleton.get_bone_count(), 3)
	assert_eq(skeleton.get_bone_name(1), "chest")
	assert_eq(skeleton.get_bone_parent(1), skeleton.find_bone("spine"), "parents follow the spec")
	assert_true(skeleton.get_bone_rest(0).origin.is_equal_approx(Vector3(0, 0.2, 0)),
		"rest positions come from the spec")
	var chest_angle := rad_to_deg(skeleton.get_bone_rest(1).basis.get_rotation_quaternion().get_euler().x)
	assert_true(absf(chest_angle - 10.0) < 0.01, "rest rotation is in degrees about X (%s)" % chest_angle)
	assert_true(skeleton.get_bone_pose_position(0).is_equal_approx(skeleton.get_bone_rest(0).origin),
		"the default pose equals the rest")
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(ValueCodec.resolve_scene_path(path, scene_root) == null,
		"one undo removes the created skeleton")


func test_rig_chain_appends_and_validates() -> void:
	var rig := _rig("RigChainAppend")
	if rig.has("error"):
		skip(rig.error)
		return
	var before: int = rig.skeleton.get_bone_count()
	var appended := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path,
		"bones": [{"name": "tool_tip", "parent": "B-hand.R", "position": [0, 0.05, 0]}],
	}, null)
	assert_true(appended.has("data"), "expected data, got: %s" % str(appended))
	assert_eq(rig.skeleton.get_bone_count(), before + 1, "the bone is appended")
	var index: int = rig.skeleton.find_bone("tool_tip")
	assert_true(index >= 0, "the new bone is found")
	assert_eq(rig.skeleton.get_bone_parent(index), rig.skeleton.find_bone("B-hand.R"),
		"it can parent to an existing bone")
	var duplicate := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path, "bones": [{"name": "tool_tip"}],
	}, null)
	assert_is_error(duplicate, ErrorCodes.INVALID_PARAMS)
	var unknown := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path, "bones": [{"name": "x", "parent": "ghost"}],
	}, null)
	assert_is_error(unknown, ErrorCodes.INVALID_PARAMS)
	assert_contains(unknown.error.message, "ghost")
	var cycle := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path,
		"bones": [{"name": "a", "parent": "b"}, {"name": "b", "parent": "a"}],
	}, null)
	assert_is_error(cycle, ErrorCodes.INVALID_PARAMS)
	assert_contains(cycle.error.message, "cycle")
	_teardown(rig)


func test_rig_chain_from_subtree() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var root := Node3D.new()
	root.name = "ChainTree"
	var arm := Node3D.new()
	arm.name = "arm"
	arm.position = Vector3(0, 0.5, 0)
	var hand := Node3D.new()
	hand.name = "hand"
	hand.position = Vector3(0, 0.4, 0)
	hand.rotation_degrees = Vector3(0, 0, 15)
	arm.add_child(hand)
	root.add_child(arm)
	scene_root.add_child(root)
	_assign_owners(root, scene_root)
	var tree_path := "/" + scene_root.name + "/ChainTree"
	var result := _handler.run({"op": "rig_chain", "node_path": tree_path}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.bones_created), 3, "root + arm + hand become bones")
	assert_eq(str(result.data.mode), "subtree")
	var skeleton := ValueCodec.resolve_scene_path(str(result.data.skeleton_path), scene_root) as Skeleton3D
	assert_true(skeleton != null, "the skeleton exists")
	assert_true(skeleton.get_parent() == root, "the skeleton sits under the subtree root")
	var hand_index := skeleton.find_bone("hand")
	assert_eq(skeleton.get_bone_parent(hand_index), skeleton.find_bone("arm"), "the hierarchy is preserved")
	assert_true(skeleton.get_bone_rest(hand_index).origin.is_equal_approx(Vector3(0, 0.4, 0)),
		"rests come from the local transforms")
	assert_true(absf(rad_to_deg(skeleton.get_bone_rest(hand_index).basis.get_rotation_quaternion().get_euler().z) - 15.0) < 0.01,
		"local rotations carry over")
	_remove_node(tree_path)


func test_rig_chain_2d_bones() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var skeleton := Skeleton2D.new()
	skeleton.name = "Chain2DSkeleton"
	scene_root.add_child(skeleton)
	skeleton.owner = scene_root
	var path := "/" + scene_root.name + "/Chain2DSkeleton"
	var result := _handler.run({
		"op": "rig_chain", "skeleton_path": path, "kind": "2d",
		"bones": [
			{"name": "root_bone", "position": [0, 0], "length": 40},
			{"name": "tip_bone", "parent": "root_bone", "position": [40, 0], "rotation": 90, "length": 25},
		],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var tip: Bone2D = null
	for index in skeleton.get_bone_count():
		if str(skeleton.get_bone(index).name) == "tip_bone":
			tip = skeleton.get_bone(index)
	assert_true(tip != null, "tip_bone exists (%d bones)" % skeleton.get_bone_count())
	assert_true(tip.rest.get_origin().is_equal_approx(Vector2(40, 0)), "the 2D rest comes from the spec")
	assert_true(absf(tip.rest.get_rotation() - PI / 2.0) < 0.001, "2D rotation is degrees about Z")
	assert_true(is_equal_approx(tip.get_length(), 25.0), "the bone length is set")
	_remove_node(path)


# --- ik_setup --------------------------------------------------------------

func test_ik_setup_two_bone() -> void:
	var rig := _rig("RigIK")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"],
		"target_name": "HandTarget",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_true(bool(result.data.target_created), "the target marker was created")
	assert_true(not bool(result.data.active), "the modifier starts inactive")
	var scene_root := EditorInterface.get_edited_scene_root()
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is TwoBoneIK3D, "a TwoBoneIK3D was added (%s)" % str(result.data.modifier_class))
	assert_true(modifier.get_parent() == rig.skeleton, "the modifier is a child of the skeleton")
	assert_eq((modifier as IKModifier3D).get_setting_count(), 1)
	assert_eq((modifier as TwoBoneIK3D).get_root_bone_name(0), "B-upperArm.L")
	assert_eq((modifier as TwoBoneIK3D).get_middle_bone_name(0), "B-forearm.L")
	assert_eq((modifier as TwoBoneIK3D).get_end_bone_name(0), "B-hand.L")
	assert_true(not str((modifier as TwoBoneIK3D).get_target_node(0)).is_empty(), "the target is wired")
	var target := ValueCodec.resolve_scene_path(str(result.data.target_path), scene_root)
	assert_true(target is Marker3D, "the target is a Marker3D")
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root) == null,
		"one undo removes the modifier")
	assert_true(ValueCodec.resolve_scene_path(str(result.data.target_path), scene_root) == null,
		"one undo removes the target too")
	_teardown(rig)


func test_ik_setup_chain_kinds_and_validation() -> void:
	var rig := _rig("RigIK2")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "ccdik",
		"chain": ["B-upperArm.R", "B-hand.R"],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var scene_root := EditorInterface.get_edited_scene_root()
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is CCDIK3D, "a CCDIK3D was added (%s)" % str(result.data.modifier_class))
	assert_eq((modifier as ChainIK3D).get_root_bone_name(0), "B-upperArm.R")
	assert_eq((modifier as ChainIK3D).get_end_bone_name(0), "B-hand.R")
	var bad_kind := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "levitate", "chain": ["B-hand.R"],
	}, null)
	assert_is_error(bad_kind, ErrorCodes.VALUE_OUT_OF_RANGE)
	var bad_bone := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["ghost", "B-forearm.R", "B-hand.R"],
	}, null)
	assert_is_error(bad_bone, ErrorCodes.INVALID_PARAMS)
	var short_chain := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.R"],
	}, null)
	assert_is_error(short_chain, ErrorCodes.INVALID_PARAMS)
	var rig_2d := _rig_2d("RigIK2D")
	if not rig_2d.has("error"):
		var unsupported := _handler.run({
			"op": "ik_setup", "skeleton_path": rig_2d.skeleton_path,
			"chain": ["bone_upper", "bone_lower"],
		}, null)
		assert_is_error(unsupported, ErrorCodes.INVALID_PARAMS)
		assert_contains(unsupported.error.message, "Experimental")
		_remove_node(rig_2d.root_path)
	_teardown(rig)


# --- spring_setup ----------------------------------------------------------

func test_spring_setup_builds_springs() -> void:
	var rig := _rig("RigSpring")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{
			"root_bone": "B-forearm.L", "end_bone": "B-hand.L",
			"stiffness": 0.3, "drag": 0.2, "gravity": 0.1, "radius": 0.05,
			"rotation_axis": "z",
		}],
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.spring_count), 1)
	assert_true(not bool(result.data.active), "the simulator starts inactive")
	var scene_root := EditorInterface.get_edited_scene_root()
	var simulator := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(simulator is SpringBoneSimulator3D, "a SpringBoneSimulator3D was added (%s)" % str(result.data.modifier_class))
	assert_true(simulator.get_parent() == rig.skeleton, "the simulator is a child of the skeleton")
	assert_eq((simulator as SpringBoneSimulator3D).get_setting_count(), 1)
	assert_eq((simulator as SpringBoneSimulator3D).get_root_bone_name(0), "B-forearm.L")
	assert_eq((simulator as SpringBoneSimulator3D).get_end_bone_name(0), "B-hand.L")
	assert_true(absf((simulator as SpringBoneSimulator3D).get_stiffness(0) - 0.3) < 0.001, "stiffness is set")
	assert_eq((simulator as SpringBoneSimulator3D).get_rotation_axis(0), SkeletonModifier3D.ROTATION_AXIS_Z)
	var leaf := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{"root_bone": "B-forearm.L"}],
	}, null)
	assert_true(leaf.has("data"), "expected data, got: %s" % str(leaf))
	assert_eq((simulator as SpringBoneSimulator3D).get_setting_count(), 1, "the second call replaces the settings")
	assert_true((leaf.data.warnings as Array).size() > 0, "the leaf fallback warns")
	var missing := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{"root_bone": "ghost"}],
	}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	var bad_axis := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{"root_bone": "B-forearm.L", "rotation_axis": "w"}],
	}, null)
	assert_is_error(bad_axis, ErrorCodes.VALUE_OUT_OF_RANGE)
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(ValueCodec.resolve_scene_path(str(leaf.data.modifier_path), scene_root) == null,
		"one undo removes the simulator")
	_teardown(rig)


# --- look_at_setup ---------------------------------------------------------

func test_look_at_setup_tracks_a_target() -> void:
	var rig := _rig("RigLook")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "look_at_setup", "skeleton_path": rig.skeleton_path,
		"bone": "B-head", "target_name": "HeadTarget",
		"forward_axis": "+z", "duration": 0.2,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_true(bool(result.data.target_created), "the target marker was created")
	assert_true(not bool(result.data.active), "the modifier starts inactive")
	var scene_root := EditorInterface.get_edited_scene_root()
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is LookAtModifier3D, "a LookAtModifier3D was added (%s)" % str(result.data.modifier_class))
	assert_true(modifier.get_parent() == rig.skeleton, "the modifier is a child of the skeleton")
	assert_eq((modifier as LookAtModifier3D).get_bone_name(), "B-head")
	assert_eq((modifier as LookAtModifier3D).get_forward_axis(), SkeletonModifier3D.BONE_AXIS_PLUS_Z)
	assert_true(not str((modifier as LookAtModifier3D).get_target_node()).is_empty(), "the target is wired")
	assert_true(absf((modifier as LookAtModifier3D).get_duration() - 0.2) < 0.001, "duration is set")
	var target := ValueCodec.resolve_scene_path(str(result.data.target_path), scene_root)
	assert_true(target is Marker3D, "the target is a Marker3D")
	var missing_bone := _handler.run({
		"op": "look_at_setup", "skeleton_path": rig.skeleton_path, "bone": "ghost",
	}, null)
	assert_is_error(missing_bone, ErrorCodes.INVALID_PARAMS)
	var bad_axis := _handler.run({
		"op": "look_at_setup", "skeleton_path": rig.skeleton_path, "bone": "B-head", "forward_axis": "up",
	}, null)
	assert_is_error(bad_axis, ErrorCodes.VALUE_OUT_OF_RANGE)
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root) == null,
		"one undo removes the modifier")
	assert_true(ValueCodec.resolve_scene_path(str(result.data.target_path), scene_root) == null,
		"one undo removes the target too")
	_teardown(rig)


# --- retarget_setup --------------------------------------------------------

func test_twist_setup_disperses_over_the_chain() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var rig_path := "/" + scene_root.name + "/TwistRig"
	var bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-spine", "parent": "B-hips", "position": [0, 0.2, 0]},
		{"name": "B-chest", "parent": "B-spine", "position": [0, 0.25, 0]},
		{"name": "B-head", "parent": "B-chest", "position": [0, 0.3, 0]},
	]
	var built := _handler.run({
		"op": "rig_chain", "skeleton_path": rig_path, "name": "TwistRig", "bones": bones,
	}, null)
	assert_true(built.has("data"), "the test rig builds, got: %s" % str(built))
	var result := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(str(result.data.root_bone), "B-hips", "the chain root is the twist bone")
	assert_eq(str(result.data.end_bone), "B-head", "the chain end is the twist tip")
	assert_eq(str(result.data.mode), "weighted", "no joint amounts means the engine distributes")
	assert_true(not bool(result.data.active), "the modifier starts inactive")
	assert_eq((result.data.joint_bones as Array).size(), 4, "root -> end inclusive is the joint list")
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is BoneTwistDisperser3D, "a BoneTwistDisperser3D was added (%s)" % str(result.data.modifier_class))
	assert_true(modifier.get_parent() == ValueCodec.resolve_scene_path(rig_path, scene_root),
		"the modifier is a child of the skeleton")
	var disperser := modifier as BoneTwistDisperser3D
	assert_eq(disperser.get_root_bone_name(0), "B-hips")
	assert_eq(disperser.get_end_bone_name(0), "B-head")
	assert_eq(disperser.get_disperse_mode(0), BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED)
	assert_true(not disperser.active, "the modifier is inactive")
	var even := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path, "name": "TwistEven",
		"disperse": {"root_bone": "B-hips", "end_bone": "B-chest", "mode": "even",
			"weight_position": 0.25, "twist_from_rest": false, "damping": 0.8},
	}, null)
	assert_true(even.has("data"), "an even disperser over part of the chain is accepted, got: %s" % str(even))
	assert_eq(str(even.data.mode), "even")
	assert_eq((even.data.joint_bones as Array).size(), 3, "hips, spine, chest")
	var even_modifier := ValueCodec.resolve_scene_path(str(even.data.modifier_path), scene_root) as BoneTwistDisperser3D
	assert_eq(even_modifier.get_end_bone_name(0), "B-chest")
	assert_eq(even_modifier.get_disperse_mode(0), BoneTwistDisperser3D.DISPERSE_MODE_EVEN)
	assert_eq(even_modifier.get_weight_position(0), 0.25)
	assert_true(not even_modifier.is_twist_from_rest(0), "twist_from_rest=false is applied")
	assert_true(even_modifier.get_damping_curve(0) != null, "a damping curve is built")
	var bad_end := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"root_bone": "B-head", "end_bone": "B-hips"},
	}, null)
	assert_is_error(bad_end, ErrorCodes.INVALID_PARAMS)
	var custom_mode := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path, "disperse": {"mode": "custom"},
	}, null)
	assert_is_error(custom_mode, ErrorCodes.INVALID_PARAMS)
	var bad_mode := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path, "disperse": {"mode": "sideways"},
	}, null)
	assert_is_error(bad_mode, ErrorCodes.VALUE_OUT_OF_RANGE)
	var joints := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"joints": [{"bone": "B-spine", "amount": 0.5}]},
	}, null)
	assert_is_error(joints, ErrorCodes.INVALID_PARAMS)
	var broken_chain := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"spine_chain": ["B-chest", "B-hips"],
	}, null)
	assert_is_error(broken_chain, ErrorCodes.INVALID_PARAMS)
	var missing_bone := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"spine_chain": ["B-hips", "B-nope"],
	}, null)
	assert_is_error(missing_bone, ErrorCodes.NODE_NOT_FOUND)
	_remove_node(rig_path)


func test_retarget_setup_maps_and_moves() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var source_path := "/" + scene_root.name + "/RetargetSource"
	var target_path := "/" + scene_root.name + "/RetargetTarget"
	var bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-spine", "parent": "B-hips", "position": [0, 0.2, 0]},
		{"name": "B-head", "parent": "B-spine", "position": [0, 0.4, 0]},
	]
	var built_source := _handler.run({
		"op": "rig_chain", "skeleton_path": source_path, "name": "RetargetSource", "bones": bones,
	}, null)
	assert_true(built_source.has("data"), "the source skeleton builds, got: %s" % str(built_source))
	var built_target := _handler.run({
		"op": "rig_chain", "skeleton_path": target_path, "name": "RetargetTarget", "bones": bones,
	}, null)
	assert_true(built_target.has("data"), "the target skeleton builds, got: %s" % str(built_target))
	var result := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": target_path, "profile": "auto",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(str(result.data.profile_source), "auto")
	assert_eq(int(result.data.profile_bones), 3, "the auto profile mirrors the source skeleton")
	assert_eq(int(result.data.mapped_bones), 3, "matching bone names map")
	assert_eq((result.data.unmapped_bones as Array).size(), 0)
	assert_true(bool(result.data.moved_target), "the target was moved under the modifier")
	assert_eq(int(result.data.enable_flags), RetargetModifier3D.TRANSFORM_FLAG_ROTATION,
		"rotation-only by default")
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is RetargetModifier3D, "a RetargetModifier3D was added (%s)" % str(result.data.modifier_class))
	assert_true(modifier.get_parent() == ValueCodec.resolve_scene_path(source_path, scene_root),
		"the modifier is a child of the source skeleton")
	var target := ValueCodec.resolve_scene_path(str(result.data.target_path), scene_root)
	assert_true(target != null and target.get_parent() == modifier,
		"the target skeleton is a child of the modifier (at %s)" % str(result.data.target_path))
	assert_true((modifier as RetargetModifier3D).get_profile() != null, "the profile is assigned")
	assert_eq((modifier as RetargetModifier3D).get_profile().get_bone_size(), 3)
	assert_true(not bool(result.data.active), "the modifier starts inactive")
	var same := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path, "target_path": source_path,
	}, null)
	assert_is_error(same, ErrorCodes.INVALID_PARAMS)
	var wrong_type := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path, "target_path": "/" + scene_root.name,
	}, null)
	assert_is_error(wrong_type, ErrorCodes.WRONG_TYPE)
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root) == null,
		"one undo removes the modifier")
	var restored := ValueCodec.resolve_scene_path(target_path, scene_root)
	assert_true(restored != null and restored.get_parent() == scene_root,
		"one undo puts the target skeleton back (found %s)" % str(restored))
	_remove_node(target_path)
	_remove_node(source_path)


func test_retarget_setup_moves_instanced_targets_whole() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var source_path := "/" + scene_root.name + "/RetargetPlain"
	var built := _handler.run({
		"op": "rig_chain", "skeleton_path": source_path, "name": "RetargetPlain",
		"bones": [{"name": "B-hips", "position": [0, 0.9, 0]}],
	}, null)
	if not built.has("data"):
		skip("the plain skeleton did not build")
		return
	var target_rig := _rig("RetargetTgt2")
	if target_rig.has("error"):
		_remove_node(source_path)
		skip(target_rig.error)
		return
	var instance_root: Node = target_rig.skeleton.get_parent()
	var result := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": target_rig.skeleton_path,
	}, null)
	assert_true(result.has("data"), "an instanced target is moved as a whole, got: %s" % str(result))
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(instance_root.get_parent() == modifier, "the instance root moved under the modifier")
	assert_true(target_rig.skeleton.get_parent() == instance_root,
		"the skeleton stays inside its own scene, so the skin binding survives")
	assert_eq(str(result.data.moved_path), ValueCodec.from_node(instance_root, scene_root),
		"the response reports the node that moved")
	var instanced_source := _handler.run({
		"op": "retarget_setup", "skeleton_path": str(result.data.target_path),
		"target_path": source_path,
	}, null)
	assert_is_error(instanced_source, ErrorCodes.INVALID_PARAMS)
	assert_contains(instanced_source.error.message, "instanced scene")
	editor_undo(_undo_redo)
	_teardown(target_rig)
	_remove_node(source_path)


# --- procedural recipes ----------------------------------------------------

func test_walk_cycle_builds_roles_and_clip() -> void:
	var rig := _rig("RigWalk")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.track_count), 7, "two thighs, two shins, two arms and the hip bob")
	var roles: Dictionary = result.data.roles
	for role in ["thigh_l", "thigh_r", "shin_l", "shin_r", "arm_l", "arm_r", "hips"]:
		assert_true(roles.has(role), "%s was auto-detected (%s)" % [role, str(roles.get(role, "<missing>"))])
	var anim: Animation = rig.player.get_animation("walk")
	assert_true(anim != null, "the clip exists")
	assert_true(absf(anim.length - 1.0) < 0.001, "length follows duration")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR, "loop mode is applied")
	var thigh_index := -1
	for index in anim.get_track_count():
		if str(anim.track_get_path(index)).ends_with(":B-thigh.L"):
			thigh_index = index
	assert_true(thigh_index >= 0, "the left thigh has a track")
	assert_eq(anim.track_get_key_count(thigh_index), 3, "three keys per swing")
	var rest: Quaternion = rig.skeleton.get_bone_rest(rig.skeleton.find_bone("B-thigh.L")).basis.get_rotation_quaternion()
	var first: Quaternion = anim.track_get_key_value(thigh_index, 0)
	assert_true((rest.inverse() * first).get_angle() > 0.2, "the thigh actually swings")
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(rig.player.get_animation("walk") == null, "one undo removes the cycle")
	_teardown(rig)


func test_walk_cycle_arm_down_lowers_the_arms() -> void:
	var rig := _rig("RigWalkDown")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_down",
		"duration": 1.0, "loop_mode": "linear", "arm_down": 60.0,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(float(result.data.arm_down), 60.0, "arm_down is reported back")
	var anim: Animation = rig.player.get_animation("walk_down")
	assert_true(anim != null, "the clip exists")
	var arm_index := -1
	for index in anim.get_track_count():
		if str(anim.track_get_path(index)).ends_with(":B-upperArm.L"):
			arm_index = index
	assert_true(arm_index >= 0, "the left arm has a track")
	var bone: int = rig.skeleton.find_bone("B-upperArm.L")
	var parent: int = rig.skeleton.get_bone_parent(bone)
	var posed: Basis = Basis(anim.track_get_key_value(arm_index, 0))
	var direction: Vector3 = (rig.skeleton.get_bone_global_rest(parent).basis * posed * Vector3.UP).normalized()
	assert_true(direction.y < -0.5,
		"the arm points downward with arm_down=60 (dir.y=%.2f)" % direction.y)
	_teardown(rig)


func test_jumping_jack_raises_arms_and_spreads_legs() -> void:
	var rig := _rig("RigJack")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "jumping_jack", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "jack",
		"duration": 1.0, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var skeleton: Skeleton3D = rig.skeleton
	var anim: Animation = rig.player.get_animation("jack")
	assert_true(anim != null, "the clip exists")
	var arm_index := _track_index(anim, ":B-upperArm.L", Animation.TYPE_ROTATION_3D)
	var thigh_index := _track_index(anim, ":B-thigh.L", Animation.TYPE_ROTATION_3D)
	assert_true(arm_index >= 0 and thigh_index >= 0, "arms and thighs have tracks")
	assert_eq(anim.track_get_key_count(arm_index), 3, "three keys per jack")
	var arm_bone := skeleton.find_bone("B-upperArm.L")
	var arm_parent := skeleton.get_bone_parent(arm_bone)
	var down_dir := _dir_of(skeleton, arm_parent, anim.track_get_key_value(arm_index, 0))
	var up_dir := _dir_of(skeleton, arm_parent, anim.track_get_key_value(arm_index, 1))
	assert_true(down_dir.y < -0.5, "the arms start down (y=%.2f)" % down_dir.y)
	assert_true(up_dir.y > 0.5, "the arms swing overhead (y=%.2f)" % up_dir.y)
	var thigh_bone := skeleton.find_bone("B-thigh.L")
	var thigh_parent := skeleton.get_bone_parent(thigh_bone)
	var spread_dir := _dir_of(skeleton, thigh_parent, anim.track_get_key_value(thigh_index, 1))
	assert_true(spread_dir.x > 0.2, "the left leg spreads outward (x=%.2f)" % spread_dir.x)
	_teardown(rig)


func test_squat_keeps_the_feet_planted() -> void:
	var rig := _rig("RigSquat")
	if rig.has("error"):
		skip(rig.error)
		return
	var depth := 0.25
	var result := _handler.run({
		"op": "squat", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "squat",
		"duration": 2.0, "bob": depth, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var skeleton: Skeleton3D = rig.skeleton
	var anim: Animation = rig.player.get_animation("squat")
	assert_true(anim != null, "the clip exists")
	var bottom := 1
	var hips_index := _track_index(anim, ":B-hips", Animation.TYPE_POSITION_3D)
	assert_true(hips_index >= 0, "the hips have a position track")
	var hips_key: Vector3 = anim.track_get_key_value(hips_index, bottom)
	var hips_rest: Vector3 = skeleton.get_bone_rest(skeleton.find_bone("B-hips")).origin
	assert_true(hips_key.y < hips_rest.y - depth * 0.8, "the hips drop (%.2f -> %.2f)" % [hips_rest.y, hips_key.y])
	for bone_name in ["B-thigh.L", "B-shin.L", "B-thigh.R", "B-shin.R"]:
		var track := _track_index(anim, ":" + bone_name, Animation.TYPE_ROTATION_3D)
		assert_true(track >= 0, "%s has a rotation track" % bone_name)
		skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), anim.track_get_key_value(track, bottom))
	skeleton.set_bone_pose_position(skeleton.find_bone("B-hips"), hips_key)
	for side in ["L", "R"]:
		var foot := skeleton.find_bone("B-foot." + side)
		var rest_ankle: Vector3 = skeleton.get_bone_global_rest(foot).origin
		var posed_ankle: Vector3 = skeleton.get_bone_global_pose(foot).origin
		assert_true(posed_ankle.distance_to(rest_ankle) < 0.02,
			"the %s ankle stays planted (moved %.3f m)" % [side, posed_ankle.distance_to(rest_ankle)])
	_teardown(rig)


func test_punch_extends_the_arm_forward() -> void:
	var rig := _rig("RigPunch")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "punch", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "boxing",
		"duration": 0.8, "cycles": 2, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(str(result.data.roles.forearm_l), "B-forearm.L", "the forearm is detected")
	assert_eq(str(result.data.roles.spine), "B-spine", "the spine is detected")
	var skeleton: Skeleton3D = rig.skeleton
	var anim: Animation = rig.player.get_animation("boxing")
	assert_true(anim != null, "the clip exists")
	var arm_index := _track_index(anim, ":B-upperArm.L", Animation.TYPE_ROTATION_3D)
	var forearm_index := _track_index(anim, ":B-forearm.L", Animation.TYPE_ROTATION_3D)
	var chest_index := _track_index(anim, ":B-chest", Animation.TYPE_ROTATION_3D)
	assert_true(arm_index >= 0 and forearm_index >= 0 and chest_index >= 0, "arm, forearm and chest have tracks")
	var arm_parent := skeleton.get_bone_parent(skeleton.find_bone("B-upperArm.L"))
	var guard_dir := _dir_of(skeleton, arm_parent, anim.track_get_key_value(arm_index, 0))
	var punch_dir := _dir_of(skeleton, arm_parent, anim.track_get_key_value(arm_index, 1))
	var forward := (skeleton.get_bone_global_rest(skeleton.find_bone("B-toe.L")).origin
		- skeleton.get_bone_global_rest(skeleton.find_bone("B-foot.L")).origin)
	forward.y = 0.0
	forward = forward.normalized()
	assert_true(guard_dir.dot(Vector3.DOWN) > 0.4, "the guard keeps the arm low (y=%.2f)" % guard_dir.y)
	assert_true(punch_dir.dot(forward) > guard_dir.dot(forward) + 0.3,
		"the punch extends forward (%.2f -> %.2f)" % [guard_dir.dot(forward), punch_dir.dot(forward)])
	var twist := (anim.track_get_key_value(chest_index, 1) as Quaternion).angle_to(
		anim.track_get_key_value(chest_index, 0) as Quaternion)
	assert_true(twist > 0.05, "the torso twists with the punch (%.2f rad)" % twist)
	_teardown(rig)


func test_idle_breathing_and_blink() -> void:
	var rig := _rig("RigIdle")
	if rig.has("error"):
		skip(rig.error)
		return
	var idle := _handler.run({
		"op": "idle_breathing", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "idle",
		"duration": 3.0, "loop_mode": "linear",
	}, null)
	assert_true(idle.has("data"), "expected data, got: %s" % str(idle))
	assert_eq(str(idle.data.roles.chest), "B-chest", "the chest is auto-detected")
	assert_true(int(idle.data.track_count) >= 2, "chest plus at least one more bone")
	var blink := _handler.run({
		"op": "blink", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "blink",
		"bones": ["B-jaw"], "duration": 0.2, "blinks": 2,
	}, null)
	assert_true(blink.has("data"), "expected data, got: %s" % str(blink))
	assert_eq(str(blink.data.mode), "scale")
	var anim: Animation = rig.player.get_animation("blink")
	assert_true(anim != null, "the blink clip exists")
	assert_eq(anim.track_get_type(0), Animation.TYPE_SCALE_3D, "scale mode keys scale tracks")
	assert_true(anim.track_get_key_count(0) >= 7,
		"two blinks keep a key per pose (the shared boundary merges): %d" % anim.track_get_key_count(0))
	assert_true((anim.track_get_key_value(0, 0) as Vector3).is_equal_approx(Vector3.ONE),
		"the clip starts with the eye open")
	assert_true((anim.track_get_key_value(0, 1) as Vector3).y < 0.5,
		"the second key is the closed lid")
	_teardown(rig)


func test_bake_pose_sequence_samples_and_restores() -> void:
	var rig := _rig("RigBake")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_src",
		"duration": 0.5, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source cycle builds, got: %s" % str(built))
	var before: Quaternion = rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone("B-thigh.L"))
	var result := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_baked",
		"source_animation": "walk_src", "duration": 0.5, "fps": 10,
		"loop_mode": "linear", "scales": true,
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	assert_eq(int(result.data.samples), 6, "duration * fps + 1 samples")
	assert_eq(int(result.data.bone_count), 56, "every bone is baked by default")
	var anim: Animation = rig.player.get_animation("walk_baked")
	assert_true(anim != null, "the baked clip exists")
	assert_eq(anim.track_get_key_count(0), 6, "one key per sample")
	var source_anim: Animation = rig.player.get_animation("walk_src")
	var source_thigh := -1
	var baked_thigh := -1
	for index in source_anim.get_track_count():
		if str(source_anim.track_get_path(index)).ends_with(":B-thigh.L"):
			source_thigh = index
	for index in anim.get_track_count():
		if anim.track_get_type(index) == Animation.TYPE_ROTATION_3D \
				and str(anim.track_get_path(index)).ends_with(":B-thigh.L"):
			baked_thigh = index
			break
	assert_true(source_thigh >= 0 and baked_thigh >= 0, "both clips key the left thigh")
	assert_true((anim.track_get_key_value(baked_thigh, 0) as Quaternion).is_equal_approx(
		source_anim.track_get_key_value(source_thigh, 0)),
		"the first baked sample is the source clip's pose (the player is seeked while sampling)")
	assert_true((anim.track_get_key_value(baked_thigh, 0) as Quaternion).angle_to(
		anim.track_get_key_value(baked_thigh, 2) as Quaternion) > 0.05,
		"sampled poses differ across the clip")
	var after: Quaternion = rig.skeleton.get_bone_pose_rotation(rig.skeleton.find_bone("B-thigh.L"))
	assert_true(before.is_equal_approx(after), "the skeleton pose is restored after sampling")
	_teardown(rig)


func test_bake_pose_sequence_captures_ik() -> void:
	var rig := _rig("RigBakeIK")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var target := Marker3D.new()
	target.name = "BakeTarget"
	target.position = Vector3(0.5, 1.7, 0.3)
	scene_root.add_child(target)
	target.owner = scene_root
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_src",
		"duration": 0.5, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source cycle builds, got: %s" % str(built))
	var setup := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path,
		"kind": "two_bone", "chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"],
		"target_path": "/" + scene_root.name + "/BakeTarget", "active": true,
	}, null)
	assert_true(setup.has("data"), "ik_setup: %s" % str(setup))
	var result := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "walk_ik",
		"source_animation": "walk_src", "duration": 0.5, "fps": 10,
		"loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "expected data, got: %s" % str(result))
	var anim: Animation = rig.player.get_animation("walk_ik")
	var source_anim: Animation = rig.player.get_animation("walk_src")
	assert_true(anim != null and source_anim != null, "both clips exist")
	var source_upper := -1
	var baked_upper := -1
	for index in source_anim.get_track_count():
		if str(source_anim.track_get_path(index)).ends_with(":B-upperArm.L"):
			source_upper = index
	for index in anim.get_track_count():
		if anim.track_get_type(index) == Animation.TYPE_ROTATION_3D \
				and str(anim.track_get_path(index)).ends_with(":B-upperArm.L"):
			baked_upper = index
			break
	assert_true(source_upper >= 0 and baked_upper >= 0, "both clips key the left upper arm")
	var moved: float = (anim.track_get_key_value(baked_upper, 0) as Quaternion).angle_to(
		source_anim.track_get_key_value(source_upper, 0) as Quaternion)
	assert_true(moved > 0.3, "the IK-modified pose is baked (arm moved %.2f rad)" % moved)
	scene_root.remove_child(target)
	target.queue_free()
	_teardown(rig)


func test_registry_matches_rig_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_RIG)
	assert_false(info.is_empty(), "the rig family is registered")
	var op_enum: Array = info.schema.properties.op.enum
	assert_eq(op_enum.size(), 19, "the rig schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(info.schema.properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the rig description fits the custom-tool cap")
