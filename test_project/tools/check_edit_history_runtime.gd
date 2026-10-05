extends SceneTree

## Batch saved undo/redo states in a fresh engine. Expected values are authored
## here, independently of the edit modifiers and the editor's snapshots.
const OPS := ["retime", "reverse", "mirror", "trim", "amplitude", "resample", "layer", "offset", "loop", "key_edit", "overlap", "retarget", "ease_range", "set_interp", "split_at", "merge", "cleanup", "smooth", "reduce", "add_noise"]
var failures: Array = []
var saved_states := 0

class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)

func _initialize() -> void: _probe.call_deferred()

func _checks(op: String, variant: String, state: String) -> Array:
	if state == "undo":
		if op == "cleanup": return [["idle", 0.5, "Character", "x", 0.0]]
		if op == "smooth": return [["jump", 0.5, "Character", "y", -80.0]]
		if variant == "overwrite":
			return [["walk_head" if op == "split_at" else "walk_run", 0.4, "Character", "x", 832.5], ["walk", 0.5, "Character", "x", 50.0]]
		return [["walk", 0.5, "Character", "x", 50.0]]
	match op:
		"retime": return [["walk", 0.25, "Character", "x", 50.0]]
		"reverse": return [["walk", 0.25, "Character", "x", 75.0]]
		"mirror": return [["walk", 0.5, "Character", "x", -50.0]]
		"trim": return [["walk", 0.3, "Character", "x", 50.0]]
		"amplitude": return [["walk", 0.5, "Character", "x", 25.0]]
		"resample", "reduce", "loop": return [["walk", 0.25, "Character", "x", 25.0], ["walk", 0.75, "Character", "x", 75.0]]
		"layer": return [["walk", 0.5, "Character", "x", 90.0]]
		"offset": return [["walk", 0.5, "Character", "x", 30.0]]
		"key_edit": return [["walk", 0.5, "Character", "x", 15.0]]
		"overlap": return [["walk", 0.5, "Character", "x", 40.0]]
		"retarget": return [["walk", 0.5, "OtherCharacter", "x", 50.0], ["walk", 0.5, "Character", "x", 0.0]]
		"ease_range": return [["walk", 0.25, "Character", "x", 6.25], ["walk", 0.5, "Character", "x", 25.0]]
		"set_interp": return [["walk", 0.75, "Character", "x", 0.0]]
		"split_at": return [["walk_head", 0.25, "Character", "x", 25.0], ["walk", 0.25, "Character", "x", 75.0]]
		"merge": return [["walk_run", 0.5, "Character", "x", 50.0], ["walk_run", 1.5, "Character", "x", 100.0]]
		"cleanup": return [["idle", 0.5, "Character", "x", 0.0]]
		"smooth": return [["jump", 0.0, "Character", "y", -20.0], ["jump", 0.5, "Character", "y", -40.0]]
		"add_noise": return [["walk", 0.0, "Character", "x", -0.9593609], ["walk", 0.0, "Character", "y", -0.5208515]]
	return []

func _state(mode: String, op: String, variant: String, state: String) -> void:
	var label := "%s_%s_%s_%s" % [mode, op, variant, state]
	var path := "user://edit_history_%s.tscn" % label
	if not ResourceLoader.exists(path):
		failures.append(label + " missing scene")
		return
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		failures.append(label + " cannot load scene")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var fixture := scene.get_node("EditHistory")
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var checks := _checks(op, variant, state)
	if checks.is_empty(): failures.append(label + " no expectations")
	# Unrelated/source clips must also still play in each persisted state.
	checks.append(["run", 0.5, "Character", "x", 100.0])
	for check in checks:
		player.stop()
		fixture.get_node("Character").position = Vector2.ZERO
		fixture.get_node("OtherCharacter").position = Vector2.ZERO
		if not player.has_animation(check[0]):
			failures.append(label + " missing " + str(check[0]))
			continue
		player.play(check[0])
		player.seek(float(check[1]), true)
		player.advance(0.0)
		var measured: Vector2 = fixture.get_node(check[2]).position
		var value: float = measured.x if check[3] == "x" else measured.y
		if absf(value - float(check[4])) > 0.02:
			failures.append({"case": label, "check": check, "measured": value})
	player.stop()
	var other := fixture.get_node("OtherPlayer") as AnimationPlayer
	other.play("run")
	other.seek(0.5, true)
	other.advance(0.0)
	if absf(fixture.get_node("Character").position.x - 100.0) > 0.02: failures.append(label + " cross-player input playback")
	scene.free()
	saved_states += 1

func _probe() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["local", "instanced", "editable"]:
		failures.append("pass a known layout after --")
	else:
		for op in OPS:
			for state in ["undo", "redo"]: _state(args[0], op, "base", state)
		for op in ["split_at", "merge"]:
			for state in ["undo", "redo"]: _state(args[0], op, "overwrite", state)
		for op in ["merge", "layer"]:
			for state in ["undo", "redo"]: _state(args[0], op, "cross", state)
	OS.remove_logger(logger)
	if saved_states != 48: failures.append("expected exactly 48 saved states")
	print("EDIT_HISTORY_RUNTIME=" + JSON.stringify({"saved_states": saved_states, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
