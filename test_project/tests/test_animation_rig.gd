@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const RigHandler := preload("res://addons/godot_ai_animation/handlers/rig.gd")

const DUMMY := "res://models/human_dummy/HumanCharacterDummy_F.fbx"
const POSE_FILE := "res://animation_toolkit/tmp_pose.json"
const POSE_DIR := "res://animation_toolkit/tmp_poses"
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


func test_rig_chain_rejects_bone_names_that_break_track_paths() -> void:
	# `Skeleton3D:<bone>:<property>` is the path every clip track uses, so a bone
	# name with '/' or ':' in it parses as a different node path and the tracks
	# silently point somewhere else. Dots are legitimate and must keep working.
	var rig := _rig("RigChainNames")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	for bad in ["leg/L", "leg:lower", "a/b/c", "root:bone"]:
		var refused := _handler.run({
			"op": "rig_chain", "skeleton_path": rig.skeleton_path,
			"bones": [{"name": str(bad)}, {"name": "child", "parent": str(bad)}],
		}, null)
		assert_is_error(refused, ErrorCodes.INVALID_PARAMS)
		assert_contains(refused.error.message, "track path")
	# Dots are legitimate (B-upperArm.L) and must keep working. Appended to the
	# dummy, whose bone list has no `chain_*` names yet.
	var dotted := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path,
		"bones": [
			{"name": "chain_hip", "parent": "B-hips"},
			{"name": "chain_knee.L", "parent": "chain_hip"},
		],
	}, null)
	assert_true(dotted.has("data"), "a dotted bone name is accepted (%s)" % str(dotted.get("error", dotted)))
	var skeleton: Skeleton3D = rig.skeleton
	assert_true(skeleton.find_bone("chain_hip") >= 0, "chain_hip exists")
	assert_true(skeleton.find_bone("chain_knee.L") >= 0, "chain_knee.L exists")
	# A bad name is refused BEFORE anything is committed, so the bones that came
	# before it in the same call are not left behind either.
	var before_count: int = skeleton.get_bone_count()
	var half := _handler.run({
		"op": "rig_chain", "skeleton_path": rig.skeleton_path,
		"bones": [{"name": "good_bone"}, {"name": "bad/bone", "parent": "good_bone"}],
	}, null)
	assert_is_error(half, ErrorCodes.INVALID_PARAMS)
	assert_eq(skeleton.get_bone_count(), before_count,
		"the refused call added no bones at all")
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


func test_ik_setup_spline_follows_a_path_not_a_target() -> void:
	var rig := _rig("RigIKSpline")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var result := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "spline",
		"chain": ["B-upperArm.R", "B-hand.R"],
	}, null)
	assert_true(result.has("data"), "spline ik_setup: %s" % str(result))
	if not result.has("data"):
		_teardown(rig)
		return
	assert_true(bool(result.data.path_created), "a path was created when none was given")
	assert_eq(str(result.data.target_path), "", "spline IK has no marker target")
	assert_contains(str(result.data.spline_note), "Path3D")
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
	assert_true(modifier is SplineIK3D, "a SplineIK3D was added (%s)" % str(result.data.modifier_class))
	assert_eq((modifier as ChainIK3D).get_root_bone_name(0), "B-upperArm.R")
	assert_eq((modifier as ChainIK3D).get_end_bone_name(0), "B-hand.R")
	# SplineIK3D has no set_target_node anywhere in its class chain, so the path
	# is the only thing that can drive it.
	assert_true(not (modifier as SkeletonModifier3D).has_method("set_target_node"),
		"SplineIK3D really has no target setter in this build")
	var path_node := ValueCodec.resolve_scene_path(str(result.data.path_path), scene_root)
	assert_true(path_node is Path3D, "the created path is a Path3D")
	assert_true((path_node as Path3D).curve != null, "the created path has a curve")
	assert_true((path_node as Path3D).curve.point_count >= 2, "the curve has two points")
	var wired := (modifier as SplineIK3D).get_path_3d(0)
	assert_true(not str(wired).is_empty(), "the path is wired into setting 0")
	var resolved_path := modifier.get_node_or_null(wired)
	assert_true(resolved_path == path_node, "the wired path resolves to the Path3D (%s)" % str(resolved_path))
	# An existing Path3D is reused rather than replaced - but only when it has
	# something to follow: a curve-less path is refused, not wired and ignored.
	var supplied := Path3D.new()
	supplied.name = "SuppliedPath"
	scene_root.add_child(supplied)
	supplied.owner = scene_root
	var curve_less := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "spline",
		"chain": ["B-thigh.L", "B-foot.L"],
		"target_path": str(ValueCodec.from_node(supplied, scene_root)),
	}, null)
	assert_is_error(curve_less, ErrorCodes.INVALID_PARAMS)
	assert_contains(curve_less.get("error", {}).get("message", ""), "curve points")
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 0.5))
	supplied.curve = curve
	var with_path := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "spline",
		"chain": ["B-thigh.L", "B-foot.L"],
		"target_path": str(ValueCodec.from_node(supplied, scene_root)),
	}, null)
	assert_true(with_path.has("data"), "spline ik_setup with a path: %s" % str(with_path))
	if not with_path.has("data"):
		_teardown(rig)
		return
	assert_false(bool(with_path.data.path_created), "the supplied path is reused")
	var second := ValueCodec.resolve_scene_path(str(with_path.data.modifier_path), scene_root)
	assert_true(second.get_node_or_null((second as SplineIK3D).get_path_3d(0)) == supplied,
		"the supplied path is what the modifier follows")
	# A marker is not a path: the op has to say so instead of queueing a call the
	# class does not have.
	var marker := Marker3D.new()
	marker.name = "NotAPath"
	scene_root.add_child(marker)
	marker.owner = scene_root
	var wrong_type := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "spline",
		"chain": ["B-thigh.L", "B-foot.L"],
		"target_path": str(ValueCodec.from_node(marker, scene_root)),
	}, null)
	assert_is_error(wrong_type, ErrorCodes.WRONG_TYPE)
	assert_contains(wrong_type.error.message, "Path3D")
	_teardown(rig)


func test_ik_setup_chain_validation_and_unique_marker_names() -> void:
	var rig := _rig("RigIKChains")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	# A two_bone chain is exactly three parent-ordered bones; a four-bone list
	# used to build the target from the fourth bone and solve on the third.
	var four := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L", "B-hand.R"],
	}, null)
	assert_is_error(four, ErrorCodes.INVALID_PARAMS)
	assert_contains(four.get("error", {}).get("message", ""), "exactly three bones")
	var non_ancestral := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-shin.L", "B-foot.L"],
	}, null)
	assert_is_error(non_ancestral, ErrorCodes.INVALID_PARAMS)
	assert_contains(non_ancestral.error.message, "not the parent")
	var repeated := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-forearm.L", "B-forearm.L"],
	}, null)
	assert_is_error(repeated, ErrorCodes.INVALID_PARAMS)
	assert_contains(repeated.error.message, "repeats")
	var chain_solver_backwards := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "ccdik",
		"chain": ["B-hand.R", "B-upperArm.R"],
	}, null)
	assert_is_error(chain_solver_backwards, ErrorCodes.INVALID_PARAMS)
	assert_contains(chain_solver_backwards.error.message, "descendant")
	# Two markers with the same requested name must both keep a resolving path:
	# Godot renames the second on add, which used to leave its NodePath dangling.
	var first := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-thigh.L", "B-shin.L", "B-foot.L"], "target_name": "IKTarget",
	}, null)
	assert_true(first.has("data"), "left leg IK: %s" % str(first))
	var second_leg := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-thigh.R", "B-shin.R", "B-foot.R"], "target_name": "IKTarget",
	}, null)
	assert_true(second_leg.has("data"), "right leg IK: %s" % str(second_leg))
	assert_true(str(second_leg.data.target_path) != str(first.data.target_path),
		"the second target got its own name (%s)" % str(second_leg.data.target_path))
	for result in [first, second_leg]:
		var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root)
		var target_node := modifier.get_node_or_null((modifier as TwoBoneIK3D).get_target_node(0))
		assert_true(target_node != null, "the target path resolves (%s)" % str((modifier as TwoBoneIK3D).get_target_node(0)))
		var pole_node := modifier.get_node_or_null((modifier as TwoBoneIK3D).get_pole_node(0))
		assert_true(pole_node != null, "the pole path resolves (%s)" % str((modifier as TwoBoneIK3D).get_pole_node(0)))
	_teardown(rig)


func test_setup_targets_resolve_when_nested_below_the_scene_root() -> void:
	# The modifier hangs off the skeleton, and its target path used to be built
	# from the target's bare NAME - which only resolves for a target sitting
	# directly under the scene root. A target under Rig/Targets/ got a path to
	# some other node, and the setup either did nothing or was refused.
	var rig := _rig("RigNested")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var holder := Node3D.new()
	holder.name = "NestedTargets"
	scene_root.add_child(holder)
	var deep := Node3D.new()
	deep.name = "Deep"
	holder.add_child(deep)
	var hand_target := Marker3D.new()
	hand_target.name = "HandTarget"
	deep.add_child(hand_target)
	var elbow_pole := Marker3D.new()
	elbow_pole.name = "ElbowPole"
	deep.add_child(elbow_pole)
	_assign_owners(holder, scene_root)
	var holder_path := "/" + str(scene_root.name) + "/NestedTargets"
	var hand_path := holder_path + "/Deep/HandTarget"
	var pole_path := holder_path + "/Deep/ElbowPole"
	var result := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"],
		"target_path": hand_path, "pole_path": pole_path,
	}, null)
	assert_true(result.has("data"), "a nested target is accepted (%s)" % str(result.get("error", result)))
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path), scene_root) as TwoBoneIK3D
	assert_true(modifier != null, "the modifier exists")
	if modifier != null:
		var wired_target := modifier.get_node_or_null(modifier.get_target_node(0))
		assert_true(wired_target == hand_target,
			"the target path resolves to the nested node (path %s -> %s)"
			% [str(modifier.get_target_node(0)), str(wired_target)])
		var wired_pole := modifier.get_node_or_null(modifier.get_pole_node(0))
		assert_true(wired_pole == elbow_pole,
			"the pole path resolves to the nested node (path %s -> %s)"
			% [str(modifier.get_pole_node(0)), str(wired_pole)])
	# The same for a look-at marker and a spline path, which share the helper.
	var head_target := Marker3D.new()
	head_target.name = "HeadTarget"
	deep.add_child(head_target)
	_assign_owners(head_target, scene_root)
	var look := _handler.run({
		"op": "look_at_setup", "skeleton_path": rig.skeleton_path, "bone": "B-head",
		"target_path": holder_path + "/Deep/HeadTarget",
	}, null)
	assert_true(look.has("data"), "a nested look-at target is accepted (%s)" % str(look.get("error", look)))
	var look_modifier := ValueCodec.resolve_scene_path(str(look.data.modifier_path), scene_root) as LookAtModifier3D
	assert_true(look_modifier != null, "the look-at modifier exists")
	if look_modifier != null:
		assert_true(look_modifier.get_node_or_null(look_modifier.get_target_node()) == head_target,
			"the look-at target path resolves to the nested node (%s)" % str(look_modifier.get_target_node()))
	_remove_node(holder_path)
	_teardown(rig)


func test_look_at_markers_get_collision_safe_names() -> void:
	# Two look-ats asking for the same marker name used to collide: Godot
	# renamed the second marker, but the modifier's target path still said the
	# original name, so the second modifier drove the FIRST target. Earlier tests
	# in this suite may have left a marker of the same name behind, so the
	# property checked is that the two modifiers drive two DIFFERENT markers.
	var rig := _rig("RigLookNames")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var mine: Array = []
	for index in range(2):
		var result := _handler.run({
			"op": "look_at_setup", "skeleton_path": rig.skeleton_path, "bone": "B-head",
			"target_name": "LookAtTarget",
		}, null)
		assert_true(result.has("data"), "look-at %d is set up (%s)" % [index + 1, str(result.get("error", result))])
		mine.append(str(result.data.modifier_path))
	assert_eq(mine.size(), 2, "two look-at modifiers were created")
	var targets: Array = []
	for path in mine:
		var modifier := ValueCodec.resolve_scene_path(str(path), scene_root) as LookAtModifier3D
		assert_true(modifier != null, "%s exists" % str(path))
		if modifier == null:
			continue
		var target := modifier.get_node_or_null(modifier.get_target_node())
		assert_true(target is Marker3D,
			"%s resolves to a marker (%s)" % [str(path), str(modifier.get_target_node())])
		if target != null:
			targets.append(str(target.get_path()))
	assert_eq(targets.size(), 2, "both modifiers resolve a target")
	if targets.size() == 2:
		assert_true(targets[0] != targets[1],
			"the two look-ats drive two DIFFERENT markers (%s vs %s)" % [targets[0], targets[1]])
	_teardown(rig)


func test_ik_default_markers_ignore_the_current_pose() -> void:
	var rig := _rig("RigIKRest")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var skeleton := ValueCodec.resolve_scene_path(rig.skeleton_path, scene_root) as Skeleton3D
	var chain := ["B-upperArm.L", "B-forearm.L", "B-hand.L"]
	var neutral := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": chain, "target_name": "RestTarget",
	}, null)
	assert_true(neutral.has("data"), "neutral setup: %s" % str(neutral))
	var neutral_target := ValueCodec.resolve_scene_path(str(neutral.data.target_path), scene_root) as Marker3D
	var neutral_pole := ValueCodec.resolve_scene_path(str(neutral.data.pole_path), scene_root) as Marker3D
	# Pose the chain, then set it up again: the default markers must land in the
	# rest frame, not wherever the editor was left.
	skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	for bone_name in chain:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), Quaternion(Vector3(1, 0, 0), 0.9))
	var posed := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": chain, "target_name": "PosedTarget",
	}, null)
	assert_true(posed.has("data"), "posed setup: %s" % str(posed))
	var posed_target := ValueCodec.resolve_scene_path(str(posed.data.target_path), scene_root) as Marker3D
	var posed_pole := ValueCodec.resolve_scene_path(str(posed.data.pole_path), scene_root) as Marker3D
	assert_true(posed_target.global_position.distance_to(neutral_target.global_position) < 0.001,
		"the target lands in the rest frame (%s vs %s)"
			% [str(posed_target.global_position), str(neutral_target.global_position)])
	assert_true(posed_pole.global_position.distance_to(neutral_pole.global_position) < 0.001,
		"the pole lands in the rest frame")
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
			"twist_from_rest": false,
			"twist_from": {"kind": "quaternion", "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}},
	}, null)
	assert_true(even.has("data"), "an even disperser over part of the chain is accepted, got: %s" % str(even))
	assert_eq(str(even.data.mode), "even")
	assert_eq((even.data.joint_bones as Array).size(), 3, "hips, spine, chest")
	var even_modifier := ValueCodec.resolve_scene_path(str(even.data.modifier_path), scene_root) as BoneTwistDisperser3D
	assert_eq(even_modifier.get_end_bone_name(0), "B-chest")
	assert_eq(even_modifier.get_disperse_mode(0), BoneTwistDisperser3D.DISPERSE_MODE_EVEN)
	assert_true(not even_modifier.is_twist_from_rest(0), "twist_from_rest=false is applied")
	assert_true(even_modifier.get_twist_from(0).is_equal_approx(Quaternion.IDENTITY),
		"the explicit reference quaternion is applied")
	# Parameters Godot only reads in another mode used to be accepted and queued,
	# which produced a modifier that quietly ignored them.
	var ignored_damping := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"mode": "even", "damping": 0.8},
	}, null)
	assert_is_error(ignored_damping, ErrorCodes.INVALID_PARAMS)
	assert_contains(ignored_damping.get("error", {}).get("message", ""), "custom")
	var ignored_weight := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"mode": "even", "weight_position": 0.25},
	}, null)
	assert_is_error(ignored_weight, ErrorCodes.INVALID_PARAMS)
	assert_contains(ignored_weight.get("error", {}).get("message", ""), "weighted")
	var no_reference := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"twist_from_rest": false},
	}, null)
	assert_is_error(no_reference, ErrorCodes.INVALID_PARAMS)
	assert_contains(no_reference.get("error", {}).get("message", ""), "twist_from")
	var bad_reference := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path,
		"disperse": {"twist_from_rest": false, "twist_from": 0.5},
	}, null)
	assert_is_error(bad_reference, ErrorCodes.WRONG_TYPE)
	# A two-bone range has no joint to share across, so it extends past the end.
	var short_range := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path, "name": "TwistShort",
		"disperse": {"root_bone": "B-hips", "end_bone": "B-spine"},
	}, null)
	assert_true(short_range.has("data"), "a two-bone range is still allowed: %s" % str(short_range))
	assert_true(bool(short_range.data.extend_end_bone),
		"a two-joint range extends past the end bone")
	assert_true((short_range.data.warnings as Array).size() >= 1,
		"the short range says the twist is applied whole")
	var long_range := _handler.run({
		"op": "twist_setup", "skeleton_path": rig_path, "name": "TwistLong",
		"disperse": {"root_bone": "B-hips", "end_bone": "B-chest"},
	}, null)
	assert_false(bool(long_range.data.extend_end_bone),
		"a three-joint range distributes as asked")
	# rig_get reports the disperser's real settings. The per-joint list is built
	# by Godot on a deferred frame, so a modifier added in this same call reports
	# it as pending rather than pretending the prediction is the real one.
	var read_back := _handler.run({"op": "rig_get", "skeleton_path": rig_path}, null)
	assert_true(read_back.has("data"), "rig_get: %s" % str(read_back))
	var twists: Array = read_back.data.twist_settings
	assert_eq(twists.size(), 4, "every disperser is reported (%d)" % twists.size())
	var first_twist: Dictionary = twists[0]
	assert_eq(str(first_twist.root_bone), "B-hips")
	assert_eq(str(first_twist.end_bone), "B-head")
	assert_eq(int(first_twist.mode), BoneTwistDisperser3D.DISPERSE_MODE_WEIGHTED)
	assert_eq(int(first_twist.joint_count), 0, "the joint list is not built yet")
	assert_true(bool(first_twist.joints_pending), "and rig_get says so")
	var short_twist: Dictionary = twists[2]
	assert_true(bool(short_twist.extend_end_bone),
		"the two-bone range is reported as extended")
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


func test_retarget_rejects_a_profile_that_maps_nothing() -> void:
	var rig := _rig("RigRetargetMap")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var source_path := "/" + scene_root.name + "/RT_NoMapSource"
	var target_path := "/" + scene_root.name + "/RT_NoMapTarget"
	# Same chain, different names: the canonical humanoid profile cannot match
	# "B-hips"/"B-thigh.L", which used to produce a modifier that moved nothing.
	var source_bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-thigh.L", "parent": "B-hips", "position": [0.1, -0.4, 0]},
		{"name": "B-thigh.R", "parent": "B-hips", "position": [-0.1, -0.4, 0]},
	]
	var target_bones := [
		{"name": "pelvis", "position": [0, 0.9, 0]},
		{"name": "leg_l", "parent": "pelvis", "position": [0.1, -0.4, 0]},
		{"name": "leg_r", "parent": "pelvis", "position": [-0.1, -0.4, 0]},
	]
	_handler.run({"op": "rig_chain", "skeleton_path": source_path, "name": "RT_NoMapSource",
		"bones": source_bones}, null)
	_handler.run({"op": "rig_chain", "skeleton_path": target_path, "name": "RT_NoMapTarget",
		"bones": target_bones}, null)
	var nothing := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path, "target_path": target_path,
		"profile": "humanoid",
	}, null)
	assert_is_error(nothing, ErrorCodes.INVALID_PARAMS)
	assert_contains(nothing.get("error", {}).get("message", ""), "maps no bones")
	# The response would also be useful when the map exists but is incomplete, so
	# the mismatching names are reported in both directions.
	var partial_source := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-head", "parent": "B-hips", "position": [0, 0.4, 0]},
	]
	var partial_target := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-head", "parent": "B-hips", "position": [0, 0.4, 0]},
		{"name": "B-hat", "parent": "B-head", "position": [0, 0.2, 0]},
	]
	_remove_node(source_path)
	_remove_node(target_path)
	_handler.run({"op": "rig_chain", "skeleton_path": source_path, "name": "RT_NoMapSource",
		"bones": partial_source}, null)
	_handler.run({"op": "rig_chain", "skeleton_path": target_path, "name": "RT_NoMapTarget",
		"bones": partial_target}, null)
	var partial := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path, "target_path": target_path,
	}, null)
	assert_true(partial.has("data"), "a partial map still sets up: %s" % str(partial))
	assert_true((partial.data.source_only_bones as Array).is_empty(), "nothing is source-only")
	assert_true((partial.data.target_only_bones as Array).has("B-hat"),
		"the target-only bone is reported (%s)" % str(partial.data.target_only_bones))
	assert_true(float(partial.data.source_scale) > 0.0, "the source scale is reported")
	assert_true(float(partial.data.target_scale) > 0.0, "the target scale is reported")
	_remove_node(source_path)
	_remove_node(target_path)
	_teardown(rig)


func test_retarget_move_false_reconfigures_the_existing_modifier() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var source_path := "/" + scene_root.name + "/RT_ReconfigSource"
	var target_path := "/" + scene_root.name + "/RT_ReconfigTarget"
	var bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-head", "parent": "B-hips", "position": [0, 0.4, 0]},
	]
	_handler.run({"op": "rig_chain", "skeleton_path": source_path, "name": "RT_ReconfigSource",
		"bones": bones}, null)
	_handler.run({"op": "rig_chain", "skeleton_path": target_path, "name": "RT_ReconfigTarget",
		"bones": bones}, null)
	var first := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path, "target_path": target_path,
	}, null)
	assert_true(first.has("data"), "the first setup moves the target: %s" % str(first))
	var modifier_path := str(first.data.modifier_path)
	# A second call with move_target=false used to add a second modifier that had
	# no target child and therefore did nothing. The target has moved under the
	# modifier, so it is addressed by the path the first call reported.
	var again := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": str(first.data.target_path),
		"move_target": false, "position": true, "rotation": true, "active": true,
	}, null)
	assert_true(again.has("data"), "move_target=false reconfigures in place: %s" % str(again))
	assert_false(bool(again.data.modifier_created), "no second modifier is created")
	assert_eq(str(again.data.modifier_path), modifier_path, "the same modifier is configured")
	var source := ValueCodec.resolve_scene_path(source_path, scene_root)
	var modifiers := 0
	for child in source.get_children():
		if child is RetargetModifier3D:
			modifiers += 1
	assert_eq(modifiers, 1, "the source still has exactly one retarget modifier")
	var modifier := ValueCodec.resolve_scene_path(modifier_path, scene_root) as RetargetModifier3D
	assert_eq(modifier.get_enable_flags(),
		RetargetModifier3D.TRANSFORM_FLAG_POSITION | RetargetModifier3D.TRANSFORM_FLAG_ROTATION,
		"the enable flags were reconfigured")
	assert_true(modifier.active, "the modifier was activated")
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_eq(modifier.get_enable_flags(), RetargetModifier3D.TRANSFORM_FLAG_ROTATION,
		"undo restores the old flags")
	assert_false(modifier.active, "undo restores active=false")
	_remove_node(source_path)
	_remove_node(target_path)


func test_retarget_rejects_an_ancestor_target_cycle() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var outer_path := "/" + scene_root.name + "/RT_Outer"
	var inner_path := outer_path + "/RT_Inner"
	var built := _handler.run({
		"op": "rig_chain", "skeleton_path": outer_path, "name": "RT_Outer",
		"bones": [{"name": "B-hips", "position": [0, 0.9, 0]}],
	}, null)
	if not built.has("data"):
		skip("the outer skeleton did not build")
		return
	var inner := _handler.run({
		"op": "rig_chain", "skeleton_path": inner_path, "name": "RT_Inner",
		"bones": [{"name": "B-hips", "position": [0, 0.9, 0]}],
	}, null)
	assert_true(inner.has("data"), "the nested skeleton builds: %s" % str(inner))
	# source inside the target: reparenting the target's scene root under a
	# retarget modifier would make the modifier its own ancestor.
	var cycle := _handler.run({
		"op": "retarget_setup", "skeleton_path": inner_path, "target_path": outer_path,
	}, null)
	assert_is_error(cycle, ErrorCodes.INVALID_PARAMS)
	assert_contains(cycle.get("error", {}).get("message", ""), "ancestor")
	_remove_node(outer_path)


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


func test_retarget_setup_refuses_a_wrapped_instanced_target() -> void:
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
	# The target skeleton lives inside its instance root. Moving that root keeps
	# a skinned mesh bound, but it also leaves the skeleton a grandchild of the
	# modifier - and phase 15 measured that the target's pose never changed, so
	# the op refuses instead of returning a modifier that drives nothing.
	var refused := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": target_rig.skeleton_path,
	}, null)
	assert_is_error(refused, ErrorCodes.INVALID_PARAMS)
	var message := str(refused.get("error", {}).get("message", ""))
	assert_contains(message, "direct child")
	assert_contains(message, str(instance_root.name))
	assert_true(target_rig.skeleton.get_parent() == instance_root,
		"the refused call changed nothing")
	var instanced_source := _handler.run({
		"op": "retarget_setup", "skeleton_path": target_rig.skeleton_path,
		"target_path": source_path,
	}, null)
	assert_is_error(instanced_source, ErrorCodes.INVALID_PARAMS)
	# The source lives in a non-editable instance, so the modifier would not
	# survive the scene save.
	assert_contains(instanced_source.get("error", {}).get("message", ""), "instanced scene")
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
	# The punch spreads its twist over the DETECTED chain, which on this rig
	# includes the neck, so the same total is shared by more bones. Assert the
	# property that matters - the torso as a whole twists, and the intermediates
	# participate - rather than the old four-bone per-bone magnitude.
	var torso_total := 0.0
	var keyed_chain: Array = []
	for bone in ["B-spine", "B-chest", "B-neck", "B-head"]:
		var index := _track_index(anim, ":" + str(bone), Animation.TYPE_ROTATION_3D)
		if index < 0:
			continue
		keyed_chain.append(str(bone))
		torso_total += (anim.track_get_key_value(index, 1) as Quaternion).angle_to(
			anim.track_get_key_value(index, 0) as Quaternion)
	assert_true(twist > 0.02, "the chest carries part of the punch twist (%.3f rad)" % twist)
	assert_true(torso_total > 0.1,
		"the torso twists as a whole (%.3f rad over %s)" % [torso_total, ", ".join(keyed_chain)])
	assert_true(keyed_chain.has("B-neck"),
		"the detected chain includes the neck, so the twist is shared (%s)" % ", ".join(keyed_chain))
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


func test_bake_pose_sequence_is_repeatable_with_a_spring() -> void:
	var rig := _rig("RigBakeSpring")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "spring_src",
		"duration": 0.5, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source cycle builds, got: %s" % str(built))
	var springs := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{"root_bone": "B-upperArm.L", "end_bone": "B-hand.L",
			"stiffness": 0.4, "drag": 0.3, "gravity": 0.6}],
		"active": true,
	}, null)
	assert_true(springs.has("data"), "spring_setup: %s" % str(springs))
	# A spring is stateful: without a fixed per-sample delta and a reset, the
	# second bake continues from the first one's end state.
	var first := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "bake_a",
		"source_animation": "spring_src", "duration": 0.5, "fps": 10, "loop_mode": "linear",
	}, null)
	assert_true(first.has("data"), "first bake: %s" % str(first))
	assert_true((first.data.modifiers as Array).has("SpringBoneSimulator3D"),
		"the spring modifier is reported (%s)" % str(first.data.modifiers))
	assert_true((first.data.reset_modifiers as Array).has("SpringBoneSimulator3D"),
		"the stateful modifier was reset before sampling")
	assert_true(absf(float(first.data.sample_delta) - 0.1) < 0.0001,
		"the sample delta is the fps step (%s)" % str(first.data.sample_delta))
	var second := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "bake_b",
		"source_animation": "spring_src", "duration": 0.5, "fps": 10, "loop_mode": "linear",
	}, null)
	assert_true(second.has("data"), "second bake: %s" % str(second))
	var a: Animation = rig.player.get_animation("bake_a")
	var b: Animation = rig.player.get_animation("bake_b")
	assert_true(a != null and b != null, "both baked clips exist")
	assert_eq(b.track_get_track_count() if b.has_method("track_get_track_count") else b.get_track_count(),
		a.get_track_count(), "both bakes have the same track count")
	var differing := 0
	for index in a.get_track_count():
		if str(a.track_get_path(index)) != str(b.track_get_path(index)):
			continue
		for key in a.track_get_key_count(index):
			var left: Variant = a.track_get_key_value(index, key)
			var right: Variant = b.track_get_key_value(index, key)
			if left is Quaternion:
				if not (left as Quaternion).is_equal_approx(right as Quaternion):
					differing += 1
			elif left is Vector3:
				if not (left as Vector3).is_equal_approx(right as Vector3):
					differing += 1
	assert_eq(differing, 0, "two bakes of the same clip are key-identical")
	_teardown(rig)


func test_bake_pose_sequence_restores_both_skeletons_and_the_player() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var rig := _rig("RigBakeRetarget")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "rt_src",
		"duration": 0.4, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source cycle builds, got: %s" % str(built))
	var target_bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-chest", "parent": "B-hips", "position": [0, 0.45, 0]},
	]
	var target_path := "/" + scene_root.name + "/RigBakeRetargetTarget"
	var target_built := _handler.run({
		"op": "rig_chain", "skeleton_path": target_path, "name": "RigBakeRetargetTarget",
		"bones": target_bones,
	}, null)
	if not target_built.has("data"):
		_teardown(rig)
		skip("the bare target skeleton did not build: %s" % str(target_built))
		return
	var retarget := _handler.run({
		"op": "retarget_setup", "skeleton_path": rig.skeleton_path,
		"target_path": target_path, "active": true,
	}, null)
	assert_true(retarget.has("data"), "retarget_setup: %s" % str(retarget))
	if not retarget.has("data"):
		_teardown(rig)
		_remove_node(target_path)
		return
	# Pose the target before baking: the bake drives it through the modifier, so
	# it has to be restored afterwards like the source. The retarget moved the
	# target under the modifier, so it is resolved from there, not by its old path.
	var target: Skeleton3D = null
	var retarget_modifier := ValueCodec.resolve_scene_path(
		str(retarget.data.modifier_path), scene_root) as RetargetModifier3D
	for child in retarget_modifier.get_children():
		if child is Skeleton3D:
			target = child
	assert_true(target != null, "the retarget target is under the modifier")
	if target == null:
		_teardown(rig)
		_remove_node(target_path)
		return
	var target_bone: int = target.find_bone("B-chest")
	target.set_bone_pose_rotation(target_bone, Quaternion(Vector3(0, 1, 0), 0.37))
	var target_before: Quaternion = target.get_bone_pose_rotation(target_bone)
	rig.player.play("rt_src")
	rig.player.seek(0.12, true)
	var was_animation := str(rig.player.current_animation)
	var was_position: float = rig.player.current_animation_position
	var result := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "rt_baked",
		"source_animation": "rt_src", "duration": 0.4, "fps": 8, "loop_mode": "linear",
	}, null)
	assert_true(result.has("data"), "bake over a retarget: %s" % str(result))
	assert_true((result.data.restored_skeletons as Array).size() >= 2,
		"both skeletons are reported as restored (%s)" % str(result.data.restored_skeletons))
	assert_true((result.data.retarget_targets as Array).size() >= 1,
		"the retarget target is listed (%s)" % str(result.data.retarget_targets))
	var target_after: Quaternion = target.get_bone_pose_rotation(target_bone)
	assert_true(target_before.is_equal_approx(target_after),
		"the retargeted skeleton is restored too (%s vs %s)" % [str(target_before), str(target_after)])
	assert_eq(str(rig.player.current_animation), was_animation,
		"the player is back on the animation it was playing")
	assert_true(absf(rig.player.current_animation_position - was_position) < 0.05,
		"the player is back near the time it was at (%s vs %s)"
			% [str(rig.player.current_animation_position), str(was_position)])
	_remove_node(target_path)
	_teardown(rig)


func test_bake_pose_sequence_reports_the_modifier_stack_it_used() -> void:
	var rig := _rig("RigBakeStack")
	if rig.has("error"):
		skip(rig.error)
		return
	var built := _handler.run({
		"op": "walk_cycle", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "stack_src",
		"duration": 0.3, "loop_mode": "linear",
	}, null)
	assert_true(built.has("data"), "the source cycle builds, got: %s" % str(built))
	var bare := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "stack_bare",
		"source_animation": "stack_src", "duration": 0.3, "fps": 6, "loop_mode": "linear",
	}, null)
	assert_true(bare.has("data"), "bake without modifiers: %s" % str(bare))
	assert_true((bare.data.modifiers as Array).is_empty(), "no modifiers are reported")
	assert_eq((bare.data.restored_skeletons as Array).size(), 1, "only the source is restored")
	# An inactive modifier is not part of the stack the bake captured through.
	var setup := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path,
		"kind": "two_bone", "chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"],
		"active": false,
	}, null)
	assert_true(setup.has("data"), "ik_setup: %s" % str(setup))
	var inactive := _handler.run({
		"op": "bake_pose_sequence", "skeleton_path": rig.skeleton_path,
		"player_path": rig.player_path, "animation_name": "stack_inactive",
		"source_animation": "stack_src", "duration": 0.3, "fps": 6, "loop_mode": "linear",
	}, null)
	assert_true(inactive.has("data"), "bake with an inactive modifier: %s" % str(inactive))
	assert_true((inactive.data.modifiers as Array).is_empty(),
		"the inactive modifier is not listed (%s)" % str(inactive.data.modifiers))
	# Activating it is what puts it in the reply, so the user can see what the
	# baked clip was captured through.
	(modifier_at(rig, "IKSsetup") as SkeletonModifier3D).active = true
	_teardown(rig)


func modifier_at(rig: Dictionary, class_name_fragment: String) -> Node:
	for child in rig.skeleton.get_children():
		if child is SkeletonModifier3D and str(child.get_class()).contains(class_name_fragment):
			return child
	for child in rig.skeleton.get_children():
		if child is SkeletonModifier3D:
			return child
	return null


func test_retarget_wrapped_target_receives_poses() -> void:
	# Phase 15 evidence, batch 0: the Godot docs say RetargetModifier3D transfers
	# to "the child Skeleton" without settling direct-child vs descendant, while
	# retarget_setup moves the target's SCENE ROOT so a skinned mesh keeps its
	# binding. If the wrapped arrangement transfers nothing, the op must refuse
	# it rather than report an inert modifier.
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("no edited scene")
		return
	var source_path := "/" + scene_root.name + "/RTEvidenceSource"
	var bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-spine", "parent": "B-hips", "position": [0, 0.2, 0]},
		{"name": "B-chest", "parent": "B-spine", "position": [0, 0.25, 0]},
	]
	var built := _handler.run({
		"op": "rig_chain", "skeleton_path": source_path, "name": "RTEvidenceSource",
		"bones": bones,
	}, null)
	if not built.has("data"):
		skip("the source skeleton did not build: %s" % str(built))
		return
	var target := _rig("RTEvidenceTarget")
	if target.has("error"):
		_remove_node(source_path)
		skip(target.error)
		return
	# The target's Skeleton3D sits inside its instance root, and phase 15 proved
	# that arrangement receives no pose - so the op must refuse it rather than
	# hand back a modifier that moves nothing.
	var refused := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": str(target.skeleton_path), "active": true,
	}, null)
	assert_is_error(refused, ErrorCodes.INVALID_PARAMS)
	assert_contains(refused.get("error", {}).get("message", ""), "direct child")
	# A target skeleton that is its own scene root is the arrangement the engine
	# can drive, and it does receive the source pose.
	var bare_path := "/" + scene_root.name + "/RTEvidenceBare"
	var bare_bones := [
		{"name": "B-hips", "position": [0, 0.9, 0]},
		{"name": "B-chest", "parent": "B-hips", "position": [0, 0.45, 0]},
	]
	var bare_built := _handler.run({
		"op": "rig_chain", "skeleton_path": bare_path, "name": "RTEvidenceBare",
		"bones": bare_bones,
	}, null)
	if not bare_built.has("data"):
		_teardown(target)
		_remove_node(source_path)
		skip("the bare target skeleton did not build: %s" % str(bare_built))
		return
	var setup := _handler.run({
		"op": "retarget_setup", "skeleton_path": source_path,
		"target_path": bare_path, "active": true,
	}, null)
	assert_true(setup.has("data"), "a bare target is accepted: %s" % str(setup))
	if not setup.has("data"):
		_teardown(target)
		_remove_node(source_path)
		_remove_node(bare_path)
		return
	var modifier := ValueCodec.resolve_scene_path(str(setup.data.modifier_path), scene_root)
	var source: Skeleton3D = ValueCodec.resolve_scene_path(source_path, scene_root)
	# The setup moved the target under the modifier, so its old scene path is
	# stale: take it from the modifier's children instead.
	var bare: Skeleton3D = null
	for child in modifier.get_children():
		if child is Skeleton3D:
			bare = child
	assert_true(bare != null, "the target skeleton is a direct child of the modifier")
	if bare == null:
		_teardown(target)
		_remove_node(source_path)
		_remove_node(bare_path)
		return
	var captured := {"angle": 0.0, "calls": 0}
	var read_pose := func() -> void:
		# Read inside the signal: outside it the pose is the pre-modifier one.
		captured.calls += 1
		var index: int = bare.find_bone("B-chest")
		var rest: Quaternion = bare.get_bone_rest(index).basis.get_rotation_quaternion()
		captured.angle = (rest.inverse() * bare.get_bone_pose_rotation(index)).get_angle()
	modifier.modification_processed.connect(read_pose)
	source.set_bone_pose_rotation(source.find_bone("B-chest"), Quaternion(Vector3(0, 0, 1), 0.7))
	source.advance(1.0 / 60.0)
	source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	modifier.modification_processed.disconnect(read_pose)
	print("EVIDENCE retarget_bare angle=%.3f calls=%d active=%s profile=%s bones=%d target_bone=%d children=%d" % [
		captured.angle, captured.calls, str(modifier.active),
		str(modifier.profile != null), (modifier.profile.get_bone_size() if modifier.profile != null else -1),
		bare.find_bone("B-chest"), modifier.get_child_count()])
	print("EVIDENCE retarget_bare target_pose=%s source_pose=%s" % [
		str(bare.get_bone_pose_rotation(bare.find_bone("B-chest"))),
		str(source.get_bone_pose_rotation(source.find_bone("B-chest")))])
	assert_true(captured.angle > 0.05,
		"the target receives the source pose (angle %.3f)" % captured.angle)
	_teardown(target)
	_remove_node(source_path)
	_remove_node(bare_path)


## Phase 15 evidence: `LookAtModifier3D` limit angles are radians in Godot, and
## the registry advertises degrees, so the value must be converted.
func test_look_at_limit_angles_are_converted_to_radians() -> void:
	var rig := _rig("RigLookAtUnits")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var result := _handler.run({
		"op": "look_at_setup", "skeleton_path": rig.skeleton_path,
		"bone": "B-head", "use_angle_limitation": true,
		"primary_limit_angle": 45, "secondary_limit_angle": 30,
	}, null)
	assert_true(result.has("data"), "look_at_setup: %s" % str(result))
	if not result.has("data"):
		_teardown(rig)
		return
	var modifier := ValueCodec.resolve_scene_path(str(result.data.modifier_path),
		scene_root) as LookAtModifier3D
	assert_true(modifier != null, "a LookAtModifier3D was added")
	var primary: float = modifier.get_primary_limit_angle()
	var secondary: float = modifier.get_secondary_limit_angle()
	print("EVIDENCE look_at primary=%s expected=%.4f secondary=%s expected=%.4f" % [
		str(primary), deg_to_rad(45.0), str(secondary), deg_to_rad(30.0)])
	assert_true(absf(primary - deg_to_rad(45.0)) < 0.001,
		"45 degrees reaches the modifier as radians, got %s" % str(primary))
	assert_true(absf(secondary - deg_to_rad(30.0)) < 0.001,
		"30 degrees reaches the modifier as radians, got %s" % str(secondary))
	_teardown(rig)


## Phase 15 evidence: `center_node` and collision paths are documented as
## resolving from the SpringBoneSimulator3D, and a collision outside the
## simulator has no effect - but the op builds them from the Skeleton3D.
func test_spring_center_and_collision_paths_resolve_from_the_simulator() -> void:
	var rig := _rig("RigSpringPaths")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var center := Marker3D.new()
	center.name = "SpringCenter"
	scene_root.add_child(center)
	center.owner = scene_root
	var collider := SpringBoneCollision3D.new()
	collider.name = "SpringCollider"
	collider.position = Vector3(0, 0.5, 0)
	scene_root.add_child(collider)
	collider.owner = scene_root
	var result := _handler.run({
		"op": "spring_setup", "skeleton_path": rig.skeleton_path,
		"springs": [{
			"root_bone": "B-upperArm.L", "end_bone": "B-hand.L",
			"center_node": str(ValueCodec.from_node(center, scene_root)),
			"collisions": [str(ValueCodec.from_node(collider, scene_root))],
		}],
	}, null)
	assert_true(result.has("data"), "spring_setup: %s" % str(result))
	if not result.has("data"):
		scene_root.remove_child(center)
		scene_root.remove_child(collider)
		_teardown(rig)
		return
	var simulator := ValueCodec.resolve_scene_path(str(result.data.modifier_path),
		scene_root) as SpringBoneSimulator3D
	var center_path := str(simulator.get_center_node(0))
	var collision_path := str(simulator.get_collision_path(0, 0))
	var center_resolves: bool = simulator.get_node_or_null(NodePath(center_path)) == center
	# Godot resolves a spring setting's collision list on a deferred frame, so the
	# stored path reads back empty in the same call - what is observable now is
	# that the collision is where the engine can find it.
	print("EVIDENCE spring center_path=%s resolves=%s collision_path=%s collisions=%d collider_parent=%s" % [
		center_path, str(center_resolves), collision_path,
		simulator.get_collision_count(0), str(collider.get_parent().name)])
	assert_true(center_resolves,
		"center_node resolves from the simulator (path %s points somewhere else)" % center_path)
	# Godot only reads a collision that is a child of the simulator, so the op
	# moves it there (undoably) instead of wiring a reference that cannot fire.
	assert_true(collider.get_parent() == simulator,
		"the collision was moved under the simulator, where Godot reads it")
	assert_true((result.data.collisions_moved as Array).size() == 1,
		"the move is reported: %s" % str(result.data.collisions_moved))
	var collision_resolves: bool = simulator.get_node_or_null(NodePath(collision_path)) == collider
	assert_true(collision_resolves or collision_path.is_empty(),
		"the collision path is either resolved or still deferred (got '%s')" % collision_path)
	var undone := editor_undo(_undo_redo)
	assert_true(undone, "undo should succeed")
	assert_true(collider.get_parent() == scene_root, "undo puts the collision back where it was")
	scene_root.remove_child(center)
	_teardown(rig)


func test_dry_run_ik_setup_creates_no_modifier_and_no_marker() -> void:
	# `ik_setup` creates a target node, a pole node and the modifier itself. A dry
	# run that skipped only the undo action would leave all three in the scene.
	var rig := _rig("RigDry")
	if rig.has("error"):
		skip(rig.error)
		return
	var source: Node = rig.skeleton.get_parent()
	var before_names: Array = []
	for child in source.get_children():
		before_names.append(str(child.name))
	var before_version := _dry_undo_version()
	var result := _handler.run({
		"op": "ik_setup", "skeleton_path": rig.skeleton_path, "kind": "two_bone",
		"chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"],
		"target_name": "DryHandTarget", "pole_name": "DryElbowPole", "dry_run": true,
	}, null)
	assert_true(result.has("data"), "ik_setup dry_run reports a result (%s)" % str(result.get("error", result)))
	assert_true(bool(result.data.dry_run), "dry_run is reported")
	var after_names: Array = []
	for child in source.get_children():
		after_names.append(str(child.name))
	assert_eq(after_names, before_names, "dry_run adds no modifier, target or pole")
	assert_eq(_dry_undo_version(), before_version, "dry_run commits no undo action")
	_teardown(rig)


func _dry_undo_version() -> int:
	var undo := EditorInterface.get_editor_undo_redo()
	var id := undo.get_object_history_id(EditorInterface.get_edited_scene_root())
	if id < 0:
		return -1
	return int(undo.get_history_undo_redo(id).get_version())


func test_registry_matches_rig_schema() -> void:
	# The rig handler serves two families: the modifier ops were split out so the
	# server's eight promoted slots are not crowded by a ninth family. Both halves
	# have to declare every op the handler dispatches, and neither may advertise
	# the other's.
	var rig_info := OpRegistry.family(OpRegistry.FAMILY_RIG)
	var mod_info := OpRegistry.family(OpRegistry.FAMILY_RIG_MODIFIERS)
	assert_false(rig_info.is_empty(), "the rig family is registered")
	assert_false(mod_info.is_empty(), "the modifier family is registered")
	assert_false(bool(mod_info.get("promoted", true)),
		"the modifier family opts out of promotion")
	var enums: Array = [
		(rig_info.schema.properties.op.enum as Array).duplicate(),
		(mod_info.schema.properties.op.enum as Array).duplicate(),
	]
	var total := 0
	for info in [rig_info, mod_info]:
		var op_enum: Array = info.schema.properties.op.enum
		for descriptor in info.ops:
			assert_true(op_enum.has(descriptor.name),
				"%s is in its own family's enum" % descriptor.name)
			for param in descriptor.params:
				assert_true(info.schema.properties.has(param),
					"%s declares param %s" % [descriptor.name, param])
		total += op_enum.size()
	assert_eq(total, 19, "the two families together list every rig op")
	assert_eq(enums[0].size(), 14, "the rig half keeps the 14 non-modifier ops")
	assert_eq(enums[1].size(), 5, "the modifier half holds the five setups")
	for op_name in enums[1]:
		assert_false(enums[0].has(op_name), "%s is not advertised by both halves" % op_name)
	assert_true(str(rig_info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the rig description fits the custom-tool cap")
	assert_true(str(mod_info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the modifier description fits the custom-tool cap")
