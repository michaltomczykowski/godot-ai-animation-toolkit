extends SceneTree

## Tier-1 headless checks for the pose codec and pose math: rest-relative
## conversion, mirroring (3D and 2D conventions), blending, subsets, JSON
## round-trips and validation. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_pose_math.gd

const PoseMath := preload("res://addons/godot_ai_animation/spec/pose_math.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_basics()
	_check_rest_conversion()
	_check_mirror_names()
	_check_mirror_pose()
	_check_blend()
	_check_subset()
	_check_json()
	_check_validation()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_quat(actual: Quaternion, expected: Quaternion, message: String) -> void:
	_expect((actual as Quaternion).is_equal_approx(expected), "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_vec(actual: Vector3, expected: Vector3, message: String) -> void:
	_expect((actual as Vector3).is_equal_approx(expected), "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_error(result: Dictionary, message: String) -> void:
	_expect(result.has("error"), message)


func _pose() -> Dictionary:
	var pose := PoseMath.make_pose("res://test/Skeleton3D")
	PoseMath.set_bone(pose, "B-hips", Quaternion.IDENTITY, Vector3.ZERO, Vector3.ONE)
	PoseMath.set_bone(pose, "B-upperArm.L", Quaternion(Vector3(0, 0, 1), PI / 4.0), Vector3(0.1, 0, 0), Vector3.ONE)
	PoseMath.set_bone(pose, "B-upperArm.R", Quaternion.IDENTITY, Vector3(-0.1, 0, 0), Vector3.ONE)
	return pose


func _check_basics() -> void:
	var pose := _pose()
	_expect(PoseMath.bone_count(pose) == 3, "bone_count counts bones")
	_expect(PoseMath.has_bone(pose, "B-hips"), "has_bone finds a bone")
	_expect(not PoseMath.has_bone(pose, "B-nope"), "has_bone rejects unknown bones")
	_expect(str(PoseMath.bone_names(pose)) == str(["B-hips", "B-upperArm.L", "B-upperArm.R"]),
		"bone_names are sorted (%s)" % str(PoseMath.bone_names(pose)))
	_expect(bool(pose.rest_relative), "poses are rest-relative by default")
	_expect(str(pose.source) == "res://test/Skeleton3D", "the source is recorded")


func _check_rest_conversion() -> void:
	var rest_rotation := Quaternion(Vector3(0, 1, 0), PI / 2.0)
	var rest_position := Vector3(1, 2, 3)
	var delta := PoseMath.pose_to_delta(rest_rotation, rest_position, Vector3.ONE, rest_rotation, rest_position)
	_expect_quat(delta.rotation, Quaternion.IDENTITY, "a rest pose has an identity rotation delta")
	_expect_vec(delta.position, Vector3.ZERO, "a rest pose has a zero position delta")
	var absolute := PoseMath.delta_to_pose(delta, rest_rotation, rest_position)
	_expect_quat(absolute.rotation, rest_rotation, "identity deltas restore the rest rotation")
	_expect_vec(absolute.position, rest_position, "identity deltas restore the rest position")
	var posed_rotation := Quaternion(Vector3(0, 1, 0), PI / 3.0)
	var posed := PoseMath.pose_to_delta(posed_rotation, Vector3(2, 2, 3), Vector3.ONE, rest_rotation, rest_position)
	_expect_quat(posed.rotation, Quaternion(Vector3(0, 1, 0), PI / 3.0 - PI / 2.0),
		"rotation deltas are rest-relative")
	_expect_vec(posed.position, Vector3(1, 0, 0), "position deltas are rest-relative")
	var back := PoseMath.delta_to_pose(posed, rest_rotation, rest_position)
	_expect_quat(back.rotation, posed_rotation, "deltas convert back to the pose rotation")
	_expect_vec(back.position, Vector3(2, 2, 3), "deltas convert back to the pose position")


func _check_mirror_names() -> void:
	_expect(str(PoseMath.mirror_name("B-upperArm.L")) == "B-upperArm.R", ".L mirrors to .R")
	_expect(str(PoseMath.mirror_name("B-upperArm.R")) == "B-upperArm.L", ".R mirrors to .L")
	_expect(str(PoseMath.mirror_name("arm_L")) == "arm_R", "_L mirrors to _R")
	_expect(str(PoseMath.mirror_name("arm-R")) == "arm-L", "-R mirrors to -L")
	_expect(str(PoseMath.mirror_name("LeftHand")) == "RightHand", "Left mirrors to Right")
	_expect(str(PoseMath.mirror_name("RightHand")) == "LeftHand", "Right mirrors to Left")
	_expect(str(PoseMath.mirror_name("B-spine")) == "", "bones without a side are unmappable")
	_expect(str(PoseMath.mirror_name("B-hand.L.R")) == "B-hand.L.L", "the last side marker wins")


func _check_mirror_pose() -> void:
	var mirrored := PoseMath.mirror_pose(_pose())
	var out: Dictionary = mirrored.pose
	_expect(PoseMath.bone_count(out) == 3, "mirroring keeps the bone count")
	_expect(PoseMath.has_bone(out, "B-upperArm.R"), "the left arm moves to the right bone")
	var arm: Dictionary = out.bones["B-upperArm.R"]
	_expect_quat(arm.rotation, Quaternion(Vector3(0, 0, 1), -PI / 4.0),
		"mirroring a Z rotation reverses it (%s)" % str(arm.rotation))
	_expect_vec(arm.position, Vector3(-0.1, 0, 0), "mirroring negates the position X")
	var yaw := PoseMath.make_pose()
	PoseMath.set_bone(yaw, "B-upperArm.L", Quaternion(Vector3(0, 1, 0), PI / 2.0), Vector3.ZERO, Vector3.ONE)
	var yaw_out: Dictionary = PoseMath.mirror_pose(yaw).pose
	_expect_quat(yaw_out.bones["B-upperArm.R"].rotation, Quaternion(Vector3(0, 1, 0), -PI / 2.0),
		"mirroring a Y rotation reverses it (%s)" % str(yaw_out.bones["B-upperArm.R"].rotation))
	var roll := PoseMath.make_pose()
	PoseMath.set_bone(roll, "B-upperArm.L", Quaternion(Vector3(1, 0, 0), PI / 2.0), Vector3.ZERO, Vector3.ONE)
	var roll_out: Dictionary = PoseMath.mirror_pose(roll).pose
	_expect_quat(roll_out.bones["B-upperArm.R"].rotation, Quaternion(Vector3(1, 0, 0), PI / 2.0),
		"mirroring an X rotation keeps it (%s)" % str(roll_out.bones["B-upperArm.R"].rotation))
	_expect((mirrored.unmapped as Array).has("B-hips"), "unmappable bones are reported (%s)" % str(mirrored.unmapped))
	var twice: Dictionary = PoseMath.mirror_pose(out).pose
	var original: Dictionary = _pose().bones["B-upperArm.L"]
	var restored: Dictionary = twice.bones["B-upperArm.L"]
	_expect_quat(restored.rotation, original.rotation, "mirroring twice restores the rotation")
	_expect_vec(restored.position, original.position, "mirroring twice restores the position")


func _check_blend() -> void:
	var a := PoseMath.make_pose()
	PoseMath.set_bone(a, "bone", Quaternion.IDENTITY, Vector3(0, 0, 0), Vector3.ONE)
	PoseMath.set_bone(a, "shared", Quaternion.IDENTITY, Vector3(0, 0, 0), Vector3.ONE)
	var b := PoseMath.make_pose()
	PoseMath.set_bone(b, "bone", Quaternion(Vector3(0, 0, 1), PI / 2.0), Vector3(2, 0, 0), Vector3(2, 2, 2))
	PoseMath.set_bone(b, "other", Quaternion.IDENTITY, Vector3.ZERO, Vector3.ONE)
	var start := PoseMath.blend_pose(a, b, 0.0)
	_expect_quat(start.pose.bones["bone"].rotation, Quaternion.IDENTITY, "factor 0 keeps the first pose")
	_expect_vec(start.pose.bones["bone"].position, Vector3.ZERO, "factor 0 keeps the first position")
	var end := PoseMath.blend_pose(a, b, 1.0)
	_expect_quat(end.pose.bones["bone"].rotation, Quaternion(Vector3(0, 0, 1), PI / 2.0), "factor 1 takes the second pose")
	var half := PoseMath.blend_pose(a, b, 0.5)
	_expect_quat(half.pose.bones["bone"].rotation, Quaternion(Vector3(0, 0, 1), PI / 4.0),
		"rotations slerp (%s)" % str(half.pose.bones["bone"].rotation))
	_expect_vec(half.pose.bones["bone"].position, Vector3(1, 0, 0), "positions lerp")
	_expect_vec(half.pose.bones["bone"].scale, Vector3(1.5, 1.5, 1.5), "scales lerp")
	_expect(PoseMath.bone_count(half.pose) == 3, "the blend unions the bones")
	_expect((half.only_a as Array).has("shared"), "bones only in 'from' are reported")
	_expect((half.only_b as Array).has("other"), "bones only in 'to' are reported")
	var weighted := PoseMath.blend_many([a, b], [1.0, 3.0])
	_expect_quat(weighted.bones["bone"].rotation, Quaternion(Vector3(0, 0, 1), PI * 0.375),
		"blend_many weights the poses (%s)" % str(weighted.bones["bone"].rotation))


func _check_subset() -> void:
	var subset := PoseMath.subset(_pose(), ["B-hips", "B-nope"])
	_expect(PoseMath.bone_count(subset.pose) == 1, "subsets keep only the requested bones")
	_expect((subset.missing as Array).has("B-nope"), "missing bones are reported")
	_expect(PoseMath.has_bone(subset.pose, "B-hips"), "the kept bone survives")


func _check_json() -> void:
	var pose := _pose()
	var json := PoseMath.to_json(pose)
	_expect(str(json.format) == "godot-ai-animation-pose", "the JSON envelope names the format")
	_expect((json.bones as Dictionary).size() == 3, "every bone is encoded")
	_expect(str(json.bones["B-upperArm.L"].rotation.kind) == "quaternion", "rotations carry their kind")
	_expect(str(json.bones["B-upperArm.L"].position.kind) == "vector3", "positions carry their kind")
	var back := PoseMath.from_json(json)
	_expect(not back.has("error"), "poses decode")
	_expect(PoseMath.bone_count(back.pose) == 3, "the bone count round-trips")
	var original: Dictionary = pose.bones["B-upperArm.L"]
	var restored: Dictionary = back.pose.bones["B-upperArm.L"]
	_expect_quat(restored.rotation, original.rotation, "quaternions round-trip exactly")
	_expect_vec(restored.position, original.position, "positions round-trip exactly")
	var summary := PoseMath.summarize(back.pose)
	_expect(int(summary.bone_count) == 3, "summaries count bones")
	_expect((summary.bones as Array).size() == 3, "summaries list bone names")


func _check_validation() -> void:
	_expect_error(PoseMath.from_json("text"), "poses must be objects")
	_expect_error(PoseMath.from_json({"version": 1}), "poses need a bones section")
	_expect_error(PoseMath.from_json({"bones": {}}), "poses need at least one bone")
	var bad := PoseMath.to_json(_pose())
	bad.bones["B-hips"]["rotation"] = {"kind": "blob"}
	_expect_error(PoseMath.from_json(bad), "malformed values are rejected")
	var missing := PoseMath.to_json(_pose())
	missing.bones["B-hips"].erase("position")
	var defaulted := PoseMath.from_json(missing)
	_expect(not defaulted.has("error"), "missing position values default to zero")
	_expect_vec(defaulted.pose.bones["B-hips"].position, Vector3.ZERO, "the default position is zero")
