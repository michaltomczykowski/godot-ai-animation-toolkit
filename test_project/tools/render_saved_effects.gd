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
var _runtime_failures: Array = []
var _logger: ErrorCapture
const CAPTURE_SIZE := Vector2i(1400, 800)
const BODY_TOP := 190
var _capture_geometry: Dictionary = {}
var _startup_capture: Dictionary = {}

class ErrorCapture extends Logger:
	var errors: Array = []
	func _log_error(fn: String, file: String, line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1:
			errors.append({"function": fn, "file": file, "line": line,
				"code": code, "message": rationale, "type": type})

class CalibrationGrid extends Node2D:
	func _draw() -> void:
		for index in range(-12, 13):
			var value := float(index * 50)
			draw_line(Vector2(value, -600), Vector2(value, 600), Color(0.3, 0.45, 0.55, 0.5), 1.0)
			draw_line(Vector2(-600, value), Vector2(600, value), Color(0.3, 0.45, 0.55, 0.5), 1.0)
		draw_line(Vector2(-600, 0), Vector2(600, 0), Color(0.95, 0.55, 0.2), 2.0)
		draw_line(Vector2(0, -600), Vector2(0, 600), Color(0.95, 0.55, 0.2), 2.0)
		draw_circle(Vector2.ZERO, 10, Color.WHITE, false, 2.0)

func _native_camera_mode() -> bool:
	return _case.operation in ["animation_fx.shake", "animation_fx.zoom_punch"]

func _camera_presentation() -> String:
	return "native_camera_static_calibration_grid" if _native_camera_mode() else "fixed_comparison_frame"

func _camera_states() -> Array:
	var result: Array = []
	for fixture in _fixtures:
		var camera := fixture.get_node_or_null("Camera2D") as Camera2D
		result.append({"enabled": camera.enabled, "current": camera.is_current()} if camera != null else {})
	return result

func _initialize() -> void:
	_logger = ErrorCapture.new()
	OS.add_logger(_logger)
	_startup_capture = {"viewport_width": ProjectSettings.get_setting("display/window/size/viewport_width"),
		"viewport_height": ProjectSettings.get_setting("display/window/size/viewport_height"),
		"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"),
		"stretch_aspect": ProjectSettings.get_setting("display/window/stretch/aspect")}
	if _startup_capture.viewport_width != CAPTURE_SIZE.x or _startup_capture.viewport_height != CAPTURE_SIZE.y or _startup_capture.stretch_mode != "viewport" or _startup_capture.stretch_aspect != "keep":
		push_error("Movie Maker requires fixed viewport settings BEFORE startup; use movie_capture_startup.py: " + str(_startup_capture))
		quit(1)
		return
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
	# Render the complete comparison at a fixed base resolution even when the
	# OS clamps the physical window to a smaller remote-desktop work area.
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = CAPTURE_SIZE
	for state in ["undo", "redo"]:
		var path: String = _case.scenes[state].path
		if FileAccess.get_sha256(path) != _case.scenes[state].sha256:
			push_error("Scene hash mismatch: " + path)
			quit(1)
			return
		var container := SubViewportContainer.new()
		container.position = Vector2(_fixtures.size() * 700, BODY_TOP)
		container.size = Vector2(700, 610)
		root.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(700, 610)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = World2D.new()
		viewport.own_world_3d = true
		container.add_child(viewport)
		_viewports.append(viewport)
		_load_scene(viewport, state)
	_caption = Label.new()
	_caption.position = Vector2(12, 8)
	_caption.size = Vector2(1376, 170)
	_caption.clip_contents = true
	_caption.max_lines_visible = 6
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.text = _case.operation + "    UNDO reference (left) / REDO result (right)\nDisplay-only cyan markers; native camera + static grid for shake/zoom, fixed framing otherwise. Audio output NOT qualified."
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
	if _case.get("display_mode", "") == "showcase":
		_apply_fixed_presentation(viewport)
		_play_saved(fixture, state)
		return
	for child in fixture.get_children():
		if child is CanvasItem and str(child.name) not in targets and not child is Camera2D:
			child.visible = false # Display isolation; all native tracks still play.
		if child is ProgressBar or child is Panel:
			child.size = Vector2(220, 50) # Unkeyed fixture display extent, both clones.
	for child in fixture.get_children():
		if child is Camera2D:
			child.enabled = _native_camera_mode()
			if _native_camera_mode(): child.make_current()
		if (child is Node2D and not child is Sprite2D and not child is AnimatedSprite2D) or child is Control:
			var marker := Polygon2D.new()
			marker.polygon = PackedVector2Array([Vector2(-12,-12),Vector2(12,-12),Vector2(12,12),Vector2(-12,12)])
			marker.color = Color(0.2,0.8,0.9,0.7)
			child.add_child(marker) # Display-only child follows real saved transform.
	for child in fixture.get_children():
		if child is Node3D and str(child.name) in targets:
			var marker := MeshInstance3D.new()
			marker.mesh = BoxMesh.new()
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.2, 0.8, 0.9)
			marker.material_override = material
			child.add_child(marker) # Display-only rigid geometry, no pose/key writer.
	if fixture.get_node_or_null("Target3D") != null:
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(9, 9, 16)
		camera.look_at(Vector3(2, 3, 4))
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -30, 0)
		viewport.add_child(light)
	if _native_camera_mode():
		var grid := CalibrationGrid.new()
		grid.z_index = -10
		viewport.add_child(grid) # Static world calibration; camera alone changes its presentation.
	_play_saved(fixture, state)
	var sprite := fixture.get_node_or_null("SheetSprite") as AnimatedSprite2D
	if _case.operation.ends_with("sprite_frames") and sprite != null and sprite.sprite_frames != null:
		if sprite.sprite_frames.has_animation(_case.clip):
			sprite.play(_case.clip) # Native process clock; never assign frame.
	_apply_fixed_presentation(viewport)

func _fixed_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(0.55, 0.55), 0.0, Vector2(0, 100)) if _case.get("display_mode", "") == "showcase" else Transform2D(0.0, Vector2(250, 260))

func _apply_fixed_presentation(viewport: SubViewport) -> void:
	if _native_camera_mode(): return
	# Camera shutdown resets its viewport canvas transform. Apply framing only
	# after every saved camera is disabled, including freshly instanced take 2.
	for camera in viewport.find_children("*", "Camera2D", true, false):
		camera.enabled = false
	viewport.canvas_transform = _fixed_transform()

func _presentation_states() -> Array:
	var states: Array = []
	for viewport in _viewports:
		var transform := viewport.canvas_transform
		var expected := _fixed_transform()
		var fixed_ok := _native_camera_mode() or transform.is_equal_approx(expected)
		if not fixed_ok and not _runtime_failures.has("Fixed comparison framing changed after camera shutdown"):
			_runtime_failures.append("Fixed comparison framing changed after camera shutdown")
		states.append({"canvas_transform": [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y],
			"body_rect": [viewport.get_parent().position.x, BODY_TOP, 700, 610], "fixed_frame_valid": fixed_ok})
	return states

func _play_saved(fixture: Node, state: String) -> void:
	if _case.operation == "animation_fx.sprite_frames": return
	var playbacks: Array = _case.get("playbacks", [{"player": _case.player, "undo_clip": _case.clip, "redo_clip": _case.clip}])
	for playback in playbacks:
		var player := fixture.get_node_or_null(NodePath(playback.player)) as AnimationPlayer
		var clip := str(playback[state + "_clip"])
		if player == null:
			if state == "redo": _runtime_failures.append("Missing required saved player: " + str(playback.player))
			continue
		player.stop()
		if player.has_animation(clip): player.play(clip)
		elif state == "redo": _runtime_failures.append("Missing required saved clip: " + clip)

func _player_times(fixture: Node, state: String) -> Dictionary:
	var result := {}
	var playbacks: Array = _case.get("playbacks", [{"player": _case.player, "undo_clip": _case.clip, "redo_clip": _case.clip}])
	for playback in playbacks:
		var player := fixture.get_node_or_null(NodePath(playback.player)) as AnimationPlayer
		if player != null:
			result[str(playback.player)] = {"clip": playback[state + "_clip"],
				"position": player.current_animation_position if not player.current_animation.is_empty() else 0.0,
				"playing": player.is_playing()}
	return result

func _state(fixture: Node) -> Dictionary:
	var result := {}
	for path in _case.targets:
		var child := fixture.get_node_or_null(NodePath(path))
		if child == null:
			result[path] = {}
			continue
		var props := {}
		for property in child.get_property_list():
			if str(property.name) in ["position", "rotation", "quaternion", "scale", "zoom", "modulate", "color", "text", "value", "visible_characters", "frame", "playing"]:
				props[str(property.name)] = str(child.get(property.name))
		result[path] = props
	return result

func _process(delta: float) -> bool:
	if _fixtures.size() != 2:
		return false
	var rendered := Vector2i(root.get_texture().get_size())
	_capture_geometry = {"logical_size": [root.content_scale_size.x, root.content_scale_size.y],
		"render_size": [rendered.x, rendered.y], "window_size": [root.size.x, root.size.y],
		"content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect}
	if rendered != CAPTURE_SIZE or root.content_scale_size != CAPTURE_SIZE:
		_runtime_failures.append("Capture viewport lost full 1400x800 logical/render extent: " + str(_capture_geometry))
		push_error(_runtime_failures[-1])
		quit(1)
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
		_samples.append({"frame": _frames, "time": _elapsed, "take": 2 if _second_take else 1, "states": states, "presentation": _presentation_states(), "players": [_player_times(_fixtures[0], "undo"), _player_times(_fixtures[1], "redo")]})
	_caption.text = _case.operation + "  UNDO (left) / REDO (right)  t=%.2f\nDisplay-only cyan markers; camera presentation: %s. Native property changes: %s\n50-unit static calibration grid for native camera cases. Audio output proof remains separate.\nUNDO %s\nREDO %s" % [_elapsed, _camera_presentation(), str(_changes), _target_text(states[0]), _target_text(states[1])]
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
			"case_id": _case.id, "header_rect": [12, 8, 1376, 170], "startup_capture": _startup_capture, "capture_geometry": _capture_geometry, "runtime_failures": _runtime_failures, "engine_errors": _logger.errors,
			"camera_presentation": _camera_presentation(), "native_camera_states": _camera_states(), "scenes": _case.scenes, "dependencies_verified": _resource_checks, "samples": _samples,
			"native_changed_frames": _changes, "observed_difference": _different,
			"frames": _frames, "elapsed": _elapsed, "plan_sha256": _plan_sha, "renderer_sha256": _renderer_sha, "max_delta_error": _max_delta_error, "engine": Engine.get_version_info(),
			"status": "failed_engine_or_runtime" if not _logger.errors.is_empty() or not _runtime_failures.is_empty() else "observation_only", "semantic_effect_check": "pending",
			"continuous_visual_assessment": "pending", "audio_output": "pending" if _case.audio_output_required else "not_applicable",
			"limits": "Difference/progression are observations, not semantic correctness or visual approval. Native camera plus static50-unit calibration grid for shake/zoom; other cameras disabled for stable framing; unrelated CanvasItems hidden; unkeyed bar/panel display extents 220x50; Control/Node2D cyan polygons and Node3D rigid cube/camera/light are display-only; showcase framed at0.55; markers are display-only children. Both clones re-instantiated for take2. SpriteFrames explicitly played for review (saved play=false remains documented)."}
		var file := FileAccess.open(_output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
		quit(1 if not _logger.errors.is_empty() or not _runtime_failures.is_empty() else 0)
	return false

func _target_text(state: Dictionary) -> String:
	var out := {}
	for target in _case.targets:
		out[target] = state.get(target, {})
	return JSON.stringify(out)
