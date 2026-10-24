extends SceneTree
const Framing := preload("saved_media_framing.gd")
const Native := preload("saved_graph_media_native.gd")
class Errors extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _trace: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
class Board extends Node2D:
	func _draw() -> void:
		for x in range(-300, 701, 25): draw_line(Vector2(x,-160),Vector2(x,120),Color(0.14,0.19,0.24),0.5)
		for y in range(-150, 121, 25): draw_line(Vector2(-300,y),Vector2(700,y),Color(0.14,0.19,0.24),0.5)
		draw_line(Vector2(-300,0),Vector2(700,0),Color(0.6,0.7,0.8),1)
		draw_line(Vector2.ZERO,Vector2(200,0),Color(0.7,0.3,0.2),2)
		draw_rect(Rect2(-18,-70,36,70),Color(0.6,0.6,0.6,0.5),false,1)
var logger := Errors.new()
var manifest: Dictionary
var manifest_path := ""
var report_path := ""
var runs: Array = []
var failures: Array[String] = []
var view: Dictionary = {}
var current: Dictionary = {}
var index := 0
var take := 0
var frame := 0
var fps := 60
var native_only := false
var control := ""
var rendering := false
var startup_admission := {}
var title: Label
var details: Label

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	OS.add_logger(logger)
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	manifest_path=args[0]; report_path=args[1]
	if FileAccess.file_exists(report_path):
		printerr("Preserve previous graph evidence")
		quit(1)
		return
	manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	native_only=args.size()>2 and args[2]=="native"
	control=args[3] if args.size()>3 else ""
	if control not in ["","no_effect","competing_player"] or (not control.is_empty() and not native_only):
		failures.append("Invalid checker control");_finish();return
	if not _valid_manifest():
		_finish()
		return
	if native_only:
		for rate in [30,60,120]:
			fps=rate
			for row: Dictionary in manifest.cases:
				for repetition in 2:
					_start(row,repetition)
					if view.has("error"):
						failures.append(str(view.error))
						continue
					for tick in 2*fps+1: _step(tick)
					_end()
		_finish()
	else:
		fps=60
		startup_admission=Framing.startup()
		if not startup_admission.passed:failures.append("Require1920x1080viewportstretch before MovieMaker startup");_finish();return
		_setup_display()
		_start(manifest.cases[0],0)
		rendering=not view.has("error")
		if not rendering:
			failures.append(str(view.error));_finish()

func _valid_manifest() -> bool:
	var ops: Array = []
	for row: Dictionary in manifest.get("cases",[]):
		ops.append(str(row.get("operation","")))
		var schedule: Array = row.get("schedule",[])
		if schedule.size()!=7: failures.append("Incomplete control schedule")
		else:
			for i in 7:
				if float(schedule[i].time_s)!=[0.0,0.5,1.0,1.1,1.2,1.5,2.0][i] or str(schedule[i].command)!=["neutral","effect","check_effect","faster","check_faster","neutral","check_reset"][i]: failures.append("Unsupported control schedule")
	ops.sort()
	if ops != ["additive_lean","blend_space","blend_tree","locomotion","one_shot_layer","state_machine","wire"]: failures.append("Require all seven distinct graph producing operations")
	if int(manifest.get("fps",0))!=60 or int(manifest.get("takes",0))!=2 or float(manifest.get("take_duration_s",0))!=2.0: failures.append("Unsupported capture clock")
	return failures.is_empty()

func _start(row: Dictionary, repetition: int) -> void:
	view=Native.load_case(row,root)
	current={"operation":row.operation,"take":repetition+1,"fps":fps,"scene_sha256":row.scene_sha256,"trace":[],"failures":[],"walk_x":0.0,"walk_speed":0.0,"run_speed":0.0,"max_effect_x":0.0}
	if view.has("error"):return
	if Native.neutral_error(view)>0.01: current.failures.append("Initial baseline is not neutral")
	if not native_only:
		var marker := Polygon2D.new()
		marker.name="DisplayOnlyTargetMarker"
		marker.polygon=PackedVector2Array([Vector2(-18,0),Vector2(-18,-70),Vector2(10,-70),Vector2(30,-50),Vector2(10,-30),Vector2(18,0)])
		marker.color=Color(0.15,0.75,0.95)
		view.target.add_child(marker)
		view["display_marker"]=marker

func _step(tick: int) -> void:
	var time := float(tick)/fps
	if control=="competing_player":view.player.active=true
	if tick>0 and not (control=="no_effect" and str(view.row.operation)=="state_machine"):view.tree.advance(1.0/fps)
	for event: Dictionary in view.row.schedule:
		if tick!=roundi(float(event.time_s)*fps):continue
		var action := str(event.command)
		if action=="check_effect":
			var op := str(view.row.operation)
			current.walk_x=view.target.position.x
			if op in ["state_machine","blend_space","blend_tree","locomotion"] and float(current.max_effect_x)<20.0:current.failures.append("Saved graph did not produce walk")
			if op=="state_machine" and str((view.tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).get_current_node())!="walk":current.failures.append("State machine did not travel to walk")
			if op=="one_shot_layer" and view.target.position.y > -20.0:current.failures.append("Saved OneShot did not produce jump")
			if op=="additive_lean" and view.target.rotation<0.05:current.failures.append("Saved additive graph did not produce lean")
			if op=="wire" and Native.neutral_error(view)>0.01:current.failures.append("Wired idle graph moved unexpectedly")
		elif action=="check_faster":
			if str(view.row.operation) in ["blend_space","locomotion"] and (absf(float(current.walk_speed)-100.0)>0.01 or absf(float(current.run_speed)-200.0)>0.01):current.failures.append("Run control did not produce faster saved output")
		elif action=="check_reset":
			if str(view.row.operation)=="state_machine":
				# This saved graph automatically advances idle->walk. Its native
				# transition clock may continue after stop(); reset is a fresh instance.
				current["reset_policy"]="fresh saved instance; automatic transitions may continue despite playback stop flag"
			elif Native.neutral_error(view)>0.01:current.failures.append("Native controls did not recover neutral baseline")
		else:
			var error := "" if control=="no_effect" and action in ["effect","faster"] else Native.command(view,action)
			if not error.is_empty():current.failures.append(error)
	if time>0.5 and time<=1.0:
		current.max_effect_x=maxf(float(current.max_effect_x),view.target.position.x)
	if current.trace.size()>0:
		var previous: Dictionary=current.trace[-1]
		var velocity: float=(view.target.position.x-float(previous.position[0]))*fps
		# Ignore negative loop-wrap displacement; measure actual positive native
		# segment velocity in the walk/run windows instead of a phase endpoint.
		if time>0.6 and time<1.0:current.walk_speed=maxf(float(current.walk_speed),velocity)
		if time>1.1+1.5/fps and time<=1.2:current.run_speed=maxf(float(current.run_speed),velocity)
	var sample := Native.sample(view,time)
	if not sample.ownership and not current.failures.has("Competing graph/player ownership"):current.failures.append("Competing graph/player ownership")
	if not view.target.position.is_finite() or not is_finite(view.target.rotation):current.failures.append("Nonfinite native effect")
	if not native_only:
		sample["movie_frame"]=tick<2*fps
		sample["framing"]=Framing.graph(view.display_marker)
		if not sample.framing.fits:current.failures.append("Projected graph geometry leaves body/header guard")
	current.trace.append(sample)
	if not native_only:
		title.text="SAVED GRAPH | %s | TAKE %d/2 | %.3fs" % [view.row.operation,take+1,time]
		details.text="Tree only | x %.3f  y %.3f  rotation %.4f rad | %s\nFixed camera/grid | Cyan polygon is display-only geometry on the invisible saved target\n%s" % [view.target.position.x,view.target.position.y,view.target.rotation,"native automatic transition; reset by fresh instance" if str(view.row.operation)=="state_machine" else ("neutral" if time<0.5 or time>=1.5 else "native control effect"), "WIRE: saved idle binding/neutral hold; wire does not author movement" if str(view.row.operation)=="wire" else "Original saved clips and graph; no generated animation or target poses"]

func _end() -> void:
	if Native.clip_digest(view.player)!=view.clips:current.failures.append("Saved clip data changed")
	if FileAccess.get_sha256(view.row.scene)!=view.row.scene_sha256:current.failures.append("Saved scene changed")
	current.passed=current.failures.is_empty()
	runs.append(current)
	if not current.passed:failures.append("%s/%s/%s: %s" % [current.operation,current.fps,current.take,str(current.failures)])
	view.scene.free()
	view={}

func _process(_delta: float) -> bool:
	if not rendering:return false
	var texture_size:Vector2i=root.get_texture().get_size()
	var logical_size:Vector2i=Vector2i(root.get_visible_rect().size)
	if texture_size!=Vector2i(1920,1080) or logical_size!=Vector2i(1920,1080):
		failures.append("Incorrect logical render target: texture=%s visible=%s physical=%s"%[texture_size,logical_size,root.size])
		rendering=false;_finish();return false
	if frame==2*fps:
		# Last take frame has already rendered. Check the exact end boundary,
		# then replace the instance before the next take's first movie frame.
		_step(2*fps)
		_end()
		frame=0;take+=1
		if take==2:take=0;index+=1
		if index==manifest.cases.size():
			rendering=false;_finish();return false
		_start(manifest.cases[index],take)
		if view.has("error"):
			failures.append(str(view.error));rendering=false;_finish();return false
	_step(frame)
	frame+=1
	if index==manifest.cases.size()-1 and take==1 and frame==2*fps:
		# Keep the last accepted target alive through its draw. Quitting from
		# next _process would write an extra frame after _end frees the target.
		rendering=false
		RenderingServer.frame_post_draw.connect(_finish_after_last_draw,CONNECT_ONE_SHOT)
		# SceneTree must observe quit during process; post-draw alone is too
		# late for this iteration and would permit another MovieMaker frame.
		quit(0)
	return false

func _finish_after_last_draw() -> void:
	_step(2*fps)
	_end()
	_finish()

func _setup_display() -> void:
	root.size=Vector2i(1920,1080)
	root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	var board:=Board.new();root.add_child(board)
	var camera:=Camera2D.new();camera.position=Vector2(100,-40);camera.zoom=Vector2(3,3);root.add_child(camera);camera.make_current()
	var layer:=CanvasLayer.new();root.add_child(layer)
	title=Label.new();title.position=Vector2(30,25);title.add_theme_font_size_override("font_size",34);layer.add_child(title)
	details=Label.new();details.position=Vector2(30,900);details.add_theme_font_size_override("font_size",25);layer.add_child(details)

func _finish() -> void:
	# Fresh reloads must repeat the same native trace, not inherit the prior take.
	for first: Dictionary in runs:
		if first.take!=1:continue
		for second: Dictionary in runs:
			if second.take==2 and second.operation==first.operation and second.fps==first.fps and second.trace!=first.trace:
				failures.append("Fresh reset takes differ: "+str(first.operation))
	var expected:=42 if native_only else 14
	var passed:=runs.size()==expected and failures.is_empty() and logger.errors.is_empty()
	var report:={"passed":passed,"control":control,"mode":"native" if native_only else "render","runs":runs,"failures":failures,"engine_errors":logger.errors,
		"manifest_sha256":FileAccess.get_sha256(manifest_path),"renderer_sha256":FileAccess.get_sha256(get_script().resource_path),
		"startup_admission":startup_admission,"framing_helper_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("saved_media_framing.gd")),
		"native_helper_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("saved_graph_media_native.gd")),
		"frames":0 if native_only else 7*2*2*60,"fixed_camera":{"position":[100,-40],"zoom":[3,3]},"reset_policy":"Each take instantiates the original hashed scene anew; state-machine saved automatic transition continues; no neutral tail is claimed.","viewport_sizes":{"physical_window":[root.size.x,root.size.y],"logical":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"texture":[root.get_texture().get_size().x,root.get_texture().get_size().y]},"visual_approval":false,"display_geometry":manifest.get("display_geometry","")}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("SAVED_GRAPH_MEDIA="+JSON.stringify({"passed":passed,"runs":runs.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if passed else 1)
