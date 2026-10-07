@tool
extends RefCounted

const Sandbox := preload("res://addons/godot_ai_animation/utils/evaluation_sandbox.gd")
const Errors := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const RootMotion := preload("res://addons/godot_ai_animation/utils/bake_root_motion.gd")
const SUPPORTED := ["TwoBoneIK3D", "CCDIK3D", "FABRIK3D", "SplineIK3D", "LookAtModifier3D", "BoneTwistDisperser3D", "RetargetModifier3D", "SpringBoneSimulator3D"]
class Witness extends SkeletonModifier3D:
	var poses: Array = []
	var count := 0
	var skin_poses: Array = []
	var skin_count := 0
	func _process_modification_with_delta(_delta: float) -> void:
		poses.clear()
		var skeleton := get_skeleton()
		for i in skeleton.get_bone_count():
			poses.append({"rotation": skeleton.get_bone_pose_rotation(i), "position": skeleton.get_bone_pose_position(i), "scale": skeleton.get_bone_pose_scale(i)})
		count += 1
	func capture_skin() -> void:
		skin_poses.clear()
		var rig := get_skeleton()
		for i in rig.get_bone_count(): skin_poses.append(rig.get_bone_pose(i))
		skin_count += 1
var sandbox := Sandbox.new()
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var graph_replay: RefCounted
var root_motion: RefCounted
var rigs: Array[Skeleton3D] = []
var witnesses: Dictionary = {}
var modifiers: Array = []
var reset_modifiers: Array = []
var preserved: Array = []
var _test_fail_at := -1.0 # Internal failure injection; never exposed on the tool wire.

func open(scene_root: Node, source_skeleton: Skeleton3D, source_player: AnimationPlayer, animation: String, source_tree: AnimationTree = null, replay: RefCounted = null, motion: RefCounted = null, motion_owner: Node3D = null) -> Dictionary:
	if source_player.get_script() != null:
		return _fail("custom animation processors cannot be replayed")
	if source_tree != null and source_tree.get_script() != null: return _fail("custom tree processors cannot be replayed")
	var needed := {source_skeleton: true}
	var ancestor := source_skeleton.get_parent()
	while ancestor != null and ancestor != scene_root:
		if ancestor is Skeleton3D: needed[ancestor] = true
		ancestor = ancestor.get_parent()
	for rig in needed.keys(): _retarget_rigs(rig, needed)
	var candidates: Array = []
	for rig in needed:
		preserved.append(rig)
		for child in rig.get_children():
			if child is SkeletonModifier3D: candidates.append(child)
	for candidate in candidates:
		if not candidate.active: continue
		if candidate is PhysicalBoneSimulator3D and not candidate.is_simulating_physics(): continue
		if candidate.get_script() != null or not SUPPORTED.has(candidate.get_class()):
			return _fail("unsupported active modifier %s (%s)" % [candidate.get_path(), candidate.get_class()])
		if candidate is SpringBoneSimulator3D:
			for i in candidate.get_setting_count():
				if candidate.get_center_from(i) != SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN and not candidate.get_children().filter(func(child): return child is SpringBoneCollision3D).is_empty():
					return _fail("relative spring centers with collisions remain unavailable")
	var opened := sandbox.open(scene_root)
	if opened.has("error"): return opened
	skeleton = sandbox.get_copy(source_skeleton)
	player = sandbox.get_copy(source_player)
	if skeleton == null or player == null:
		return _fail("required source nodes missing from private hierarchy")
	for original in sandbox.nodes:
		var copy: Node = sandbox.get_copy(original)
		if copy is Skeleton3D and needed.has(original):
			rigs.append(copy)
			var witness := Witness.new()
			witness.name = "BakeFinalPoseWitness"
			copy.add_child(witness)
			copy.skeleton_updated.connect(witness.capture_skin)
			witnesses[copy] = witness
			for child in copy.get_children():
				if child is SkeletonModifier3D and child != witness and child.active:
					if child is PhysicalBoneSimulator3D and not child.is_simulating_physics(): continue
					modifiers.append(child.get_class())
					if child is SpringBoneSimulator3D:
						reset_modifiers.append(child.get_class())
	# Dictionary insertion follows the copied hierarchy: parent/source skeletons
	# are evaluated before native retarget children and their own stacks.
	player.speed_scale = 1.0
	player.playback_auto_capture = false
	if source_tree != null:
		tree = sandbox.get_copy(source_tree)
		if tree == null: return _fail("source tree missing from private hierarchy")
		graph_replay = replay
		tree.active = true
		graph_replay.begin(tree)
		graph_replay.advance(0.0, 0.0)
	elif not animation.is_empty():
		player.active = true
		player.play(animation)
		player.advance(0.0)
	root_motion = motion
	if root_motion != null: root_motion.begin(sandbox.get_copy(motion_owner) if motion_owner != null else null)
	for rig in rigs:
		for child in rig.get_children():
			if child is SpringBoneSimulator3D and child.active: child.reset()
	return {"ok": true}

func _retarget_rigs(rig: Skeleton3D, needed: Dictionary) -> void:
	for child in rig.get_children():
		if not child is RetargetModifier3D or not child.active: continue
		for target in child.find_children("*", "Skeleton3D", true, false):
			if needed.has(target): continue
			needed[target] = true
			_retarget_rigs(target, needed)

func sample(delta: float, time: float) -> Dictionary:
	if _test_fail_at >= 0.0 and time >= _test_fail_at:
		return _fail("injected missing capture at t=%.6f" % time)
	var motion_delta: Dictionary = {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "scale": Vector3.ZERO, "accumulator": Quaternion.IDENTITY}
	if tree != null:
		if time > 0.0: graph_replay.advance(delta, time)
		motion_delta = graph_replay.last_motion
	elif delta > 0.0:
		# Stopped players retain old getter values; consume only played intervals.
		if player.is_playing():
			player.advance(delta)
			motion_delta = RootMotion.capture(player)
	if root_motion != null and time > 0.0:
		var consumed: Dictionary = root_motion.consume(motion_delta, time)
		if consumed.has("error"):
			close()
			return consumed
	var count: int = witnesses[skeleton].count
	for rig in rigs:
		var final_capture: Witness = witnesses[rig]
		var skin_count := final_capture.skin_count
		rig.advance(delta)
		rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		if final_capture.skin_count > skin_count:
			if final_capture.skin_poses.size() != final_capture.poses.size(): return _fail("skin capture missing rig=%s t=%.6f" % [rig.name, time])
			for i in final_capture.skin_poses.size():
				var pose: Dictionary = final_capture.poses[i]
				var skin: Transform3D = final_capture.skin_poses[i]
				if not skin.is_equal_approx(Transform3D(Basis(pose.rotation).scaled_local(pose.scale), pose.position)):
					return _fail("skin/final witness mismatch rig=%s bone=%s t=%.6f" % [rig.name, rig.get_bone_name(i), time])
	var witness: Witness = witnesses[skeleton]
	if witness.count != count + 1 or witness.poses.size() != skeleton.get_bone_count():
		return _fail("missing final capture at t=%.6f" % time)
	for i in witness.poses.size():
		var pose: Dictionary = witness.poses[i]
		if not pose.rotation.is_finite() or not pose.position.is_finite() or not pose.scale.is_finite():
			return _fail("nonfinite final pose bone=%s t=%.6f" % [skeleton.get_bone_name(i), time])
	return {"poses": witness.poses.duplicate(true), "motion": root_motion.sample() if root_motion != null else {}}

func close() -> void:
	sandbox.close()
	witnesses.clear()
	rigs.clear()
	skeleton = null
	player = null
	tree = null
	graph_replay = null
	root_motion = null

func _fail(message: String) -> Dictionary:
	close()
	return Errors.make(Errors.OPERATION_UNAVAILABLE, "Bake sampling: " + message)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and sandbox != null: sandbox.close()
