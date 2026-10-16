extends "res://tools/check_setup_tree_quality.gd"
## Saved native setup capture. No replacement graph, animation, helper or bone writes.
## Args: immutable schedule.json NEW_OUTPUT clean|diagnostic
var render_views: Array = []
func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=0.85
	return m
func _caption(text: String, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text=text
	label.position=at
	label.add_theme_font_size_override("font_size",size)
	root.add_child(label)
	return label
func _port(index: int) -> SubViewport:
	var p := SubViewport.new()
	p.size=Vector2i(952,900)
	p.own_world_3d=true
	p.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(p)
	var image := TextureRect.new()
	image.texture=p.get_texture()
	image.position=Vector2(4+960*index,125)
	image.size=Vector2(952,900)
	root.add_child(image)
	return p
func _view(row: Dictionary, port: SubViewport, side: bool, diagnostic: bool) -> Dictionary:
	var v := _load(row) # Shared saved-hash, ownership and helper admission.
	if v.has("error"): return v
	var world := Node3D.new()
	port.add_child(world)
	var holder: Node = v.driver if v.has("driver") else v.scene
	holder.reparent(world,true)
	v.world=world
	v.skin_updates=0
	v.rig.skeleton_updated.connect(func(): v.skin_updates+=1)
	v.rig.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var env := WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0.035,0.055,0.075)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=0.6
	world.add_child(env)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees=Vector3(-40,-30,0)
	var right: Vector3 = v.forward.cross(v.up).normalized()
	var speed := float(row.render_spec.speed_mps)
	var duration := float(row.render_spec.frames_per_take)/60.0
	var travel := speed*duration
	var center: Vector3 = _point(v,"hips",true)+v.forward*travel*0.5
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(maxf(6.0*float(v.leg),travel+4.0*float(v.leg)),maxf(6.0*float(v.leg),travel+4.0*float(v.leg)))
	plane.material=_material(Color(0.15,0.19,0.23))
	floor.mesh=plane
	world.add_child(floor)
	floor.global_basis=Basis(right,v.up,-v.forward)
	floor.global_position=center+v.up*(float(v.ground)-center.dot(v.up)-0.005*float(v.leg))
	# Static quarter-leg grid uses measured geometry axes, never a world-Y guess.
	for axis in 2:
		for offset in range(-12,13):
			var line := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size=Vector3(0.004*float(v.leg),0.004*float(v.leg),6.0*float(v.leg)) if axis==0 else Vector3(6.0*float(v.leg),0.004*float(v.leg),0.004*float(v.leg))
			box.material=_material(Color(0.23,0.28,0.32))
			line.mesh=box
			world.add_child(line)
			line.global_basis=Basis(right,v.up,-v.forward)
			line.global_position=floor.global_position+v.up*0.002*float(v.leg)+(right if axis==0 else v.forward)*float(offset)*0.25*float(v.leg)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=maxf(3.5*float(v.leg),travel+2.5*float(v.leg))
	camera.global_position=center+(right if side else v.forward)*8.0*float(v.leg)+v.up*0.35*float(v.leg)
	camera.look_at(center,v.up)
	camera.current=true
	v.proxy=[]
	# Proxy geometry is display-only. Real meshes remain native and untouched.
	var visible_meshes := 0
	for mesh: MeshInstance3D in v.scene.find_children("*","MeshInstance3D",true,false):
		if mesh.visible: visible_meshes+=1
	v.presentation="original saved meshes" if visible_meshes>0 else "display-only skeleton proxy"
	if visible_meshes==0 or diagnostic:
		for bone in v.rig.get_bone_count():
			var parent: int = v.rig.get_bone_parent(bone)
			if parent<0: continue
			var rod := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.height=1.0
			cylinder.top_radius=0.014*float(v.leg)
			cylinder.bottom_radius=cylinder.top_radius
			cylinder.material=_material(Color(0.25,0.8,0.9))
			rod.mesh=cylinder
			world.add_child(rod)
			v.proxy.append({"node":rod,"a":parent,"b":bone})
	v.tree.set(v.speed_parameter,speed)
	v.tree.active=true
	v.tree.advance(0.0)
	v.modifier.reset_grounding("fresh_recording_take")
	v.rig.advance(0.0)
	v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	v.prime_signals=v.signals
	if v.signals!=1: push_error("Fresh take requires exactly one zero-time final signal")
	return v
func _advance_view(v: Dictionary, row: Dictionary, frame: int) -> Dictionary:
	if frame==int(row.render_spec.jump_fire_at_frame): v.tree.set(v.jump_parameter,AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var before: Vector3 = v.owner.global_position
	v.tree.advance(1.0/60.0)
	var delta: Vector3 = v.tree.get_root_motion_position()
	if v.rooted: v.owner.position+=delta
	else: v.owner.global_position+=v.forward*float(row.render_spec.controller_speed_mps)/60.0
	var prior: int = v.signals
	v.rig.advance(1.0/60.0)
	v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	if v.signals!=prior+1: push_error("Missing or duplicate final signal during native frame")
	if v.modifier.status!="grounded" or not v.modifier.last_error.is_empty() or v.modifier.unreachable>0: push_error("Saved grounding runtime failed")
	for segment: Dictionary in v.proxy:
		var a: Vector3 = v.rig.global_transform*_pose(v,segment.a).origin
		var b: Vector3 = v.rig.global_transform*_pose(v,segment.b).origin
		var direction := b-a
		segment.node.visible=direction.length()>0.000001
		if segment.node.visible: segment.node.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized()))*Basis.from_scale(Vector3(1,direction.length(),1)),(a+b)*0.5)
	var phases := []
	for point: Dictionary in _points(v,float(row.render_spec.speed_mps)):
		phases.append({"clip":point.clip,"weight":point.weight,"phase":v.tree.get(point.phase_path)})
	return {"frame":frame,"time_s":float(frame+1)/60.0,"signals":v.signals,"skin_updates":v.skin_updates,"root_delta_parent":[delta.x,delta.y,delta.z],"travel_m":v.owner.global_position.distance_to(v.initial_owner),"owner_step_m":v.owner.global_position.distance_to(before),"phases":phases,"grounding":v.modifier.diagnostics(),"shot_active":bool(v.tree.get("parameters/OneShot/active")) if v.shot!=null else false}
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=3: quit(1); return
	var schedule: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var output: String = args[1]
	if DirAccess.dir_exists_absolute(output): push_error("Output exists; preserve original capture"); quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var size := Vector2i(1920,1080)
	if int(ProjectSettings.get_setting("display/window/size/viewport_width",0))!=size.x or int(ProjectSettings.get_setting("display/window/size/viewport_height",0))!=size.y:
		push_error("Require prestartup logical viewport1920x1080; use movie_capture_startup.py")
	root.content_scale_size=size
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	root.size=size
	var title := _caption("SAVED SETUP | fixed FRONT / SIDE",Vector2(24,10),30)
	var status := _caption("",Vector2(24,55),22)
	_caption("Actual saved Tree + owned helper | fresh reset takes | proxy geometry labeled where used",Vector2(24,1035),20)
	var ports := [_port(0),_port(1)]
	var count := 0
	var results := []
	for row: Dictionary in schedule.cases:
		for take in 2:
			render_views=[_view(row,ports[0],false,args[2]=="diagnostic"),_view(row,ports[1],true,args[2]=="diagnostic")]
			if render_views[0].has("error") or render_views[1].has("error"): push_error("Saved setup view admission failed"); break
			title.text="%s | %s | TAKE %d (fresh reset)" % [row.id,row.render_spec.condition,take+1]
			var trace := []
			for frame in int(row.render_spec.frames_per_take):
				var samples := []
				for v: Dictionary in render_views: samples.append(_advance_view(v,row,frame))
				status.text="%.3fs | %s | native travel %.3fm" % [float(frame+1)/60.0,render_views[0].presentation,float(samples[0].travel_m)]
				await process_frame
				await RenderingServer.frame_post_draw
				for index in 2:
					samples[index]["skin_updates_after_draw"]=render_views[index].skin_updates
					if render_views[index].skin_updates<=0: push_error("No actual skeleton skin-update witness")
					if render_views[index].signals!=samples[index].signals: push_error("Unexpected modifier evaluation between final witness and rendered frame")
				var image := root.get_texture().get_image()
				if image.get_size()!=size: push_error("Incorrect actual render dimensions"); break
				if image.save_png(output.path_join("%06d.png" % count))!=OK: push_error("PNG write failed")
				trace.append(samples)
				count+=1
				if not logger.errors.is_empty(): break
			results.append({"id":row.id,"take":take+1,"scene_sha256":row.scene_sha256,"frames":trace.size(),"trace":trace,"presentation":render_views[0].presentation,"prime_signals":[render_views[0].prime_signals,render_views[1].prime_signals]})
			for v: Dictionary in render_views: v.world.free()
			render_views=[]
			if not logger.errors.is_empty(): break
		if not logger.errors.is_empty(): break
	var report := {"passed":logger.errors.is_empty() and results.size()==8,"frames":count,"fps":60,"size":[1920,1080],"schedule_sha256":FileAccess.get_sha256(args[0]),"renderer_sha256":FileAccess.get_sha256(get_script().resource_path),"checker_loader_sha256":FileAccess.get_sha256("res://tools/check_setup_tree_quality.gd"),"runtime_sha256":FileAccess.get_sha256("res://addons/godot_ai_animation/runtime/setup_grounding.gd"),"render_texture_size":root.get_texture().get_size(),"physical_window_size":root.size,"visible_rect":root.get_visible_rect(),"cases":results,"engine_errors":logger.errors,"root_consumers_per_view":1,"visual_assessment":"pending"}
	FileAccess.open(output.path_join("render.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if report.passed else 1)
