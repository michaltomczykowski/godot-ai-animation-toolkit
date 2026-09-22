@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

const PresetsHandler := preload("res://addons/godot_ai_animation/handlers/presets.gd")

## Tests for the animation toolkit presets (pulse/bounce/orbit/sweep/drift).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: PresetsHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_presets"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = PresetsHandler.new()


func suite_teardown() -> void:
	pass


# --- helpers ---------------------------------------------------------------

## Add an AnimationPlayer (with a default library) to the scene root and return
## its path. Added directly, not through a tool, so no setup action lands on the
## undo stack and `editor_undo` only ever sees the preset's action.
func _add_player(player_name: String = "TestAnimPlayer") -> String:
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


## Add a sibling node to the scene_root. Presets resolve target_path against
## the player's root_node (the scene_root when the player lives directly under
## it), so target_path is just the sibling's name.
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


# --- rollup dispatch -------------------------------------------------------

func test_rollup_dispatches_and_rejects_unknown_op() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "RollupNode")
	var player_path := _add_player("TestRollup")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/RollupNode")
		skip("Scene not ready")
		return
	var unknown := _handler.run({"op": "wobble"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "pulse")
	var bounced := _handler.run({
		"op": "bounce", "player_path": player_path, "target_path": "RollupNode",
	}, null)
	assert_has_key(bounced, "data")
	assert_true(_fetch_anim(player_path, "bounce") != null, "the rollup must build the clip")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/RollupNode")


# --- pulse -----------------------------------------------------------------

func test_preset_pulse_2d_three_keyframes() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "Pulser")
	var player_path := _add_player("TestPresetPulse")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Pulser")
		skip("Scene not ready")
		return
	var result := _handler.preset_pulse({
		"player_path": player_path,
		"target_path": "Pulser",
		"from_scale": 1.0,
		"to_scale": 1.2,
		"duration": 0.4,
	})
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "pulse")
	assert_eq(anim.track_get_key_count(0), 3)
	var k0 = anim.track_get_key_value(0, 0)
	var k1 = anim.track_get_key_value(0, 1)
	var k2 = anim.track_get_key_value(0, 2)
	assert_true(k0 is Vector2 and k1 is Vector2 and k2 is Vector2,
		"2D pulse keyframes should be Vector2")
	## Vector2 components are float32 — compare approximately.
	assert_true(is_equal_approx((k0 as Vector2).x, 1.0))
	assert_true(is_equal_approx((k1 as Vector2).x, 1.2))
	assert_true(is_equal_approx((k2 as Vector2).x, 1.0))
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), 0.2), "peak sits at the midpoint")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Pulser")


func test_preset_pulse_3d_stores_vector3() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node3D.new(), "Pulse3D")
	var player_path := _add_player("TestPresetPulse3D")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Pulse3D")
		skip("Scene not ready")
		return
	_handler.preset_pulse({"player_path": player_path, "target_path": "Pulse3D"})
	var anim := _fetch_anim(player_path, "pulse")
	var peak = anim.track_get_key_value(0, 1)
	assert_true(peak is Vector3, "3D pulse peak should be Vector3, got %s" % typeof(peak))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Pulse3D")


func test_preset_pulse_accepts_scene_absolute_target() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "AbsPulser")
	var player_path := _add_player("TestPresetPulseAbs")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/AbsPulser")
		skip("Scene not ready")
		return
	var abs_target := "/" + scene_root.name + "/AbsPulser"
	var result := _handler.preset_pulse({"player_path": player_path, "target_path": abs_target})
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "pulse")
	assert_eq(String(anim.track_get_path(0)), "AbsPulser:scale",
		"absolute target_path must convert to a root_node-relative track path")
	_remove_node(player_path)
	_remove_node(abs_target)


func test_preset_pulse_property_modulate_alpha() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Sprite2D.new(), "PulseAlpha")
	var player_path := _add_player("TestPulseAlpha")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/PulseAlpha")
		skip("Scene not ready")
		return
	var result := _handler.preset_pulse({
		"player_path": player_path,
		"target_path": "PulseAlpha",
		"property": "modulate:a",
		"from_value": 0.2,
		"to_value": 1.0,
	})
	assert_has_key(result, "data")
	assert_eq(result.data.property, "modulate:a")
	var anim := _fetch_anim(player_path, "pulse")
	assert_eq(String(anim.track_get_path(0)), "PulseAlpha:modulate:a")
	var low = anim.track_get_key_value(0, 0)
	var high = anim.track_get_key_value(0, 1)
	assert_true(low is float, "modulate:a keys must be floats, got %s" % type_string(typeof(low)))
	assert_eq(low, 0.2)
	assert_eq(high, 1.0)
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/PulseAlpha")


func test_preset_pulse_property_position_vector2() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "PulsePos")
	var player_path := _add_player("TestPulsePos")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/PulsePos")
		skip("Scene not ready")
		return
	var result := _handler.preset_pulse({
		"player_path": player_path,
		"target_path": "PulsePos",
		"property": "position",
		"from_value": {"x": 0.0, "y": 0.0},
		"to_value": {"x": 10.0, "y": -4.0},
	})
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "pulse")
	var peak = anim.track_get_key_value(0, 1)
	assert_true(peak is Vector2, "position keys must be Vector2, got %s" % type_string(typeof(peak)))
	assert_eq(peak, Vector2(10.0, -4.0))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/PulsePos")


func test_preset_pulse_property_requires_values() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Sprite2D.new(), "PulseNoVals")
	var player_path := _add_player("TestPulseNoVals")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/PulseNoVals")
		skip("Scene not ready")
		return
	var result := _handler.preset_pulse({
		"player_path": player_path,
		"target_path": "PulseNoVals",
		"property": "modulate:a",
	})
	assert_is_error(result, ErrorCodes.MISSING_REQUIRED_PARAM)
	assert_contains(result.error.message, "from_value")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/PulseNoVals")


func test_preset_pulse_loop_mode_linear() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "PulseLoop")
	var player_path := _add_player("TestPulseLoop")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/PulseLoop")
		skip("Scene not ready")
		return
	var result := _handler.preset_pulse({
		"player_path": player_path,
		"target_path": "PulseLoop",
		"property": "modulate:a",
		"from_value": 0.4,
		"to_value": 1.0,
		"loop_mode": "linear",
	})
	assert_has_key(result, "data")
	assert_eq(result.data.loop_mode, "linear")
	var anim := _fetch_anim(player_path, "pulse")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR)
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/PulseLoop")


# --- shared behaviours -----------------------------------------------------

func test_preset_overwrite_required_for_second_call() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Sprite2D.new(), "OverwriteTarget")
	var player_path := _add_player("TestPresetOverwrite")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/OverwriteTarget")
		skip("Scene not ready")
		return
	var r1 := _handler.preset_pulse({"player_path": player_path, "target_path": "OverwriteTarget"})
	assert_has_key(r1, "data")
	## Second call with the same (auto-derived) name errors without overwrite.
	var r2 := _handler.preset_pulse({"player_path": player_path, "target_path": "OverwriteTarget"})
	assert_is_error(r2, ErrorCodes.INVALID_PARAMS)
	var r3 := _handler.preset_pulse({
		"player_path": player_path, "target_path": "OverwriteTarget",
		"overwrite": true, "duration": 0.25,
	})
	assert_has_key(r3, "data")
	assert_eq(r3.data.overwritten, true)
	assert_eq(r3.data.length, 0.25)
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/OverwriteTarget")


# --- bounce ----------------------------------------------------------------

func test_preset_bounce_shape_and_control_pivot() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var control: Control = _add_sibling(Control.new(), "BounceControl") as Control
	control.size = Vector2(120.0, 40.0)
	control.pivot_offset = Vector2.ZERO
	var player_path := _add_player("TestPresetBounce")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/BounceControl")
		skip("Scene not ready")
		return
	var result := _handler.preset_bounce({
		"player_path": player_path,
		"target_path": "BounceControl",
		"intensity": 0.2,
	})
	assert_has_key(result, "data")
	assert_true(result.data.pivot_recentered, "a Control bounce must recenter its pivot")
	var anim := _fetch_anim(player_path, "bounce")
	assert_eq(anim.get_track_count(), 1)
	assert_eq(anim.track_get_key_count(0), 4, "bounce must have 4 keyframes")
	var rest = anim.track_get_key_value(0, 0)
	var peak = anim.track_get_key_value(0, 1)
	assert_true(rest is Vector2, "Control scale keys must be Vector2")
	assert_eq(rest, Vector2.ONE)
	assert_true((peak as Vector2).x > 1.0, "peak must overshoot, got %s" % str(peak))
	assert_true(control.pivot_offset.is_equal_approx(Vector2(60.0, 20.0)),
		"pivot_offset must recenter to half the Control size, got %s" % str(control.pivot_offset))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/BounceControl")


func test_preset_bounce_undo_restores_pivot() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var control: Control = _add_sibling(Control.new(), "BounceUndo") as Control
	control.size = Vector2(80.0, 20.0)
	control.pivot_offset = Vector2(3.0, 4.0)
	var player_path := _add_player("TestPresetBounceUndo")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/BounceUndo")
		skip("Scene not ready")
		return
	var result := _handler.preset_bounce({"player_path": player_path, "target_path": "BounceUndo"})
	assert_has_key(result, "data")
	assert_true(control.pivot_offset.is_equal_approx(Vector2(40.0, 10.0)))
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(control.pivot_offset.is_equal_approx(Vector2(3.0, 4.0)),
		"one undo must restore the previous pivot_offset, got %s" % str(control.pivot_offset))
	var player := ValueCodec.resolve_scene_path(player_path, scene_root) as AnimationPlayer
	assert_false(player.has_animation("bounce"), "the same undo must remove the bounce clip")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/BounceUndo")


func test_preset_bounce_preserves_current_scale() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var node: Node3D = _add_sibling(Node3D.new(), "BounceScaled") as Node3D
	node.scale = Vector3(2.0, 3.0, 4.0)
	var player_path := _add_player("TestPresetBounceScaled")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/BounceScaled")
		skip("Scene not ready")
		return
	var result := _handler.preset_bounce({
		"player_path": player_path,
		"target_path": "BounceScaled",
		"intensity": 0.5,
	})
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "bounce")
	var rest = anim.track_get_key_value(0, 0)
	var peak = anim.track_get_key_value(0, 1)
	assert_true(rest is Vector3, "3D bounce keys must be Vector3")
	assert_true((rest as Vector3).is_equal_approx(Vector3(2.0, 3.0, 4.0)),
		"bounce must start from the target's current scale, got %s" % str(rest))
	assert_true((peak as Vector3).is_equal_approx(Vector3(3.0, 4.5, 6.0)),
		"peak must scale the current baseline, got %s" % str(peak))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/BounceScaled")


func test_preset_bounce_rejects_bad_intensity() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "BounceBad")
	var player_path := _add_player("TestPresetBounceBad")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/BounceBad")
		skip("Scene not ready")
		return
	var result := _handler.preset_bounce({
		"player_path": player_path,
		"target_path": "BounceBad",
		"intensity": 0.0,
	})
	assert_is_error(result, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(result.error.message, "intensity")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/BounceBad")


# --- orbit -----------------------------------------------------------------

func test_preset_orbit_circle_is_seamless() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var node: Node2D = _add_sibling(Node2D.new(), "OrbitNode") as Node2D
	node.position = Vector2(5.0, 7.0)
	var player_path := _add_player("TestPresetOrbit")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/OrbitNode")
		skip("Scene not ready")
		return
	var result := _handler.preset_orbit({
		"player_path": player_path,
		"target_path": "OrbitNode",
		"radius": 50.0,
		"duration": 2.0,
		"loop_mode": "linear",
	})
	assert_has_key(result, "data")
	assert_eq(result.data.radius, 50.0)
	var anim := _fetch_anim(player_path, "orbit")
	assert_eq(anim.track_get_key_count(0), 17, "orbit must sample 16 angular segments")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR)
	var first = anim.track_get_key_value(0, 0)
	var last = anim.track_get_key_value(0, 16)
	var quarter = anim.track_get_key_value(0, 4)
	var eighth = anim.track_get_key_value(0, 2)
	assert_true(first is Vector2, "orbit keys must be Vector2")
	assert_true((first as Vector2).is_equal_approx(last as Vector2), "orbit must be seamless")
	assert_true((quarter as Vector2).is_equal_approx(Vector2(5.0, 57.0)),
		"a quarter turn must be radius above the center, got %s" % str(quarter))
	## The 45-degree sample must sit on the circle, not on the diamond chord a
	## four-key version would trace.
	assert_true(
		(eighth as Vector2).is_equal_approx(Vector2(5.0 + 50.0 * sqrt(0.5), 7.0 + 50.0 * sqrt(0.5))),
		"a 45-degree sample must lie on the circle, got %s" % str(eighth)
	)
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/OrbitNode")


# --- sweep -----------------------------------------------------------------

func test_preset_sweep_control_pivot_and_rotation() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var control: Control = _add_sibling(Control.new(), "SweepControl") as Control
	control.size = Vector2(60.0, 60.0)
	control.pivot_offset = Vector2.ZERO
	var player_path := _add_player("TestPresetSweep")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/SweepControl")
		skip("Scene not ready")
		return
	var result := _handler.preset_sweep({
		"player_path": player_path,
		"target_path": "SweepControl",
		"turns": 1.0,
	})
	assert_has_key(result, "data")
	assert_true(result.data.pivot_recentered)
	var anim := _fetch_anim(player_path, "sweep")
	assert_eq(String(anim.track_get_path(0)), "SweepControl:rotation")
	var end_value = anim.track_get_key_value(0, 1)
	assert_true(end_value is float, "Control rotation keys must be floats")
	assert_true(absf(float(end_value) - TAU) < 0.0001, "one turn must sweep TAU radians, got %s" % str(end_value))
	assert_true(control.pivot_offset.is_equal_approx(Vector2(30.0, 30.0)))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/SweepControl")


func test_preset_sweep_preserves_current_rotation() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var node: Node3D = _add_sibling(Node3D.new(), "SweepRotated") as Node3D
	node.rotation.y = 0.5
	var player_path := _add_player("TestPresetSweepRotated")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/SweepRotated")
		skip("Scene not ready")
		return
	var result := _handler.preset_sweep({"player_path": player_path, "target_path": "SweepRotated"})
	assert_has_key(result, "data")
	assert_true(absf(float(result.data.start_rotation) - 0.5) < 0.0001,
		"the response must report the starting rotation, got %s" % str(result.data.start_rotation))
	var anim := _fetch_anim(player_path, "sweep")
	var start = anim.track_get_key_value(0, 0)
	var end = anim.track_get_key_value(0, 1)
	assert_true(absf(float(start) - 0.5) < 0.0001,
		"sweep must start at the current rotation, got %s" % str(start))
	assert_true(absf(float(end) - (0.5 + TAU)) < 0.0001,
		"sweep must add a full turn to the current rotation, got %s" % str(end))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/SweepRotated")


func test_preset_sweep_3d_rotates_local_y() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node3D.new(), "Sweep3D")
	var player_path := _add_player("TestPresetSweep3D")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Sweep3D")
		skip("Scene not ready")
		return
	var result := _handler.preset_sweep({
		"player_path": player_path,
		"target_path": "Sweep3D",
		"clockwise": false,
	})
	assert_has_key(result, "data")
	var anim := _fetch_anim(player_path, "sweep")
	assert_eq(String(anim.track_get_path(0)), "Sweep3D:rotation:y")
	var end_value = anim.track_get_key_value(0, 1)
	assert_true(absf(float(end_value) + TAU) < 0.0001,
		"counter-clockwise one turn must sweep -TAU, got %s" % str(end_value))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Sweep3D")


# --- drift -----------------------------------------------------------------

func test_preset_drift_axis_and_loop() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var node: Node3D = _add_sibling(Node3D.new(), "DriftNode") as Node3D
	node.position = Vector3(1.0, 0.0, 0.0)
	var player_path := _add_player("TestPresetDrift")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/DriftNode")
		skip("Scene not ready")
		return
	var result := _handler.preset_drift({
		"player_path": player_path,
		"target_path": "DriftNode",
		"axis": "z",
		"distance": 2.0,
		"loop_mode": "pingpong",
	})
	assert_has_key(result, "data")
	assert_eq(result.data.axis, "z")
	var anim := _fetch_anim(player_path, "drift")
	assert_eq(anim.loop_mode, Animation.LOOP_PINGPONG)
	var start = anim.track_get_key_value(0, 0)
	var end = anim.track_get_key_value(0, 1)
	assert_true(start is Vector3 and end is Vector3, "drift keys must be Vector3")
	assert_eq(start, Vector3(1, 0, 0))
	assert_eq(end, Vector3(1, 0, 2))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/DriftNode")


func test_preset_drift_rejects_bad_axis_and_loop_mode() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Sprite2D.new(), "DriftBad")
	var player_path := _add_player("TestPresetDriftBad")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/DriftBad")
		skip("Scene not ready")
		return
	var bad_axis := _handler.preset_drift({
		"player_path": player_path,
		"target_path": "DriftBad",
		"axis": "z",
	})
	assert_is_error(bad_axis, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(bad_axis.error.message, "Invalid axis")
	var bad_loop := _handler.preset_drift({
		"player_path": player_path,
		"target_path": "DriftBad",
		"axis": "x",
		"loop_mode": "bogus",
	})
	assert_is_error(bad_loop, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(bad_loop.error.message, "Invalid loop_mode")
	## A net-offset drift must not loop linearly (it would snap back each cycle).
	var linear_loop := _handler.preset_drift({
		"player_path": player_path,
		"target_path": "DriftBad",
		"axis": "x",
		"loop_mode": "linear",
	})
	assert_is_error(linear_loop, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(linear_loop.error.message, "pingpong")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/DriftBad")


# --- spin ------------------------------------------------------------------

func test_preset_spin_quarter_turn_quaternions() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node3D.new(), "Spin3D")
	var player_path := _add_player("TestPresetSpin")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Spin3D")
		skip("Scene not ready")
		return
	var result := _handler.preset_spin({
		"player_path": player_path,
		"target_path": "Spin3D",
		"loop_mode": "linear",
	})
	assert_has_key(result, "data")
	assert_eq(result.data.loop_mode, "linear")
	var anim := _fetch_anim(player_path, "spin")
	assert_eq(anim.track_get_key_count(0), 5, "one turn must sample four quarter turns")
	assert_eq(String(anim.track_get_path(0)), "Spin3D:quaternion")
	assert_eq(anim.loop_mode, Animation.LOOP_LINEAR)
	var first = anim.track_get_key_value(0, 0)
	var quarter = anim.track_get_key_value(0, 1)
	var last = anim.track_get_key_value(0, 4)
	assert_true(first is Quaternion, "spin keys must be Quaternion")
	assert_true((quarter as Quaternion).is_equal_approx(Quaternion(Vector3.UP, PI * 0.5)),
		"the second key must be a quarter turn, got %s" % str(quarter))
	## The closing key is the same rotation as the first (q == -q is the same
	## rotation, so accept either sign).
	assert_true(
		(last as Quaternion).is_equal_approx(first as Quaternion)
			or (last as Quaternion).is_equal_approx(-(first as Quaternion)),
		"spin must close seamlessly, got %s" % str(last)
	)

	## Control/2D targets are refused — sweep is the in-plane equivalent.
	_add_sibling(Node2D.new(), "Spin2D")
	var rejected := _handler.preset_spin({"player_path": player_path, "target_path": "Spin2D"})
	assert_is_error(rejected, ErrorCodes.WRONG_TYPE)
	assert_contains(rejected.error.message, "sweep")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Spin3D")
	_remove_node("/" + scene_root.name + "/Spin2D")


# --- showcase --------------------------------------------------------------

func test_preset_showcase_builds_and_undoes_a_runnable_demo() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_undo_redo.clear_history()
	var result := _handler.preset_showcase({"name": "PresetShowcase"})
	assert_has_key(result, "data")
	assert_eq(result.data.animations, 6, "the demo must build one clip per preset")
	var showcase := ValueCodec.resolve_scene_path(result.data.path, scene_root)
	assert_true(showcase != null, "the demo subtree must exist")
	assert_eq(showcase.owner, scene_root, "the subtree must be owned so the scene can save it")
	var float_cube := showcase.get_node_or_null("World3D/FloatCube") as MeshInstance3D
	assert_true(float_cube != null, "the demo must include the 3D float cube")
	var float_player := showcase.get_node_or_null("AnimFloat") as AnimationPlayer
	assert_true(float_player != null and float_player.has_animation("float"),
		"the demo must autoplay the float clip")
	for player_name in result.data.players:
		var player := showcase.get_node_or_null(str(player_name)) as AnimationPlayer
		assert_true(player != null, "%s must exist" % player_name)
		if player == null:
			continue
		assert_eq(player.get_animation_list().size(), 1, "%s must carry one clip" % player_name)
		assert_false(player.autoplay.is_empty(), "%s must autoplay its clip" % player_name)
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "one undo must remove the whole demo")
	assert_true(
		ValueCodec.resolve_scene_path(result.data.path, scene_root) == null,
		"the demo subtree must be gone after undo"
	)
	## A second showcase with the same name is refused while the node exists.
	var again := _handler.preset_showcase({"name": "PresetShowcase"})
	assert_has_key(again, "data")
	var duplicate := _handler.preset_showcase({"name": "PresetShowcase"})
	assert_is_error(duplicate, ErrorCodes.INVALID_PARAMS)
	_remove_node(again.data.path)


# --- float -----------------------------------------------------------------

func test_preset_float_bob_scale_and_turn() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var node: Node3D = _add_sibling(Node3D.new(), "Float3D") as Node3D
	node.position = Vector3(1.0, 2.0, 3.0)
	node.scale = Vector3(2.0, 2.0, 2.0)
	var player_path := _add_player("TestPresetFloat")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Float3D")
		skip("Scene not ready")
		return
	var result := _handler.preset_float({
		"player_path": player_path,
		"target_path": "Float3D",
		"height": 0.5,
		"scale": 1.5,
		"turns": 0.5,
		"duration": 2.0,
		"loop_mode": "pingpong",
	})
	assert_has_key(result, "data")
	assert_eq(result.data.loop_mode, "pingpong")
	var anim := _fetch_anim(player_path, "float")
	assert_eq(anim.track_get_key_count(0), 2)
	assert_eq(String(anim.track_get_path(0)), "Float3D:transform")
	var first = anim.track_get_key_value(0, 0)
	var last = anim.track_get_key_value(0, 1)
	assert_true(first is Transform3D and last is Transform3D, "float keys must be Transform3D")
	assert_true((first as Transform3D).origin.is_equal_approx(Vector3(1.0, 2.0, 3.0)),
		"the first key must be the baseline transform, got %s" % str(first))
	assert_true((last as Transform3D).origin.is_equal_approx(Vector3(1.0, 2.5, 3.0)),
		"the last key must rise by 'height', got %s" % str(last))
	assert_true(absf((last as Transform3D).basis.get_scale().x - 3.0) < 0.001,
		"the last key must scale the baseline by 'scale', got %s" % str((last as Transform3D).basis.get_scale()))
	## Midpoint through the engine's own interpolation: half the rise, half the
	## scale, half the turn.
	var mid: Transform3D = anim.value_track_interpolate(0, 1.0)
	assert_true(absf(mid.origin.y - 2.25) < 0.001, "midpoint must be half-raised, got %s" % str(mid.origin))
	assert_true(absf(mid.basis.get_scale().x - 2.5) < 0.001,
		"midpoint must be half-scaled, got %s" % str(mid.basis.get_scale()))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Float3D")


func test_preset_float_rejects_2d_and_linear_loop() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "Float2D")
	var player_path := _add_player("TestPresetFloatBad")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Float2D")
		skip("Scene not ready")
		return
	var wrong_kind := _handler.preset_float({"player_path": player_path, "target_path": "Float2D"})
	assert_is_error(wrong_kind, ErrorCodes.WRONG_TYPE)
	assert_contains(wrong_kind.error.message, "pulse")
	var linear_loop := _handler.preset_float({
		"player_path": player_path, "target_path": "Float2D", "loop_mode": "linear",
	})
	assert_is_error(linear_loop, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(linear_loop.error.message, "pingpong")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Float2D")


# --- stagger ---------------------------------------------------------------

func test_preset_stagger_offsets_and_length() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var first: Node2D = _add_sibling(Node2D.new(), "StaggerA") as Node2D
	var second: Node2D = _add_sibling(Node2D.new(), "StaggerB") as Node2D
	var third: Node2D = _add_sibling(Node2D.new(), "StaggerC") as Node2D
	second.position = Vector2(10.0, 0.0)
	var player_path := _add_player("TestPresetStagger")
	if player_path.is_empty():
		for name in ["StaggerA", "StaggerB", "StaggerC"]:
			_remove_node("/" + scene_root.name + "/" + name)
		skip("Scene not ready")
		return
	var result := _handler.preset_stagger({
		"player_path": player_path,
		"target_paths": ["StaggerA", "StaggerB", "StaggerC"],
		"effect": "slide_in",
		"direction": "left",
		"distance": 50.0,
		"stagger": 0.1,
		"duration": 0.3,
	})
	assert_has_key(result, "data")
	assert_eq(result.data.target_count, 3)
	assert_true(absf(float(result.data.length) - 0.5) < 0.0001,
		"length must be (n-1)*stagger + duration, got %s" % str(result.data.length))
	var anim := _fetch_anim(player_path, "stagger")
	assert_eq(anim.get_track_count(), 3)
	assert_eq(anim.loop_mode, Animation.LOOP_NONE)
	assert_eq(String(anim.track_get_path(0)), "StaggerA:position")
	assert_true(absf(anim.track_get_key_time(0, 0) - 0.0) < 0.0001)
	assert_true(absf(anim.track_get_key_time(0, 1) - 0.3) < 0.0001)
	assert_true((anim.track_get_key_value(0, 0) as Vector2).is_equal_approx(Vector2(-50.0, 0.0)),
		"slide_in must start one distance to the left, got %s" % str(anim.track_get_key_value(0, 0)))
	assert_true((anim.track_get_key_value(0, 1) as Vector2).is_equal_approx(Vector2.ZERO))
	assert_true(absf(anim.track_get_key_time(1, 0) - 0.1) < 0.0001,
		"the second target must be delayed by 'stagger'")
	assert_true((anim.track_get_key_value(1, 1) as Vector2).is_equal_approx(Vector2(10.0, 0.0)),
		"each target must land on its own baseline")
	assert_true(absf(anim.track_get_key_time(2, 0) - 0.2) < 0.0001,
		"the third target must be delayed by 2 * stagger")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/StaggerA")
	_remove_node("/" + scene_root.name + "/StaggerB")
	_remove_node("/" + scene_root.name + "/StaggerC")


func test_preset_stagger_effects_fade_and_pop() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var sprite: Sprite2D = _add_sibling(Sprite2D.new(), "StaggerFade") as Sprite2D
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.5)
	var popper: Node2D = _add_sibling(Node2D.new(), "StaggerPop") as Node2D
	popper.scale = Vector2(2.0, 2.0)
	var player_path := _add_player("TestPresetStaggerEffects")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/StaggerFade")
		_remove_node("/" + scene_root.name + "/StaggerPop")
		skip("Scene not ready")
		return
	var fade := _handler.preset_stagger({
		"player_path": player_path,
		"target_paths": ["StaggerFade"],
		"effect": "fade_in",
	})
	assert_has_key(fade, "data")
	var fade_anim := _fetch_anim(player_path, "stagger")
	assert_eq(String(fade_anim.track_get_path(0)), "StaggerFade:modulate:a")
	assert_eq(fade_anim.track_get_key_value(0, 0), 0.0)
	assert_true(absf(float(fade_anim.track_get_key_value(0, 1)) - 0.5) < 0.0001,
		"fade_in must land on the target's current alpha")
	var pop := _handler.preset_stagger({
		"player_path": player_path,
		"target_paths": ["StaggerPop"],
		"effect": "pop_in",
		"overwrite": true,
	})
	assert_has_key(pop, "data")
	assert_eq(pop.data.overwritten, true)
	var pop_anim := _fetch_anim(player_path, "stagger")
	assert_eq(String(pop_anim.track_get_path(0)), "StaggerPop:scale")
	assert_true((pop_anim.track_get_key_value(0, 0) as Vector2).is_equal_approx(Vector2(1.2, 1.2)),
		"pop_in must start at 0.6x the baseline, got %s" % str(pop_anim.track_get_key_value(0, 0)))
	assert_true((pop_anim.track_get_key_value(0, 1) as Vector2).is_equal_approx(Vector2(2.0, 2.0)))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/StaggerFade")
	_remove_node("/" + scene_root.name + "/StaggerPop")


func test_preset_stagger_rejects_bad_input() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node3D.new(), "Stagger3D")
	var player_path := _add_player("TestPresetStaggerBad")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/Stagger3D")
		skip("Scene not ready")
		return
	_undo_redo.clear_history()
	var empty := _handler.preset_stagger({"player_path": player_path, "target_paths": []})
	assert_is_error(empty, ErrorCodes.MISSING_REQUIRED_PARAM)
	var duplicate := _handler.preset_stagger({
		"player_path": player_path, "target_paths": ["Stagger3D", "Stagger3D"],
	})
	assert_is_error(duplicate, ErrorCodes.INVALID_PARAMS)
	assert_contains(duplicate.error.message, "Duplicate")
	var bad_effect := _handler.preset_stagger({
		"player_path": player_path, "target_paths": ["Stagger3D"], "effect": "explode",
	})
	assert_is_error(bad_effect, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(bad_effect.error.message, "fade_in")
	var fade_on_3d := _handler.preset_stagger({
		"player_path": player_path, "target_paths": ["Stagger3D"], "effect": "fade_in",
	})
	assert_is_error(fade_on_3d, ErrorCodes.WRONG_TYPE)
	assert_contains(fade_on_3d.error.message, "CanvasItem")
	var bad_direction := _handler.preset_stagger({
		"player_path": player_path, "target_paths": ["Stagger3D"],
		"effect": "slide_in", "direction": "sideways",
	})
	assert_is_error(bad_direction, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_false(editor_undo(_undo_redo), "a refused stagger must not commit an undo action")
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/Stagger3D")


func test_preset_stagger_from_selection() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	var first: Node2D = _add_sibling(Node2D.new(), "SelA") as Node2D
	var second: Node2D = _add_sibling(Node2D.new(), "SelB") as Node2D
	var player_path := _add_player("TestPresetStaggerSel")
	if player_path.is_empty():
		_remove_node("/" + scene_root.name + "/SelA")
		_remove_node("/" + scene_root.name + "/SelB")
		skip("Scene not ready")
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(first)
	selection.add_node(second)
	var result := _handler.preset_stagger({
		"player_path": player_path,
		"use_selection": true,
		"effect": "pop_in",
	})
	selection.clear()
	assert_has_key(result, "data")
	assert_eq(result.data.target_count, 2)
	var anim := _fetch_anim(player_path, "stagger")
	assert_eq(anim.get_track_count(), 2)
	var targets: Array = result.data.targets
	assert_true(targets.has("SelA") and targets.has("SelB"),
		"both selected nodes must be animated, got %s" % str(targets))
	_remove_node(player_path)
	_remove_node("/" + scene_root.name + "/SelA")
	_remove_node("/" + scene_root.name + "/SelB")
