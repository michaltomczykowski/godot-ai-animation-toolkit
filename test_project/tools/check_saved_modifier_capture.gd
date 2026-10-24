extends SceneTree
## Five original saved modifiers; no replacement nodes or output pose authoring.
class Errors extends Logger:
	var errors:Array[String]=[]
	func _log_error(_fn:String,_file:String,_line:int,code:String,reason:String,_notify:bool,type:int,_trace:Array)->void:
		if type!=1:errors.append(reason if not reason.is_empty() else code)
class Final extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta:float)->void:pass
var logger:=Errors.new()
var failures:Array=[]
var runs:Array=[]
var manifest:Dictionary
var report_path:=""
var inert_control:=false
func _initialize()->void:_run.call_deferred()
func _check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _nodes(node:Node,type:String)->Array:
	var found:Array=[]
	if node.is_class(type):found.append(node)
	for child in node.get_children(true):found.append_array(_nodes(child,type))
	return found
func _poses(rig:Skeleton3D)->Array:
	var out:Array=[]
	for i in rig.get_bone_count():out.append(rig.get_bone_pose(i))
	return out
func _restore(rig:Skeleton3D,poses:Array)->void:
	for i in poses.size():
		rig.set_bone_pose_position(i,poses[i].origin)
		rig.set_bone_pose_rotation(i,poses[i].basis.get_rotation_quaternion())
		rig.set_bone_pose_scale(i,poses[i].basis.get_scale())
func _difference(a:Array,b:Array)->float:
	if a.size()!=b.size():return INF
	var result:=0.0
	for i in a.size():
		result=maxf(result,a[i].origin.distance_to(b[i].origin))
		var q:Quaternion=a[i].basis.get_rotation_quaternion().inverse()*b[i].basis.get_rotation_quaternion()
		result=maxf(result,2*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
		result=maxf(result,a[i].basis.get_scale().distance_to(b[i].basis.get_scale()))
	return result
func _stable(v:Variant)->Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Basis:return [_stable(v.x),_stable(v.y),_stable(v.z)]
	if v is Transform3D:return {"basis":_stable(v.basis),"origin":_stable(v.origin)}
	if v is Node:return str(v.get_path())
	if v is Script:return {"class":v.get_class(),"path":v.resource_path,"sha256":FileAccess.get_sha256(v.resource_path)}
	if v is Resource:
		var out:={"class":v.get_class()}
		for p in v.get_property_list():
			if int(p.usage)&PROPERTY_USAGE_STORAGE and str(p.name) not in ["resource_path","resource_local_to_scene"]:out[str(p.name)]=_stable(v.get(p.name))
		return out
	if v is Dictionary:
		var out:={}
		for k in v:out[str(k)]=_stable(v[k])
		return out
	if v is Array:
		var out:Array=[]
		for item in v:out.append(_stable(item))
		return out
	return v
func _config(modifier:SkeletonModifier3D)->String:
	var out:={}
	for p in modifier.get_property_list():
		var key:=str(p.name)
		if int(p.usage)&PROPERTY_USAGE_STORAGE and key not in ["active","influence"] and not key.contains("/joints/") and not key.ends_with("/joint_count"):out[key]=_stable(modifier.get(key))
	var collisions:Array=[]
	for child in modifier.get_children():
		if child is SpringBoneCollision3D:
			var fields:={}
			for p in child.get_property_list():
				if int(p.usage)&PROPERTY_USAGE_STORAGE:fields[str(p.name)]=_stable(child.get(p.name))
			collisions.append(fields)
	out["collision_children"]=collisions
	return var_to_str(out).sha256_text()
func _inert_internal(node:Node)->bool:
	return node is PhysicalBoneSimulator3D and node.get_script()==null and node.get_child_count(true)==0 and not node.is_simulating_physics()
func _stimulus(row:Dictionary,source:Skeleton3D,modifier:SkeletonModifier3D,input:Array,time:float)->void:
	_restore(source,input)
	if row.op=="spring_setup":source.set_bone_pose_rotation(0,input[0].basis.get_rotation_quaternion()*Quaternion(Vector3.FORWARD,0.15*sin(time*TAU)))
func _effector(source:Skeleton3D,modifier:SkeletonModifier3D)->Vector3:
	var index:int=modifier.get_end_bone(0)
	var pose:=source.get_bone_global_pose(index)
	if modifier is TwoBoneIK3D and modifier.is_using_virtual_end(0):
		var rest:=source.get_bone_global_rest(index)
		var parent:=source.get_bone_global_rest(source.get_bone_parent(index))
		var axis:Vector3=(rest.basis.inverse()*(rest.origin-parent.origin)).normalized()
		pose.origin+=pose.basis*axis*modifier.get_end_bone_length(0)
	return source.global_transform*pose.origin
func _input(row:Dictionary,source:Skeleton3D,modifier:SkeletonModifier3D)->Array:
	if row.op=="twist_setup":
		var end:int=modifier.get_end_bone(0)
		if not modifier.is_end_bone_extended(0):end=source.get_bone_parent(end)
		source.set_bone_pose_rotation(end,source.get_bone_rest(end).basis.get_rotation_quaternion()*Quaternion(Vector3.UP,0.7))
	if row.op=="retarget_setup":
		source.set_bone_pose_rotation(1,source.get_bone_rest(1).basis.get_rotation_quaternion()*Quaternion(Vector3.FORWARD,0.6))
		source.set_bone_pose_position(1,source.get_bone_rest(1).origin+Vector3(0.15,0.04,-0.03))
		source.set_bone_pose_scale(1,Vector3(1.2,0.9,1.1))
	if row.op=="ik_setup":
		var start:Vector3=source.global_transform*source.get_bone_global_pose(modifier.get_root_bone(0)).origin
		var end:Vector3=_effector(source,modifier)
		var direction:=end-start
		var side:=direction.normalized().cross(Vector3.FORWARD).normalized()
		if side.length()<0.1:side=Vector3.RIGHT
		modifier.get_node(modifier.get_target_node(0)).global_position=start+direction*0.7+side*direction.length()*0.15
		modifier.get_node(modifier.get_target_node(0)).reset_physics_interpolation()
	if row.op=="look_at_setup":
		var origin:=source.global_transform*source.get_bone_global_pose(modifier.bone).origin
		if modifier.origin_from==LookAtModifier3D.ORIGIN_FROM_SPECIFIC_BONE:origin=source.global_transform*source.get_bone_global_pose(modifier.origin_bone).origin
		if modifier.origin_from==LookAtModifier3D.ORIGIN_FROM_EXTERNAL_NODE:origin=modifier.get_node(modifier.origin_external_node).global_position
		modifier.get_node(modifier.target_node).global_position=origin+source.global_basis*Vector3(0.7,0.4,1.0)
		modifier.get_node(modifier.target_node).reset_physics_interpolation()
	return _poses(source)
# Observation-only virtual hooks. Default preflight clocks and stimuli unchanged.
func _sample_frames(row:Dictionary,fps:int)->int:return 4*fps if row.op=="spring_setup" else 1
func _capture_begin(_context:Dictionary):pass
func _capture_frame(_context:Dictionary):pass
func _capture_end(_context:Dictionary):pass
func _take(row:Dictionary,fps:int,active:bool,take:int)->Dictionary:
	var before:=failures.size()
	_check(FileAccess.get_sha256(row.scene.path)==row.scene.sha256,row.id+" scene hash")
	var scene:Node=(ResourceLoader.load(row.scene.path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(scene)
	for rig in _nodes(scene,"Skeleton3D"):rig.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	# Original saved retarget helper restores original child inputs after cache entry.
	await process_frame
	await process_frame
	var source:=scene.get_node(row.source) as Skeleton3D
	var observed:=scene.get_node(row.receiver) as Skeleton3D if row.op=="retarget_setup" else source
	var modifier:=scene.get_node(row.modifier) as SkeletonModifier3D
	_check(modifier!=null and modifier.active==false,row.id+" original saved inactive modifier")
	for node in _nodes(scene,"AnimationMixer"):
		_check(not node.active or (node is AnimationPlayer and not node.is_playing()),row.id+" competing mixer admission")
		node.active=false
	for node in _nodes(scene,"SkeletonModifier3D"):
		if node!=modifier:_check(not node.active or _inert_internal(node),row.id+" foreign active modifier "+str(node.get_path()))
	var receiver_position:=observed.global_transform
	var config_before:=_config(modifier)
	var input:=_input(row,source,modifier)
	var observed_input:=_poses(observed)
	var witness:=Final.new();witness.name="CaptureFinalWitness";source.add_child(witness)
	var sample:={"raw":0,"final":0,"skin":0,"poses":[],"skin_pose":[],"globals":[]}
	var raw_cb:=func():sample.raw+=1
	var final_cb:=func():
		sample.final+=1;sample.poses=_poses(observed);sample.globals=[]
		for bone in observed.get_bone_count():sample.globals.append(observed.global_transform*observed.get_bone_global_pose(bone))
	var skin_cb:=func():sample.skin+=1;sample.skin_pose=_poses(observed)
	modifier.modification_processed.connect(raw_cb)
	witness.modification_processed.connect(final_cb)
	source.skeleton_updated.connect(skin_cb)
	modifier.active=active and not inert_control;modifier.influence=1.0
	if modifier is SpringBoneSimulator3D:modifier.reset()
	var trace:Array=[]
	var focus:Array=[]
	for name in ["B-upperArm.L","B-forearm.L","B-hand.L","B-spine","B-chest","B-head"]:
		var index:=observed.find_bone(name)
		if index>=0:focus.append(index)
	if focus.is_empty():
		for i in mini(6,observed.get_bone_count()):focus.append(i)
	var baseline:Array=[]
	var frames:=_sample_frames(row,fps)
	var capture:={"row":row,"fps":fps,"active":active,"take":take,"scene":scene,"source":source,"observed":observed,"modifier":modifier,"config_sha256":config_before,"frames":frames,"excluded_loading_process_frames":2}
	await _capture_begin(capture)
	for tick in frames:
		var time:=float(tick)/fps
		_stimulus(row,source,modifier,input,time)
		if observed!=source:_restore(observed,observed_input)
		baseline=_poses(observed)
		var input_source_sha:=var_to_str(_poses(source)).sha256_text()
		var raw_before:int=sample.raw;var final_before:int=sample.final;var skin_before:int=sample.skin
		source.advance(1.0/fps);source.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(sample.final==final_before+1 and sample.skin>=skin_before+1,row.id+" final/skin signal progression")
		_check(sample.raw==raw_before+(1 if active else 0),row.id+" raw activation signal")
		_check(_config(modifier)==config_before,row.id+" saved modifier/collider config changed")
		_check(observed.global_transform==receiver_position,row.id+" receiver placement changed")
		var finite:=true
		for pose:Transform3D in sample.poses:finite=finite and pose.origin.is_finite() and pose.basis.is_finite()
		_check(finite,row.id+" finite final pose")
		var effect:=_difference(sample.poses,baseline)
		if not active:_check(effect<0.001,row.id+" inactive baseline changed")
		_check(_difference(sample.poses,sample.skin_pose)<0.001,row.id+" final witness agrees with skin")
		var writers:Array=[]
		for node in _nodes(scene,"SkeletonModifier3D"):
			if node.active and not _inert_internal(node):writers.append(str(node.get_path()))
		_check(writers.size()==(2 if active else 1),row.id+" exclusive runtime modifier/final witness ownership")
		var lo:=Vector3(INF,INF,INF);var hi:=Vector3(-INF,-INF,-INF)
		for pose:Transform3D in sample.globals:lo=lo.min(pose.origin);hi=hi.max(pose.origin)
		var focused:={}
		for i:int in focus:focused[str(i)]={"name":observed.get_bone_name(i),"input":_stable(baseline[i]),"final":_stable(sample.poses[i]),"world":_stable(sample.globals[i])}
		var record:={"raw_before":raw_before,"final_before":final_before,"skin_before":skin_before,"active_writers":writers,"focus_poses":focused,"bounds_min":_stable(lo),"bounds_max":_stable(hi),"tick":tick,"time":time,"raw":sample.raw,"final":sample.final,"skin":sample.skin,"effect":effect,"pose_sha256":var_to_str(sample.poses).sha256_text(),"finite":finite}
		trace.append(record)
		await _capture_frame(capture.merged({"record":record,"baseline":baseline,"globals":sample.globals,"signals":sample,"source_input_sha256":input_source_sha},true))
	await _capture_end(capture)
	_check(FileAccess.get_sha256(row.scene.path)==row.scene.sha256,row.id+" immutable scene")
	var result:={"id":row.id,"op":row.op,"fps":fps,"active":active,"take":take,"saved_active":false,"runtime_influence":1.0,"frames":frames,"excluded_loading_process_frames":2,"scene_sha256":row.scene.sha256,"config_sha256":config_before,"trace":trace,"final_pose":sample.poses,"failures":failures.slice(before)}
	modifier.modification_processed.disconnect(raw_cb);witness.modification_processed.disconnect(final_cb);source.skeleton_updated.disconnect(skin_cb)
	scene.free()
	return result
func _run()->void:
	OS.add_logger(logger)
	var args:=OS.get_cmdline_user_args()
	if args.size()<2 or args.size()>3:printerr("Expected immutable manifest and NEW report path");quit(1);return
	report_path=args[1]
	inert_control=args.size()==3 and args[2]=="inert"
	if args.size()==3 and not inert_control:printerr("Unknown control");quit(1);return
	if FileAccess.file_exists(report_path):printerr("Preserve earlier preflight");quit(1);return
	manifest=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var operations:Array=[]
	for row:Dictionary in manifest.cases:operations.append(row.op)
	operations.sort()
	_check(operations==["ik_setup","look_at_setup","retarget_setup","spring_setup","twist_setup"],"Exactly five declared modifier cases")
	for dependency in manifest.capture_dependencies:
		_check(FileAccess.get_sha256(dependency.path)==dependency.sha256,"Capture script dependency "+str(dependency.path))
	for row:Dictionary in manifest.cases:
		for fps in [30,60,120]:
			var on:Array=[];var off:Array=[]
			for take in 2:
				var a:Dictionary=await _take(row,fps,false,take);var b:Dictionary=await _take(row,fps,true,take)
				_check(_difference(a.final_pose,b.final_pose)>0.001,row.id+" native activation has visible effect")
				off.append(a);on.append(b);runs.append(a);runs.append(b)
			_check(_difference(on[0].final_pose,on[1].final_pose)<0.001,row.id+" fresh reset active pose")
			_check(_difference(off[0].final_pose,off[1].final_pose)<0.001,row.id+" fresh reset inactive pose")
	var report:={"kind":"saved_modifier_capture_preflight","inert_control":inert_control,"checker_sha256":FileAccess.get_sha256("res://tools/check_saved_modifier_capture.gd"),"manifest_sha256":FileAccess.get_sha256(args[0]),"runs":runs,"failures":failures,"engine_errors":logger.errors,"passed":failures.is_empty() and logger.errors.is_empty(),"limits":"Saved inactive configuration plus declared runtime activation/input stimuli; no rendered quality claim"}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(_stable(report)))
	OS.remove_logger(logger)
	print("SAVED_MODIFIER_PREFLIGHT="+JSON.stringify({"passed":report.passed,"runs":runs.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if report.passed else 1)
