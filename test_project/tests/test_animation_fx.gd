@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const FxHandler := preload("res://addons/godot_ai_animation/handlers/fx.gd")

const SHEET := "res://tests/fixtures/sheet.png"
const CUE := "res://tests/fixtures/cue.wav"

## Tests for the animation_fx generators (shake/zoom_punch/hit_flash/...).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: FxHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_fx"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = FxHandler.new()


func suite_teardown() -> void:
	pass


# --- helpers ---------------------------------------------------------------

func _add_player(player_name: String) -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ""
	var player := AnimationPlayer.new()
	player.name = player_name
	player.add_animation_library("", AnimationLibrary.new())
	scene_root.add_child(player)
	player.set_owner(scene_root)
	return "/" + scene_root.name + "/" + player_name


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _add_sibling(node: Node, sibling_name: String) -> Node:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	node.name = sibling_name
	scene_root.add_child(node)
	node.owner = scene_root
	return node


func _fetch_anim(player_path: String, anim_name: String) -> Animation:
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(player_path, scene_root) as AnimationPlayer
	if player == null or not player.has_animation(anim_name):
		return null
	return player.get_animation(anim_name)


## Player + one target sibling, returning both paths.
func _rig(prefix: String, target: Node) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	_add_sibling(target, prefix + "Target")
	var player_path := _add_player("FxPlayer" + prefix)
	if player_path.is_empty():
		return {"error": "no player"}
	return {
		"player_path": player_path,
		"target_path": "/" + scene_root.name + "/" + prefix + "Target",
		"target": target,
	}


func _teardown(rig: Dictionary) -> void:
	if rig.has("player_path"):
		_remove_node(rig.player_path)
	if rig.has("target_path"):
		_remove_node(rig.target_path)


# --- rollup ----------------------------------------------------------------

func test_rollup_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "sparkle"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "shake")
	assert_contains(unknown.error.message, "typewriter")


# --- feedback --------------------------------------------------------------

func test_shake_on_camera2d_settles() -> void:
	var camera := Camera2D.new()
	var rig := _rig("Shake", camera)
	if rig.has("error"):
		skip(rig.error)
		return
	var origin := camera.position
	var result := _handler.run({
		"op": "shake", "player_path": rig.player_path, "target_path": "ShakeTarget",
		"intensity": 12.0, "duration": 0.4, "frequency": 24.0, "seed": 3,
	}, null)
	assert_has_key(result, "data")
	assert_eq(str(result.data.animation_name), "shake")
	var anim := _fetch_anim(rig.player_path, "shake")
	assert_true(anim != null, "the shake clip exists")
	assert_true(anim.track_get_key_count(0) > 8, "shake is densely sampled")
	var last = anim.track_get_key_value(0, anim.track_get_key_count(0) - 1)
	assert_true((last as Vector2).is_equal_approx(origin), "the camera returns to its origin")
	var peak := 0.0
	for index in anim.track_get_key_count(0):
		peak = maxf(peak, (anim.track_get_key_value(0, index) as Vector2).distance_to(origin))
	assert_true(peak > 2.0 and peak <= 12.01, "shake amplitude stays within the intensity (%s)" % peak)
	_teardown(rig)


func test_shake_rejects_non_vector_property() -> void:
	var rig := _rig("ShakeBad", Node.new())
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "shake", "player_path": rig.player_path, "target_path": "ShakeBadTarget",
	}, null)
	assert_is_error(result, ErrorCodes.WRONG_TYPE)
	_teardown(rig)


func test_zoom_punch_on_camera2d() -> void:
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.0, 2.0)
	var rig := _rig("Zoom", camera)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "zoom_punch", "player_path": rig.player_path, "target_path": "ZoomTarget",
		"amount": 0.1, "duration": 0.3,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "zoom_punch")
	var peak = anim.track_get_key_value(0, 1)
	assert_true((peak as Vector2).is_equal_approx(Vector2(2.2, 2.2)),
		"the punch overshoots by amount, got %s" % str(peak))
	assert_eq(anim.track_get_key_count(0), 3)
	var not_a_camera := _rig("ZoomBad", Node2D.new())
	var rejected := _handler.run({
		"op": "zoom_punch", "player_path": not_a_camera.player_path, "target_path": "ZoomBadTarget",
	}, null)
	assert_is_error(rejected, ErrorCodes.WRONG_TYPE)
	_teardown(rig)
	_teardown(not_a_camera)


func test_hit_flash_accepts_hex_color() -> void:
	var rect := ColorRect.new()
	var rig := _rig("Flash", rect)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "hit_flash", "player_path": rig.player_path, "target_path": "FlashTarget",
		"color": "#ff0000", "count": 2, "duration": 0.2,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "hit_flash")
	assert_eq(anim.track_get_key_count(0), 5, "two flashes produce five keys")
	var peak: Color = anim.track_get_key_value(0, 1)
	assert_true(peak.is_equal_approx(Color(1, 0, 0, 1)), "the flash color is parsed from hex, got %s" % str(peak))
	_teardown(rig)


func test_damage_bar_holds_then_eases() -> void:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 80.0
	var rig := _rig("Damage", bar)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "damage_bar", "player_path": rig.player_path, "target_path": "DamageTarget",
		"to": 30.0, "delay": 0.3, "duration": 0.4,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "damage_bar")
	assert_eq(anim.track_get_key_count(0), 3, "hold + ease")
	assert_true(is_equal_approx(float(anim.track_get_key_value(0, 0)), 80.0), "from defaults to the current value")
	assert_true(is_equal_approx(float(anim.track_get_key_value(0, 1)), 80.0), "the bar holds during the delay")
	assert_true(is_equal_approx(float(anim.track_get_key_value(0, 2)), 30.0), "the bar eases to the target value")
	_teardown(rig)


# --- UI --------------------------------------------------------------------

func test_typewriter_steps_on_label() -> void:
	var label := Label.new()
	var rig := _rig("Type", label)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "typewriter", "player_path": rig.player_path, "target_path": "TypeTarget",
		"steps": 12, "duration": 1.2, "delay": 0.1,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "typewriter")
	assert_eq(str(anim.track_get_path(0)), "TypeTarget:visible_ratio")
	assert_eq(anim.track_get_key_count(0), 13, "one key per step")
	assert_eq(anim.track_get_interpolation_type(0), Animation.INTERPOLATION_NEAREST)
	assert_true(is_equal_approx(anim.length, 1.3), "the delay extends the clip")
	_teardown(rig)


func test_progress_fill_on_progress_bar() -> void:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 10.0
	var rig := _rig("Fill", bar)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "progress_fill", "player_path": rig.player_path, "target_path": "FillTarget",
		"to": 100.0, "duration": 0.6,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "progress_fill")
	assert_true(is_equal_approx(float(anim.track_get_key_value(0, 0)), 10.0), "from defaults to the current value")
	assert_true(is_equal_approx(float(anim.track_get_key_value(0, 1)), 100.0), "the bar fills to 'to'")
	_teardown(rig)


func test_counter_builds_method_track() -> void:
	var label := Label.new()
	var rig := _rig("Counter", label)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "counter", "player_path": rig.player_path, "target_path": "CounterTarget",
		"from": 0, "to": 100, "steps": 4, "duration": 1.0, "prefix": "$",
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "counter")
	assert_eq(anim.get_track_count(), 1)
	assert_eq(anim.track_get_type(0), Animation.TYPE_METHOD, "counter uses a method track")
	assert_eq(anim.track_get_key_count(0), 5)
	assert_eq(String(anim.method_track_get_name(0, 0)), "set_text")
	assert_eq(str(anim.method_track_get_params(0, 4)[0]), "$100", "the final call carries the formatted value")
	_teardown(rig)


func test_dialog_pop_scales_and_fades() -> void:
	var panel := Panel.new()
	panel.size = Vector2(200, 120)
	var rig := _rig("Pop", panel)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "dialog_pop", "player_path": rig.player_path, "target_path": "PopTarget",
		"from_scale": 0.8, "overshoot": 1.05, "duration": 0.35,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "dialog_pop")
	assert_eq(anim.get_track_count(), 2, "scale + fade tracks")
	var scale_start = anim.track_get_key_value(0, 0)
	assert_true((scale_start as Vector2).is_equal_approx(Vector2(0.8, 0.8)), "starts at from_scale")
	_teardown(rig)


func test_transition_fade_and_wipe_pivot() -> void:
	var overlay := ColorRect.new()
	overlay.size = Vector2(320, 180)
	overlay.pivot_offset = Vector2(160, 90)
	var rig := _rig("Fade", overlay)
	if rig.has("error"):
		skip(rig.error)
		return
	var fade := _handler.run({
		"op": "transition", "player_path": rig.player_path, "target_path": "FadeTarget",
		"mode": "fade_out", "duration": 0.5,
	}, null)
	assert_has_key(fade, "data")
	var anim := _fetch_anim(rig.player_path, "transition")
	assert_eq(str(anim.track_get_path(0)), "FadeTarget:modulate:a")
	var wipe := _handler.run({
		"op": "transition", "player_path": rig.player_path, "target_path": "FadeTarget",
		"mode": "wipe_right", "duration": 0.5, "animation_name": "wipe",
	}, null)
	assert_has_key(wipe, "data")
	var wipe_anim := _fetch_anim(rig.player_path, "wipe")
	assert_eq(str(wipe_anim.track_get_path(0)), "FadeTarget:scale")
	assert_true(overlay.pivot_offset.is_equal_approx(Vector2(0, 90)),
		"wipe_right moves the pivot to the left edge, got %s" % str(overlay.pivot_offset))
	_teardown(rig)


# --- motion ----------------------------------------------------------------

func test_wave_builds_one_track_per_target() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	for index in 3:
		_add_sibling(ColorRect.new(), "WaveItem%d" % index)
	var player_path := _add_player("FxPlayerWave")
	if player_path.is_empty():
		skip("Scene not ready")
		return
	var result := _handler.run({
		"op": "wave", "player_path": player_path,
		"target_paths": ["WaveItem0", "WaveItem1", "WaveItem2"],
		"axis": "y", "amplitude": 14.0, "period": 1.0, "phase_step": 0.2,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "wave")
	assert_eq(anim.get_track_count(), 3, "one track per target")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR)
	var first = anim.track_get_key_value(0, 0)
	var second = anim.track_get_key_value(1, 0)
	assert_false((first as Vector2).is_equal_approx(second as Vector2), "targets are phase-shifted")
	_remove_node(player_path)
	for index in 3:
		_remove_node("/" + scene_root.name + "/WaveItem%d" % index)


func test_spring_settles_on_the_offset() -> void:
	var body := Node2D.new()
	body.position = Vector2(200, 200)
	var rig := _rig("Spring", body)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "spring", "player_path": rig.player_path, "target_path": "SpringTarget",
		"offset": {"x": 0, "y": -80}, "frequency": 2.0, "damping": 0.3, "duration": 1.0,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "spring")
	var first = anim.track_get_key_value(0, 0)
	var last = anim.track_get_key_value(0, anim.track_get_key_count(0) - 1)
	assert_true((first as Vector2).is_equal_approx(Vector2(200, 200)), "spring starts at the current position")
	assert_true((last as Vector2).distance_to(Vector2(200, 120)) < 1.0,
		"spring settles on position + offset, got %s" % str(last))
	_teardown(rig)


func test_pendulum_rotates_around_zero() -> void:
	var sign := Node2D.new()
	var rig := _rig("Pendulum", sign)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "pendulum", "player_path": rig.player_path, "target_path": "PendulumTarget",
		"amplitude": 20.0, "period": 1.0, "duration": 2.0, "decay": 1.0,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "pendulum")
	assert_eq(str(anim.track_get_path(0)), "PendulumTarget:rotation")
	assert_true(absf(float(anim.track_get_key_value(0, 0)) - deg_to_rad(20.0)) < 0.001,
		"the swing starts at +amplitude")
	var negative := false
	for index in anim.track_get_key_count(0):
		if float(anim.track_get_key_value(0, index)) < 0.0:
			negative = true
	assert_true(negative, "the swing crosses the rest angle")
	_teardown(rig)


func test_path_follow_samples_the_curve() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var path := Path2D.new()
	var curve := Curve2D.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(120, 0))
	curve.add_point(Vector2(120, 90))
	path.curve = curve
	_add_sibling(path, "FxPatrolPath")
	var drone := Node2D.new()
	var rig := _rig("Drone", drone)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "path_follow", "player_path": rig.player_path, "target_path": "DroneTarget",
		"path_node": "/" + scene_root.name + "/FxPatrolPath", "duration": 3.0, "samples": 16,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "path_follow")
	assert_eq(anim.track_get_key_count(0), 16)
	var start = anim.track_get_key_value(0, 0)
	var end = anim.track_get_key_value(0, 15)
	assert_true((start as Vector2).distance_to(Vector2(0, 0)) < 1.0, "starts at the curve start, got %s" % str(start))
	assert_true((end as Vector2).distance_to(Vector2(120, 90)) < 1.0, "ends at the curve end, got %s" % str(end))
	_teardown(rig)
	_remove_node("/" + scene_root.name + "/FxPatrolPath")


# --- sprites / audio -------------------------------------------------------

func test_flipbook_steps_sprite_frames_property() -> void:
	var sprite := Sprite2D.new()
	var rig := _rig("Flip", sprite)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "flipbook", "player_path": rig.player_path, "target_path": "FlipTarget",
		"frames": 6, "fps": 12.0, "from_frame": 2,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "flipbook")
	assert_eq(str(anim.track_get_path(0)), "FlipTarget:frame")
	assert_eq(anim.track_get_key_count(0), 6)
	assert_eq(anim.track_get_interpolation_type(0), Animation.INTERPOLATION_NEAREST)
	assert_true(is_equal_approx(anim.length, 0.5), "length is frames / fps")
	_teardown(rig)


func test_sprite_frames_assigns_resource() -> void:
	if not ResourceLoader.exists(SHEET):
		skip("fixture sheet.png is not imported")
		return
	var animated := AnimatedSprite2D.new()
	var rig := _rig("Sheet", animated)
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "sprite_frames", "sprite_path": rig.target_path,
		"texture": SHEET, "hframes": 4, "vframes": 1, "fps": 10.0, "animation_name": "idle",
	}, null)
	assert_has_key(result, "data")
	assert_eq(int(result.data.frame_count), 4)
	var frames := animated.sprite_frames
	assert_true(frames != null and frames.has_animation("idle"), "the SpriteFrames resource is assigned")
	assert_eq(frames.get_frame_count("idle"), 4)
	assert_true(animated.is_playing(), "the animation starts playing")
	assert_true(animated.animation == StringName("idle"), "the assigned animation is playing")
	var sprite_rig := _rig("SheetBad", Sprite2D.new())
	var rejected := _handler.run({
		"op": "sprite_frames", "sprite_path": sprite_rig.target_path, "texture": SHEET,
	}, null)
	assert_is_error(rejected, ErrorCodes.WRONG_TYPE)
	_teardown(rig)
	_teardown(sprite_rig)


func test_audio_cue_builds_audio_track() -> void:
	if not ResourceLoader.exists(CUE):
		skip("fixture cue.wav is not imported")
		return
	var rig := _rig("Cue", Node2D.new())
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "audio_cue", "player_path": rig.player_path, "target_path": "CueTarget",
		"stream": CUE, "time": 0.2,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(rig.player_path, "audio_cue")
	assert_eq(anim.track_get_type(0), Animation.TYPE_AUDIO, "the cue is an audio track")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 0), 0.2), "the cue fires at 'time'")
	assert_true(anim.audio_track_get_key_stream(0, 0) != null, "the stream is stored")
	var missing := _handler.run({
		"op": "audio_cue", "player_path": rig.player_path, "target_path": "CueTarget",
		"stream": "res://nope.wav",
	}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


# --- undo + registry -------------------------------------------------------

func test_undo_removes_the_generated_clip() -> void:
	var rig := _rig("Undo", Node2D.new())
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "spring", "player_path": rig.player_path, "target_path": "UndoTarget",
		"offset": {"x": 40, "y": 0},
	}, null)
	assert_has_key(result, "data")
	assert_true(_fetch_anim(rig.player_path, "spring") != null, "the clip landed")
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(_fetch_anim(rig.player_path, "spring") == null, "one undo removes the clip")
	_teardown(rig)


func test_registry_matches_fx_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_FX)
	assert_false(info.is_empty(), "the fx family is registered")
	var op_enum: Array = info.schema.properties.op.enum
	assert_eq(op_enum.size(), 16, "the fx schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(info.schema.properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the fx description fits the custom-tool cap")
