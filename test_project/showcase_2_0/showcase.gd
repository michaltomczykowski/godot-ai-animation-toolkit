extends Control
## A browsable gallery of saved toolkit examples. --showcase-tour runs the film.

const DESIGN := Vector2(1280, 720)
const INK := Color("#111919")
const PANEL := Color("#1d2a2a")
const LINE := Color("#3a5150")
const LIGHT := Color("#f1f5eb")
const SOFT := Color("#a9bcba")
const MINT := Color("#a3f3cc")
const GOLD := Color("#f7c974")
const BASE := "res://showcase_2_0/"
const CHAPTERS := ["Presets + FX", "Motion", "Rigging", "Graphs", "Editing + library", "Inspection"]
const CHAPTER_SLIDES := [1, 6, 13, 17, 20, 24]
const SLIDES := [
	[0, -1, "Make a scene\nmove.", "Author motion, effects and reusable animation in Godot.", "10 families · 103 operations", ["walk"]],
	[8, 0, "Start with\na preset.", "Give a button a springy response, pulse a property or stagger a reveal.", "animation_presets", ["demo_bounce", "demo_pulse", "demo_stagger"]],
	[14, 0, "Build a\nmotion loop.", "Orbit, sweep and drift. Spin or float a prop with the same clip workflow.", "animation_presets", ["demo_orbit", "demo_sweep", "demo_drift", "demo_spin", "demo_float"]],
	[20, 0, "Animate\nthe interface.", "Type an objective, fill a progress bar and animate a counter in place.", "animation_fx", ["demo_fx_ui"]],
	[26, 0, "Add\ngame feel.", "Shake, flash, punch, follow a path or layer a spring response.", "animation_fx", ["demo_fx_feedback", "demo_fx_motion"]],
	[30, 0, "Play a\nsprite cue.", "Slice a sprite sheet, sequence frames and place a timed audio cue.", "animation_fx", ["sprite_cue"]],
	[34, 1, "Set the\ngait.", "Responsive is the default. Compare it with the Heavy style on the same rig.", "animation_motion · walk_cycle / cycle", ["walk", "heavy_walk"]],
	[38, 1, "Pick up\nthe pace.", "Walk and run are keyed skeletal clips with distinct support and flight phases.", "animation_motion · run_cycle", ["run"]],
	[42, 1, "Move\nsideways.", "Tune a strafe in place or extract its lateral travel.", "animation_motion · strafe_cycle", ["strafe"]],
	[45, 1, "Take off.\nLand.", "A one-shot with anticipation, flight and recovery.", "animation_motion · jump", ["jump"]],
	[48, 1, "Turn on\na beat.", "Pivot in place with a timed settle and contact markers.", "animation_motion · turn_cycle", ["turn"]],
	[51, 1, "Start\nand stop.", "Match a walk cycle at its phase boundary and carry the actor into the next clip.", "animation_motion · walk_start / walk_stop", ["start", "stop"]],
	[55, 1, "Compose\na take.", "Schedule idle, start, walk and stop as one playable clip, with timed blends.", "animation_sequence · compose", ["sequence"]],
	[61, 2, "Pose the\nperformer.", "Build keyed recipes on a Skeleton3D and save motions as ordinary clips.", "animation_rig", ["jumping_jack", "squat", "punch"]],
	[67, 2, "Reach for\na target.", "Attach a two-bone IK chain and move its target through a controlled arc.", "animation_rig_modifiers · ik_setup", ["ik"]],
	[73, 2, "Follow\nthe cue.", "Steer a head bone with a LookAtModifier3D. The target moves inside the scene.", "animation_rig_modifiers · look_at_setup", ["look"]],
	[78, 2, "Let it\nsettle.", "Drive the robot's aerial with a spring chain. Bake a rig's motion when you need a keyed clip.", "animation_rig_modifiers · spring_setup", ["spring"]],
	[83, 3, "Change\nstates.", "Wire idle, walk and run states and observe the active branch as conditions change.", "animation_graph · state_machine", ["demo_graph_states"]],
	[90, 3, "Blend\nand layer.", "Sweep between clips in a blend space and trigger a one-shot over that base.", "animation_graph · blend_space / one_shot_layer", ["demo_graph_blend"]],
	[97, 3, "Set up\nlocomotion.", "Generate the clips and a locomotion tree. Feed its blend input from gameplay.", "animation_motion · character_setup", ["graph"]],
	[103, 4, "Edit\nwith intent.", "Before and after, side by side. Retiming changes when the keys arrive.", "animation_edit · retime", ["demo_edit_retime"]],
	[109, 4, "Reframe\na clip.", "Reverse, trim or mirror the motion while preserving editable tracks.", "animation_edit", ["demo_edit_reverse", "demo_edit_trim", "demo_edit_mirror"]],
	[115, 4, "Reuse\nyour work.", "Save a template and apply it to another target, or round-trip a portable clip spec.", "animation_library", ["demo_lib_template", "demo_lib_spec"]],
	[120, 4, "Tune\nthe details.", "Edit a key or scale the strength of the motion against the original.", "animation_edit · key_edit / amplitude", ["demo_edit_keyedit", "demo_edit_amplitude"]],
	[124, 5, "Inspect\nthe result.", "Check tracks, key counts and whether their node paths still resolve.", "animation_inspect · timeline / describe", ["timeline"]],
	[132, 5, "Catch\na bad path.", "Audit unresolved tracks, loop seams and other clip issues before handing off a scene.", "animation_inspect · audit", ["demo_inspect_audit"]],
	[138, 5, "See the\nplayed pose.", "Render frames from the saved clip before they leave the editor.", "animation_inspect · preview", ["preview"]],
	[144, -1, "Open it.\nMake it yours.", "Install the toolkit, run the examples and give your Godot AI agent the guide.", "Godot AI Animation Toolkit 2.0.0", ["idle"]],
]

var _canvas: Control
var _stage: Control
var _chapter_buttons: Array[Button] = []
var _heading: Label
var _copy: Label
var _family: Label
var _counter: Label
var _progress: ColorRect
var _auto: Button
var _slide := -1
var _clock := 0.0
var _cue_clock := 0.0
var _tour := false
var _worlds: Array[Dictionary] = []
var _problems: Array[String] = []


func _ready() -> void:
	_canvas = Control.new()
	add_child(_canvas)
	_rect(_canvas, Vector2.ZERO, DESIGN, INK)
	_label(_canvas, "GODOT AI  /  ANIMATION TOOLKIT 2.0", Vector2(44, 25), Vector2(815, 25), 17, MINT)
	_counter = _label(_canvas, "", Vector2(960, 25), Vector2(276, 25), 17, SOFT)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var x := 44.0
	for index in CHAPTERS.size():
		var chapter: int = CHAPTER_SLIDES[index]
		var chapter_button := _button(CHAPTERS[index], Vector2(x, 68), Vector2(193, 38),
			func() -> void: _select(chapter))
		_chapter_buttons.append(chapter_button)
		x += 200
	_rect(_canvas, Vector2(44, 125), Vector2(1192, 1), LINE)
	_heading = _label(_canvas, "", Vector2(44, 193), Vector2(364, 162), 55, LIGHT)
	_copy = _label(_canvas, "", Vector2(46, 375), Vector2(340, 118), 23, SOFT)
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_family = _label(_canvas, "", Vector2(46, 529), Vector2(350, 62), 17, MINT)
	_family.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage = Control.new()
	_stage.position = Vector2(424, 151)
	_stage.size = Vector2(812, 464)
	_canvas.add_child(_stage)
	_rect(_canvas, Vector2(44, 637), Vector2(1192, 1), LINE)
	_progress = _rect(_canvas, Vector2(44, 637), Vector2(0, 2), MINT)
	_button("‹ Previous", Vector2(44, 656), Vector2(122, 36), func() -> void: _select(_slide - 1))
	_button("Replay", Vector2(177, 656), Vector2(97, 36), _replay)
	_button("Next ›", Vector2(284, 656), Vector2(97, 36), func() -> void: _select(_slide + 1))
	_auto = _button("Play full tour", Vector2(1094, 656), Vector2(142, 36), _toggle_tour)
	resized.connect(_fit)
	_fit()
	_show(0)
	if "--showcase-tour" in OS.get_cmdline_user_args():
		_toggle_tour()
	if "--showcase-check" in OS.get_cmdline_user_args():
		_check_all.call_deferred()


func _fit() -> void:
	var ratio := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_canvas.scale = Vector2.ONE * ratio
	_canvas.position = (size - DESIGN * ratio) * 0.5


func _process(delta: float) -> void:
	_cue_clock += delta
	if _tour:
		_clock += delta
		if _slide + 1 < SLIDES.size() and _clock >= float(SLIDES[_slide + 1][0]):
			_show(_slide + 1)
		_progress.size.x = 1192.0 * clampf(_clock / 150.0, 0.0, 1.0)
		if _clock >= 150.0:
			_tour = false
			_auto.text = "Play full tour"
	for world in _worlds:
		_step_world(world)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_select(_slide + 1)
	elif event.is_action_pressed("ui_left"):
		_select(_slide - 1)
	elif event.is_action_pressed("ui_accept"):
		_replay()


func _toggle_tour() -> void:
	_tour = not _tour
	_auto.text = "Pause tour" if _tour else "Play full tour"
	if _tour:
		_clock = 0.0
		_slide = -1
		_show(0)


func _select(index: int) -> void:
	_tour = false
	_auto.text = "Play full tour"
	_show(wrapi(index, 0, SLIDES.size()))
	_progress.size.x = 1192.0 * float(SLIDES[_slide][0]) / 150.0


func _replay() -> void:
	var index := _slide
	_slide = -1
	_show(index)
	_clock = float(SLIDES[index][0])


func _show(index: int) -> void:
	if index == _slide:
		return
	_slide = index
	_cue_clock = 0.0
	_worlds.clear()
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	var slide: Array = SLIDES[index]
	var chapter: int = slide[1]
	for i in _chapter_buttons.size():
		_chapter_buttons[i].add_theme_stylebox_override("normal", _style(MINT if i == chapter else PANEL))
		_chapter_buttons[i].add_theme_color_override("font_color", INK if i == chapter else SOFT)
	_heading.text = slide[2]
	_copy.text = slide[3]
	_family.text = slide[4]
	_counter.text = CHAPTERS[chapter].to_upper() if chapter >= 0 else "SHOWCASE"
	var entries: Array = slide[5]
	if entries[0] == "timeline":
		_inspector()
	elif entries[0] == "preview":
		_frames()
	else:
		_tiles(entries)


func _tiles(entries: Array) -> void:
	var columns := 3 if entries.size() > 3 else entries.size()
	var rows := ceili(float(entries.size()) / columns)
	var cell := (_stage.size - Vector2(12 * (columns - 1), 12 * (rows - 1))) / Vector2(columns, rows)
	for i in entries.size():
		var at := Vector2(i % columns, floori(float(i) / columns)) * (cell + Vector2(12, 12))
		var tile := _rect(_stage, at, cell, PANEL)
		var key: String = entries[i]
		var title := key.trim_prefix("demo_").replace("_", " ").to_upper()
		var stage_size := cell - Vector2(2, 30)
		var host := SubViewportContainer.new()
		host.position = Vector2(1, 28)
		host.size = stage_size
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(host)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(stage_size)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.own_world_3d = true
		host.add_child(viewport)
		if key.begins_with("demo_") or key == "sprite_cue":
			_demo(viewport, key)
		else:
			_robot(viewport, key)
		_label(tile, title, Vector2(12, 3), Vector2(cell.x - 22, 23), 14, LIGHT)


func _demo(viewport: SubViewport, key: String) -> void:
	var path := BASE + "sprite_cue.tscn" if key == "sprite_cue" else ("res://%s.tscn" % key)
	var scene := load(path) as PackedScene
	if scene == null:
		_problem("Could not open showcase scene: " + key)
		return
	viewport.transparent_bg = true
	var demo := scene.instantiate()
	viewport.add_child(demo)
	for camera in demo.find_children("*", "Camera2D", true, false):
		(camera as Camera2D).enabled = false
	var frame := Rect2(0, 0, 1152, 648)
	match key:
		"demo_bounce":
			frame = Rect2(327, 214, 510, 220)
			for button in demo.find_children("*", "Button", true, false):
				button.add_theme_stylebox_override("normal", _style(MINT))
				button.add_theme_color_override("font_color", INK)
		"demo_pulse":
			frame = Rect2(299, 205, 540, 235)
		"demo_stagger":
			frame = Rect2(15, 245, 1120, 160)
		"demo_orbit", "demo_sweep":
			frame = Rect2(270, 18, 612, 612)
		"demo_drift":
			frame = Rect2(98, 240, 975, 163)
	var dimensions := Vector2(viewport.size)
	var scale_factor := minf(dimensions.x / frame.size.x, dimensions.y / frame.size.y)
	viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_factor, 0.0,
		(dimensions - frame.size * scale_factor) * 0.5 - frame.position * scale_factor)


func _robot(viewport: SubViewport, key: String) -> void:
	var rig_demo := key in ["jumping_jack", "squat", "punch", "ik", "look", "spring"]
	var file := "robot_graph.tscn" if key == "graph" else ("robot_rig.tscn" if rig_demo else "robot_motion.tscn")
	var scene := load(BASE + file) as PackedScene
	if scene == null:
		_problem("Could not open showcase rig: " + file)
		return
	var stage := Node3D.new()
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#243736")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#d0e5da")
	env.environment.ambient_light_energy = 0.53
	stage.add_child(env)
	var performer := scene.instantiate() as Node3D
	stage.add_child(performer)
	_block(stage, Vector3(0, -0.067, 0), Vector3(26, 0.13, 26), Color("#344b47"))
	for n in range(-12, 13):
		_block(stage, Vector3(n, 0.002, 0), Vector3(0.009, 0.005, 26), Color("#425d57"))
		_block(stage, Vector3(0, 0.002, n), Vector3(26, 0.005, 0.009), Color("#425d57"))
	for z in range(-10, 11):
		_block(stage, Vector3(-0.8, 0.008, z), Vector3(0.04, 0.006, 0.25), MINT)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38, -31, 0)
	key_light.light_energy = 1.15
	key_light.light_color = Color("#fff2d7")
	key_light.shadow_enabled = true
	stage.add_child(key_light)
	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees = Vector3(-22, 138, 0)
	bounce.light_energy = 0.58
	bounce.light_color = Color("#aefbd0")
	stage.add_child(bounce)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.54
	stage.add_child(camera)
	camera.make_current()
	var player := performer.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := performer.get_node("Robot/Skeleton3D") as Skeleton3D
	var state := {"camera": camera, "actor": performer.get_node("Robot"), "player": player, "key": key}
	var choice := key
	if key in ["ik", "look", "spring"]:
		var modifier_name: String = {"ik": "ReachIK", "look": "HeadLook", "spring": "AerialSpring"}[key]
		var modifier := skeleton.get_node_or_null(NodePath(modifier_name)) as SkeletonModifier3D
		if modifier != null:
			modifier.active = true
		choice = "punch" if key == "spring" else "idle_breathing"
		var marker_name := "ReachTarget" if key == "ik" else "LookTarget"
		var target := performer.get_node_or_null(NodePath(marker_name)) as Node3D
		if key != "spring" and target != null:
			state["marker"] = target
			state["origin"] = target.position
			_block(target, Vector3.ZERO, Vector3.ONE * 0.064, GOLD)
	if key == "graph":
		var tree := performer.get_node("AnimationTree") as AnimationTree
		tree.active = true
		state["tree"] = tree
		for entry in tree.get_property_list():
			var path := String(entry.name)
			if path.begins_with("parameters/") and path.ends_with("/blend_position"):
				state["blend"] = path
				break
		if tree.tree_root is AnimationNodeStateMachine:
			var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
			var graph := tree.tree_root as AnimationNodeStateMachine
			if playback != null and graph.has_node("locomotion"):
				playback.start("locomotion")
	elif player.has_animation(choice):
		state["speed"] = 1.75 if key == "sequence" and _tour else 1.0
		player.play(choice, -1.0, state.speed)
		state["clip"] = choice
	else:
		_problem("Showcase clip is missing: %s" % choice)
	_worlds.append(state)
	_step_world(state)


func _step_world(world: Dictionary) -> void:
	var player := world.player as AnimationPlayer
	if world.has("clip") and not player.is_playing():
		player.play(world.clip, -1.0, world.speed)
	var center: Vector3 = (world.actor as Node3D).global_position + Vector3(0, 0.98, 0)
	var camera := world.camera as Camera3D
	var angle := 0.56 if world.key not in ["run", "strafe", "spring"] else 0.87
	camera.position = center + Vector3(sin(angle) * 4.2, 1.05, cos(angle) * 4.2)
	camera.look_at(center)
	if world.has("marker"):
		var origin: Vector3 = world.origin
		var marker := world.marker as Node3D
		if world.key == "ik":
			marker.position = origin + Vector3(-0.05, sin(_cue_clock * 2.5) * 0.12 + 0.15, 0.16)
		else:
			marker.position = Vector3(sin(_cue_clock * 2.0) * 0.58, 1.73, 1.8)
	if world.has("blend"):
		var tree := world.tree as AnimationTree
		tree.set(world.blend, (1.0 - cos(_cue_clock * 1.55)) * 1.3)
		var actor := world.actor as Node3D
		actor.position += tree.get_root_motion_position()


func _inspector() -> void:
	_rect(_stage, Vector2.ZERO, _stage.size, PANEL)
	_label(_stage, "KITE  /  WALK", Vector2(32, 27), Vector2(730, 34), 25, MINT)
	_label(_stage, "Timeline of the saved Responsive walk clip", Vector2(32, 70), Vector2(730, 34), 21, LIGHT)
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE + "inspection.json"))
	if not evidence is Dictionary or evidence.get("tracks", []).is_empty():
		_problem("Saved showcase inspection is missing")
		return
	var tracks: Array = evidence.get("tracks", [])
	_label(_stage, "%s s   •   %s tracks" % [evidence.get("duration", "—"), evidence.get("track_count", "—")],
		Vector2(32, 125), Vector2(730, 29), 20, GOLD)
	_label(_stage, "TRACK", Vector2(32, 176), Vector2(386, 22), 15, SOFT)
	_label(_stage, "SAVED KEYS", Vector2(576, 176), Vector2(208, 22), 15, SOFT)
	for i in mini(tracks.size(), 7):
		var y := 210.0 + i * 31
		_rect(_stage, Vector2(32, y - 1), Vector2(744, 1), LINE)
		_label(_stage, str(tracks[i].path), Vector2(32, y + 2), Vector2(510, 26), 18, LIGHT)
		_label(_stage, str(tracks[i].keys), Vector2(576, y + 2), Vector2(198, 26), 18, MINT)


func _frames() -> void:
	_rect(_stage, Vector2.ZERO, _stage.size, PANEL)
	_label(_stage, "RENDERED INSPECTION  /  WALK", Vector2(23, 15), Vector2(760, 30), 19, MINT)
	for i in 4:
		var texture := load(BASE + "preview/walk_%02d.png" % i) as Texture2D
		if texture == null:
			_problem("Showcase preview frame %d is missing" % i)
			continue
		var frame := TextureRect.new()
		frame.texture = texture
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.position = Vector2(24 + 394 * (i % 2), 47 + 199 * floori(float(i) / 2))
		frame.size = Vector2(370, 185)
		_stage.add_child(frame)


func _block(parent: Node3D, location: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.9
	mesh.material = paint
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = location
	parent.add_child(instance)


func _rect(parent: Node, at: Vector2, dimensions: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = dimensions
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(parent: Node, words: String, at: Vector2, dimensions: Vector2, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.text = words
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _style(color: Color) -> StyleBoxFlat:
	var face := StyleBoxFlat.new()
	face.bg_color = color
	face.set_corner_radius_all(5)
	face.set_border_width_all(1)
	face.border_color = LINE
	return face


func _button(words: String, at: Vector2, dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_stylebox_override("normal", _style(PANEL))
	button.add_theme_stylebox_override("hover", _style(LINE))
	button.add_theme_stylebox_override("pressed", _style(PANEL))
	button.add_theme_color_override("font_color", LIGHT)
	button.add_theme_color_override("font_hover_color", LIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	_canvas.add_child(button)
	return button


func _problem(message: String) -> void:
	_problems.append(message)
	push_error(message)


func _check_all() -> void:
	for i in _chapter_buttons.size():
		_chapter_buttons[i].pressed.emit()
		if _slide != CHAPTER_SLIDES[i] or SLIDES[_slide][1] != i:
			_problem("Chapter button targets the wrong example")
		_replay()
		if _cue_clock != 0.0:
			_problem("Replay did not reset the current example")
	for index in SLIDES.size():
		_select(index)
		await get_tree().process_frame
	print("SHOWCASE_CHECK slides=%d problems=%s" % [SLIDES.size(), _problems])
	get_tree().quit(0 if _problems.is_empty() else 1)
