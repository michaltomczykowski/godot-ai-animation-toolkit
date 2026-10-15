extends SceneTree
## Native saved scene comparison. No animation creation, key edits or pose writers.
## Usage: --script res://tools/render_saved_effects.gd -- plan.json case_index report.json
var _case: Dictionary
var _samples: Array = []
var _fixtures: Array[Node] = []
var _elapsed := 0.0
var _frames := 0
var _output := ""
var _last: Array = [{}, {}]
var _changes := [0, 0]
var _different := false
var _caption: Label
var _viewports: Array[SubViewport] = []
var _second_take := false
var _resource_checks := {}
var _plan_sha := ""
var _max_delta_error := 0.0
var _renderer_sha := ""

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected plan.json case_index report.json")
		quit(1)
		return
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not plan is Dictionary or plan.get("kind") != "saved_effect_render_plan":
		quit(1)
		return
	_case = plan.cases[int(args[1])]
	_plan_sha = FileAccess.get_sha256(args[0])
	_renderer_sha = FileAccess.get_sha256(get_script().resource_path)
	if _renderer_sha != plan.tool_sha256["test_project/tools/render_saved_effects.gd"]:
		push_error("Renderer hash differs from plan")
		quit(1)
		return
	_output = args[2]
	if FileAccess.file_exists(_output):
		push_error("Refusing to replace receipt")
		quit(1)
		return
	for resource in _case.dependencies:
		if FileAccess.get_sha256(resource) != _case.dependencies[resource]:
			push_error("Dependency mismatch: " + resource)
			quit(1)
			return
	_resource_checks = _case.dependencies.duplicate()
	root.size = Vector2i(1400, 800)
	for state in ["undo", "redo"]:
		var path: String = _case.scenes[state].path
		if FileAccess.get_sha256(path) != _case.scenes[state].sha256:
			push_error("Scene hash mismatch: " + path)
			quit(1)
			return
		var container := SubViewportContainer.new()
		container.position = Vector2(_fixtures.size() * 700, 80)
		container.size = Vector2(700, 640)
		root.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(700, 640)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = World2D.new()
		viewport.canvas_transform = Transform2D(0.0, Vector2(250, 260))
		container.add_child(viewport)
		_viewports.append(viewport)
		_load_scene(viewport, state)
	_caption = Label.new()
	_caption.size = Vector2(1400, 790)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.text = _case.operation + "    UNDO reference (left) / REDO result (right)\nDisplay-only cyan markers; fixed framing (camera values observed). Audio output NOT qualified."
	root.add_child(_caption)

func _load_scene(viewport: SubViewport, state: String) -> void:
	var packed := load(_case.scenes[state].path) as PackedScene
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	viewport.add_child(scene)
	var fixture := scene.get_node(NodePath(_case.fixture))
	_fixtures.append(fixture)
	var targets: Array = _case.targets
	for child in fixture.get_children():
		if child is CanvasItem and str(child.name) not in targets and not child is Camera2D:
			child.visible = false # Display isolation; all native tracks still play.
		if child is ProgressBar or child is Panel:
			child.size = Vector2(220, 50) # Unkeyed fixture display extent, both clones.
	for child in fixture.get_children():
		if child is Camera2D:
			child.enabled = false # Stable comparison frame; camera properties still observed.
		if child is Node2D and not child is Sprite2D and not child is AnimatedSprite2D:
			var marker := Polygon2D.new()
			marker.polygon = PackedVector2Array([Vector2(-12,-12),Vector2(12,-12),Vector2(12,12),Vector2(-12,12)])
			marker.color = Color(0.2,0.8,0.9,0.7)
			child.add_child(marker) # Display-only child follows real saved transform.
	var player := fixture.get_node_or_null(NodePath(_case.player)) as AnimationPlayer
	if player != null:
		player.stop()
		if player.has_animation(_case.clip):
			player.play(_case.clip)
	var sprite := fixture.get_node_or_null("SheetSprite") as AnimatedSprite2D
	if _case.operation.ends_with("sprite_frames") and sprite != null and sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation(_case.clip):
			sprite.play(_case.clip) # Native process clock; never assign frame.

func _state(fixture: Node) -> Dictionary:
	var result := {}
	for child in fixture.get_children():
		var props := {}
		for property in child.get_property_list():
			if str(property.name) in ["position", "rotation", "scale", "zoom", "modulate", "color", "text", "value", "visible_characters", "frame", "playing"]:
				props[str(property.name)] = str(child.get(property.name))
		result[str(child.name)] = props
	return result

func _process(delta: float) -> bool:
	if _fixtures.size() != 2:
		return false
	_max_delta_error = maxf(_max_delta_error, absf(delta - 1.0 / float(_case.fps)))
	_elapsed += delta
	_frames += 1
	var states := [_state(_fixtures[0]), _state(_fixtures[1])]
	for i in 2:
		if not _last[i].is_empty() and states[i] != _last[i]:
			_changes[i] += 1
	_last = states
	_different = _different or states[0] != states[1]
	if _frames % 1 == 0:
		_samples.append({"frame": _frames, "time": _elapsed, "take": 2 if _second_take else 1, "states": states})
	_caption.text = _case.operation + "  UNDO (left) / REDO (right)  t=%.2f\nDisplay-only cyan markers; fixed camera framing. Native property changes: %s\nAudio requires separate captured output/event proof.\nUNDO %s\nREDO %s" % [_elapsed, str(_changes), _target_text(states[0]), _target_text(states[1])]
	if not _second_take and _elapsed >= float(_case.take_seconds):
		_second_take = true
		for viewport in _viewports:
			for child in viewport.get_children():
				viewport.remove_child(child)
				child.queue_free()
		_fixtures.clear()
		_last = [{}, {}]
		_load_scene(_viewports[0], "undo")
		_load_scene(_viewports[1], "redo")
	if _elapsed >= float(_case.seconds):
		var report := {"schema_version": 1, "operation": _case.operation,
			"case_id": _case.id, "scenes": _case.scenes, "dependencies_verified": _resource_checks, "samples": _samples,
			"native_changed_frames": _changes, "observed_difference": _different,
			"frames": _frames, "elapsed": _elapsed, "plan_sha256": _plan_sha, "renderer_sha256": _renderer_sha, "max_delta_error": _max_delta_error, "engine": Engine.get_version_info(),
			"status": "observation_only", "semantic_effect_check": "pending",
			"continuous_visual_assessment": "pending", "audio_output": "pending" if _case.audio_output_required else "not_applicable",
			"limits": "Difference/progression are observations, not semantic correctness or visual approval. Camera disabled for stable framing; unrelated CanvasItems hidden; unkeyed bar/panel display extents 220x50; markers are display-only children. Both clones re-instantiated for take2. SpriteFrames explicitly played for review (saved play=false remains documented)."}
		var file := FileAccess.open(_output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		quit()
	return false

func _target_text(state: Dictionary) -> String:
	var out := {}
	for target in _case.targets:
		out[target] = state.get(target, {})
	return JSON.stringify(out)
