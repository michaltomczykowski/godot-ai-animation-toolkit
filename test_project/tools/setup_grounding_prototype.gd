extends SkeletonModifier3D
## Disposable runtime prototype. No rest/position/key edits or root consumer.
var view:Dictionary={}
var points:Array=[]
var anchors:Dictionary={}
var evaluations:=0
var unreachable:=0
var errors:Array[String]=[]
var max_residual:=0.0
var max_correction:=0.0
var bypass:=false
var max_upper_rotation:=0.0
var max_position_change:=0.0
var max_rest_change:=0.0
var max_foot_rotation:=0.0
var max_owner_motion:=0.0
func _angle(a:Quaternion,b:Quaternion)->float:
	var q:=a.inverse()*b
	return 2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w))
func _contact(side:String)->bool:
	var tree:AnimationTree=view.tree
	if view.has("shot") and bool(tree.get("parameters/OneShot/active")):
		var clip:Animation=view.player.get_animation("jump")
		var phase:=float(tree.get("parameters/Shot/current_position"))
		return phase<=clip.get_marker_time("takeoff")+0.000001 or phase>=clip.get_marker_time("land")-0.000001
	for point:Dictionary in points:
		if float(point.weight)<=0.000001 or point.clip=="idle":continue
		var clip:Animation=view.player.get_animation(point.clip)
		var phase:=float(tree.get(point.phase_path))
		var start:=clip.get_marker_time("contact."+side.to_upper())
		var end:=clip.get_marker_time("toe_off."+side.to_upper())
		if fposmod(phase-start,clip.length)>=fposmod(end-start,clip.length)-0.000001:return false
	return true
func _arc(from:Vector3,to:Vector3)->Quaternion:
	var a:=from.normalized()
	var b:=to.normalized()
	var cross:=a.cross(b)
	var magnitude:=cross.length()
	if magnitude<0.0000000001:
		if a.dot(b)>0.0:return Quaternion.IDENTITY
		var axis:=a.cross(Vector3.RIGHT if absf(a.x)<0.8 else Vector3.UP).normalized()
		return Quaternion(axis,PI)
	return Quaternion(cross/magnitude,atan2(magnitude,a.dot(b)))
func _set_global_rotation(rig:Skeleton3D,bone:int,basis:Basis)->void:
	var parent:=rig.get_bone_parent(bone)
	var parent_basis:=rig.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	rig.set_bone_pose_rotation(bone,(parent_basis.inverse()*basis).orthonormalized().get_rotation_quaternion())
func _solve(side:String,target_world:Vector3)->void:
	var rig:=get_skeleton()
	var thigh:int=view.indices["thigh_"+side]
	var shin:int=view.indices["shin_"+side]
	var foot:int=view.indices["foot_"+side]
	var h:=rig.get_bone_global_pose(thigh)
	var k:=rig.get_bone_global_pose(shin)
	var f:=rig.get_bone_global_pose(foot)
	var target:=rig.global_transform.affine_inverse()*target_world
	var a:=h.origin.distance_to(k.origin)
	var b:=k.origin.distance_to(f.origin)
	var d:=h.origin.distance_to(target)
	if d>a+b+0.000001 or d<absf(a-b)+0.000001:
		unreachable+=1
		if not errors.has("Unreachable grounded target"):errors.append("Unreachable grounded target")
		return
	var axis:Vector3=(target-h.origin).normalized()
	var forward:Vector3=rig.global_basis.inverse()*view.forward
	var measured:Vector3=k.origin-h.origin-axis*(k.origin-h.origin).dot(axis)
	var pole:Vector3=measured if measured.length()>0.005*(a+b) else forward-axis*forward.dot(axis)
	if pole.length()<0.0001:
		if not errors.has("Degenerate anatomical pole"):errors.append("Degenerate anatomical pole")
		return
	pole=pole.normalized()
	var along:float=(a*a+d*d-b*b)/(2.0*d)
	var altitude:=sqrt(maxf(0.0,a*a-along*along))
	var knee:Vector3=h.origin+axis*along+pole*altitude
	var q1:=_arc(k.origin-h.origin,knee-h.origin)
	_set_global_rotation(rig,thigh,Basis(q1)*h.basis)
	k=rig.get_bone_global_pose(shin)
	var moved_foot:=rig.get_bone_global_pose(foot)
	var q2:=_arc(moved_foot.origin-k.origin,target-k.origin)
	_set_global_rotation(rig,shin,Basis(q2)*k.basis)
	_set_global_rotation(rig,foot,f.basis)
	var final_world:Vector3=(rig.global_transform*rig.get_bone_global_pose(foot)).origin
	max_residual=maxf(max_residual,final_world.distance_to(target_world))
func _process_modification_with_delta(_delta:float)->void:
	if view.is_empty() or not is_instance_valid(view.tree) or not view.tree.active:return
	evaluations+=1
	if bypass:return
	var rig:=get_skeleton()
	var before:Array=[]
	var rests:Array=[]
	var owned:Array=[]
	var foot_rotations:Dictionary={}
	var owner_before:Vector3=view.owner.global_position
	for bone in rig.get_bone_count():
		before.append(rig.get_bone_pose(bone));rests.append(rig.get_bone_rest(bone))
	for side in ["l","r"]:
		for role in ["thigh_","shin_","foot_"]:owned.append(view.indices[role+side])
		foot_rotations[side]=rig.get_bone_global_pose(view.indices["foot_"+side]).basis.orthonormalized().get_rotation_quaternion()
	for side in ["l","r"]:
		var foot:Vector3=(rig.global_transform*rig.get_bone_global_pose(view.indices["foot_"+side])).origin
		var height:float=foot.dot(view.up)-float(view.ground)
		var target:=foot
		var contact:=_contact(side)
		if contact:
			if not anchors.has(side):anchors[side]=foot-view.up*height
			target=anchors[side]
		else:
			anchors.erase(side)
			if height<0.0:target=foot-view.up*height
		max_correction=maxf(max_correction,target.distance_to(foot))
		if target.distance_to(foot)>0.000001:_solve(side,target)

	for bone in rig.get_bone_count():
		var after:=rig.get_bone_pose(bone)
		max_position_change=maxf(max_position_change,after.origin.distance_to(before[bone].origin))
		if not owned.has(bone):max_upper_rotation=maxf(max_upper_rotation,_angle(before[bone].basis.orthonormalized().get_rotation_quaternion(),after.basis.orthonormalized().get_rotation_quaternion()))
		var rest:=rig.get_bone_rest(bone)
		if rest!=rests[bone]:max_rest_change=INF
	for side in ["l","r"]:max_foot_rotation=maxf(max_foot_rotation,_angle(foot_rotations[side],rig.get_bone_global_pose(view.indices["foot_"+side]).basis.orthonormalized().get_rotation_quaternion()))
	max_owner_motion=maxf(max_owner_motion,view.owner.global_position.distance_to(owner_before))
