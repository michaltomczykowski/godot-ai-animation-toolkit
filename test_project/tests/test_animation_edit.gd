@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const EditHandler := preload("res://addons/godot_ai_animation/handlers/edit.gd")

## Tests for the animation_edit tool (retime/retarget/reverse/mirror/offset/...).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: EditHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_edit"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = EditHandler.new()


func suite_teardown() -> void:
	pass


# --- helpers ---------------------------------------------------------------

func _add_player(player_name: String = "EditAnimPlayer") -> String:
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


## Add a clip built from a spec directly (no undo action), so `editor_undo`
## only ever sees the edit op's action.
func _add_clip(player_path: String, clip_name: String, spec: Dictionary) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(player_path, scene_root) as AnimationPlayer
	if player == null:
		return
	var anim := SpecBuilder.to_animation(spec)
	player.get_animation_library("").add_animation(clip_name, anim)


## Standard fixture: a Node2D sibling plus a player holding one clip with a
## position track (3 keys, 1 s) and a modulate:a track.
func _fixture(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	_add_sibling(Node2D.new(), prefix + "Target")
	var player_path := _add_player("EditPlayer" + prefix)
	if player_path.is_empty():
		return {"error": "no player"}
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, prefix + "Target:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(10, 4), "transition": 1.0},
		{"time": 1.0, "value": Vector2(20, 0), "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, prefix + "Target:modulate:a", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 1.0, "value": 1.0, "transition": 1.0},
	])
	_add_clip(player_path, "clip", spec)
	return {"player_path": player_path, "target": "/" + scene_root.name + "/" + prefix + "Target"}


func _teardown(fixture: Dictionary) -> void:
	if fixture.has("player_path"):
		_remove_node(fixture.player_path)
	if fixture.has("target"):
		_remove_node(fixture.target)


# --- rollup ----------------------------------------------------------------

func test_rollup_dispatches_and_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "wobble"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "retime")
	assert_contains(unknown.error.message, "cleanup")


# --- retime ----------------------------------------------------------------

func test_retime_scales_keys_and_length() -> void:
	var fixture := _fixture("Retime")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "retime", "player_path": fixture.player_path,
		"animation_name": "clip", "factor": 0.5,
	}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.keys_before, 5)
	assert_eq(result.data.keys_after, 5)
	assert_true(is_equal_approx(float(result.data.length), 0.5), "length should halve")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.length, 0.5), "the clip length should halve")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), 0.25), "key times should halve")
	_teardown(fixture)


func test_retime_to_length_and_keys_only() -> void:
	var fixture := _fixture("Retime2")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "retime", "player_path": fixture.player_path,
		"animation_name": "clip", "length": 2.0, "keys_only": true,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.length, 2.0), "keys_only retime sets the length")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), 0.5), "keys_only keeps key times")
	var missing := _handler.run({
		"op": "retime", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_is_error(missing, ErrorCodes.MISSING_REQUIRED_PARAM)
	_teardown(fixture)


# --- retarget --------------------------------------------------------------

func test_retarget_node_and_prefix_modes() -> void:
	var fixture := _fixture("Retarget")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "retarget", "player_path": fixture.player_path, "animation_name": "clip",
		"from_path": "RetargetTarget", "to_path": "Player/RetargetTarget", "mode": "prefix",
	}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.changed_tracks, 2)
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_eq(str(anim.track_get_path(0)), "Player/RetargetTarget:position")
	assert_eq(str(anim.track_get_path(1)), "Player/RetargetTarget:modulate:a")
	var no_match := _handler.run({
		"op": "retarget", "player_path": fixture.player_path, "animation_name": "clip",
		"from_path": "Nope", "to_path": "X",
	}, null)
	assert_is_error(no_match, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(no_match.error.message, "RetargetTarget")
	_teardown(fixture)


# --- reverse / mirror / offset ---------------------------------------------

func test_reverse_mirrors_key_times_and_values() -> void:
	var fixture := _fixture("Reverse")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "reverse", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 0), 0.0), "reverse keeps the span")
	var first = anim.track_get_key_value(0, 0)
	assert_true(first is Vector2 and (first as Vector2).is_equal_approx(Vector2(20, 0)),
		"reverse should move the last value to the front, got %s" % str(first))
	_teardown(fixture)


func test_mirror_position_about_pivot() -> void:
	var fixture := _fixture("Mirror")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "mirror", "player_path": fixture.player_path, "animation_name": "clip",
		"axis": "x", "pivot": {"x": 10, "y": 0},
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	var mirrored = anim.track_get_key_value(0, 0)
	assert_true(mirrored is Vector2 and (mirrored as Vector2).is_equal_approx(Vector2(20, 0)),
		"mirror about pivot x=10 should map 0 to 20, got %s" % str(mirrored))
	var bad_axis := _handler.run({
		"op": "mirror", "player_path": fixture.player_path, "animation_name": "clip", "axis": "q",
	}, null)
	assert_is_error(bad_axis, ErrorCodes.VALUE_OUT_OF_RANGE)
	_teardown(fixture)


func test_offset_wrap_keeps_length() -> void:
	var fixture := _fixture("Offset")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "offset", "player_path": fixture.player_path, "animation_name": "clip",
		"delta": 0.5, "wrap": true,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.length, 1.0), "wrapped offset keeps the length")
	assert_eq(anim.track_get_key_count(0), 2, "wrapped offset dedupes the seam keys")
	_teardown(fixture)


# --- easing / interpolation ------------------------------------------------

func test_ease_range_sets_key_transitions() -> void:
	var fixture := _fixture("Ease")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "ease_range", "player_path": fixture.player_path, "animation_name": "clip",
		"from": 0.0, "to": 0.5, "transition": "ease_out",
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.track_get_key_transition(0, 0), 0.5),
		"ease_out should be stored as 0.5")
	assert_true(is_equal_approx(anim.track_get_key_transition(0, 2), 1.0),
		"keys outside the range keep their transition")
	_teardown(fixture)


func test_set_interp_and_cubic_refusal() -> void:
	var fixture := _fixture("Interp")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "set_interp", "player_path": fixture.player_path, "animation_name": "clip",
		"interpolation": "nearest",
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.track_get_interpolation_type(0), Animation.INTERPOLATION_NEAREST)
	var cubic := _handler.run({
		"op": "set_interp", "player_path": fixture.player_path, "animation_name": "clip",
		"interpolation": "cubic",
	}, null)
	assert_is_error(cubic, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(cubic.error.message, "cubic")
	_teardown(fixture)


# --- trim / split / merge --------------------------------------------------

func test_trim_keeps_bounds() -> void:
	var fixture := _fixture("Trim")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "trim", "player_path": fixture.player_path, "animation_name": "clip",
		"from": 0.25, "to": 0.75,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.length, 0.5), "trim sets the length to the range")
	assert_eq(anim.track_get_key_count(0), 3, "trim keeps the middle key and adds boundaries")
	var first = anim.track_get_key_value(0, 0)
	assert_true(first is Vector2 and (first as Vector2).is_equal_approx(Vector2(5, 2)),
		"the boundary key should be sampled at the cut, got %s" % str(first))
	_teardown(fixture)


func test_split_at_creates_head_and_tail() -> void:
	var fixture := _fixture("Split")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "split_at", "player_path": fixture.player_path, "animation_name": "clip",
		"time": 0.5, "head_name": "clip_head",
	}, null)
	assert_has_key(result, "data")
	assert_eq(str(result.data.head_name), "clip_head")
	var head := _fetch_anim(fixture.player_path, "clip_head")
	var tail := _fetch_anim(fixture.player_path, "clip")
	assert_true(head != null and tail != null, "split should create both clips")
	assert_true(is_equal_approx(head.length, 0.5) and is_equal_approx(tail.length, 0.5),
		"split halves should be 0.5 s")
	var collision := _handler.run({
		"op": "split_at", "player_path": fixture.player_path, "animation_name": "clip",
		"time": 0.2, "head_name": "clip_head",
	}, null)
	assert_is_error(collision, ErrorCodes.INVALID_PARAMS)
	_teardown(fixture)


func test_merge_concatenates_clips() -> void:
	var fixture := _fixture("Merge")
	if fixture.has("error"):
		skip(fixture.error)
		return
	_add_clip(fixture.player_path, "second", ClipSpec.make(0.5, Animation.LOOP_NONE))
	var result := _handler.run({
		"op": "merge", "player_path": fixture.player_path, "animation_name": "clip",
		"sources": [{"animation_name": "clip"}, {"animation_name": "second"}],
		"new_name": "combined", "gap": 0.25,
	}, null)
	assert_has_key(result, "data")
	assert_eq(str(result.data.new_name), "combined")
	assert_true(is_equal_approx(float(result.data.length), 1.75), "merge adds the gap")
	var merged := _fetch_anim(fixture.player_path, "combined")
	assert_true(merged != null, "the merged clip exists")
	assert_eq(merged.get_track_count(), 2, "merge unions the source tracks")
	_teardown(fixture)


# --- amplitude / loop / key_edit / cleanup ---------------------------------

func test_amplitude_scales_deltas() -> void:
	var fixture := _fixture("Amplitude")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "amplitude", "player_path": fixture.player_path, "animation_name": "clip",
		"factor": 0.5,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	var peak = anim.track_get_key_value(0, 1)
	assert_true(peak is Vector2 and (peak as Vector2).is_equal_approx(Vector2(5, 2)),
		"amplitude 0.5 should halve the delta, got %s" % str(peak))
	_teardown(fixture)


func test_loop_sets_mode_and_seam() -> void:
	var fixture := _fixture("Loop")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "loop", "player_path": fixture.player_path, "animation_name": "clip",
		"loop_mode": "linear", "make_seamless": true,
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR)
	var last = anim.track_get_key_value(0, anim.track_get_key_count(0) - 1)
	var first = anim.track_get_key_value(0, 0)
	assert_true((last as Vector2).is_equal_approx(first as Vector2),
		"make_seamless should copy the first value onto the final key")
	_teardown(fixture)


func test_key_edit_add_set_and_move() -> void:
	var fixture := _fixture("KeyEdit")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var added := _handler.run({
		"op": "key_edit", "player_path": fixture.player_path, "animation_name": "clip",
		"action": "add", "track_path": "KeyEditTarget:position", "time": 0.25,
		"value": {"x": 3, "y": 3},
	}, null)
	assert_has_key(added, "data")
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.track_get_key_count(0), 4, "key_edit add inserts a key")
	var inserted = anim.track_get_key_value(0, 1)
	assert_true(inserted is Vector2 and (inserted as Vector2).is_equal_approx(Vector2(3, 3)),
		"the added key should be a coerced Vector2, got %s" % str(inserted))
	var moved := _handler.run({
		"op": "key_edit", "player_path": fixture.player_path, "animation_name": "clip",
		"action": "move", "track_path": "KeyEditTarget:position", "time": 0.25, "new_time": 0.4,
	}, null)
	assert_has_key(moved, "data")
	anim = _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), 0.4), "key_edit move retimes the key")
	var removed := _handler.run({
		"op": "key_edit", "player_path": fixture.player_path, "animation_name": "clip",
		"action": "remove", "track_path": "KeyEditTarget:position", "time": 0.4,
	}, null)
	assert_has_key(removed, "data")
	anim = _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.track_get_key_count(0), 3, "key_edit remove drops the key")
	_teardown(fixture)


func test_cleanup_dedupes_holds() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var player_path := _add_player("EditPlayerCleanup")
	if player_path.is_empty():
		skip("Scene not ready")
		return
	var spec := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "CleanupTarget:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 1.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 1.5, "value": Vector2(5, 0), "transition": 1.0},
	])
	_add_clip(player_path, "clip", spec)
	var result := _handler.run({
		"op": "cleanup", "player_path": player_path, "animation_name": "clip",
	}, null)
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "clip")
	assert_eq(anim.track_get_key_count(0), 2, "cleanup keeps the hold end and the change")
	assert_true(is_equal_approx(anim.length, 2.0), "cleanup preserves the length")
	_remove_node(player_path)


# --- errors + undo ---------------------------------------------------------

func test_missing_clip_reports_available_names() -> void:
	var fixture := _fixture("Missing")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "reverse", "player_path": fixture.player_path, "animation_name": "nope",
	}, null)
	assert_is_error(result, ErrorCodes.INVALID_PARAMS)
	assert_contains(result.error.message, "Available")
	assert_contains(result.error.message, "clip")
	_teardown(fixture)


func test_unsupported_track_is_refused() -> void:
	var fixture := _fixture("Unsupported")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var anim := _fetch_anim(fixture.player_path, "clip")
	var bezier := anim.add_track(Animation.TYPE_BEZIER)
	anim.track_set_path(bezier, NodePath("UnsupportedTarget:value"))
	anim.bezier_track_insert_key(bezier, 0.0, 0.0)
	var result := _handler.run({
		"op": "reverse", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_is_error(result, ErrorCodes.WRONG_TYPE)
	assert_contains(result.error.message, "bezier")
	_teardown(fixture)


func test_undo_restores_the_original_clip() -> void:
	var fixture := _fixture("Undo")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "retime", "player_path": fixture.player_path, "animation_name": "clip", "factor": 0.5,
	}, null)
	assert_has_key(result, "data")
	assert_true(is_equal_approx(_fetch_anim(fixture.player_path, "clip").length, 0.5),
		"the edit should land")
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	var restored := _fetch_anim(fixture.player_path, "clip")
	assert_true(is_equal_approx(restored.length, 1.0), "one undo must restore the original length")
	assert_eq(restored.track_get_key_count(0), 3, "one undo must restore every key")
	var did_redo := editor_redo(_undo_redo)
	assert_true(did_redo, "redo should succeed")
	assert_true(is_equal_approx(_fetch_anim(fixture.player_path, "clip").length, 0.5),
		"redo should re-apply the edit")
	_teardown(fixture)


# --- registry --------------------------------------------------------------

func test_quality_passes_smooth_resample_noise_overlap_layer() -> void:
	var fixture := _fixture("QP")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var smoothed := _handler.run({
		"op": "smooth", "player_path": fixture.player_path, "animation_name": "clip",
		"strength": 0.5, "passes": 1,
	}, null)
	assert_true(smoothed.has("data"), "smooth: %s" % str(smoothed))
	var anim := _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.track_get_key_count(0), 3, "smooth keeps the key count")
	var mid: Vector2 = anim.track_get_key_value(0, 1)
	assert_true(mid.distance_to(Vector2(10, 2)) < 0.01, "smooth pulls the middle key toward its neighbours (got %s)" % mid)
	var resampled := _handler.run({
		"op": "resample", "player_path": fixture.player_path, "animation_name": "clip", "fps": 10.0,
	}, null)
	assert_true(resampled.has("data"), "resample: %s" % str(resampled))
	anim = _fetch_anim(fixture.player_path, "clip")
	assert_eq(anim.track_get_key_count(0), 11, "resample gives 11 keys for 1 s at 10 fps")
	var noised := _handler.run({
		"op": "add_noise", "player_path": fixture.player_path, "animation_name": "clip",
		"amount": 0.5, "frequency": 2.0, "seed": 3, "track_path": "QPTarget:position",
	}, null)
	assert_true(noised.has("data"), "add_noise: %s" % str(noised))
	var overlapped := _handler.run({
		"op": "overlap", "player_path": fixture.player_path, "animation_name": "clip",
		"track_path": "QPTarget:position", "delay": 0.1, "wrap": true,
	}, null)
	assert_true(overlapped.has("data"), "overlap: %s" % str(overlapped))
	var source := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(source, "QPTarget:modulate:a", [
		{"time": 0.0, "value": 1.0, "transition": 1.0},
		{"time": 1.0, "value": 1.0, "transition": 1.0},
	])
	_add_clip(fixture.player_path, "src", source)
	var layered := _handler.run({
		"op": "layer", "player_path": fixture.player_path, "animation_name": "clip",
		"source_animation": "src", "layer_mode": "mix", "weight": 0.5,
	}, null)
	assert_true(layered.has("data"), "layer: %s" % str(layered))
	anim = _fetch_anim(fixture.player_path, "clip")
	var modulate := -1
	for index in anim.get_track_count():
		if str(anim.track_get_path(index)).ends_with(":modulate:a"):
			modulate = index
	assert_true(modulate >= 0, "the modulate track survived every pass")
	assert_true(absf(float(anim.track_get_key_value(modulate, 0)) - 0.5) < 0.001,
		"layer mixed the base toward the source (got %s)" % anim.track_get_key_value(modulate, 0))
	var bad_mode := _handler.run({
		"op": "layer", "player_path": fixture.player_path, "animation_name": "clip",
		"source_animation": "src", "layer_mode": "multiply",
	}, null)
	assert_is_error(bad_mode, ErrorCodes.VALUE_OUT_OF_RANGE)
	var bad_delay := _handler.run({
		"op": "overlap", "player_path": fixture.player_path, "animation_name": "clip",
		"track_path": "QPTarget:position", "delay": 0.0,
	}, null)
	assert_is_error(bad_delay, ErrorCodes.MISSING_REQUIRED_PARAM)
	_teardown(fixture)


func test_registry_matches_edit_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_EDIT)
	assert_false(info.is_empty(), "the edit family is registered")
	var schema: Dictionary = info.schema
	var properties: Dictionary = schema.properties
	var op_enum: Array = properties.op.enum
	assert_eq(op_enum.size(), 19, "the edit schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the edit description fits the custom-tool cap")
