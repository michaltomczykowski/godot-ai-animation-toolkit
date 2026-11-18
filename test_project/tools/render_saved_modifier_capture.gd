extends "check_saved_modifier_capture.gd"
## Technical native joints only. Shared qualified _take owns every evaluation.
const Framing:=preload("saved_media_framing.gd")
var native_only:=true
var frames_path:=""
var preflight:Dictionary={}
var preflight_sha:=""
var accepted_frames:=0
var camera:Camera3D
var heading:Label
var caption:Label
var output_meshes:Array=[]
var output_lines:MeshInstance3D
var input_lines:MeshInstance3D
var markers:Array=[]
var camera_receipt:Dictionary={}
func _sample_frames(_row:Dictionary,rate:int)->int:return 4*rate
func _input_global(rig:Skeleton3D,poses:Array,bone:int)->Transform3D:
	var parent:=rig.get_bone_parent(bone)
	return _input_global(rig,poses,parent)*poses[bone] if parent>=0 else poses[bone]
func _vertices(context:Dictionary)->Array:
	var points:Array=[]
	for pose:Transform3D in context.globals:
		for x in [-1,1]:
			for y in [-1,1]:
				for z in [-1,1]:points.append(pose*Vector3(x*.06,y*.06,z*.06))
		points.append(pose.origin+pose.basis.x*.25)
	var rig:Skeleton3D=context.observed
	for bone in rig.get_bone_count():points.append((rig.global_transform*_input_global(rig,context.baseline,bone)).origin)
	var modifier:SkeletonModifier3D=context.modifier
	var targets:Array=[]
	if modifier is TwoBoneIK3D:targets=[modifier.get_node(modifier.get_target_node(0)),modifier.get_node(modifier.get_pole_node(0))]
	elif modifier is LookAtModifier3D:targets=[modifier.get_node(modifier.target_node)]
	for node:Node3D in targets:
		for x in [-1,1]:
			for y in [-1,1]:
				for z in [-1,1]:points.append(node.global_position+Vector3(x,y,z)*.04)
	return points
func _envelope(points:Array)->Dictionary:
	var lo:=Vector3(INF,INF,INF);var hi:=Vector3(-INF,-INF,-INF)
	for point:Vector3 in points:lo=lo.min(point);hi=hi.max(point)
	return {"minimum":[lo.x,lo.y,lo.z],"maximum":[hi.x,hi.y,hi.z],"vertex_count":points.size()}
func _corners(envelope:Dictionary)->Array:
	var a:Array=envelope.minimum;var b:Array=envelope.maximum
	var out:Array=[]
	for x in [a[0],b[0]]:
		for y in [a[1],b[1]]:
			for z in [a[2],b[2]]:out.append(Vector3(x,y,z))
	return out
func _material(color:Color)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=color
	return m
func _sphere(radius:float,color:Color)->MeshInstance3D:
	var node:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=radius;sphere.height=2*radius
	node.mesh=sphere;node.material_override=_material(color);root.add_child(node);return node
func _capture_begin(context:Dictionary):
	if native_only or not context.active:return
	for node in _nodes(context.scene,"MeshInstance3D"):node.visible=false
	for bone in context.observed.get_bone_count():output_meshes.append(_sphere(.06,Color(.15,.85,1)))
	output_lines=MeshInstance3D.new();output_lines.material_override=_material(Color(.15,.85,1));root.add_child(output_lines)
	input_lines=MeshInstance3D.new();input_lines.material_override=_material(Color(.55,.55,.6));root.add_child(input_lines)
	var modifier:SkeletonModifier3D=context.modifier
	if modifier is TwoBoneIK3D:markers=[_sphere(.04,Color(1,.85,.15)),_sphere(.04,Color(1,.4,.15))]
	elif modifier is LookAtModifier3D:markers=[_sphere(.04,Color(1,.85,.15))]
	var selected:Array=preflight.runs.filter(func(r):return r.id==context.row.id)
	var lo:=Vector3(INF,INF,INF);var hi:=Vector3(-INF,-INF,-INF)
	for run:Dictionary in selected:
		for record:Dictionary in run.trace:
			for point:Vector3 in _corners(record.display_envelope):lo=lo.min(point);hi=hi.max(point)
	var center:Vector3=(lo+hi)*.5
	camera.position=center+Vector3(4,2,7);camera.look_at(center,Vector3.UP)
	camera.size=maxf(.001,(hi-lo).length()*.25)
	# Fit the complete qualified envelope, including target/pole and sphere radius.
	var env:={"minimum":_stable(lo),"maximum":_stable(hi)}
	var fitted:=false
	for attempt in 80:
		var result:=_project(env)
		if result.fits:fitted=true;break
		camera.size*=1.1
	_check(fitted,str(context.row.id)+" complete preflight envelope cannot fit")
	camera_receipt={"position":_stable(camera.position),"basis":_stable(camera.basis),"size":camera.size,"qualified_envelope":env,"preflight_sha256":preflight_sha}
func _project(envelope:Dictionary)->Dictionary:
	var points:Array=[];var clipped:=0
	for point:Vector3 in _corners(envelope):
		var depth:=-(camera.global_transform.affine_inverse()*point).z
		if camera.is_position_behind(point) or depth<camera.near or depth>camera.far:clipped+=1
		points.append(camera.unproject_position(point))
	return Framing.projected(points,clipped,true,8)
func _geometry(context:Dictionary)->void:
	var rig:Skeleton3D=context.observed
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var ghost:=ImmediateMesh.new();ghost.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone in rig.get_bone_count():
		var pose:Transform3D=context.globals[bone];output_meshes[bone].transform=pose
		mesh.surface_add_vertex(pose.origin);mesh.surface_add_vertex(pose.origin+pose.basis.x*.25)
		var parent:=rig.get_bone_parent(bone)
		if parent>=0:
			mesh.surface_add_vertex(pose.origin);mesh.surface_add_vertex(context.globals[parent].origin)
			ghost.surface_add_vertex((rig.global_transform*_input_global(rig,context.baseline,bone)).origin)
			ghost.surface_add_vertex((rig.global_transform*_input_global(rig,context.baseline,parent)).origin)
	mesh.surface_end();ghost.surface_end();output_lines.mesh=mesh;input_lines.mesh=ghost
	var modifier:SkeletonModifier3D=context.modifier
	if modifier is TwoBoneIK3D:
		markers[0].position=modifier.get_node(modifier.get_target_node(0)).global_position;markers[1].position=modifier.get_node(modifier.get_pole_node(0)).global_position
	elif modifier is LookAtModifier3D:markers[0].position=modifier.get_node(modifier.target_node).global_position
func _capture_frame(context:Dictionary):
	var record:Dictionary=context.record
	record["native_elapsed_s"]=float(record.tick+1)/context.fps
	record["input_time_s"]=record.time
	record["display_envelope"]=_envelope(_vertices(context))
	record["source_input_pose_sha256"]=context.source_input_sha256
	if native_only or not context.active:return
	var size:Vector2i=root.get_texture().get_size()
	_check(size==Vector2i(1920,1080),"Actual root render texture must be1920x1080")
	record["fixed_camera"]=camera_receipt
	record["framing"]=_project(record.display_envelope)
	_check(record.framing.fits,str(context.row.id)+" complete displayed geometry framing")
	_geometry(context)
	heading.text="SAVED NATIVE MODIFIER | %s | TAKE %d/2 | %.3fs"%[context.row.op,context.take+1,record.native_elapsed_s]
	caption.text="Technical unskinned joints/axes only | grey authored input, cyan native final | yellow target / orange pole
Original saved inactive configuration; declared runtime activation/influence1 | no collider or receiver edits"
	await process_frame
	await RenderingServer.frame_post_draw
	record["framing"]=_project(record.display_envelope)
	_check(record.framing.fits,str(context.row.id)+" post-draw complete geometry framing")
	var image:=root.get_texture().get_image()
	_check(image.get_size()==Vector2i(1920,1080),"Actual PNG dimensions")
	var path:=frames_path.path_join("%06d.png"%accepted_frames)
	_check(not FileAccess.file_exists(path),"Preserve existing accepted frame")
	var result:=image.save_png(path);_check(result==OK,"PNG save failed")
	record["raw_after_draw"]=context.signals.raw;record["final_after_draw"]=context.signals.final;record["skin_after_draw"]=context.signals.skin
	_check(context.signals.raw==record.raw and context.signals.final==record.final,"No native modifier evaluation outside declared frame")
	record["movie_frame"]=accepted_frames;record["png_path"]=path;record["png_sha256"]=FileAccess.get_sha256(path);record["png_dimensions"]=[image.get_width(),image.get_height()]
	accepted_frames+=1
func _capture_end(_context:Dictionary):
	if native_only:return
	for node in output_meshes:node.free()
	output_meshes.clear()
	for node in markers:node.free()
	markers.clear()
	if is_instance_valid(output_lines):output_lines.free()
	if is_instance_valid(input_lines):input_lines.free()
func _run()->void:
	OS.add_logger(logger)
	var args:=OS.get_cmdline_user_args()
	if args.size()<3:printerr("manifest NEWreport native|render [qualifiedNativeReport NEWframes]");quit(1);return
	report_path=args[1]
	if args[2] not in ["native","render","inert"]:printerr("Unknown mode");quit(1);return
	inert_control=args[2]=="inert";native_only=args[2]!="render"
	if FileAccess.file_exists(report_path):printerr("Preserve previous report");quit(1);return
	manifest=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for dependency in manifest.capture_dependencies:_check(FileAccess.get_sha256(dependency.path)==dependency.sha256,"Immutable capture dependency "+str(dependency.path))
	if not native_only:
		if args.size()!=5:printerr("Render requires preflight and NEW frames directory");quit(1);return
		preflight=JSON.parse_string(FileAccess.get_file_as_string(args[3]));preflight_sha=FileAccess.get_sha256(args[3]);frames_path=args[4]
		_check(preflight.get("passed",false) and preflight.get("mode","")=="native" and preflight.manifest_sha256==FileAccess.get_sha256(args[0]),"Require exact qualified4s native preflight")
		_check(preflight.get("renderer_sha256","")==FileAccess.get_sha256(get_script().resource_path) and preflight.get("shared_evaluator_sha256","")==FileAccess.get_sha256("res://tools/check_saved_modifier_capture.gd") and preflight.get("engine_errors",["missing"]).is_empty() and preflight.get("failures",["missing"]).is_empty() and preflight.get("runs",[]).size()==20 and not preflight.get("inert_control",true),"Qualified native source/cells/errors differ")
		_check(not DirAccess.dir_exists_absolute(frames_path),"Preserve prior frames directory")
		if not failures.is_empty():quit(1);return
		DirAccess.make_dir_recursive_absolute(frames_path)
		root.size=Vector2i(1920,1080);root.content_scale_size=Vector2i(1920,1080);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
		camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;root.add_child(camera);camera.make_current()
		var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.025,.04,.065);root.add_child(env)
		var layer:=CanvasLayer.new();root.add_child(layer);heading=Label.new();heading.position=Vector2(24,24);heading.add_theme_font_size_override("font_size",32);layer.add_child(heading)
		caption=Label.new();caption.position=Vector2(24,905);caption.add_theme_font_size_override("font_size",25);layer.add_child(caption)
	for row:Dictionary in manifest.cases:
		var active_runs:Array=[]
		for take in 2:
			var off:Dictionary=await _take(row,60,false,take);var on:Dictionary=await _take(row,60,true,take)
			_check(_difference(off.final_pose,on.final_pose)>.001,row.id+" noninert4s native effect")
			active_runs.append(on);runs.append(off);runs.append(on)
		_check(active_runs[0].final_pose==active_runs[1].final_pose,row.id+" fresh4s reset final pose")
	_check(native_only or accepted_frames==2400,"Exactly2400 accepted PNGs")
	for dependency in manifest.capture_dependencies:_check(FileAccess.get_sha256(dependency.path)==dependency.sha256,"Immutable source after evaluation "+str(dependency.path))
	var passed:=failures.is_empty() and logger.errors.is_empty() and runs.size()==20
	var result:={"kind":"saved_modifier_joint_media","mode":"native" if native_only else "render","inert_control":inert_control,"passed":passed,"manifest_sha256":FileAccess.get_sha256(args[0]),"renderer_sha256":FileAccess.get_sha256(get_script().resource_path),"shared_evaluator_sha256":FileAccess.get_sha256("res://tools/check_saved_modifier_capture.gd"),"framing_sha256":FileAccess.get_sha256("res://tools/saved_media_framing.gd"),"native_preflight_sha256":preflight_sha,"accepted_frames":accepted_frames,"expected_frames":0 if native_only else 2400,"fps":60,"runs":runs,"failures":failures,"engine_errors":logger.errors,"visual_approval":false,"scope":"Technical original native joint effects; no human character-motion quality claim. Loading warmup excluded before each timeline; PNGs sampled after every explicit native step and final draw."}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(_stable(result)))
	OS.remove_logger(logger)
	print("SAVED_MODIFIER_MEDIA="+JSON.stringify({"passed":passed,"mode":result.mode,"frames":accepted_frames,"failures":failures,"engine_errors":logger.errors}))
	quit(0 if passed else 1)
