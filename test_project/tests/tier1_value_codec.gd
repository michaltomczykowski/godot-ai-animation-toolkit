extends SceneTree

## Tier-1 headless checks for the addon's pure helpers — no editor, no undo
## manager, no MCP. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_value_codec.gd
##
## (Named without the `test_` prefix so the editor suite runner ignores it.)

const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const Presets := preload("res://addons/godot_ai_animation/handlers/generate.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_transitions()
	_check_loop_modes()
	_check_serialize()
	_check_paths()
	_check_coercion()
	_check_builders()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_error(result: Dictionary, code: String, message: String) -> void:
	_checks += 1
	if not result.has("error"):
		_failures += 1
		print("  FAIL: %s (expected error, got %s)" % [message, str(result)])
		return
	if result.error.code != code:
		_failures += 1
		print("  FAIL: %s (expected %s, got %s)" % [message, code, result.error.code])


func _check_transitions() -> void:
	_expect(ValueCodec.parse_transition("linear") == 1.0, "linear -> 1.0")
	_expect(ValueCodec.parse_transition("ease_out") == 0.5, "ease_out -> 0.5")
	_expect(ValueCodec.parse_transition("ease_in") == 2.0, "ease_in -> 2.0")
	_expect(ValueCodec.parse_transition("ease_in_out") == -2.0, "ease_in_out -> -2.0")
	_expect(ValueCodec.parse_transition(0.25) == 0.25, "raw float passthrough")
	_expect(ValueCodec.parse_transition("wobble") == 1.0, "unknown name falls back to linear")


func _check_loop_modes() -> void:
	_expect(ValueCodec.loop_mode_to_string(Animation.LOOP_LINEAR) == "linear", "LOOP_LINEAR label")
	_expect(ValueCodec.loop_mode_to_string(Animation.LOOP_PINGPONG) == "pingpong", "LOOP_PINGPONG label")
	_expect(ValueCodec.loop_mode_to_string(Animation.LOOP_NONE) == "none", "LOOP_NONE label")


func _check_serialize() -> void:
	_expect(ValueCodec.serialize(null) == null, "null serializes to null")
	_expect(ValueCodec.serialize(1.5) == 1.5, "float passthrough")
	var color: Dictionary = ValueCodec.serialize(Color(0.1, 0.2, 0.3, 0.4))
	_expect(
		is_equal_approx(color.get("r"), 0.1) and is_equal_approx(color.get("a"), 0.4),
		"Color -> {r,g,b,a}",
	)
	var v2: Dictionary = ValueCodec.serialize(Vector2(3.0, 4.0))
	_expect(v2.get("x") == 3.0 and v2.get("y") == 4.0, "Vector2 -> {x,y}")
	var v3: Dictionary = ValueCodec.serialize(Vector3(3.0, 4.0, 5.0))
	_expect(v3.get("z") == 5.0, "Vector3 -> {x,y,z}")


func _check_paths() -> void:
	var root := Node.new()
	root.name = "Root"
	var child := Node.new()
	child.name = "Child"
	root.add_child(child)
	var grandchild := Node.new()
	grandchild.name = "Grand"
	child.add_child(grandchild)

	_expect(ValueCodec.resolve_scene_path("/", root) == root, "'/' resolves to the scene root")
	_expect(ValueCodec.resolve_scene_path("/Root", root) == root, "'/Root' resolves to the scene root")
	_expect(ValueCodec.resolve_scene_path("/Root/Child", root) == child, "absolute path")
	_expect(ValueCodec.resolve_scene_path("/root/Root/Child/Grand", root) == grandchild, "/root alias")
	_expect(ValueCodec.resolve_scene_path("Child/Grand", root) == grandchild, "relative path")
	_expect(ValueCodec.resolve_scene_path("/Root/Nope", root) == null, "missing node resolves to null")
	_expect(ValueCodec.format_node_error("/Root/Nope", root).contains("Nope"), "error names the node")
	_expect(ValueCodec.from_node(child, root) == "/Root/Child", "from_node builds a scene path")
	root.free()


func _check_coercion() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	var node2d := Node2D.new()
	node2d.name = "Node2D"
	var node3d := Node3D.new()
	node3d.name = "Node3D"

	var alpha := ValueCodec.coerce_for_property(0.2, sprite, "modulate:a")
	_expect(alpha.get("ok") == 0.2, "component subpath coerces to float")

	var color := ValueCodec.coerce_for_property({"r": 1.0, "g": 0.0, "b": 0.0}, sprite, "modulate")
	_expect(color.get("ok") is Color and (color.ok as Color).is_equal_approx(Color.RED), "Color dict")

	var named := ValueCodec.coerce_for_property("#00ff00", sprite, "modulate")
	_expect(named.get("ok") is Color and (named.ok as Color).is_equal_approx(Color.GREEN), "hex Color")

	var v2 := ValueCodec.coerce_for_property([1.0, 2.0], node2d, "position")
	_expect(v2.get("ok") == Vector2(1.0, 2.0), "array coerces to Vector2")

	var v3 := ValueCodec.coerce_for_property({"x": 1.0, "y": 2.0, "z": 3.0}, node3d, "position")
	_expect(v3.get("ok") == Vector3(1.0, 2.0, 3.0), "dict coerces to Vector3")

	_expect_error(ValueCodec.coerce_for_property("abc", node2d, "position"), "WRONG_TYPE", "garbage Vector2")
	_expect_error(ValueCodec.coerce_for_property(1.0, node2d, "wobble"), "PROPERTY_NOT_ON_CLASS", "unknown property")
	_expect_error(ValueCodec.coerce_for_property([1.0], node2d, "position"), "WRONG_TYPE", "short Vector2 array")

	sprite.free()
	node2d.free()
	node3d.free()


func _check_builders() -> void:
	## float: two Transform3D keys from the baseline, rising and scaling.
	var baseline := Transform3D(Basis(), Vector3(1.0, 2.0, 3.0))
	var float_keys: Array = Presets.build_float_keys(baseline, 0.5, 1.5, 0.5, 2.0)
	_expect(float_keys.size() == 2, "float builds two keys")
	_expect((float_keys[0].value as Transform3D).origin.is_equal_approx(Vector3(1.0, 2.0, 3.0)),
		"float starts at the baseline")
	var raised: Transform3D = float_keys[1].value
	_expect(raised.origin.is_equal_approx(Vector3(1.0, 2.5, 3.0)), "float rises by 'height'")
	_expect(absf(raised.basis.get_scale().x - 1.5) < 0.001, "float scales the baseline")

	## stagger: one [start, end] pair per target, length = (n-1)*stagger + duration.
	var times: Array = Presets.stagger_key_times(3, 0.1, 0.3)
	_expect(times.size() == 3, "stagger builds one time pair per target")
	_expect(absf(times[0][0]) < 1e-9 and absf(times[0][1] - 0.3) < 1e-9, "first target starts at 0")
	_expect(absf(times[1][0] - 0.1) < 1e-9, "second target is delayed by stagger")
	_expect(absf(times[2][0] - 0.2) < 1e-9, "third target is delayed by 2 * stagger")
	_expect(absf(Presets.stagger_length(3, 0.1, 0.3) - 0.5) < 1e-9,
		"stagger length is (n-1)*stagger + duration")
	_expect(Presets.stagger_length(0, 0.1, 0.3) == 0.0, "an empty stagger has zero length")
