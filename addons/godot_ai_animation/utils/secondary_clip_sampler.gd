@tool
extends RefCounted

## Only private native playback writes poses. Secondary motion follows the
## source clip's unmodified parent transforms and invocation-authored inputs.
const Sandbox := preload("res://addons/godot_ai_animation/utils/evaluation_sandbox.gd")
const Errors := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

static func capture(root: Node, rig: Skeleton3D, source: AnimationPlayer, animation: String, bones: Array, times: Array, fail_at: int = -1) -> Dictionary:
	if source.get_script() != null: return Errors.make(Errors.OPERATION_UNAVAILABLE, "Scripted animation processors cannot be sampled for secondary motion")
	var sandbox := Sandbox.new()
	var opened := sandbox.open(root)
	if opened.has("error"): return opened
	var skeleton := sandbox.get_copy(rig) as Skeleton3D
	var player := sandbox.get_copy(source) as AnimationPlayer
	if skeleton == null or player == null:
		sandbox.close()
		return Errors.make(Errors.OPERATION_UNAVAILABLE, "The source rig/player could not be isolated from this scene")
	for original in sandbox.nodes:
		var copy := sandbox.get_copy(original)
		if copy is SkeletonModifier3D: copy.active = false
	player.stop()
	player.root_motion_track = NodePath()
	player.active = true
	player.speed_scale = 1.0
	player.playback_auto_capture = false
	player.play(animation, 0.0, 1.0)
	player.advance(0.0)
	var parents := {}
	var targets := {}
	var authored := {}
	for bone in bones:
		parents[bone] = []
		targets[bone] = []
		authored[bone] = rig.get_bone_pose_rotation(rig.find_bone(str(bone)))
	for step in times.size():
		if step == fail_at:
			sandbox.close()
			return Errors.make(Errors.OPERATION_UNAVAILABLE, "Injected secondary sampling failure at sample %d" % step)
		if step > 0: player.advance(float(times[step]) - float(times[step - 1]))
		# Value tracks may animate activation. Every sample follows the
		# unmodified parent, regardless of an authored activation key.
		for original in sandbox.nodes:
			var copy := sandbox.get_copy(original)
			if copy is SkeletonModifier3D: copy.active = false
		for bone in bones:
			var index := skeleton.find_bone(str(bone))
			var parent := skeleton.get_bone_parent(index)
			var raw_basis := skeleton.get_bone_global_pose(parent).basis
			if not raw_basis.is_finite() or absf(raw_basis.determinant()) <= 0.00000001:
				sandbox.close()
				return Errors.make(Errors.OPERATION_UNAVAILABLE, "Degenerate secondary parent transform at sample %d" % step)
			var parent_basis := raw_basis.orthonormalized()
			var target := (parent_basis * Basis(authored[bone])).get_rotation_quaternion().normalized()
			if not parent_basis.is_finite() or not target.is_finite():
				sandbox.close()
				return Errors.make(Errors.OPERATION_UNAVAILABLE, "Nonfinite secondary parent transform at sample %d" % step)
			parents[bone].append(parent_basis)
			targets[bone].append(target)
	sandbox.close()
	return {"parents": parents, "targets": targets}
