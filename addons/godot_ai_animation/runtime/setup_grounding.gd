@tool
extends SkeletonModifier3D
## Setup-owned level-plane correction after native AnimationTree FK blending.
## Serialized fields contain paths/scalars/role names only. Never consumes root motion.
const CONTRACT_VERSION := 1
const Space := preload("res://addons/godot_ai_animation/spec/motion_space.gd")
const CONFIG_FIELDS := ["influence","tree_path","player_path","role_names","rig_up","rig_forward","speed_parameter","base_prefix","jump_parameter","maximum_correction_leg_ratio","target_tolerance_m"]
@export var tree_path: NodePath
@export var player_path: NodePath
@export var role_names: Dictionary = {}
@export var rig_up := Vector3.UP
@export var rig_forward := Vector3.FORWARD
@export var speed_parameter := "parameters/blend_position"
@export var base_prefix := "parameters/"
@export var jump_parameter := ""
@export var maximum_correction_leg_ratio := 0.25
@export var target_tolerance_m := 0.00001
var status := "unbound"
var last_error := ""
var evaluations := 0
var unreachable := 0
var resets := 0
var reset_reason := "new_instance"
var max_residual_m := 0.0
var evaluation_residual_m := 0.0
var max_correction_m := 0.0
var _view: Dictionary = {}
var _signature := ""
var _anchors: Dictionary = {}
var _phases: Dictionary = {}
var _was_enabled := false
var _points: Array = []

func reset_grounding(reason: String = "explicit_seek_or_new_take") -> void:
	_anchors.clear()
	_phases.clear()
	resets += 1
	reset_reason = reason

func diagnostics() -> Dictionary:
	return {"contract_version":CONTRACT_VERSION,"status":status,"error":last_error,"evaluations":evaluations,
		"unreachable":unreachable,"resets":resets,"reset_reason":reset_reason,"max_residual_m":max_residual_m,
		"evaluation_residual_m":evaluation_residual_m,"max_correction_m":max_correction_m,"target_tolerance_m":target_tolerance_m,
		"maximum_correction_leg_ratio":maximum_correction_leg_ratio,"stance_anchors":_anchors.size()}

func _process(_delta: float) -> void:
	var tree := get_node_or_null(tree_path) as AnimationTree if not tree_path.is_empty() else null
	var enabled := active and tree != null and tree.active
	if _was_enabled and not enabled: reset_grounding("deactivated")
	_was_enabled = enabled
	if not enabled: status = "inactive"

func _fail(message: String) -> bool:
	last_error = message
	status = "unavailable"
	reset_grounding("configuration_or_runtime_error")
	return false

func validate_configuration() -> String:
	if not is_equal_approx(influence,1.0): return "Grounding requires full influence=1 for its final-pose contract"
	var rig := get_skeleton()
	if rig == null: return "Grounding must be a direct child of its Skeleton3D"
	var tree := get_node_or_null(tree_path) as AnimationTree if not tree_path.is_empty() else null
	var player := get_node_or_null(player_path) as AnimationPlayer if not player_path.is_empty() else null
	if tree == null or player == null or tree.get_node_or_null(tree.anim_player) != player: return "Grounding Tree/Player binding is unresolved or inconsistent"
	var animation_root := player.get_node_or_null(player.root_node)
	if animation_root == null or tree.get_node_or_null(tree.root_node) != animation_root: return "Grounding Tree and Player animation roots differ"
	if tree.root_motion_track != player.root_motion_track: return "Grounding extraction bindings differ"
	if not Space.geometry(rig.global_basis).has("world_scale"): return "Grounding requires a positive uniform unsheared world basis"
	if not rig_up.is_finite() or not rig_forward.is_finite() or rig_up.length() < 0.9 or rig_forward.length() < 0.9 or absf(rig_up.normalized().dot(rig_forward.normalized())) > 0.001: return "Grounding measured axes are invalid"
	if not is_finite(maximum_correction_leg_ratio) or maximum_correction_leg_ratio <= 0.0 or not is_finite(target_tolerance_m) or target_tolerance_m <= 0.0: return "Grounding solve limits are invalid"
	var owned := 0
	for node in rig.get_children():
		if node is SkeletonModifier3D:
			if node.get_script() == get_script(): owned += 1
			elif node.active: return "Foreign active bone modifier has unsupported setup ownership/order"
	if owned != 1: return "Duplicate setup grounding ownership"
	for side in ["l","r"]:
		var thigh := rig.find_bone(str(role_names.get("thigh_"+side,"")))
		var shin := rig.find_bone(str(role_names.get("shin_"+side,"")))
		var foot := rig.find_bone(str(role_names.get("foot_"+side,"")))
		if thigh < 0 or shin < 0 or foot < 0 or rig.get_bone_parent(shin) != thigh or rig.get_bone_parent(foot) != shin: return "Grounding needs explicit direct thigh/shin/foot chains"
		var a := rig.get_bone_global_rest(thigh).origin.distance_to(rig.get_bone_global_rest(shin).origin)
		var b := rig.get_bone_global_rest(shin).origin.distance_to(rig.get_bone_global_rest(foot).origin)
		if not is_finite(a+b) or minf(a,b)<=0.0000001: return "Grounding measured leg geometry is degenerate"
	var scope: Node = owner if owner != null else rig
	for mixer in scope.find_children("*","AnimationMixer",true,false):
		if mixer == tree or not mixer.active or (mixer is AnimationPlayer and not mixer.is_playing()): continue
		var other_root: Node = mixer.get_node_or_null(mixer.root_node)
		if other_root != null and (other_root == rig or other_root.is_ancestor_of(rig)): return "Another active mixer can write the grounded skeleton"
	var base: AnimationRootNode = tree.tree_root
	if base is AnimationNodeBlendTree:
		if not base.has_node("Base"): return "Grounding saved Base graph is missing"
		base = base.get_node("Base")
	if not base is AnimationNodeBlendSpace1D or base.get_blend_mode() != AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED: return "Grounding requires the setup interpolated 1D graph"
	var properties := {}
	for entry in tree.get_property_list(): properties[str(entry.name)] = true
	if not properties.has(speed_parameter): return "Grounding speed parameter is absent"
	for index in base.get_blend_point_count():
		var node: AnimationRootNode = base.get_blend_point_node(index)
		if not node is AnimationNodeAnimation or not player.has_animation(node.animation): return "Grounding point clip is missing"
		if not properties.has(base_prefix+str(base.get_blend_point_name(index))+"/current_position"): return "Grounding native point phase is absent"
		var clip := player.get_animation(node.animation)
		if str(node.animation) != "idle":
			for side in ["L","R"]:
				if not clip.has_marker("contact."+side) or not clip.has_marker("toe_off."+side): return "Grounding contact markers are missing"
	if not jump_parameter.is_empty():
		if not properties.has(jump_parameter) or not properties.has("parameters/Shot/current_position") or not properties.has("parameters/OneShot/active") or not player.has_animation("jump"): return "Grounding OneShot binding is missing"
		var clip := player.get_animation("jump")
		if not clip.has_marker("takeoff") or not clip.has_marker("land"): return "Grounding jump contact events are missing"
	return ""

func _resolve() -> bool:
	var error := validate_configuration()
	if not error.is_empty(): return _fail(error)
	var rig := get_skeleton()
	var tree := get_node(tree_path) as AnimationTree
	var player := get_node(player_path) as AnimationPlayer
	var signature := var_to_str([tree_path,player_path,role_names,rig_up,rig_forward,speed_parameter,base_prefix,jump_parameter,maximum_correction_leg_ratio,target_tolerance_m,rig.global_basis,tree.get_instance_id(),player.get_instance_id(),tree.tree_root.get_instance_id()])
	if signature != _signature:
		_signature = signature
		reset_grounding("rebound_or_reconfigured")
		var up := (rig.global_basis*rig_up).normalized()
		var indices := {}
		for side in ["l","r"]:
			for role in ["thigh_","shin_","foot_"]: indices[role+side] = rig.find_bone(str(role_names[role+side]))
		var ground := INF
		var leg := 0.0
		for side in ["l","r"]:
			var h := rig.global_transform*rig.get_bone_global_rest(indices["thigh_"+side])
			var k := rig.global_transform*rig.get_bone_global_rest(indices["shin_"+side])
			var f := rig.global_transform*rig.get_bone_global_rest(indices["foot_"+side])
			ground = minf(ground,f.origin.dot(up))
			leg += h.origin.distance_to(k.origin)+k.origin.distance_to(f.origin)
		_view = {"rig":rig,"tree":tree,"player":player,"indices":indices,"up":up,"forward":(rig.global_basis*rig_forward).normalized(),"ground":ground,"leg":leg*0.5}
	last_error = ""
	return true

func _update_points(delta: float) -> bool:
	var tree: AnimationTree = _view.tree
	var base: AnimationNodeBlendSpace1D = tree.tree_root.get_node("Base") if tree.tree_root is AnimationNodeBlendTree else tree.tree_root
	var speed := float(tree.get(speed_parameter))
	if not is_finite(speed): return _fail("Grounding speed is nonfinite")
	_points.clear()
	var sought := false
	for index in base.get_blend_point_count():
		var node := base.get_blend_point_node(index) as AnimationNodeAnimation
		var phase := float(tree.get(base_prefix+str(base.get_blend_point_name(index))+"/current_position"))
		var clip: Animation = _view.player.get_animation(node.animation)
		if _phases.has(str(node.animation)):
			var step := fposmod(phase-float(_phases[str(node.animation)]),clip.length)
			if step > maxf(0.1,4.0*absf(delta)): sought = true
		_points.append({"clip":str(node.animation),"position":base.get_blend_point_position(index),"phase":phase,"weight":0.0})
	if sought: reset_grounding("native_phase_seek")
	for point in _points: _phases[point.clip] = point.phase
	_points.sort_custom(func(a,b): return a.position < b.position)
	if _points.is_empty(): return _fail("Grounding blend points are empty")
	if speed <= float(_points[0].position): _points[0].weight = 1.0
	elif speed >= float(_points[-1].position): _points[-1].weight = 1.0
	else:
		for index in _points.size()-1:
			if speed >= float(_points[index].position) and speed <= float(_points[index+1].position):
				var weight := (speed-float(_points[index].position))/(float(_points[index+1].position)-float(_points[index].position))
				_points[index].weight = 1.0-weight
				_points[index+1].weight = weight
				break
	return true

func _contact(side: String) -> bool:
	var tree: AnimationTree = _view.tree
	if not jump_parameter.is_empty() and bool(tree.get("parameters/OneShot/active")):
		var clip: Animation = _view.player.get_animation("jump")
		var phase := float(tree.get("parameters/Shot/current_position"))
		return phase <= clip.get_marker_time("takeoff")+0.000001 or phase >= clip.get_marker_time("land")-0.000001
	for point in _points:
		if float(point.weight) <= 0.000001 or point.clip == "idle": continue
		var clip: Animation = _view.player.get_animation(point.clip)
		var start := clip.get_marker_time("contact."+side.to_upper())
		var end := clip.get_marker_time("toe_off."+side.to_upper())
		if fposmod(float(point.phase)-start,clip.length) >= fposmod(end-start,clip.length)-0.000001: return false
	return true

func _arc(from: Vector3,to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var cross := a.cross(b)
	var magnitude := cross.length()
	if magnitude < 0.0000000001:
		if a.dot(b) > 0.0: return Quaternion.IDENTITY
		return Quaternion(a.cross(Vector3.RIGHT if absf(a.x)<0.8 else Vector3.UP).normalized(),PI)
	return Quaternion(cross/magnitude,atan2(magnitude,a.dot(b)))

func _set_global_rotation(rig: Skeleton3D,bone: int,basis: Basis) -> void:
	var parent := rig.get_bone_parent(bone)
	var parent_basis := rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	rig.set_bone_pose_rotation(bone,(parent_basis.inverse()*basis).orthonormalized().get_rotation_quaternion())

func _reachable(side: String,target_world: Vector3) -> bool:
	var rig: Skeleton3D = _view.rig
	var h := rig.get_bone_global_pose(_view.indices["thigh_"+side]).origin
	var k := rig.get_bone_global_pose(_view.indices["shin_"+side]).origin
	var f := rig.get_bone_global_pose(_view.indices["foot_"+side]).origin
	var a := h.distance_to(k)
	var b := k.distance_to(f)
	var d := h.distance_to(rig.global_transform.affine_inverse()*target_world)
	return d <= a+b+0.000001 and d >= absf(a-b)+0.000001

func _solve(side: String,target_world: Vector3) -> void:
	var rig: Skeleton3D = _view.rig
	var thigh: int = _view.indices["thigh_"+side]
	var shin: int = _view.indices["shin_"+side]
	var foot: int = _view.indices["foot_"+side]
	var h := rig.get_bone_global_pose(thigh)
	var k := rig.get_bone_global_pose(shin)
	var f := rig.get_bone_global_pose(foot)
	var target := rig.global_transform.affine_inverse()*target_world
	var a := h.origin.distance_to(k.origin)
	var b := k.origin.distance_to(f.origin)
	var d := h.origin.distance_to(target)
	var axis := (target-h.origin).normalized()
	var forward: Vector3 = rig.global_basis.inverse()*_view.forward
	var measured := k.origin-h.origin-axis*(k.origin-h.origin).dot(axis)
	var pole := measured if measured.length()>0.005*(a+b) else forward-axis*forward.dot(axis)
	if pole.length()<0.0001: _fail("Grounding anatomical pole is degenerate");return
	pole= pole.normalized()
	var along := (a*a+d*d-b*b)/(2.0*d)
	var knee := h.origin+axis*along+pole*sqrt(maxf(0.0,a*a-along*along))
	_set_global_rotation(rig,thigh,Basis(_arc(k.origin-h.origin,knee-h.origin))*h.basis)
	k=rig.get_bone_global_pose(shin)
	var moved_foot := rig.get_bone_global_pose(foot)
	_set_global_rotation(rig,shin,Basis(_arc(moved_foot.origin-k.origin,target-k.origin))*k.basis)
	_set_global_rotation(rig,foot,f.basis)
	evaluation_residual_m=maxf(evaluation_residual_m,(rig.global_transform*rig.get_bone_global_pose(foot)).origin.distance_to(target_world))
	max_residual_m=maxf(max_residual_m,evaluation_residual_m)

func _process_modification_with_delta(delta: float) -> void:
	if not _resolve(): return
	if not _view.tree.active:
		reset_grounding("inactive_tree")
		status="inactive"
		return
	evaluation_residual_m=0.0
	if not _update_points(delta): return
	var rig: Skeleton3D = _view.rig
	var targets := {}
	for side in ["l","r"]:
		var foot := (rig.global_transform*rig.get_bone_global_pose(_view.indices["foot_"+side])).origin
		var height: float = foot.dot(_view.up)-float(_view.ground)
		var target := foot
		if _contact(side):
			if not _anchors.has(side): _anchors[side]=foot-_view.up*height
			target=_anchors[side]
		else:
			_anchors.erase(side)
			if height < 0.0: target=foot-_view.up*height
		var correction := target.distance_to(foot)
		max_correction_m=maxf(max_correction_m,correction)
		if correction > maximum_correction_leg_ratio*float(_view.leg): _fail("Grounding correction exceeds configured leg-relative limit");return
		if not _reachable(side,target):
			unreachable+=1
			_fail("Grounding target is unreachable")
			return
		targets[side]=target
	for side in ["l","r"]:
		var foot := (rig.global_transform*rig.get_bone_global_pose(_view.indices["foot_"+side])).origin
		if foot.distance_to(targets[side])>minf(0.000001,target_tolerance_m*0.1): _solve(side,targets[side])
		if not last_error.is_empty(): return
	evaluations+=1
	if evaluation_residual_m > target_tolerance_m: _fail("Grounding IK residual exceeds configured tolerance");return
	status="grounded"
