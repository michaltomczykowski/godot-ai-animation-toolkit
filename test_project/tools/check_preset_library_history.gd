extends SceneTree

## Expected values are authored independently of handlers, SpecIO and snapshots.
const OPS := ["pulse", "bounce", "orbit", "sweep", "drift", "spin", "float", "stagger", "template_preset", "template_fx", "spec_apply"]
var failures: Array = []
var saved_states := 0
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
func _initialize() -> void: _probe.call_deferred()
func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2 and b is Vector2: return a.distance_to(b) < 0.001
	if a is Vector3 and b is Vector3: return a.distance_to(b) < 0.001
	if a is Quaternion and b is Quaternion: return a.angle_to(b) < 0.002
	if a is Color and b is Color: return a.is_equal_approx(b)
	if a is float or a is int: return absf(float(a) - float(b)) < 0.001
	return a == b
func _check(target: Node, property: String, expected: Variant, label: String) -> void:
	var actual: Variant = target.get_indexed(NodePath(property))
	if not _same(actual, expected): failures.append({"case": label, "property": property, "actual": str(actual), "expected": str(expected)})
func _play(player: AnimationPlayer, name: String, time: float) -> bool:
	if not player.has_animation(name):
		failures.append("missing clip " + name)
		return false
	player.stop()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(name)
	player.seek(time, true)
	player.advance(0.0)
	return true
func _load_state(label: String) -> Node:
	var path := "user://preset_library_history_%s.tscn" % label
	if not ResourceLoader.exists(path):
		failures.append(label + " missing scene")
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		failures.append(label + " invalid scene")
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	saved_states += 1
	return scene
func _case(mode: String, op: String, state: String) -> void:
	var label := "%s_%s_%s" % [mode, op, state]
	var scene := _load_state(label)
	if scene == null: return
	var fixture := scene.get_node("PresetHistory")
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var widget := fixture.get_node("Widget")
	var target := fixture.get_node("Target3D")
	_check(widget, "pivot_offset", Vector2(60, 30) if state == "redo" and op in ["bounce", "sweep", "template_preset"] else Vector2(7, 9), label)
	if state == "undo":
		if mode == "overwrite":
			if _play(player, "generated", 0.5): _check(widget, "position:x", 20.0, label)
		elif player.has_animation("generated"): failures.append(label + " undone clip still present")
	else:
		match op:
			"pulse":
				if _play(player, "generated", 0.5): _check(target, "scale", Vector3(1.4, 1.4, 1.4), label)
			"bounce", "template_preset":
				if _play(player, "generated", 0.35): _check(widget, "scale", Vector2(2.4, 2.4), label)
			"orbit":
				if _play(player, "generated", 0.25): _check(target, "position", Vector3(2, 3, 6), label)
			"sweep":
				if _play(player, "generated", 0.25): _check(widget, "rotation", PI / 2, label)
			"drift":
				if _play(player, "generated", 0.5): _check(target, "position", Vector3(4, 3, 4), label)
			"spin":
				if _play(player, "generated", 0.25): _check(target, "quaternion", Quaternion(Vector3.UP, PI / 2), label)
			"float":
				if _play(player, "generated", 0.5):
					_check(target, "position", Vector3(2, 4, 4), label)
					_check(target, "scale", Vector3(1.25, 1.25, 1.25), label)
			"stagger":
				if _play(player, "generated", 0.5):
					# Authored ease-out: 1 - (1 - fraction)^2, including delay.
					_check(widget, "modulate:a", 0.75, label)
					_check(fixture.get_node("OtherWidget"), "modulate:a", 0.51, label)
			"template_fx":
				if _play(player, "generated", 0.5): _check(widget, "modulate", Color(1, 0, 0, 1), label)
			"spec_apply":
				if _play(player, "generated", 0.5): _check(widget, "position:x", 20.0, label)
	if mode != "missing_library":
		if _play(player, "unrelated", 0.5): _check(widget, "position:x", 20.0, label + " unrelated")
	var other := fixture.get_node("OtherPlayer") as AnimationPlayer
	player.stop()
	if _play(other, "unrelated", 0.5): _check(widget, "position:x", 20.0, label + " other")
	scene.free()
func _showcase(mode: String, state: String) -> void:
	var label := "showcase_%s_%s" % [mode, state]
	var scene := _load_state(label)
	if scene == null: return
	var showcase := scene.get_node_or_null("ReviewShowcase" if mode == "root" else "PresetHistory/ReviewShowcase")
	if state == "undo":
		if showcase != null: failures.append(label + " undone subtree present")
	elif showcase == null: failures.append(label + " missing subtree")
	else:
		var checks := [
			["AnimBounce", "bounce", 0.14, "BounceButton", "scale", Vector2(1.15, 1.15)],
			["AnimOrbit", "orbit", 0.75, "OrbitDot", "position", Vector2(900, 210)],
			["AnimSweep", "sweep", 0.5, "SweepPivot", "rotation", PI / 2],
			["AnimDrift", "drift", 1.0, "DriftLine", "position:x", 860.0],
			["AnimPulse", "pulse", 0.6, "PulseLabel", "modulate:a", 1.0],
			["AnimFloat", "float", 1.2, "World3D/FloatCube", "position:y", 0.35],
			["AnimSpin", "spin", 0.75, "World3D/SpinCube", "quaternion", Quaternion(Vector3.UP, PI / 2)],
		]
		for check in checks:
			var player := showcase.get_node_or_null(check[0]) as AnimationPlayer
			if player == null: failures.append(label + " missing player " + check[0])
			elif player.autoplay != check[1]: failures.append(label + " lost autoplay " + check[0])
			elif _play(player, check[1], check[2]): _check(showcase.get_node(check[3]), check[4], check[5], label + " " + check[0])
	scene.free()
func _typed(kind: String, state: String) -> void:
	var label := "typed_%s_%s" % [kind, state]
	var scene := _load_state(label)
	if scene == null: return
	var fixture := scene.get_node("LibraryContracts")
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var name := "copy" if state == "redo" else "typed"
	if kind == "cues":
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
		player.play(name)
		player.advance(0.01)
		if fixture.get_node("Widget").get_meta("cue", 0) != 42: failures.append(label + " method did not fire")
		if not fixture.get_node("Audio").is_playing(): failures.append(label + " audio did not start")
	elif _play(player, name, 0.5):
		match kind:
			"2d":
				_check(fixture.get_node("Widget"), "position", Vector2(20, 30), label)
				_check(fixture.get_node("Widget"), "visible", false, label)
				_check(fixture.get_node("Widget"), "tooltip_text", "first", label)
			"3d":
				_check(fixture.get_node("Target3D"), "position", Vector3(3, 4, 5), label)
				_check(fixture.get_node("Target3D"), "scale", Vector3(1.5, 1.5, 1.5), label)
				_check(fixture.get_node("Target3D"), "quaternion", Quaternion(Vector3.UP, PI / 4), label)
			"transform":
				_check(fixture.get_node("Target3D"), "position", Vector3(2, 4, 4), label)
				_check(fixture.get_node("Target3D"), "scale", Vector3(1.5, 1.5, 1.5), label)
	scene.free()
func _probe() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	var args := OS.get_cmdline_user_args()
	if args.size() != 1: failures.append("one layout required")
	elif args[0] == "showcase":
		for mode in ["root", "local", "instanced", "editable"]:
			for state in ["undo", "redo"]: _showcase(mode, state)
	elif args[0] == "typed":
		for kind in ["2d", "3d", "transform", "cues"]:
			for state in ["undo", "redo"]: _typed(kind, state)
	elif args[0] in ["local", "overwrite", "missing_library", "instanced", "editable"]:
		for op in OPS:
			for state in ["undo", "redo"]: _case(args[0], op, state)
	else: failures.append("unknown layout")
	OS.remove_logger(logger)
	print("PRESET_LIBRARY_HISTORY_RUNTIME=" + JSON.stringify({"saved_states": saved_states, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
