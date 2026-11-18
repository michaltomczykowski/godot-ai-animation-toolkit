extends SceneTree
const Checker := preload("../tools/check_jump_quality.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for scale_value in [0.5, 1.0, 2.0]:
		var rig := Skeleton3D.new()
		root.add_child(rig)
		rig.position = Vector3(8, -3, 4)
		rig.basis = Basis(Vector3(1,2,3).normalized(), 0.7).scaled(Vector3.ONE * scale_value)
		for name in ["armature", "hips", "child", "grandchild", "sibling"]: rig.add_bone(name)
		rig.set_bone_parent(1, 0)
		rig.set_bone_parent(2, 1)
		rig.set_bone_parent(3, 2)
		rig.set_bone_parent(4, 0)
		for bone in 5: rig.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
		rig.reset_bone_poses()
		var before: Array[Vector3] = []
		for bone in 5: before.append(rig.get_bone_global_pose(bone).origin)
		var travel := Vector3(0.3, 0.0, -0.4)
		rig.set_bone_pose_position(1, rig.get_bone_pose_position(1) + rig.global_basis.inverse() * travel)
		for bone in 5:
			var expected: Vector3 = Checker._recovery_translation(rig, bone, 1, travel)
			check(expected == (travel if bone in [1,2,3] else Vector3.ZERO), "travel ownership follows actual hips ancestry")
			var actual := rig.global_basis * (rig.get_bone_global_pose(bone).origin - before[bone])
			check((actual - expected).length() < 0.000001, "untouched ancestor/sibling and moved hips descendants recover in world metres")
		# A physical residual in either ownership class must remain visible.
		for bone in [0, 2]:
			var saved := rig.get_bone_pose_position(bone)
			var fault := Vector3(0.013, 0.0, 0.0)
			rig.set_bone_pose_position(bone, saved + rig.global_basis.inverse() * fault)
			var residual := rig.global_basis * (rig.get_bone_global_pose(bone).origin - before[bone]) - Checker._recovery_translation(rig, bone, 1, travel)
			check(absf(residual.length() - 0.013) < 0.000001, "unrecovered ancestor or hips child is never subtracted away")
			rig.set_bone_pose_position(bone, saved)
		rig.free()
	print("JUMP_RECOVERY_CONTROLS=" + JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
