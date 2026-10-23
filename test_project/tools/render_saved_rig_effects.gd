extends SceneTree
const Framing:=preload("saved_media_framing.gd")
const Native:=preload("saved_rig_media_native.gd")
const Clips:=preload("saved_graph_media_native.gd")
class Errors extends Logger:
	var errors: Array[String]=[]
	func _log_error(_fn:String,_file:String,_line:int,code:String,reason:String,_notify:bool,type:int,_trace:Array)->void:
		if type!=1:errors.append(reason if not reason.is_empty() else code)
var logger:=Errors.new()
var manifest:Dictionary
var manifest_path:=""
var report_path:=""
var native_only:=false
var control:=""
var runs:Array=[]
var failures:Array=[]
var view:Dictionary={}
var result:Dictionary={}
var initial_pair:Array=[]
var clip_digest:=""
var fps:=60
var case_index:=0
var take:=0
var frame:=0
var rendering:=false
var startup_admission:={}
var meshes:Array=[]
var lines:MeshInstance3D
var material:StandardMaterial3D
var title:Label
var caption:Label
var camera:Camera3D

func _initialize()->void:_run.call_deferred()
func _run()->void:
	OS.add_logger(logger)
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:quit(1);return
	manifest_path=args[0];report_path=args[1]
	if FileAccess.file_exists(report_path):printerr("Preserve previous rig evidence");quit(1);return
	manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	native_only=args.size()>2 and args[2]=="native"
	control=args[3] if args.size()>3 else ""
	if control not in ["","inert","competing_player"] or (not native_only and not control.is_empty()):failures.append("Invalid control");_finish();return
	var operations:Array=[]
	for row:Dictionary in manifest.cases:operations.append(str(row.operation))
	operations.sort()
	if operations!=["bake_pose_sequence","blink","idle_breathing","jumping_jack","pose_apply","pose_to_clip","punch","squat","walk_cycle"]:failures.append("Expected nine distinct rig operations");_finish();return
	if native_only:
		for rate in [30,60,120]:
			fps=rate
			for row:Dictionary in manifest.cases:
				for repetition in 2:
					_start(row,repetition)
					if view.has("error"):failures.append(view.error);continue
					for tick in 4*fps+1:_step(tick)
					_end()
		_finish()
	else:
		startup_admission=Framing.startup()
		if not startup_admission.passed:failures.append("Require1920x1080viewportstretch before MovieMaker startup");_finish();return
		_setup_display();_start(manifest.cases[0],0)
		if view.has("error"):failures.append(view.error);_finish();return
		rendering=true
func _start(row:Dictionary,repetition:int)->void:
	view=Native.load_state(row,row.kind=="saved_static_pair",root)
	result={"operation":row.operation,"take":repetition+1,"fps":fps,"trace":[],"failures":[],"max_motion":0.0,"max_channel_error":0.0,"initial_pose_digest":"","scene_sha256":row.scene.sha256,"before_sha256":row.get("before",{}).get("sha256","")}
	if view.has("error"):return
	initial_pair=Native.poses(view.rig)
	result.initial_pose_digest=var_to_str(initial_pair).sha256_text()
	clip_digest=Clips.clip_digest(view.player) if view.player!=null else ""
	if not native_only:_geometry(true)
func _step(tick:int)->void:
	var time:=float(tick)/fps
	if view.row.kind=="saved_static_pair" and tick==2*fps:
		var row:Dictionary=view.row
		if FileAccess.get_sha256(view.receipt.path)!=view.receipt.sha256:result.failures.append("Saved before scene changed")
		_clear_geometry();view.scene.free()
		view=Native.load_state(row,false,root)
		if view.has("error"):result.failures.append(view.error);return
		var after:Array=Native.poses(view.rig)
		if Native.difference(initial_pair,after)<0.001:result.failures.append("Saved pose_apply pair has no changed pose")
		var untouched:int=view.rig.find_bone("untouched")
		if untouched<0 or not initial_pair[untouched].is_equal_approx(after[untouched]):result.failures.append("Saved pose_apply changed untouched bone")
		result["saved_pair_difference"]=Native.difference(initial_pair,after)
		if not native_only:_geometry(false)
	if tick>0 and view.player!=null and control!="inert":view.player.advance(1.0/fps)
	if control=="competing_player":
		for node in view.scene.find_children("*","AnimationPlayer",true,false):
			if node!=view.player:node.active=true;break
	var sample:=Native.evaluate(view)
	if sample.has("error"):
		if not result.failures.has(sample.error):result.failures.append(sample.error)
		return
	if not is_finite(float(sample.fresh_global_pose_error)) or float(sample.fresh_global_pose_error)>=0.00001 or int(sample.skinned_meshes)!=0:
		if not result.failures.has("Unfresh native global pose or unsupported skin"):result.failures.append("Unfresh native global pose or unsupported skin")
	sample["time_s"]=time
	if not native_only:
		sample["movie_frame"]=tick<4*fps
		sample["framing"]=Framing.rig(view.rig,camera)
		if not sample.framing.fits:result.failures.append("Projected rig geometry leaves body/header guard")
	result.trace.append(sample)
	result.max_motion=maxf(float(result.max_motion),float(sample.motion))
	var error:=maxf(float(sample.position_error),maxf(float(sample.rotation_error),float(sample.scale_error)))
	result.max_channel_error=maxf(float(result.max_channel_error),error)
	if error>0.00001 and not result.failures.has("Native authored channel mismatch"):result.failures.append("Native authored channel mismatch")
	if (not sample.finite or sample.writers!=sample.expected_writers) and not result.failures.has("Nonfinite or competing writer"):result.failures.append("Nonfinite or competing writer")
	if not native_only:
		_geometry_update()
		title.text="PRESERVED RIG | %s | TAKE %d/2 | %.3fs"%[view.row.operation,take+1,time]
		caption.text="Display-only unskinned joints, parent links and local-axis rods\n%s | native phase %.3fs | max channel error %.7f\nFixed camera per case; original saved bones and clips only"%[("saved BEFORE" if view.before else "saved AFTER") if view.row.kind=="saved_static_pair" else "one native Player; no live modifiers",sample.phase_s,error]
func _end()->void:
	if view.row.kind=="clip":
		if float(result.max_motion)<0.001:result.failures.append("Inert saved clip")
		if Clips.clip_digest(view.player)!=clip_digest:result.failures.append("Original clip data changed")
	if FileAccess.get_sha256(view.receipt.path)!=view.receipt.sha256:result.failures.append("Saved scene changed")
	result.passed=result.failures.is_empty();runs.append(result)
	if not result.passed:failures.append("%s/%s/%s: %s"%[result.operation,result.fps,result.take,str(result.failures)])
	_clear_geometry();view.scene.free();view={}
func _process(_delta:float)->bool:
	if not rendering:return false
	var texture_size:Vector2i=root.get_texture().get_size()
	var logical_size:Vector2i=Vector2i(root.get_visible_rect().size)
	if texture_size!=Vector2i(1920,1080) or logical_size!=Vector2i(1920,1080):
		failures.append("Incorrect logical render target: texture=%s visible=%s physical=%s"%[texture_size,logical_size,root.size])
		rendering=false;_finish();return false
	if frame==4*fps:
		_step(frame);_end();frame=0;take+=1
		if take==2:take=0;case_index+=1
		if case_index==manifest.cases.size():rendering=false;_finish();return false
		_start(manifest.cases[case_index],take)
		if view.has("error"):failures.append(view.error);rendering=false;_finish();return false
	_step(frame);frame+=1;return false
func _setup_display()->void:
	root.size=Vector2i(1920,1080)
	root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6;root.add_child(camera);camera.make_current()
	material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(0.2,0.8,1)
	var layer:=CanvasLayer.new();root.add_child(layer)
	title=Label.new();title.position=Vector2(24,24);title.add_theme_font_size_override("font_size",34);layer.add_child(title)
	caption=Label.new();caption.position=Vector2(24,900);caption.add_theme_font_size_override("font_size",26);layer.add_child(caption)
func _geometry(reframe:bool)->void:
	for bone in view.rig.get_bone_count():
		var node:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.06;sphere.height=0.12
		node.mesh=sphere;node.material_override=material;root.add_child(node);meshes.append(node)
	lines=MeshInstance3D.new();lines.material_override=material;root.add_child(lines)
	if reframe:
		var center:=Vector3.ZERO
		for bone in view.rig.get_bone_count():center+=(view.rig.global_transform*view.rig.get_bone_global_pose(bone)).origin
		center/=float(view.rig.get_bone_count())
		camera.position=center+Vector3(4,2,7);camera.look_at(center,Vector3.UP)
		result["fixed_camera"]={"position":[camera.position.x,camera.position.y,camera.position.z],"target":[center.x,center.y,center.z],"orthographic_size":camera.size}
	_geometry_update()
func _geometry_update()->void:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# A stable world-reference grid; it never follows animated joint positions.
	for grid in range(-10,11):
		mesh.surface_add_vertex(Vector3(grid,0,-10));mesh.surface_add_vertex(Vector3(grid,0,10))
		mesh.surface_add_vertex(Vector3(-10,0,grid));mesh.surface_add_vertex(Vector3(10,0,grid))
	for bone in view.rig.get_bone_count():
		var pose:Transform3D=view.rig.global_transform*view.rig.get_bone_global_pose(bone)
		meshes[bone].transform=pose
		mesh.surface_add_vertex(pose.origin);mesh.surface_add_vertex(pose.origin+pose.basis.x*0.25)
		var parent:int=view.rig.get_bone_parent(bone)
		if parent>=0:mesh.surface_add_vertex(pose.origin);mesh.surface_add_vertex((view.rig.global_transform*view.rig.get_bone_global_pose(parent)).origin)
	mesh.surface_end();lines.mesh=mesh
func _clear_geometry()->void:
	for node in meshes:node.free()
	meshes.clear()
	if is_instance_valid(lines):lines.free()
func _finish()->void:
	for first:Dictionary in runs:
		if first.take!=1:continue
		for second:Dictionary in runs:
			if second.take==2 and first.operation==second.operation and first.fps==second.fps and (first.trace!=second.trace or first.initial_pose_digest!=second.initial_pose_digest):failures.append("Fresh reset trace mismatch")
	var passed:=runs.size()==(54 if native_only else 18) and failures.is_empty() and logger.errors.is_empty()
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"runs":runs,"failures":failures,"engine_errors":logger.errors,"control":control,"manifest_sha256":FileAccess.get_sha256(manifest_path),"renderer_sha256":FileAccess.get_sha256(get_script().resource_path),"clip_helper_sha256":FileAccess.get_sha256(Clips.resource_path),"native_helper_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("saved_rig_media_native.gd")),"mode":"native" if native_only else "render","startup_admission":startup_admission,"framing_helper_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("saved_media_framing.gd")),"display_geometry":manifest.get("geometry",""),"viewport_sizes":{"physical_window":[root.size.x,root.size.y],"logical":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"texture":[root.get_texture().get_size().x,root.get_texture().get_size().y]},"visual_approval":false,"intended_frames":0 if native_only else 9*2*4*60}))
	OS.remove_logger(logger)
	print("SAVED_RIG_MEDIA="+JSON.stringify({"passed":passed,"runs":runs.size(),"failures":failures,"engine_errors":logger.errors}));quit(0 if passed else 1)
