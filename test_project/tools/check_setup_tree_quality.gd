extends SceneTree
## Saved public character_setup graph only; never generates or replaces clips.
## godot --headless --path test_project --script res://tools/check_setup_tree_quality.gd -- route.json report.json
## See docs/setup-tree-checker.md for the manifest and measurement contract.
class Errors extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _trace: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
var logger := Errors.new()
const Grounding := preload("res://addons/godot_ai_animation/runtime/setup_grounding.gd")
const FPS := [30,60,120]
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _data(value: Dictionary) -> Dictionary:
	for _step in 4:
		if value.has("clips"): return value
		var advanced := false
		for key in ["data","result","response"]:
			if value.get(key) is Dictionary:
				value=value[key]
				advanced=true
				break
		if not advanced: break
	return value
func _node(scene: Node, path: String) -> Node:
	var saved_name := str(scene.get_meta("setup_checker_saved_root",scene.name))
	if path=="/"+saved_name or path==saved_name: return scene
	path=path.trim_prefix("/"+saved_name+"/")
	return scene.get_node_or_null(NodePath(path))
func _point(v: Dictionary, role: String, rest: bool=false) -> Vector3:
	var transform: Transform3D = v.rig.get_bone_global_rest(v.indices[role]) if rest else _pose(v,v.indices[role])
	return (v.rig.global_transform*transform).origin
func _flat(value: Vector3, up: Vector3) -> Vector3: return value-up*value.dot(up)
func _properties(tree: AnimationTree) -> Dictionary:
	var found := {}
	for property in tree.get_property_list(): found[str(property.name)]=true
	return found
func _load(row: Dictionary) -> Dictionary:
	var path := str(row.get("scene",""))
	if path.is_empty() or not ResourceLoader.exists(path): return {"error":"Saved scene missing"}
	if not row.has("scene_sha256") or FileAccess.get_sha256(path)!=str(row.scene_sha256): return {"error":"Saved scene hash missing or changed"}
	var packed := ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed==null: return {"error":"Saved scene cannot be loaded"}
	var scene := packed.instantiate()
	scene.set_meta("setup_checker_saved_root",str(scene.name))
	for mixer in scene.find_children("*","AnimationMixer",true,false):
		mixer.active=false
		mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(scene)
	var meta := _data(row.get("write",{}))
	if not meta.has("clips"): meta=_data(row.get("setup_response",{}))
	var player := _node(scene,str(row.get("player",meta.get("player_path","")))) as AnimationPlayer
	var rig := _node(scene,str(row.get("skeleton",meta.get("skeleton_path","")))) as Skeleton3D
	var tree := _node(scene,str(row.get("tree",meta.get("tree_path","AnimationTree")))) as AnimationTree
	var issues: Array[String] = []
	if player==null or rig==null or tree==null: issues.append("Saved player/skeleton/setup tree path unresolved")
	if not meta.has("clips"): issues.append("Public setup result metadata missing")
	if not issues.is_empty():
		scene.free()
		return {"error":str(issues)}
	var modifier := _node(scene,str(meta.get("grounding_path",""))) as Grounding
	if modifier==null or modifier.get_script()!=Grounding or modifier.get_parent()!=rig:
		issues.append("Saved setup-owned grounder is missing or has wrong script/parent")
	else:
		if not modifier.active: issues.append("Saved setup grounder is disabled")
		if modifier.get_node_or_null(modifier.get("tree_path"))!=tree or modifier.get_node_or_null(modifier.get("player_path"))!=player: issues.append("Saved setup grounder binds another Tree/Player")
		if int(meta.get("grounding",{}).get("contract_version",-1))!=Grounding.CONTRACT_VERSION: issues.append("Saved grounding contract metadata is missing")
		var problem: String = modifier.validate_configuration()
		if not problem.is_empty(): issues.append("Saved grounding configuration: "+problem)
	for candidate in scene.find_children("*","SkeletonModifier3D",true,false):
		if candidate!=modifier and candidate.active: issues.append("Foreign active modifier prevents final grounded ownership witness")
	if tree.get_node_or_null(tree.anim_player)!=player: issues.append("Saved tree does not bind the requested player")
	var animation_root := player.get_node_or_null(player.root_node)
	if tree.get_node_or_null(tree.root_node)!=animation_root: issues.append("Saved tree and player root_node differ")
	var roles: Dictionary = row.get("roles",{})
	var indices := {}
	for role in ["hips","head","thigh_l","shin_l","foot_l","toe_l","thigh_r","shin_r","foot_r"]:
		var index := rig.find_bone(str(roles.get(role,"")))
		if index<0: issues.append("Required reported role missing: "+role)
		indices[role]=index
	if not issues.is_empty():
		scene.free()
		return {"error":str(issues)}
	var local_spine: Vector3 = rig.get_bone_global_rest(indices.head).origin-rig.get_bone_global_rest(indices.hips).origin
	var local_up := Vector3.ZERO
	var dominant := local_spine.abs().max_axis_index()
	local_up[dominant]=signf(local_spine[dominant])
	var up: Vector3 = (rig.global_basis*local_up).normalized()
	var v := {"modifier":modifier,"signals":0,"scene":scene,"rig":rig,"player":player,"tree":tree,"meta":meta,"roles":roles,"indices":indices,"up":up}
	var forward: Vector3 = _flat(_point(v,"toe_l",true)-_point(v,"foot_l",true),up).normalized()
	if forward.length_squared()<0.9:
		scene.free()
		return {"error":"Independent rest forward axis is degenerate"}
	v.forward=forward
	v.leg=0.0
	for side in ["l","r"]: v.leg+=_point(v,"thigh_"+side,true).distance_to(_point(v,"shin_"+side,true))+_point(v,"shin_"+side,true).distance_to(_point(v,"foot_"+side,true))
	v.leg*=0.5
	v.ground=minf(_point(v,"foot_l",true).dot(up),_point(v,"foot_r",true).dot(up))
	var rooted := bool(meta.get("root_motion",false))
	var requested: Dictionary = row.get("request",row.get("params",{}))
	if requested.has("root_motion") and rooted!=bool(requested.root_motion): issues.append("Saved setup root ownership differs from request")
	if rooted:
		if tree.root_motion_track.is_empty() or tree.root_motion_track!=player.root_motion_track: issues.append("Saved graph extraction binding differs or is empty")
		v.owner=animation_root.get_node_or_null(NodePath(tree.root_motion_track.get_concatenated_names())) as Node3D if animation_root!=null else null
	else:
		if not tree.root_motion_track.is_empty() or not player.root_motion_track.is_empty(): issues.append("In-place setup retains extraction")
		var driver := Node3D.new()
		root.add_child(driver)
		scene.reparent(driver,true)
		v.driver=driver
		v.owner=driver
	if v.owner==null: issues.append("Root translation owner unresolved")
	var base: AnimationRootNode = tree.tree_root
	v.base_prefix="parameters/"
	if base is AnimationNodeBlendTree:
		if not base.has_node("Base"):
			issues.append("Setup Base node missing")
		else:
			v.base_prefix="parameters/Base/"
			v.shot=base.get_node("OneShot") if base.has_node("OneShot") else null
			base=base.get_node("Base")
	if not base is AnimationNodeBlendSpace1D: issues.append("Setup graph is not a 1D locomotion blend space")
	if base is AnimationNodeBlendSpace1D and base.get_blend_mode()!=AnimationNodeBlendSpace1D.BLEND_MODE_INTERPOLATED: issues.append("Setup checker requires the generated interpolated blend mode")
	v.base=base
	v.rooted=rooted
	v.properties=_properties(tree)
	v.speed_parameter=str(meta.get("speed_parameter",v.base_prefix+"blend_position"))
	v.jump_parameter=str(meta.get("jump_request_parameter",""))
	if not v.properties.has(v.speed_parameter): issues.append("Returned speed parameter is absent from saved graph")
	if not issues.is_empty():
		_free(v)
		return {"error":str(issues)}
	if modifier.get("role_names")!=roles: issues.append("Saved grounder roles differ from public rig profile")
	if not issues.is_empty():
		_free(v)
		return {"error":str(issues)}
	modifier.modification_processed.connect(func():
		v.captured=[]
		v.signals+=1
		for bone in rig.get_bone_count(): v.captured.append(rig.get_bone_global_pose(bone))
	)
	v.initial_owner=v.owner.global_position
	v.initial_rotation=v.owner.global_basis.orthonormalized().get_rotation_quaternion()
	return v
func _pose(v: Dictionary,bone: int) -> Transform3D:
	return v.captured[bone] if v.has("captured") else v.rig.get_bone_global_pose(bone)
func _free(v: Dictionary) -> void:
	if v.has("driver"): v.driver.free()
	elif v.has("scene"): v.scene.free()
func _points(v: Dictionary, speed: float) -> Array:
	var entries: Array = []
	for index in v.base.get_blend_point_count():
		var node: AnimationRootNode = v.base.get_blend_point_node(index)
		if not node is AnimationNodeAnimation: return []
		entries.append({"position":v.base.get_blend_point_position(index),"clip":str(node.animation),"phase_path":v.base_prefix+str(v.base.get_blend_point_name(index))+"/current_position","weight":0.0})
	entries.sort_custom(func(a,b): return a.position<b.position)
	if entries.is_empty(): return []
	if speed<=float(entries[0].position): entries[0].weight=1.0
	elif speed>=float(entries[-1].position): entries[-1].weight=1.0
	else:
		for index in entries.size()-1:
			if speed>=float(entries[index].position) and speed<=float(entries[index+1].position):
				var weight := (speed-float(entries[index].position))/(float(entries[index+1].position)-float(entries[index].position))
				entries[index].weight=1.0-weight
				entries[index+1].weight=weight
				break
	return entries
func _contact(clip: Animation, phase: float, side: String) -> bool:
	var start := clip.get_marker_time("contact."+side.to_upper())
	var end := clip.get_marker_time("toe_off."+side.to_upper())
	return fposmod(phase-start,clip.length)<fposmod(end-start,clip.length)-0.000001
func _declared(v: Dictionary, points: Array, side: String) -> bool:
	for point: Dictionary in points:
		if float(point.weight)<=0.000001 or point.clip=="idle": continue
		var clip: Animation = v.player.get_animation(point.clip)
		if not _contact(clip,float(v.tree.get(point.phase_path)),side): return false
	return true
func _check(row: Dictionary, spec: Dictionary, fps: int) -> Dictionary:
	var v := _load(row)
	var errors: Array[String] = []
	if v.has("error"): return {"passed":false,"failures":[v.error],"id":row.get("id",""),"fps":fps,"spec":spec}
	if str(spec.get("kind","")) not in ["blend","jump"]:
		_free(v)
		return {"id":row.get("id",""),"fps":fps,"spec":spec,"passed":false,"failures":["Unknown setup quality spec kind"]}
	var jump := str(spec.kind)=="jump"
	var speed := float(spec.get("speed_mps",0.0))
	var duration := float(spec.get("duration_s",6.0))
	if not is_finite(speed) or speed<0.0 or not is_finite(duration) or duration<=0.0 or duration>60.0:
		_free(v)
		return {"id":row.get("id",""),"fps":fps,"spec":spec,"passed":false,"failures":["Invalid or excessive checker speed/duration"]}
	var points := _points(v,speed)
	if points.is_empty(): errors.append("Unsupported or empty saved blend points")
	for point: Dictionary in points:
		if not v.properties.has(point.phase_path): errors.append("Saved graph exposes no actual clip phase: "+point.phase_path)
		if not v.player.has_animation(point.clip):
			errors.append("Missing base clip: "+point.clip)
			continue
		var base_clip: Animation = v.player.get_animation(point.clip)
		if float(point.weight)>0.000001 and point.clip!="idle":
			for side in ["L","R"]:
				if not base_clip.has_marker("contact."+side) or not base_clip.has_marker("toe_off."+side): errors.append("Missing base contact markers")
	var jump_clip: Animation
	var takeoff := 0.0
	var landing := 0.0
	var hold := 0.0
	var capture := 0.0
	var expected_distance := 0.0
	var requested: Dictionary = row.get("request",row.get("params",{}))
	var fadein := 0.0
	var fadeout := 0.0
	if jump:
		if not v.has("shot") or not v.shot is AnimationNodeOneShot or not v.properties.has(v.jump_parameter) or not v.player.has_animation("jump"):
			errors.append("Saved jump OneShot/request/clip missing")
		else:
			jump_clip=v.player.get_animation("jump")
			var clip_meta: Dictionary = v.meta.clips.get("jump",{})
			capture=float(clip_meta.get("capture_duration",clip_meta.get("length",jump_clip.length)))
			hold=float(clip_meta.get("root_motion_terminal_hold",0.0))
			if absf(capture-float(requested.get("jump_duration",1.2)))>0.000001: errors.append("Setup jump duration differs from requested/default1.2s")
			if absf(jump_clip.length-capture-hold)>0.000002: errors.append("Jump terminal hold/actual length mismatch")
			expected_distance=float(spec.get("distance_m",requested.get("distance",row.get("params",{}).get("distance",0.0))))
			fadein=v.shot.fadein_time
			fadeout=v.shot.fadeout_time
			if absf(fadein-float(requested.get("jump_fadein",0.1)))>0.000001 or absf(fadeout-float(requested.get("jump_fadeout",0.2)))>0.000001: errors.append("OneShot fade settings differ from request/default")
			for marker in ["takeoff","land"]:
				if not jump_clip.has_marker(marker): errors.append("Missing jump event marker "+marker)
			takeoff=jump_clip.get_marker_time("takeoff") if jump_clip.has_marker("takeoff") else 0.0
			landing=jump_clip.get_marker_time("land") if jump_clip.has_marker("land") else 0.0
			if landing<=takeoff or landing>=capture: errors.append("Unordered jump event markers")
			if not v.properties.has("parameters/Shot/current_position") or not v.properties.has("parameters/OneShot/active"): errors.append("OneShot phase/active parameters unavailable")
			duration=jump_clip.length+fadeout+0.5
		if speed!=0.0: errors.append("This jump contract requires idle base and zero external translation")
	if not errors.is_empty():
		_free(v)
		return {"id":row.get("id",""),"fps":fps,"spec":spec,"passed":false,"failures":errors}
	var tree: AnimationTree = v.tree
	tree.set(v.speed_parameter,speed)
	tree.active=true
	tree.advance(0.0)
	if jump: tree.set(v.jump_parameter,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var active_mixers := 0
	for mixer in v.scene.find_children("*","AnimationMixer",true,false):
		if mixer.active: active_mixers+=1
	if active_mixers!=1: errors.append("Graph does not have exactly one active mixer")
	var feet := {}
	for side in ["l","r"]: feet[side]={"active":false,"anchor":Vector3.ZERO,"slide":0.0,"penetration":0.0,"height":0.0,"windows":0,"frames":0,"pole":Vector3.ZERO,"knee_flips":0}
	var previous: Array[Transform3D] = []
	for bone in v.rig.get_bone_count(): previous.append(_pose(v,bone))
	var initial_hip := _point(v,"hips")
	var controller_speed := float(spec.get("controller_speed_mps",0.0 if v.rooted else speed))
	if not is_finite(controller_speed): errors.append("Controller speed must be finite")
	if v.rooted and controller_speed!=0.0: errors.append("Extracted setup cannot also receive controller translation")
	if jump and controller_speed!=0.0: errors.append("Jump cannot also receive controller travel")
	var commanded_distance := 0.0
	var speed_end := float(spec.get("speed_end_mps",speed))
	if not is_finite(speed_end) or speed_end<0.0: errors.append("Invalid ramp speed")
	var controller_start := controller_speed
	var controller_end := float(spec.get("controller_speed_end_mps",speed_end if not v.rooted and absf(controller_speed-speed)<0.000001 else controller_speed))
	if not is_finite(controller_end): errors.append("Invalid ramp controller speed")
	var reset_performed := false
	var max_velocity := 0.0
	var max_angular_velocity := 0.0
	var nonfinite := 0
	var extraction_error := 0.0
	var grounded_delta := 0.0
	var unconsumed_actor_change := 0.0
	var air_frames := 0
	var shot_frames := 0
	var previous_phase := 0.0
	var trace: Array = []
	var frames := ceili(duration*fps)
	var dt := 1.0/fps
	for frame in frames:
		var sample_speed := lerpf(speed,speed_end,(float(frame)+0.5)/frames)
		if not jump:
			tree.set(v.speed_parameter,sample_speed)
			points=_points(v,sample_speed)
			commanded_distance+=sample_speed*dt
			if not v.rooted: controller_speed=lerpf(controller_start,controller_end,(float(frame)+0.5)/frames)
		if spec.has("reset_at_s") and not reset_performed and float(frame)*dt>=float(spec.reset_at_s):
			tree.active=false
			v.modifier.reset_grounding("explicit_seek_or_new_take_test")
			tree.active=true
			reset_performed=true
		var binding_error: String = v.modifier.validate_configuration()
		if not v.modifier.active or v.modifier.get_parent()!=v.rig or v.modifier.get_node_or_null(v.modifier.tree_path)!=tree or not binding_error.is_empty(): errors.append("Saved grounding binding/ownership changed: "+binding_error)
		var before_owner: Vector3 = v.owner.global_position
		tree.advance(dt)
		unconsumed_actor_change=maxf(unconsumed_actor_change,v.owner.global_position.distance_to(before_owner))
		var delta := tree.get_root_motion_position()
		if not delta.is_finite(): nonfinite+=1
		if v.rooted: v.owner.position+=delta
		else:
			extraction_error=maxf(extraction_error,delta.length())
			if not jump: v.owner.global_position+=v.forward*controller_speed*dt
		var prior_signals: int = v.signals
		v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		if v.signals!=prior_signals+1: errors.append("Missing per-frame final modification_processed witness")
		if str(v.modifier.status)!="grounded" or not str(v.modifier.last_error).is_empty() or v.modifier.unreachable>0: errors.append("Grounding runtime diagnostic failure: "+str(v.modifier.diagnostics()))
		var phase := 0.0
		var shot_active := false
		if jump:
			phase=float(tree.get("parameters/Shot/current_position"))
			shot_active=bool(tree.get("parameters/OneShot/active"))
			if shot_active: shot_frames+=1
			if v.rooted and ((previous_phase<takeoff and phase<=takeoff) or (previous_phase>=landing and phase>=landing)): grounded_delta=maxf(grounded_delta,v.owner.global_position.distance_to(before_owner))
		var airborne := true
		var sample := {"time":float(frame+1)/fps,"shot_phase":phase,"shot_active":shot_active,"root_delta_parent":[delta.x,delta.y,delta.z],"feet":{}}
		for side: String in feet:
			var f: Dictionary = feet[side]
			var foot := _point(v,"foot_"+side)
			var height: float = foot.dot(v.up)-v.ground
			var contact := (not shot_active or phase<=takeoff+0.000001 or phase>=landing-0.000001) if jump else _declared(v,points,side)
			if contact and not f.active:
				f.anchor=foot
				f.windows+=1
			if contact:
				f.slide=maxf(f.slide,_flat(foot-f.anchor,v.up).length())
				f.height=maxf(f.height,absf(height))
				f.frames+=1
			f.penetration=maxf(f.penetration,-height)
			airborne=airborne and height>0.01*float(v.leg)
			var hip := _point(v,"thigh_"+side)
			var knee := _point(v,"shin_"+side)
			var leg_axis := (foot-hip).normalized()
			var pole := knee-hip-leg_axis*(knee-hip).dot(leg_axis)
			if pole.length()>0.005*float(v.leg):
				var normal := pole.normalized()
				if (f.pole as Vector3).length_squared()>0.5 and normal.dot(f.pole)<0.0: f.knee_flips+=1
				f.pole=normal
			f.active=contact
			sample.feet[side]={"height_m":height,"declared_contact":contact}
		if airborne: air_frames+=1
		for bone in v.rig.get_bone_count():
			var pose: Transform3D = _pose(v,bone)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite+=1
			var world_step: Vector3 = v.rig.global_basis*(pose.origin-previous[bone].origin)
			max_velocity=maxf(max_velocity,world_step.length()/dt/float(v.leg))
			var rotation := previous[bone].basis.orthonormalized().get_rotation_quaternion().inverse()*pose.basis.orthonormalized().get_rotation_quaternion()
			max_angular_velocity=maxf(max_angular_velocity,2.0*atan2(Vector3(rotation.x,rotation.y,rotation.z).length(),absf(rotation.w))/dt)
			previous[bone]=pose
		previous_phase=phase
		trace.append(sample)
	var elapsed := frames*dt
	var actual: Vector3 = v.owner.global_position-v.initial_owner if v.rooted or not jump else _point(v,"hips")-initial_hip
	var expected: Vector3 = v.forward*(expected_distance if jump else commanded_distance)
	var endpoint_error := _flat(actual-expected,v.up).length()
	if endpoint_error>0.0001: errors.append("Graph/controller world endpoint differs from exact requested distance")
	if extraction_error>0.000001: errors.append("In-place graph emits competing root extraction")
	if unconsumed_actor_change>0.000001: errors.append("Graph or another writer moves the declared owner before its single consumer")
	if grounded_delta>0.000001: errors.append("Jump root travels during an entirely grounded interval")
	if nonfinite>0: errors.append("Nonfinite graph output")
	if max_velocity<=0.000001: errors.append("Inert skeletal graph output")
	if max_velocity>10.0: errors.append("Bone speed exceeds default10leg/s heuristic")
	if jump and (shot_frames==0 or bool(tree.get("parameters/OneShot/active"))): errors.append("OneShot did not start and finish")
	if jump and air_frames==0: errors.append("No simultaneous observed jump flight")
	var slide_limit := minf(0.02*float(v.leg),0.03)
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide>slide_limit or f.penetration>0.01*float(v.leg) or f.height>0.01*float(v.leg) or f.knee_flips>0: errors.append(side+" graph contact/slide/penetration failure")
		if int(f.windows)<(2 if jump else 1) or int(f.frames)==0: errors.append(side+" insufficient declared contact coverage")
	var recovery_position := 0.0
	var recovery_rotation := 0.0
	if jump:
		var reference := _load(row)
		if reference.has("error"):
			errors.append("Idle recovery reference cannot load: "+str(reference.error))
		else:
			var idle_phase := 0.0
			for point: Dictionary in points:
				if point.clip=="idle": idle_phase=float(tree.get(point.phase_path))
			var ref_player: AnimationPlayer = reference.player
			ref_player.active=true
			ref_player.play("idle",0.0)
			ref_player.seek(idle_phase,true)
			ref_player.advance(0.0)
			var retained: Vector3 = Vector3.ZERO if v.rooted else v.forward*expected_distance
			for bone in v.rig.get_bone_count():
				var actual_pose: Transform3D = _pose(v,bone)
				var reference_pose: Transform3D = reference.rig.get_bone_global_pose(bone)
				recovery_position=maxf(recovery_position,((v.rig.global_basis*(actual_pose.origin-reference_pose.origin))-retained).length())
				var rotation := reference_pose.basis.orthonormalized().get_rotation_quaternion().inverse()*actual_pose.basis.orthonormalized().get_rotation_quaternion()
				recovery_rotation=maxf(recovery_rotation,2.0*atan2(Vector3(rotation.x,rotation.y,rotation.z).length(),absf(rotation.w)))
			if recovery_position>minf(0.01*float(v.leg),0.01) or recovery_rotation>0.01: errors.append("OneShot does not recover to native idle pose at the actual idle phase")
			_free(reference)
	var yaw_error: float = v.initial_rotation.angle_to(v.owner.global_basis.orthonormalized().get_rotation_quaternion())
	if yaw_error>0.00001: errors.append("Unexpected actor-yaw ownership")
	var result := {"id":row.get("id",""),"fps":fps,"spec":spec,"frames":frames,"elapsed_s":elapsed,"leg_length_m":v.leg,"rooted":v.rooted,"endpoint_error_m":endpoint_error,"expected_world_distance_m":expected_distance if jump else commanded_distance,"actual_world_distance_m":_flat(actual,v.up).length(),"controller_speed_mps":controller_speed,"reset_performed":reset_performed,"extraction_error_m":extraction_error,"unconsumed_actor_change_m":unconsumed_actor_change,"grounded_root_delta_world_m":grounded_delta,"jump_capture_duration_s":capture,"terminal_hold_s":hold,"fadein_s":fadein,"fadeout_s":fadeout,"recovery_position_error_m":recovery_position,"recovery_rotation_error_rad":recovery_rotation,"shot_frames":shot_frames,"observed_flight_frames":air_frames,"nonfinite":nonfinite,"max_bone_speed_legs_per_s":max_velocity,"max_bone_angular_speed_rad_s":max_angular_velocity,"feet":feet,"trace":trace,"grounding":v.modifier.diagnostics(),"modification_processed_signals":v.signals,"passed":errors.is_empty(),"failures":errors}
	_free(v)
	return result
func _specs(row: Dictionary) -> Array:
	if row.has("quality_specs"): return row.quality_specs
	var meta := _data(row.get("write",{}))
	if not meta.has("clips"): meta=_data(row.get("setup_response",{}))
	var values: Dictionary = meta.get("speed_values",{})
	var specs: Array = []
	if values.has("walk") and values.has("run"):
		for speed in [float(values.walk)*0.5,float(values.walk),0.5*(float(values.walk)+float(values.run)),float(values.run)]: specs.append({"kind":"blend","speed_mps":speed,"duration_s":6.0,"controller_speed_mps":0.0 if bool(meta.get("root_motion",false)) else speed})
	if (meta.get("clips",{}) as Dictionary).has("jump"): specs.append({"kind":"jump","speed_mps":0.0,"controller_speed_mps":0.0})
	return specs
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=2:
		print("SETUP_TREE_QUALITY_FAIL: manifest and output required")
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not manifest is Dictionary or not manifest.get("cases") is Array:
		print("SETUP_TREE_QUALITY_FAIL: invalid manifest")
		quit(1)
		return
	var runs: Array = []
	var failures: Array[String] = []
	for row: Dictionary in manifest.cases:
		var specs := _specs(row)
		if specs.is_empty(): failures.append(str(row.get("id",""))+": no setup quality specs")
		for spec: Dictionary in specs:
			for fps in FPS:
				var checked := _check(row,spec,fps)
				runs.append(checked)
				if not checked.passed: failures.append("%s/%s/%d: %s" % [str(row.get("id","")),str(spec),fps,str(checked.failures)])
	var report := {"source_head":manifest.get("source_head",""),"manifest_sha256":FileAccess.get_sha256(args[0]),"checker_sha256":FileAccess.get_sha256("res://tools/check_setup_tree_quality.gd"),"runs":runs,"failures":failures,"engine_errors":logger.errors,"passed":not runs.is_empty() and failures.is_empty() and logger.errors.is_empty(),"measurement_contract":"Saved setup graph only; native phase parameters, direct owner-parent extraction or exact world controller velocity; ankle-plane contact, world-scaled bone velocity. No generation, sole collision or visual approval."}
	var destination := FileAccess.open(args[1],FileAccess.WRITE)
	if destination==null:
		print("SETUP_TREE_QUALITY_FAIL: cannot write output report")
		OS.remove_logger(logger)
		quit(1)
		return
	destination.store_string(JSON.stringify(report))
	print("SETUP_TREE_QUALITY="+JSON.stringify({"runs":runs.size(),"passed":report.passed,"failures":failures,"engine_errors":logger.errors}))
	OS.remove_logger(logger)
	quit(0 if report.passed else 1)
