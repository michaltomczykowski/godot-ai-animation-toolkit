@tool
extends EditorPlugin

## CI-only harness. When ANIMATION_TOOLKIT_CI=1 this opens the test scene, runs
## every toolkit suite through the Godot AI test runner, prints a
## machine-readable result, and quits the editor with a non-zero exit code on
## failure. Gated by the environment variable, so normal editor sessions are
## untouched.

const ENV_FLAG := "ANIMATION_TOOLKIT_CI"
const SUITE_FILTER := ""
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

	var discovered := _discover_suites()
	var suites: Array = discovered.suites
	var missing: Array = discovered.errors
	var runner = runner_script.new()
	var results: Dictionary = runner.run_suites(
		suites, SUITE_FILTER, "", {"undo_redo": get_undo_redo()}, true,
	)
	results["discovery_errors"] = missing
	print("CI_SUITE_RESULTS=" + JSON.stringify(results))

	var failed := int(results.get("failed", 1))
	var total := int(results.get("total", 0))
	if not missing.is_empty():
		for problem in missing:
			print("CI_SUITE_MISSING: %s" % str(problem))
	if failed == 0 and total > 0 and missing.is_empty():
		print("CI_SUITE_PASS")
		get_tree().quit(0)
	else:
		print("CI_SUITE_FAIL")
		get_tree().quit(1)


## Duck-typed discovery so this harness parses even without the core addon.
## A `test_*.gd` file that cannot be loaded or instantiated is REPORTED, not
## skipped: a suite that silently vanishes leaves a green run with fewer tests,
## which is how a parse error in one file went unnoticed. Callers get
## `{suites, errors}`.
func _discover_suites() -> Dictionary:
	var suites: Array = []
	var errors: Array = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		errors.append("res://tests is not readable")
		return {"suites": suites, "errors": errors}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			var path := "res://tests/" + file_name
			var script = load(path)
			if script == null:
				errors.append("%s failed to load (parse error?)" % path)
			elif not script.can_instantiate():
				errors.append("%s cannot be instantiated" % path)
			else:
				var instance = script.new()
				if instance.has_method("suite_name") and instance.has_method("suite_setup"):
					suites.append(instance)
				else:
					errors.append("%s has no suite_name/suite_setup" % path)
		file_name = dir.get_next()
	return {"suites": suites, "errors": errors}
