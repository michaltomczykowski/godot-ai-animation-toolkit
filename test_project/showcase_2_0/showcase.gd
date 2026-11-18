extends Control
## Player and Movie Maker entry point for the 2.0 showcase.

const BASE := "res://showcase_2_0/"
const DESIGN := Vector2(1280, 720)
const INK := Color("#10171f")
const PANEL := Color("#1c2933")
const LINE := Color("#3c5159")
const PAPER := Color("#f3f8ef")
const SOFT := Color("#b5c5c6")
const MINT := Color("#a8f1ce")
const GOLD := Color("#f9c676")

var _cues: Array = []
var _chapters: Array = []
var _duration := 0.0
var _canvas: Control
var _stage: Control
var _frame: Rect2
var _progress: ColorRect
var _tour_button: Button
var _chapter_buttons: Array[Button] = []
var _worlds: Array[Dictionary] = []
var _scene: Node
var _repeat_fade: ColorRect
var _problems: Array[String] = []
var _film := false
var _tour := false
var _index := -1
var _time := 0.0
var _phase := 0.0
const REPEAT_ONE_SHOT_AT := 2.25


func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE + "tour.json"))
	if not data is Dictionary or data.get("cues", []).is_empty():
		push_error("Missing showcase timeline")
		get_tree().quit(1)
		return
	_cues = data.cues
	_chapters = data.chapters
	_duration = float(data.duration)
	_remove_identical_takes()
	var args := OS.get_cmdline_user_args()
	_film = "--showcase-tour" in args
	_tour = _film
	for arg in args:
		if arg.begins_with("--showcase-from="):
			_time = clampf(float(arg.get_slice("=", 1)), 0.0, _duration - 0.001)
	_canvas = Control.new()
	_canvas.size = DESIGN
	add_child(_canvas)
	_rect(_canvas, Rect2(Vector2.ZERO, DESIGN), INK)
	_frame = Rect2(Vector2.ZERO, DESIGN) if _film else Rect2(16, 63, 1248, 596)
	_stage = Control.new()
	_stage.position = _frame.position
	_stage.size = _frame.size
	_stage.clip_contents = true
	_canvas.add_child(_stage)
	if not _film:
		_make_controls()
	resized.connect(_fit)
	_fit()
	var start := 0
	while start + 1 < _cues.size() and float(_cues[start + 1].at) <= _time:
		start += 1
	_show(start, _film)
	if "--showcase-check" in args:
		_check_all.call_deferred()


func _remove_identical_takes() -> void:
	var seen := {}
	var actors := {}
	for cue in _cues:
		var takes: Array = cue.get("actors", [])
		var unique: Array = []
		for take in takes:
			if not take.has("dedupe_group"):
				unique.append(take)
				continue
			var group: String = take.dedupe_group
			var path: String = take.scene
			if not actors.has(path):
				var packed := load(path) as PackedScene
				actors[path] = packed.instantiate() if packed != null else null
			var instance := actors[path] as Node
			var player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer if instance != null else null
			if player == null or not player.has_animation(take.clip):
				unique.append(take)
				continue
			var digest := _fingerprint(player.get_animation(take.clip))
			if not seen.has(group):
				seen[group] = {}
			if not seen[group].has(digest):
				seen[group][digest] = true
				unique.append(take)
		if not takes.is_empty():
			cue.actors = unique
	for instance: Node in actors.values():
		if instance != null:
			instance.free()
	for index in range(_cues.size() - 1, -1, -1):
		if _cues[index].kind == "actors" and _cues[index].actors.is_empty():
			_cues.remove_at(index)


func _fingerprint(clip: Animation) -> String:
	var values: Array = [clip.length, clip.loop_mode]
	for track in clip.get_track_count():
		values.append([clip.track_get_path(track), clip.track_get_type(track),
			clip.track_get_interpolation_type(track), clip.track_get_interpolation_loop_wrap(track)])
		for key in clip.track_get_key_count(track):
			values.append([clip.track_get_key_time(track, key), clip.track_get_key_value(track, key),
				clip.track_get_key_transition(track, key)])
	for marker in clip.get_marker_names():
		values.append([marker, clip.get_marker_time(marker)])
	return var_to_bytes(values).hex_encode().sha256_text()


func _fit() -> void:
	var ratio := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_canvas.scale = Vector2.ONE * ratio
	_canvas.position = (size - DESIGN * ratio) * 0.5


func _make_controls() -> void:
	var width := 1248.0 / _chapters.size()
	for i in _chapters.size():
		var chapter: Dictionary = _chapters[i]
		var button := _button(chapter.label, Rect2(16 + i * width, 10, width - 6, 40),
			_jump_to_chapter.bind(i))
		_chapter_buttons.append(button)
	_button("Previous", Rect2(16, 672, 123, 34), _move.bind(-1))
	_button("Replay", Rect2(147, 672, 100, 34), _replay)
	_button("Next", Rect2(255, 672, 96, 34), _move.bind(1))
	_tour_button = _button("Play tour", Rect2(1108, 672, 156, 34), _toggle_tour)
	_rect(_canvas, Rect2(365, 687, 727, 4), LINE)
	_progress = _rect(_canvas, Rect2(365, 687, 0, 4), MINT)


func _process(delta: float) -> void:
	_phase += delta
	if _tour:
		_time += delta
		while _index + 1 < _cues.size() and _time + 0.000001 >= float(_cues[_index + 1].at):
			_show(_index + 1, true)
		if _time + 0.000001 >= _duration:
			_stop_tour()
	if _progress != null:
		_progress.size.x = clampf(_time / _duration, 0.0, 1.0) * 727.0
	if _repeat_fade != null:
		var opacity := maxf(0.0, 1.0 - absf(_phase - REPEAT_ONE_SHOT_AT) / 0.14)
		_repeat_fade.color.a = opacity
	for world in _worlds:
		_step_world(world)


func _jump_to_chapter(chapter: int) -> void:
	for i in _cues.size():
		if int(_cues[i].chapter) == chapter:
			_select(i)
			return


func _move(step: int) -> void:
	_select(wrapi(_index + step, 0, _cues.size()))


func _replay() -> void:
	_stop_tour()
	_time = float(_cues[_index].at)
	_show(_index, true)


func _select(index: int) -> void:
	_stop_tour()
	_time = float(_cues[index].at)
	_show(index, false)


func _toggle_tour() -> void:
	if _tour:
		_stop_tour()
	else:
		_tour = true
		_time = 0.0
		_tour_button.text = "Stop tour"
		_show(0, true)


func _stop_tour() -> void:
	_tour = false
	if _tour_button != null:
		_tour_button.text = "Play tour"


func _show(index: int, play_scene: bool) -> void:
	_index = index
	_phase = 0.0
	_worlds.clear()
	_scene = null
	_repeat_fade = null
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()
	var cue: Dictionary = _cues[index]
	for i in _chapter_buttons.size():
		var active := int(cue.chapter) == i
		_chapter_buttons[i].add_theme_stylebox_override("normal", _style(MINT if active else PANEL))
		_chapter_buttons[i].add_theme_color_override("font_color", INK if active else PAPER)
	match str(cue.kind):
		"actors":
			_show_actors(cue.actors)
		"scene":
			_show_scene(cue, play_scene)
		"closing":
			_show_harbor()
		"inspection":
			_show_inspection()
		_:
			_problem("Unknown cue kind: " + str(cue.kind))
	if cue.kind == "closing":
		_closing_caption(cue)
	elif not cue.get("canvas", false):
		_caption(cue)


func _caption(cue: Dictionary) -> void:
	var height := 94.0 if _film else 77.0
	var y := _frame.size.y - height
	_rect(_stage, Rect2(0, y, _frame.size.x, height), INK)
	_rect(_stage, Rect2(24, y + 12, 4, height - 24), MINT)
	var title_size := 36 if _film else 28
	_label(_stage, cue.title, Rect2(44, y + 4, _frame.size.x - 250, 48), title_size, PAPER)
	_label(_stage, cue.detail, Rect2(46, y + height - 32, _frame.size.x - 110, 26), 22, SOFT)
	var chapter: Dictionary = _chapters[int(cue.chapter)]
	var chip := _label(_stage, str(chapter.label).to_upper(),
		Rect2(_frame.size.x - 326, y + 12, 298, 34), 17, MINT)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _show_harbor() -> void:
	for name in ["harbor_distant.jpg", "harbor_foreground.png"]:
		var asset := load(BASE + "stages_2d/art/" + name) as Texture2D
		if asset == null:
			_problem("Missing harbor artwork " + name)
			continue
		var plate := TextureRect.new()
		plate.texture = asset
		plate.size = _frame.size
		plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(plate)


func _closing_caption(cue: Dictionary) -> void:
	_rect(_stage, Rect2(Vector2.ZERO, _frame.size), Color(0.03, 0.06, 0.12, 0.70))
	var middle := _frame.size.y * 0.43
	var title := _label(_stage, cue.title, Rect2(0, middle, _frame.size.x, 68), 55, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var detail := _label(_stage, cue.detail, Rect2(0, middle + 75, _frame.size.x, 39), 25, MINT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _show_scene(cue: Dictionary, play_scene: bool) -> void:
	var packed := load(str(cue.scene)) as PackedScene
	if packed == null:
		_problem("Cannot load " + str(cue.scene))
		return
	var native_canvas: bool = cue.get("canvas", false)
	var region := Rect2(Vector2.ZERO, _frame.size)
	if not native_canvas:
		region.size.y -= 94 if _film else 77
	var viewport := _viewport(region, native_canvas)
	_scene = packed.instantiate()
	viewport.add_child(_scene)
	if (play_scene or not native_canvas) and _scene.has_method("play"):
		_scene.call("play")


func _show_actors(actors: Array) -> void:
	var area := _frame.size
	area.y -= 94 if _film else 77
	var gap := 3.0
	var width := (area.x - gap * (actors.size() - 1)) / actors.size()
	for i in actors.size():
		var take: Dictionary = actors[i]
		var x := i * (width + gap)
		var viewport := _viewport(Rect2(x, 0, width, area.y), false)
		_spawn_actor(viewport, take)
		if take.has("label"):
			_rect(_stage, Rect2(x, 0, width, 51), Color(0.04, 0.07, 0.10, 0.82))
			var label := _label(_stage, take.label, Rect2(x, 1, width, 46), 26, PAPER)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


	if actors[0].get("once", false) and actors[0].has("dedupe_group"):
		_repeat_fade = _rect(_stage, Rect2(Vector2.ZERO, area), Color(INK, 0.0))


func _viewport(region: Rect2, native_canvas: bool) -> SubViewport:
	var host := SubViewportContainer.new()
	host.mouse_filter = Control.MOUSE_FILTER_STOP if native_canvas and not _film else Control.MOUSE_FILTER_IGNORE
	host.stretch = not native_canvas
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	if native_canvas:
		var ratio := minf(region.size.x / DESIGN.x, region.size.y / DESIGN.y)
		viewport.size = Vector2i(DESIGN)
		host.size = DESIGN
		host.scale = Vector2.ONE * ratio
		host.position = region.position + (region.size - DESIGN * ratio) * 0.5
	else:
		viewport.size = Vector2i(region.size)
		host.size = region.size
		host.position = region.position
	host.add_child(viewport)
	_stage.add_child(host)
	return viewport


func _spawn_actor(viewport: SubViewport, take: Dictionary) -> void:
	var packed := load(str(take.scene)) as PackedScene
	if packed == null:
		_problem("Cannot load actor " + str(take.scene))
		return
	var stage := Node3D.new()
	viewport.add_child(stage)
	_lighting(stage, float(take.get("floor_y", 0.0)))
	var actor := packed.instantiate() as Node3D
	stage.add_child(actor)
	var player := actor.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := actor.get_node_or_null("Robot/Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		_problem("Actor lacks its saved player or skeleton: " + str(take.scene))
		return
	var angle := float(take.get("angle", 0.56))
	var center := Vector3(0, float(take.get("center_y", 0.98)), float(take.get("center_z", 0.0)))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(take.get("size", 2.72))
	stage.add_child(camera)
	camera.position = center + Vector3(sin(angle) * 5.4, 1.08, cos(angle) * 5.4)
	camera.look_at(center)
	camera.make_current()
	var state := {"player": player, "clip": str(take.clip), "once": take.get("once", false)}
	if take.get("once", false) and take.has("dedupe_group"):
		state["repeat_pending"] = true
	if take.has("modifier"):
		var modifiers := {"ik": "ReachIK", "look": "HeadLook", "spring": "AerialSpring"}
		var id: String = take.modifier
		var modifier := skeleton.get_node_or_null(modifiers[id]) as SkeletonModifier3D
		if modifier == null:
			_problem("Missing native modifier " + id)
		else:
			modifier.active = true
		if id != "spring":
			var marker := actor.get_node_or_null("ReachTarget" if id == "ik" else "LookTarget") as Node3D
			if marker != null:
				state["marker"] = marker
				state["modifier"] = id
				_block(marker, Vector3.ZERO, Vector3.ONE * 0.065, GOLD)
	if take.clip == "graph":
		_open_graph(actor, state)
	elif player.has_animation(take.clip):
		if take.get("travel", false):
			player.root_motion_track = NodePath()
		player.play(take.clip)
		player.advance(0.0)
	else:
		_problem("Missing animation %s in %s" % [take.clip, take.scene])
	_worlds.append(state)


func _open_graph(actor: Node3D, state: Dictionary) -> void:
	var tree := actor.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null:
		_problem("Missing saved AnimationTree")
		return
	tree.active = true
	state["tree"] = tree
	for entry in tree.get_property_list():
		var path := String(entry.name)
		if path.begins_with("parameters/") and path.ends_with("/blend_position"):
			state["blend"] = path
			break
	var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var graph := tree.tree_root as AnimationNodeStateMachine
	if playback != null and graph != null and graph.has_node("locomotion"):
		playback.start("locomotion")


func _step_world(world: Dictionary) -> void:
	var player: AnimationPlayer = world.player
	if world.get("repeat_pending", false) and _phase >= REPEAT_ONE_SHOT_AT:
		world.repeat_pending = false
		player.stop()
		player.play(world.clip)
		player.advance(0.0)
	if not world.has("tree") and not world.once and not player.is_playing() and player.has_animation(world.clip):
		player.play(world.clip)
	if world.has("marker"):
		var marker: Node3D = world.marker
		if world.modifier == "ik":
			marker.position = Vector3(0.51, 1.30 + sin(_phase * 2.0) * 0.16, 0.3 + cos(_phase * 2.0) * 0.07)
		else:
			marker.position = Vector3(sin(_phase * 2.0) * 0.62, 1.73, 1.8)
	if world.has("blend"):
		var tree: AnimationTree = world.tree
		tree.set(world.blend, (1.0 - cos(_phase * 1.55)) * 1.3)


func _lighting(stage: Node3D, floor_y: float) -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#1d2b38")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#c5d7df")
	world.environment.ambient_light_energy = 0.58
	stage.add_child(world)
	_block(stage, Vector3(0, floor_y - 0.067, 0), Vector3(30, 0.13, 30), Color("#334750"))
	for i in range(-12, 13):
		_block(stage, Vector3(i, floor_y + 0.001, 0), Vector3(0.008, 0.004, 26), Color("#45616a"))
		_block(stage, Vector3(0, floor_y + 0.001, i), Vector3(26, 0.004, 0.008), Color("#45616a"))
	for i in range(-12, 13):
		_block(stage, Vector3(-0.9, floor_y + 0.008, i * 0.51), Vector3(0.035, 0.006, 0.19), MINT)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -31, 0)
	key.light_color = Color("#fff1cd")
	key.light_energy = 1.24
	key.shadow_enabled = true
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-24, 143, 0)
	rim.light_color = Color("#9ddfeb")
	rim.light_energy = 0.7
	stage.add_child(rim)


func _show_inspection() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE + "inspection.json"))
	if not data is Dictionary or data.get("tracks", []).is_empty():
		_problem("Missing saved inspection data")
		return
	var width := _frame.size.x
	var height := _frame.size.y - (94 if _film else 77)
	_rect(_stage, Rect2(0, 0, width, height), PANEL)
	for i in 4:
		var texture := load(BASE + "preview/walk_%02d.png" % i) as Texture2D
		if texture == null:
			_problem("Missing rendered inspection frame %d" % i)
			continue
		var frame := TextureRect.new()
		frame.texture = texture
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.position = Vector2(25 + (i % 2) * width * 0.28, 22 + floori(i / 2.0) * height * 0.47)
		frame.size = Vector2(width * 0.27, height * 0.44)
		_stage.add_child(frame)
	var left := width * 0.61
	_label(_stage, "Saved Responsive walk", Rect2(left, 34, 465, 43), 27, PAPER)
	_label(_stage, "%s s   ·   %s saved tracks" % [data.duration, int(data.track_count)],
		Rect2(left, 89, 460, 35), 21, MINT)
	for i in mini(data.tracks.size(), 7):
		var row: Dictionary = data.tracks[i]
		var path := str(row.path).get_file()
		_label(_stage, "%s   ·   %d keys" % [path, row.keys],
			Rect2(left, 151 + i * 48, width - left - 20, 35), 19, SOFT)


func _block(parent: Node3D, position: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)


func _rect(parent: Node, bounds: Rect2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = bounds.position
	rect.size = bounds.size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(parent: Node, text: String, bounds: Rect2, font_px: int, color: Color) -> Label:
	var label := Label.new()
	label.position = bounds.position
	label.size = bounds.size
	label.text = text
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	box.set_border_width_all(1)
	box.border_color = LINE
	return box


func _button(text: String, bounds: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = bounds.position
	button.size = bounds.size
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _style(PANEL))
	button.add_theme_stylebox_override("hover", _style(LINE))
	button.add_theme_stylebox_override("pressed", _style(INK))
	button.add_theme_stylebox_override("focus", _style(Color(0.659, 0.945, 0.80, 0.22)))
	button.add_theme_color_override("font_color", PAPER)
	button.pressed.connect(action)
	_canvas.add_child(button)
	return button


func _problem(message: String) -> void:
	_problems.append(message)
	push_error(message)


func _check_all() -> void:
	var previous := -1.0
	var reached_canvas := false
	for i in _cues.size():
		var cue: Dictionary = _cues[i]
		_show(i, true)
		await get_tree().process_frame
		if float(cue.at) <= previous:
			_problem("Cue times must strictly increase")
		previous = float(cue.at)
		if cue.get("canvas", false):
			reached_canvas = true
			if cue.kind == "scene" and not _scene is Node2D:
				_problem("Expected a native 2D scene: " + cue.title)
		elif reached_canvas:
			_problem("3D cue appears after the start of 2D")
		if cue.kind == "scene" and not cue.get("canvas", false) and not _scene is Node3D:
			_problem("Expected a native 3D scene: " + cue.title)
		var limit := float(_cues[i + 1].at) if i + 1 < _cues.size() else _duration
		for world in _worlds:
			var player: AnimationPlayer = world.player
			if player.has_animation(world.clip) and player.get_animation(world.clip).length > limit - float(cue.at) + 0.001:
				_problem("Cut ends before playing a complete take: %s / %s" % [cue.title, world.clip])
	for i in _chapter_buttons.size():
		_chapter_buttons[i].pressed.emit()
		if int(_cues[_index].chapter) != i:
			_problem("Chapter button points to another chapter")
		_replay()
		if not is_zero_approx(_phase):
			_problem("Replay did not reset the stage")
	print("SHOWCASE_CHECK slides=%d problems=%s" % [_cues.size(), _problems])
	get_tree().quit(0 if _problems.is_empty() else 1)
