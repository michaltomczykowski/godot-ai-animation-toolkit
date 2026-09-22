@tool
extends EditorPlugin

## CI-only harness. When ANIMATION_TOOLKIT_CI=1 this opens the test scene, runs
## the animation_presets suite through the Godot AI test runner, prints a
## machine-readable result, and quits the editor with a non-zero exit code on
## failure. Gated by the environment variable, so normal editor sessions are
## untouched.

const ENV_FLAG := "ANIMATION_TOOLKIT_CI"
const SUITE := "animation_presets"
const TEST_SCENE := "res://main.tscn"


func _enter_tree() -> void:
	if OS.get_environment(ENV_FLAG) != "1":
		return
	_run.call_deferred()


func _run() -> void:
	var runner_script = load("res://addons/godot_ai/testing/test_runner.gd")
	if runner_script == null:
		print("CI_SUITE_FAIL: Godot AI test runner not found")
		get_tree().quit(1)
		return

	EditorInterface.open_scene_from_path(TEST_SCENE)
	for _frame in 3:
		await get_tree().process_frame

	var suites := _discover_suites()
	var runner = runner_script.new()
	var results: Dictionary = runner.run_suites(
		suites, SUITE, "", {"undo_redo": get_undo_redo()}, true,
	)
	print("CI_SUITE_RESULTS=" + JSON.stringify(results))

	var failed := int(results.get("failed", 1))
	var total := int(results.get("total", 0))
	if failed == 0 and total > 0:
		print("CI_SUITE_PASS")
		get_tree().quit(0)
	else:
		print("CI_SUITE_FAIL")
		get_tree().quit(1)


## Duck-typed discovery so this harness parses even without the core addon.
func _discover_suites() -> Array:
	var suites: Array = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return suites
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			var script = load("res://tests/" + file_name)
			if script != null and script.can_instantiate():
				var instance = script.new()
				if instance.has_method("suite_name") and instance.has_method("suite_setup"):
					suites.append(instance)
		file_name = dir.get_next()
	return suites
