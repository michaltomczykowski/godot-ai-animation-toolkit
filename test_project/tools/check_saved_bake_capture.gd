extends "res://tools/check_rig_bake_restoration.gd"
## Original saved scenes only. No Native.replace, Reference.build, or pose writes.
var media_manifest:Dictionary
var media_runs:Array=[]
func _stable(v:Variant)->Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Quaternion:return [v.x,v.y,v.z,v.w]
	if v is Transform3D:return {"origin":_stable(v.origin),"basis":[_stable(v.basis.x),_stable(v.basis.y),_stable(v.basis.z)]}
	if v is Array:
		var a:Array=[]
		for item in v:a.append(_stable(item))
		return a
	if v is Dictionary:
		var d:={}
		for key in v:d[str(key)]=_stable(v[key])
		return d
	return v
func _observation(rig:Skeleton3D)->Dictionary:
	var worlds:Array=[]
	for i in rig.get_bone_count():worlds.append(rig.global_transform*rig.get_bone_global_pose(i))
	return {"local":_poses(rig),"world":worlds}
func _final_signal(rig:Skeleton3D,state:Dictionary)->void:
	state.final+=1;state.pose=_observation(rig)
func _skin_signal(rig:Skeleton3D,state:Dictionary)->void:
	state.skin+=1;state.skin_pose=_poses(rig)
func _capture_begin(_view:Dictionary):pass
func _capture_sample(_view:Dictionary,_sample:Dictionary):pass
func _capture_end(_view:Dictionary):pass
func _replay(row:Dictionary,side:String,take:int,paced:bool,flush:bool)->Dictionary:
	var before:=failures.size()
	var virtual:String=row.source if side=="source" else row.states.redo
	_check(FileAccess.get_sha256(virtual)==media_manifest.files[virtual].sha256,row.id+" immutable scene before")
	var scene:=_load(virtual)
	if scene==null:return {}
	await process_frame
	await process_frame
	var rig:=scene.get_node(row.skeleton) as Skeleton3D
	var body:=scene.get_node(row.movement_owner) as Node3D
	var player:=scene.get_node(row.source_player if side=="source" else row.output) as AnimationPlayer
	var tree:=scene.get_node(row.tree) as AnimationTree if side=="source" and not str(row.tree).is_empty() else null
	var mixer:AnimationMixer=tree if tree!=null else player
	if side=="redo":
		for child in scene.find_children("*","SkeletonModifier3D",true,false):child.active=false
	var required:Array=[]
	var observations:={}
	var witnesses:Array=[]
	var saved_modifiers:Array=[]
	for candidate in scene.find_children("*","Skeleton3D",true,false):
		if candidate==rig or candidate.is_ancestor_of(rig) or rig.is_ancestor_of(candidate):
			required.append(candidate)
			var state:={"final":0,"skin":0,"pose":{},"skin_pose":[]}
			observations[str(candidate.get_path())]=state
			for child in candidate.get_children():
				if child is SkeletonModifier3D:saved_modifiers.append({"path":str(child.get_path()),"class":child.get_class(),"active":child.active,"influence":child.influence})
			var witness:=FinalPose.new();candidate.add_child(witness);witness.name="BakeMediaFinalWitness"
			witness.modification_processed.connect(_final_signal.bind(candidate,state))
			candidate.skeleton_updated.connect(_skin_signal.bind(candidate,state))
			witnesses.append(witness)
	player.speed_scale=1;player.playback_auto_capture=false
	if tree!=null:
		for entry in tree.get_property_list():
			var key:=str(entry.name)
			if key.ends_with("/request"):tree.set(key,0)
			elif key.ends_with("/seek_request"):tree.set(key,-1.0)
			elif key.ends_with("/transition_request"):tree.set(key,"")
		for key in row.params.get("tree_parameters",{}):tree.set(key,_value(row.params.tree_parameters[key]))
		for start in row.params.get("tree_starts",[]):tree.get(start.playback_path).start(start.state,true)
		tree.active=true
	else:
		player.active=true;player.play(str(row.params.get("source_animation","input")) if side=="source" else str(row.params.animation_name))
	var has_spring:=false
	for candidate in required:
		for child in candidate.get_children():
			if child is SpringBoneSimulator3D and child.active:has_spring=true
	var root_mode:String=str(row.params.get("root_motion_mode","preserve"))
	var extracts:=not mixer.root_motion_track.is_empty()
	if side=="redo" and row.params.has("root_motion_mode"):
		_check(extracts==(root_mode=="preserve"),row.id+" saved root ownership")
	var view:={"row":row,"side":side,"take":take,"scene":scene,"rig":rig,"body":body,"mixer":mixer,"required":required}
	await _capture_begin(view)
	var events:Array=row.params.get("tree_events",[]) if side=="source" else []
	var cursor:=0
	var previous:=0.0
	var initial_scale:=body.scale
	var accum:=Vector3.ONE
	var trace:Array=[]
	for time in _times(row.params):
		var delta:float=float(time)-previous
		var consumed:=0
		var extraction:={}
		if delta>0 and (tree!=null or player.is_playing()):
			mixer.advance(delta)
			if extracts:
				extraction={"position":mixer.get_root_motion_position(),"rotation":mixer.get_root_motion_rotation(),"scale":mixer.get_root_motion_scale(),"rotation_accumulator":mixer.get_root_motion_rotation_accumulator()}
				if side=="redo" or root_mode!="pose_only":accum=_consume(body,mixer,initial_scale,accum);consumed=1
		var changed:=false
		while cursor<events.size() and float(events[cursor].time)<=float(time)+0.00000001:
			var event:Dictionary=events[cursor]
			if event.action=="set":tree.set(event.path,_value(event.value))
			elif event.action=="start":tree.get(event.path).start(event.state,true)
			else:tree.get(event.path).travel(event.state,true)
			cursor+=1;changed=true
		if time==0 or changed:mixer.advance(0)
		if time==0:
			for candidate in required:
				for child in candidate.get_children():
					if child is SpringBoneSimulator3D and child.active:child.reset()
			if flush and has_spring:await process_frame
		var per_rig:={}
		for candidate in required:
			var key:=str(candidate.get_path());var state:Dictionary=observations[key]
			var last_final:int=state.final;var last_skin:int=state.skin
			candidate.advance(delta);candidate.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			_check(state.final==last_final+1 and state.skin>=last_skin+1,row.id+" required final/skin "+key)
			_check(state.skin_pose.size()==candidate.get_bone_count(),row.id+" skin bone count")
			for i in mini(state.skin_pose.size(),candidate.get_bone_count()):_difference(state.pose.local[i],state.skin_pose[i],row.id+" final/skin "+key)
			per_rig[str(scene.get_path_to(candidate))]={"final_before":last_final,"skin_before":last_skin,"final":state.final,"skin":state.skin,"pose":state.pose.duplicate(true)}
		var sample:={"time":time,"delta":delta,"event_cursor":cursor,"body":_body(body),"body_world":body.global_transform,"selected_pose":observations[str(rig.get_path())].pose.local.duplicate(true),"required":per_rig,"extraction":extraction,"consumer_count":consumed,"root_track":str(mixer.root_motion_track),"root_motion_local":mixer.root_motion_local,"assigned_animation":str(player.assigned_animation),"player_position":player.current_animation_position}
		trace.append(sample)
		await _capture_sample(view,sample)
		if paced:await process_frame
		previous=float(time)
	await _capture_end(view)
	_check(FileAccess.get_sha256(virtual)==media_manifest.files[virtual].sha256,row.id+" immutable scene after")
	var result:={"id":row.id,"side":side,"take":take,"paced":paced,"flush":flush,"excluded_loading_process_frames":2,"excluded_reset_process_frames":1 if flush and has_spring else 0,"saved_modifiers":saved_modifiers,"authored_duration":row.params.duration,"trace":_stable(trace),"failures":failures.slice(before)}
	scene.free()
	return result
func _run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:push_error("bake media manifest and report required");quit(1);return
	if FileAccess.file_exists(args[1]):push_error("preserve previous bake report");quit(1);return
	media_manifest=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if media_manifest.get("state")!="current_public_inputs_staged_native_capture_pending":push_error("current public source anchor required");quit(1);return
	for path in media_manifest.files:_check(FileAccess.get_sha256(path)==media_manifest.files[path].sha256,"bound dependency before "+str(path))
	var diagnostic:=args.size()>2 and args[2]=="spring-diagnostic"
	var schedules:Array=[false,true] if diagnostic else [false]
	for row:Dictionary in media_manifest.cases:
		if diagnostic and row.id not in ["modifier_spring_1_60","modifier_ordered_spring_look_1_60"]:continue
		for flush in schedules:
			for paced in schedules:
				for take in 2:
					for side in ["source","redo"]:media_runs.append(await _replay(row,side,take,paced,flush))
	for path in media_manifest.files:_check(FileAccess.get_sha256(path)==media_manifest.files[path].sha256,"bound dependency after "+str(path))
	var report:={"kind":"saved_bake_eight_scheduling_diagnostic" if diagnostic else "saved_bake_eight_native","manifest_sha256":FileAccess.get_sha256(args[0]),"runs":media_runs,"failures":failures,"engine_errors":logger.values,"passed":failures.is_empty() and logger.values.is_empty(),"evaluator_sha256":FileAccess.get_sha256("res://tools/check_saved_bake_capture.gd"),"reference_helper_sha256":FileAccess.get_sha256("res://tools/check_rig_bake_restoration.gd"),"scope":"Actual saved source/redo observations; parity and schedule policy require independent admission; no media qualification."}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	OS.remove_logger(logger)
	quit(0 if report.passed else 1)
