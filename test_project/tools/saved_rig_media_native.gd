extends RefCounted
static func load_state(row: Dictionary, before: bool, root: Node) -> Dictionary:
	var receipt: Dictionary=row.before if before else row.scene
	if FileAccess.get_sha256(receipt.path)!=receipt.sha256:return {"error":"Saved scene hash mismatch"}
	var packed:=ResourceLoader.load(receipt.path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed==null:return {"error":"Saved scene unavailable"}
	var scene:=packed.instantiate()
	for node in scene.find_children("*","AnimationMixer",true,false):
		node.active=false
		if node is AnimationPlayer:node.stop()
	for node in scene.find_children("*","SkeletonModifier3D",true,false):
		scene.free();return {"error":"Live modifier requires signal-aware existing renderer"}
	for node in scene.find_children("*","MeshInstance3D",true,false):
		scene.free();return {"error":"Saved mesh/skin body requires separate signal-and-skin-aware capture; unskinned joints only here"}
	root.add_child(scene)
	var rig:=scene.get_node_or_null(row.skeleton) as Skeleton3D
	if rig==null:scene.free();return {"error":"Missing saved Skeleton3D"}
	var v:={"scene":scene,"rig":rig,"row":row,"before":before,"receipt":receipt,"player":null,"clip":null}
	if row.kind=="clip":
		var player:=scene.get_node_or_null(row.player) as AnimationPlayer
		if player==null or not player.has_animation(row.animation):scene.free();return {"error":"Missing saved generated clip/player"}
		if not player.root_motion_track.is_empty():scene.free();return {"error":"Unexpected rig clip extraction contract"}
		v.player=player;v.clip=player.get_animation(row.animation)
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.playback_auto_capture=false;player.active=true;player.play(row.animation);player.advance(0.0)
	v.initial=poses(rig)
	return v
static func poses(rig: Skeleton3D) -> Array:
	var result: Array=[]
	for bone in rig.get_bone_count():result.append(rig.get_bone_pose(bone))
	return result
static func difference(a: Array,b: Array) -> float:
	var worst:=0.0
	if a.size()!=b.size():return INF
	for i in a.size():
		worst=maxf(worst,a[i].origin.distance_to(b[i].origin))
		worst=maxf(worst,a[i].basis.get_scale().distance_to(b[i].basis.get_scale()))
		var q:Quaternion=a[i].basis.orthonormalized().get_rotation_quaternion().inverse()*b[i].basis.orthonormalized().get_rotation_quaternion()
		worst=maxf(worst,2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
	return worst
static func _global_from_local(rig: Skeleton3D, bone: int) -> Transform3D:
	var parent := rig.get_bone_parent(bone)
	var local := rig.get_bone_pose(bone) if rig.is_bone_enabled(bone) and not rig.show_rest_only else rig.get_bone_rest(bone)
	return _global_from_local(rig,parent)*local if parent>=0 else local
static func evaluate(v: Dictionary) -> Dictionary:
	# Existing native skeleton update path; no pose corrections or local writes.
	v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	var freshness := 0.0
	for bone in v.rig.get_bone_count():
		freshness=maxf(freshness,difference([v.rig.get_bone_global_pose(bone)],[_global_from_local(v.rig,bone)]))
	var position_error:=0.0
	var rotation_error:=0.0
	var scale_error:=0.0
	var finite:=true
	var active:=0
	for node in v.scene.find_children("*","AnimationMixer",true,false):
		if node.active:active+=1
	var expected_writers:=1 if v.row.kind=="clip" else 0
	var phase:=0.0
	var channels:=0
	if v.player!=null:
		phase=v.player.current_animation_position
		var base: Node=v.player.get_node(v.player.root_node)
		for track in v.clip.get_track_count():
			if not v.clip.track_is_enabled(track):continue
			var path: NodePath=v.clip.track_get_path(track)
			if path.get_subname_count()!=1 or base.get_node_or_null(NodePath(path.get_concatenated_names()))!=v.rig:return {"error":"Unsupported saved track target"}
			var bone:int=v.rig.find_bone(path.get_subname(0))
			if bone<0:return {"error":"Missing authored bone"}
			channels+=1
			match v.clip.track_get_type(track):
				Animation.TYPE_POSITION_3D:position_error=maxf(position_error,v.rig.get_bone_pose_position(bone).distance_to(v.clip.position_track_interpolate(track,phase)))
				Animation.TYPE_ROTATION_3D:
					var actual: Quaternion=v.rig.get_bone_pose_rotation(bone)
					var expected: Quaternion=v.clip.rotation_track_interpolate(track,phase)
					var q:=actual.inverse()*expected
					rotation_error=maxf(rotation_error,2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
				Animation.TYPE_SCALE_3D:scale_error=maxf(scale_error,v.rig.get_bone_pose_scale(bone).distance_to(v.clip.scale_track_interpolate(track,phase)))
				_:return {"error":"Unsupported rig clip channel"}
	for bone in v.rig.get_bone_count():
		var pose: Transform3D=v.rig.global_transform*v.rig.get_bone_global_pose(bone)
		finite=finite and pose.origin.is_finite() and pose.basis.is_finite()
	return {"assigned_animation":str(v.player.assigned_animation) if v.player!=null else "","clip_length":v.clip.length if v.clip!=null else 0.0,"clip_loop_mode":v.clip.loop_mode if v.clip!=null else 0,"playing":v.player.is_playing() if v.player!=null else false,"native_update_requested":true,"fresh_global_pose_error":freshness,"skinned_meshes":0,"phase_s":phase,"position_error":position_error,"rotation_error":rotation_error,"scale_error":scale_error,"channels":channels,"finite":finite,"writers":active,"expected_writers":expected_writers,"motion":difference(v.initial,poses(v.rig))}
