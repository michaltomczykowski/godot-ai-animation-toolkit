extends SceneTree
## Independent warmed-engine oracle versus actual private sampler. No baked
## fixture/golden replacement. No helper calls on the reference author rig.
const Sampler:=preload("res://addons/godot_ai_animation/utils/pose_bake_sampler.gd")
const Sandbox:=preload("res://addons/godot_ai_animation/utils/evaluation_sandbox.gd")
class Errors extends Logger:
	var errors:Array=[]
	func _log_error(_fn:String,_file:String,_line:int,code:String,reason:String,_notify:bool,type:int,_trace:Array)->void:
		if type!=1:errors.append(reason if not reason.is_empty() else code)
class Witness extends SkeletonModifier3D:
	var poses:Array=[]
	func _process_modification_with_delta(_delta:float)->void:
		poses.clear()
		var rig:=get_skeleton()
		for bone in rig.get_bone_count():poses.append({"rotation":rig.get_bone_pose_rotation(bone),"position":rig.get_bone_pose_position(bone),"scale":rig.get_bone_pose_scale(bone)})
var logger:=Errors.new()
var failures:Array=[]
var rows:Array=[]
func _initialize()->void:OS.add_logger(logger);_run.call_deferred()
func _check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _fixture(axis:int,individual:bool,animated:bool)->Dictionary:
	var node:=Node3D.new();root.add_child(node)
	var rig:=Skeleton3D.new();rig.name="Skeleton";rig.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL;node.add_child(rig)
	for bone in 3:
		rig.add_bone("bone"+str(bone))
		if bone>0:rig.set_bone_parent(bone,bone-1)
		var rest:=Transform3D(Basis.IDENTITY,Vector3(.1,.5,.07) if bone>0 else Vector3.ZERO)
		rig.set_bone_rest(bone,rest);rig.set_bone_pose(bone,rest)
	var spring:=SpringBoneSimulator3D.new();spring.name="Spring";rig.add_child(spring)
	spring.set_setting_count(1);spring.set_root_bone_name(0,"bone0");spring.set_end_bone_name(0,"bone2");spring.set_extend_end_bone(0,false)
	spring.set_rotation_axis(0,axis)
	if axis==SkeletonModifier3D.ROTATION_AXIS_CUSTOM:spring.set_rotation_axis_vector(0,Vector3.FORWARD)
	spring.set_gravity_direction(0,Vector3(.2,-1,.3))
	for field in ["stiffness","drag","gravity","radius"]:
		var value:float={"stiffness":.7,"drag":.3,"gravity":.1,"radius":.02}[field]
		spring.call("set_"+field,0,value)
		var curve:=Curve.new();curve.min_value=0;curve.max_value=2;curve.add_point(Vector2(0,.25));curve.add_point(Vector2(1,1.25))
		spring.call("set_"+field+"_damping_curve",0,curve)
	if individual:
		spring.set_individual_config(0,true)
		for joint in spring.get_joint_count(0):
			spring.set_joint_stiffness(0,joint,.2+joint*.1);spring.set_joint_drag(0,joint,.4);spring.set_joint_gravity(0,joint,.9);spring.set_joint_radius(0,joint,.03)
	var player:=AnimationPlayer.new();player.name="Player";player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;node.add_child(player)
	var clip:=Animation.new();clip.length=1
	var track:=clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(track,"Skeleton:bone0");clip.track_insert_key(track,0,Quaternion.IDENTITY);clip.track_insert_key(track,1,Quaternion(Vector3.FORWARD,.5))
	if animated:
		for field in ["stiffness","drag","gravity","radius"]:
			track=clip.add_track(Animation.TYPE_VALUE);clip.track_set_path(track,"Skeleton/Spring:settings/0/"+field+"/value")
			clip.track_insert_key(track,0,{"stiffness":.7,"drag":.3,"gravity":.1,"radius":.02}[field])
			clip.track_insert_key(track,.2,{"stiffness":1.1,"drag":.5,"gravity":.15,"radius":.03}[field])
	var library:=AnimationLibrary.new();library.add_animation("input",clip);player.add_animation_library("",library)
	return {"root":node,"rig":rig,"spring":spring,"player":player}
func _error(a:Array,b:Array)->Dictionary:
	var out:={"position":0.0,"rotation":0.0,"scale":0.0}
	_check(a.size()==b.size(),"bone count")
	for bone in mini(a.size(),b.size()):
		out.position=maxf(out.position,a[bone].position.distance_to(b[bone].position))
		var q:Quaternion=a[bone].rotation.inverse()*b[bone].rotation
		out.rotation=maxf(out.rotation,2*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
		out.scale=maxf(out.scale,a[bone].scale.distance_to(b[bone].scale))
	return out
func _stale_trajectory(author:Dictionary,fps:int)->Array:
	var private:=Sandbox.new();var opened:Dictionary=private.open(author.root)
	_check(not opened.has("error"),"stale cache negative control open")
	if opened.has("error"):return []
	var rig:Skeleton3D=private.get_copy(author.rig)
	var player:AnimationPlayer=private.get_copy(author.player)
	var spring:SpringBoneSimulator3D=private.get_copy(author.spring)
	var witness:=Witness.new();rig.add_child(witness)
	player.active=true;player.play("input");player.advance(0);spring.reset()
	var out:Array=[]
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		if delta>0:player.advance(delta)
		rig.advance(delta);rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		out.append(witness.poses.duplicate(true))
	private.close()
	return out
func _native_animated_configuration(axis:int,fps:int)->Array:
	# This rig supplies only engine-computed configuration, never expected poses.
	# Its frame callbacks may solve, so finish this lookup before reference reset.
	var configuration:=_fixture(axis,false,true)
	await process_frame
	await process_frame
	configuration.player.playback_auto_capture=false
	configuration.player.play("input");configuration.player.advance(0)
	var result:Array=[]
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		if delta>0:configuration.player.advance(delta)
		await process_frame
		var joints:Array=[]
		for joint in configuration.spring.get_joint_count(0):
			var fields:={}
			for field in ["stiffness","drag","gravity","radius"]:fields[field]=configuration.spring.call("get_joint_"+field,0,joint)
			joints.append(fields)
		result.append(joints)
	configuration.root.free()
	return result
func _case(axis:int,individual:bool,animated:bool,fps:int):
	var author:=_fixture(axis,individual,animated);var reference:=_fixture(axis,individual,animated)
	var witness:=Witness.new();reference.rig.add_child(witness)
	await process_frame
	await process_frame
	var configuration:Array=await _native_animated_configuration(axis,fps) if animated else []
	var author_before:=var_to_str(author.rig.get_bone_pose(0))
	var source_setting:float=author.spring.get_stiffness(0)
	var evaluator:=Sampler.new();var opened:Dictionary=evaluator.open(author.root,author.rig,author.player,"input")
	_check(not opened.has("error"),"actual private sampler open "+str(opened))
	if opened.has("error"):author.root.free();reference.root.free();return
	var private_spring:SpringBoneSimulator3D=evaluator.sandbox.get_copy(author.spring)
	for joint in reference.spring.get_joint_count(0):
		for field in ["stiffness","drag","gravity","radius"]:_check(private_spring.call("get_joint_"+field,0,joint)==reference.spring.call("get_joint_"+field,0,joint),"independent warmed joint cache "+field)
		_check(private_spring.get_joint_gravity_direction(0,joint)==reference.spring.get_joint_gravity_direction(0,joint),"independent gravity direction")
		_check(private_spring.get_joint_rotation_axis(0,joint)==reference.spring.get_joint_rotation_axis(0,joint),"independent rotation axis")
		_check(private_spring.get_joint_rotation_axis_vector(0,joint)==reference.spring.get_joint_rotation_axis_vector(0,joint),"independent rotation axis vector")
	# Complete every private sample without yielding, exactly as public bake.
	var private_samples:Array=[]
	var private_ticks:={"raw":0}
	private_spring.modification_processed.connect(func():private_ticks.raw+=1)
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		var prior:int=private_ticks.raw
		var sample:Dictionary=evaluator.sample(delta,time)
		_check(sample.has("poses"),"private sample "+str(sample.get("error",{})))
		_check(private_ticks.raw==prior+1,"one private Spring evaluation per sample")
		if animated:
			for joint in private_spring.get_joint_count(0):
				for field in configuration[tick][joint]:_check(private_spring.call("get_joint_"+field,0,joint)==configuration[tick][joint][field],"animated native joint cache "+field)
		private_samples.append(sample.get("poses",[]).duplicate(true))
	evaluator.close()
	var stale:Array=_stale_trajectory(author,fps)
	var stale_worst:=0.0
	# Apply separately engine-evaluated animated configuration using native joint
	# setters. No production helper or duplicated curve formula enters the oracle.
	if animated:reference.spring.set_individual_config(0,true)
	reference.player.active=true;reference.player.playback_auto_capture=false
	reference.player.play("input");reference.player.advance(0);reference.spring.reset()
	var reference_ticks:={"raw":0}
	reference.spring.modification_processed.connect(func():reference_ticks.raw+=1)
	var worst:={"position":0.0,"rotation":0.0,"scale":0.0}
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		if delta>0:reference.player.advance(delta)
		if animated:
			for joint in reference.spring.get_joint_count(0):
				for field in configuration[tick][joint]:reference.spring.call("set_joint_"+field,0,joint,configuration[tick][joint][field])
		var prior:int=reference_ticks.raw
		# No frame yield: deferred dirty-skeleton callbacks would add a second
		# simulation step before the explicit notification, even in manual mode.
		reference.rig.advance(delta);reference.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(reference_ticks.raw==prior+1,"one reference Spring evaluation per sample")
		var errors:=_error(private_samples[tick],witness.poses)
		if tick<stale.size():stale_worst=maxf(stale_worst,float(_error(stale[tick],witness.poses).rotation))
		for field in errors:worst[field]=maxf(worst[field],errors[field])
	_check(worst.position<=.0001 and worst.rotation<=.001 and worst.scale<=.0001,"warmed native parity "+str([axis,individual,animated,fps])+" "+str(worst))
	_check(author.spring.is_config_individual(0)==individual and author.spring.get_stiffness(0)==source_setting and var_to_str(author.rig.get_bone_pose(0))==author_before,"author source unchanged")
	if axis==SkeletonModifier3D.ROTATION_AXIS_ALL and not individual and not animated:_check(stale_worst>.001,"unprimed negative control must reproduce wrong curve fps="+str(fps))
	author.root.free();reference.root.free()
	rows.append({"axis":axis,"individual":individual,"animated":animated,"fps":fps,"worst":worst,"unprimed_control_rotation_error":stale_worst,"private_steps":private_ticks.raw,"reference_steps":reference_ticks.raw,"native_configuration_frames":configuration.size()})
func _single_joint_curve_refusal():
	var author:=_fixture(SkeletonModifier3D.ROTATION_AXIS_ALL,false,false)
	author.spring.set_end_bone_name(0,"bone0")
	# Refuse synchronously before the engine evaluates the undefined curve offset.
	var before:bool=author.spring.is_config_individual(0)
	var evaluator:=Sampler.new();var result:Dictionary=evaluator.open(author.root,author.rig,author.player,"input")
	_check(result.has("error") and result.error.get("code")=="OPERATION_UNAVAILABLE","undefined single joint curve typed refusal")
	_check(author.spring.is_config_individual(0)==before,"refusal author mode unchanged")
	evaluator.close();author.root.free()
func _run():
	for fps in [30,60,120]:
		for axis in [SkeletonModifier3D.ROTATION_AXIS_X,SkeletonModifier3D.ROTATION_AXIS_Y,SkeletonModifier3D.ROTATION_AXIS_Z,SkeletonModifier3D.ROTATION_AXIS_ALL,SkeletonModifier3D.ROTATION_AXIS_CUSTOM]:await _case(axis,false,false,fps)
		await _case(SkeletonModifier3D.ROTATION_AXIS_CUSTOM,true,false,fps)
		await _case(SkeletonModifier3D.ROTATION_AXIS_ALL,false,true,fps)
	await _single_joint_curve_refusal()
	_check(rows.size()==21,"complete21axis/individual/animated/FPS cases")
	var report:={"kind":"spring_private_bake_warmed_native_parity","rows":rows,"failures":failures,"engine_errors":logger.errors,"limits":{"position":.0001,"rotation":.001,"scale":.0001},"passed":failures.is_empty() and logger.errors.is_empty()}
	var args:=OS.get_cmdline_user_args()
	if args.size()==1 and not FileAccess.file_exists(args[0]):
		var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("SPRING_BAKE_CACHE="+JSON.stringify(report));OS.remove_logger(logger);quit(0 if report.passed else 1)
