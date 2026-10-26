extends "res://tools/check_spring_bake_cache.gd"
## Raw measurement only. Preserve the original failed21-case gate unchanged.
var observed_runs:Array=[]
func _stable(v:Variant)->Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Quaternion:return [v.x,v.y,v.z,v.w]
	if v is Array:
		var a:Array=[]
		for item in v:a.append(_stable(item))
		return a
	if v is Dictionary:
		var d:={}
		for key in v:d[str(key)]=_stable(v[key])
		return d
	return v
func _poses(rig:Skeleton3D)->Array:
	var out:Array=[]
	for i in rig.get_bone_count():out.append({"position":rig.get_bone_pose_position(i),"rotation":rig.get_bone_pose_rotation(i),"scale":rig.get_bone_pose_scale(i)})
	return out
func _cache(spring:SpringBoneSimulator3D)->Dictionary:
	var joints:Array=[]
	for j in spring.get_joint_count(0):
		joints.append({"stiffness":spring.get_joint_stiffness(0,j),"drag":spring.get_joint_drag(0,j),"gravity":spring.get_joint_gravity(0,j),"radius":spring.get_joint_radius(0,j),"gravity_direction":spring.get_joint_gravity_direction(0,j),"axis":spring.get_joint_rotation_axis(0,j),"axis_vector":spring.get_joint_rotation_axis_vector(0,j)})
	var globals:={}
	for field in ["stiffness","drag","gravity","radius"]:
		var curve:Curve=spring.call("get_"+field+"_damping_curve",0)
		globals[field]={"value":spring.call("get_"+field,0),"curve_samples":[curve.sample_baked(0),curve.sample_baked(.5),curve.sample_baked(1)] if curve!=null else []}
	return {"global":globals,"joints":joints,"individual":spring.is_config_individual(0),"active":spring.active,"influence":spring.influence,"gravity_direction":spring.get_gravity_direction(0),"axis":spring.get_rotation_axis(0),"axis_vector":spring.get_rotation_axis_vector(0),"mutable_axes":spring.mutable_bone_axes}
func _disable(node:Node)->void:
	node.process_mode=Node.PROCESS_MODE_DISABLED
	for child in node.get_children():_disable(child)
func _connect(rig:Skeleton3D,spring:SpringBoneSimulator3D,witness:SkeletonModifier3D,state:Dictionary)->void:
	spring.modification_processed.connect(func():state.raw+=1;state.raw_pose=_poses(rig))
	witness.modification_processed.connect(func():state.final+=1;state.final_pose=_poses(rig))
	rig.skeleton_updated.connect(func():state.skin+=1;state.skin_pose=_poses(rig))
func _state()->Dictionary:return {"raw":0,"final":0,"skin":0,"raw_pose":[],"final_pose":[],"skin_pose":[]}
func _private(axis:int,individual:bool,animated:bool,fps:int,stale:bool):
	var author:=_fixture(axis,individual,animated)
	await process_frame
	await process_frame
	var original_cache:=_cache(author.spring)
	var evaluator:RefCounted=Sandbox.new() if stale else Sampler.new()
	var opened:Dictionary=evaluator.open(author.root) if stale else evaluator.open(author.root,author.rig,author.player,"input")
	_check(not opened.has("error"),"private diagnostic open "+str(opened))
	if opened.has("error"):author.root.free();return
	var rig:Skeleton3D=evaluator.get_copy(author.rig) if stale else evaluator.sandbox.get_copy(author.rig)
	var player:AnimationPlayer=evaluator.get_copy(author.player) if stale else evaluator.sandbox.get_copy(author.player)
	var spring:SpringBoneSimulator3D=evaluator.get_copy(author.spring) if stale else evaluator.sandbox.get_copy(author.spring)
	var witness:SkeletonModifier3D
	if stale:
		witness=Witness.new();rig.add_child(witness)
		player.active=true;player.playback_auto_capture=false;player.play("input");player.advance(0);spring.reset()
	else:
		for child in rig.get_children():
			if child.name=="BakeFinalPoseWitness":witness=child
	var state:=_state();_connect(rig,spring,witness,state)
	var trace:Array=[]
	var loaded_cache:=_cache(spring)
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		var before:=state.duplicate(true);var input_before:=_poses(rig)
		var result:Dictionary={}
		if stale:
			if delta>0:player.advance(delta)
			rig.advance(delta);rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			result={"poses":state.final_pose.duplicate(true)}
		else:result=evaluator.sample(delta,time)
		_check(result.has("poses"),"private diagnostic sample")
		trace.append({"tick":tick,"time":time,"delta":delta,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"player_position":player.current_animation_position,"input_before":input_before,"before":before,"after":state.duplicate(true),"final_pose":result.get("poses",[]).duplicate(true),"restored_pose":_poses(rig),"cache":_cache(spring)})
	evaluator.close();author.root.free()
	observed_runs.append({"axis":axis,"individual":individual,"animated":animated,"fps":fps,"strategy":"unprimed-private-tight" if stale else "sampler-private-tight","author_cache":original_cache,"loaded_cache":loaded_cache,"trace":trace})
func _reference(axis:int,individual:bool,animated:bool,fps:int,strategy:String):
	var f:=_fixture(axis,individual,animated)
	var disabled:=strategy.ends_with("disabled")
	if disabled:_disable(f.root)
	await process_frame
	await process_frame
	var witness:=Witness.new();f.rig.add_child(witness)
	var state:=_state();_connect(f.rig,f.spring,witness,state)
	var original:=strategy.begins_with("original-before")
	if not original:
		# Separate witness attachment/entry notifications from reset/startup.
		await process_frame
		await process_frame
	f.player.active=true;f.player.playback_auto_capture=false;f.player.play("input");f.player.advance(0);f.spring.reset()
	var reset_state:=state.duplicate(true)
	var reset_cache:=_cache(f.spring)
	if original:await process_frame
	var post_reset_wait:=state.duplicate(true)
	var trace:Array=[]
	for tick in int(ceil(.2*fps))+1:
		var time:=minf(float(tick)/fps,.2);var delta:=0.0 if tick==0 else time-minf(float(tick-1)/fps,.2)
		var before:=state.duplicate(true);var input_before:=_poses(f.rig)
		f.player.advance(delta)
		var after_player:=state.duplicate(true)
		if original:await process_frame
		var after_wait:=state.duplicate(true)
		f.rig.advance(delta);f.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		trace.append({"tick":tick,"time":time,"delta":delta,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"player_position":f.player.current_animation_position,"input_before":input_before,"before":before,"after_player":after_player,"after_wait":after_wait,"after":state.duplicate(true),"final_pose":state.final_pose.duplicate(true),"restored_pose":_poses(f.rig),"cache":_cache(f.spring)})
		if strategy.begins_with("paced-after"):await process_frame
	f.root.free()
	observed_runs.append({"axis":axis,"individual":individual,"animated":animated,"fps":fps,"strategy":strategy,"process_disabled":disabled,"reset_state":reset_state,"post_reset_wait":post_reset_wait,"loaded_cache":reset_cache,"trace":trace})
func _run():
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [1,2] or FileAccess.file_exists(args[0]):push_error("exclusive new report required");quit(1);return
	var selection:=str(args[1]) if args.size()==2 else "full"
	if selection not in ["full","individual60"]:push_error("unknown schedule diagnostic selection");quit(1);return
	for fps in ([60] if selection=="individual60" else [30,60,120]):
		for kind in (["individual"] if selection=="individual60" else ["global","individual","animated"]):
			var individual:bool=kind=="individual";var animated:bool=kind=="animated"
			var axis:int=SkeletonModifier3D.ROTATION_AXIS_CUSTOM if individual else SkeletonModifier3D.ROTATION_AXIS_ALL
			await _private(axis,individual,animated,fps,false)
			await _private(axis,individual,animated,fps,true)
			for strategy in ["tight-inherited","tight-disabled","paced-after-inherited","original-before-inherited","original-before-disabled"]:await _reference(axis,individual,animated,fps,strategy)
	var report:={"kind":"spring_bake_raw_schedule_diagnostic","case_selection":selection,"runs":_stable(observed_runs),"failures":failures,"engine_errors":logger.errors,"passed_observations":failures.is_empty() and logger.errors.is_empty(),"scope":"Raw selected startup/process/pacing measurements; not regression or product parity approval.","script_sha256":FileAccess.get_sha256("res://tools/check_spring_bake_schedule_diagnostic.gd"),"fixture_sha256":FileAccess.get_sha256("res://tools/check_spring_bake_cache.gd"),"sampler_sha256":FileAccess.get_sha256("res://addons/godot_ai_animation/utils/pose_bake_sampler.gd"),"cache_helper_sha256":FileAccess.get_sha256("res://addons/godot_ai_animation/utils/spring_bake_cache.gd")}
	var file:=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close();OS.remove_logger(logger)
	quit(0 if report.passed_observations else 1)
