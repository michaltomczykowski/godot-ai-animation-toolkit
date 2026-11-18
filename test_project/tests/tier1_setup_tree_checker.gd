extends "res://tools/check_setup_tree_quality.gd"
## Disposable synthetic saved graphs qualify the checker, not production motion.
var test_failures: Array[String] = []
func _expect(ok: bool, label: String) -> void:
	if not ok: test_failures.append(label)
func _run() -> void:
	var directory := "user://setup_tree_checker_controls_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var valid := _fixture(directory.path_join("valid.tscn"),true,1.0,true)
	var doubled := _fixture(directory.path_join("doubled.tscn"),true,2.0,true)
	var markers := _fixture(directory.path_join("missing_markers.tscn"),true,1.0,false)
	var in_place := _fixture(directory.path_join("in_place_forward.tscn"),false,1.0,true)
	var rotated := _fixture(directory.path_join("rotated_half.tscn"),true,1.0,true,Transform3D(Basis(Vector3(1,2,3).normalized(),0.6).scaled(Vector3.ONE*0.5),Vector3(34,2,-11)))
	var zup := _fixture(directory.path_join("rotated_zup_double.tscn"),true,1.0,true,Transform3D(Basis(Vector3(3,1,2).normalized(),0.8).scaled(Vector3.ONE*2.0),Vector3(-23,4,31)),"res://repair_synthetic_zup_tall.tscn")
	var reports: Array = []
	for fps in [30,60,120]:
		var blend := _check(valid,{"kind":"blend","speed_mps":0.2,"duration_s":0.02},fps)
		reports.append(blend)
		_expect(blend.passed,"valid short native blend "+str(fps)+": "+str(blend.failures))
		for middle in [0.1,0.3]:
			var mixed := _check(valid,{"kind":"blend","speed_mps":middle,"duration_s":0.02},fps)
			reports.append(mixed)
			_expect(mixed.passed,"intermediate native blend "+str(middle)+"/"+str(fps)+": "+str(mixed.failures))
		var controlled := _check(in_place,{"kind":"blend","speed_mps":0.1,"controller_speed_mps":0.1,"duration_s":0.02},fps)
		reports.append(controlled)
		_expect(controlled.passed,"exact in-place world controller "+str(fps)+": "+str(controlled.failures))
		var wrong_control := _check(in_place,{"kind":"blend","speed_mps":0.1,"controller_speed_mps":0.2,"duration_s":0.02},fps)
		reports.append(wrong_control)
		_expect(not wrong_control.passed and str(wrong_control.failures).contains("endpoint"),"wrong controller world distance rejected "+str(fps))
		for transformed: Dictionary in [rotated,zup]:
			var transformed_jump := _check(transformed,{"kind":"jump","speed_mps":0.0},fps)
			reports.append(transformed_jump)
			_expect(transformed_jump.passed,"rotated/scaled native jump "+str(transformed.id)+"/"+str(fps)+": "+str(transformed_jump.failures))
		var jump := _check(valid,{"kind":"jump","speed_mps":0.0},fps)
		reports.append(jump)
		_expect(jump.passed,"valid native OneShot "+str(fps)+": "+str(jump.failures))
		var corrupt := _check(doubled,{"kind":"jump","speed_mps":0.0},fps)
		reports.append(corrupt)
		_expect(not corrupt.passed and str(corrupt.failures).contains("endpoint"),"doubled authored travel rejected "+str(fps))
		var missing := _check(markers,{"kind":"blend","speed_mps":0.2,"duration_s":0.02},fps)
		reports.append(missing)
		_expect(not missing.passed and str(missing.failures).contains("contact markers"),"missing contact markers rejected "+str(fps))
		var lost := _check(in_place,{"kind":"jump","speed_mps":0.0},fps)
		reports.append(lost)
		_expect(not lost.passed and str(lost.failures).contains("endpoint"),"unextracted OneShot loses travel and is detected "+str(fps))
	_expect(logger.errors.is_empty(),"no engine errors: "+str(logger.errors))
	var report := {"passed":test_failures.is_empty(),"failures":test_failures,"engine_errors":logger.errors,"runs":reports,"synthetic_fixture_root":directory}
	FileAccess.open(directory.path_join("controls.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("TIER1_SETUP_TREE_CHECKER="+JSON.stringify({"passed":report.passed,"failures":test_failures,"engine_errors":logger.errors,"runs":reports.size(),"receipt":directory.path_join("controls.json")}))
	OS.remove_logger(logger)
	print("TIER1 PASS" if report.passed else "TIER1 FAIL")
	quit(0 if report.passed else 1)
func _fixture(path: String, rooted: bool, multiplier: float, markers: bool, placement: Transform3D=Transform3D.IDENTITY, fixture: String="res://repair_synthetic_short.tscn") -> Dictionary:
	var body := (load(fixture) as PackedScene).instantiate() as Node3D
	body.name="SyntheticSetup"
	body.transform=placement
	var metric_scale := placement.basis.x.length()
	root.add_child(body)
	var skeleton := body.get_node("Dummy/Skeleton3D") as Skeleton3D
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	for name in player.get_animation_library_list(): player.remove_animation_library(name)
	var hip_index := skeleton.find_bone("B-hips")
	var hip_global := skeleton.get_bone_global_rest(hip_index).origin
	var hip := skeleton.get_bone_rest(hip_index).origin
	var hip_parent := skeleton.get_bone_parent(hip_index)
	var to_hip_parent := skeleton.get_bone_global_rest(hip_parent).basis.inverse() if hip_parent>=0 else Basis.IDENTITY
	var forward := skeleton.get_bone_global_rest(skeleton.find_bone("B-toe.L")).origin-skeleton.get_bone_global_rest(skeleton.find_bone("B-foot.L")).origin
	var spine := skeleton.get_bone_global_rest(skeleton.find_bone("B-head")).origin-hip_global
	var local_up := Vector3.ZERO
	local_up[spine.abs().max_axis_index()]=signf(spine[spine.abs().max_axis_index()])
	forward=(forward-local_up*forward.dot(local_up)).normalized()
	var library := AnimationLibrary.new()
	for pair in [["idle",0.0],["walk",0.2],["run",0.4]]:
		var clip := Animation.new()
		clip.length=1.0
		clip.loop_mode=Animation.LOOP_LINEAR
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(track,NodePath("Dummy/Skeleton3D:B-hips"))
		clip.track_insert_key(track,0.0,hip)
		clip.track_insert_key(track,0.5,hip-to_hip_parent*local_up*0.001)
		clip.track_insert_key(track,1.0,hip)
		if rooted:
			track=clip.add_track(Animation.TYPE_POSITION_3D)
			clip.track_set_path(track,NodePath(".:position"))
			clip.track_insert_key(track,0.0,body.position)
			clip.track_insert_key(track,1.0,body.position+body.basis*forward*float(pair[1])*multiplier/metric_scale)
		if markers and str(pair[0])!="idle":
			for side in ["L","R"]:
				clip.add_marker("contact."+side,0.0 if side=="L" else 0.001)
				clip.add_marker("toe_off."+side,0.99 if side=="L" else 0.991)
		library.add_animation(str(pair[0]),clip)
	var jump := Animation.new()
	jump.length=1.201
	var track := jump.add_track(Animation.TYPE_POSITION_3D)
	jump.track_set_path(track,NodePath("Dummy/Skeleton3D:B-hips"))
	for phase in [[0.0,0.0,0.0],[0.36,0.0,0.0],[0.6,0.15,0.12],[0.75,0.12,0.2],[0.96,0.0,0.2],[1.2,0.0,0.2],[1.201,0.0,0.2]]:
		jump.track_insert_key(track,float(phase[0]),hip+to_hip_parent*(local_up*float(phase[1])+(Vector3.ZERO if rooted else forward*float(phase[2])*multiplier/metric_scale)))
	if rooted:
		track=jump.add_track(Animation.TYPE_POSITION_3D)
		jump.track_set_path(track,NodePath(".:position"))
		for phase in [[0.0,0.0],[0.36,0.0],[0.6,0.12],[0.75,0.2],[0.96,0.2],[1.2,0.2],[1.201,0.2]]: jump.track_insert_key(track,float(phase[0]),body.position+body.basis*forward*float(phase[1])*multiplier/metric_scale)
	jump.add_marker("takeoff",0.36)
	jump.add_marker("land",0.96)
	library.add_animation("jump",jump)
	player.add_animation_library("",library)
	player.root_node=NodePath("..")
	player.root_motion_track=NodePath(".:position") if rooted else NodePath()
	player.root_motion_local=true
	var space := AnimationNodeBlendSpace1D.new()
	for pair in [["idle",0.0],["walk",0.2],["run",0.4]]:
		var node := AnimationNodeAnimation.new()
		node.animation=StringName(pair[0])
		space.add_blend_point(node,float(pair[1]),-1,StringName(pair[0]))
	space.min_space=0.0
	space.max_space=0.4
	space.sync=true
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("Base",space)
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time=0.1
	shot.fadeout_time=0.2
	graph.add_node("OneShot",shot)
	var shot_clip := AnimationNodeAnimation.new()
	shot_clip.animation="jump"
	graph.add_node("Shot",shot_clip)
	graph.connect_node("OneShot",0,"Base")
	graph.connect_node("OneShot",1,"Shot")
	graph.connect_node("output",0,"OneShot")
	var tree := AnimationTree.new()
	tree.name="AnimationTree"
	body.add_child(tree)
	tree.anim_player=tree.get_path_to(player)
	tree.tree_root=graph
	tree.root_motion_track=player.root_motion_track
	tree.root_motion_local=true
	tree.active=false
	var roles := {"hips":"B-hips","head":"B-head","thigh_l":"B-thigh.L","shin_l":"B-shin.L","foot_l":"B-foot.L","toe_l":"B-toe.L","thigh_r":"B-thigh.R","shin_r":"B-shin.R","foot_r":"B-foot.R"}
	var grounder := Grounding.new()
	grounder.name="SetupGrounding"
	skeleton.add_child(grounder)
	grounder.tree_path=grounder.get_path_to(tree)
	grounder.player_path=grounder.get_path_to(player)
	grounder.role_names=roles
	grounder.rig_up=local_up
	grounder.rig_forward=forward
	grounder.speed_parameter="parameters/Base/blend_position"
	grounder.base_prefix="parameters/Base/"
	grounder.jump_parameter="parameters/OneShot/request"
	for child in body.get_children(): _own(child,body)
	var packed := PackedScene.new()
	_expect(packed.pack(body)==OK and ResourceSaver.save(packed,path)==OK,"save synthetic graph")
	body.free()
	return {"id":path.get_file(),"scene":path,"scene_sha256":FileAccess.get_sha256(path),"player":"AnimationPlayer","skeleton":"Dummy/Skeleton3D","request":{"include_jump":true,"root_motion":rooted,"distance":0.2},"roles":{"hips":"B-hips","head":"B-head","thigh_l":"B-thigh.L","shin_l":"B-shin.L","foot_l":"B-foot.L","toe_l":"B-toe.L","thigh_r":"B-thigh.R","shin_r":"B-shin.R","foot_r":"B-foot.R"},"write":{"grounding_path":"/SyntheticSetup/Dummy/Skeleton3D/SetupGrounding","grounding":{"contract_version":Grounding.CONTRACT_VERSION},"root_motion":rooted,"tree_path":"/SyntheticSetup/AnimationTree","speed_parameter":"parameters/Base/blend_position","jump_request_parameter":"parameters/OneShot/request","speed_values":{"idle":0.0,"walk":0.2,"run":0.4},"clips":{"idle":{"length":1.0},"walk":{"length":1.0},"run":{"length":1.0},"jump":{"length":1.201,"capture_duration":1.2,"root_motion_terminal_hold":0.001}}}}
func _own(node: Node, owner_node: Node) -> void:
	node.owner=owner_node
	for child in node.get_children(): _own(child,owner_node)
