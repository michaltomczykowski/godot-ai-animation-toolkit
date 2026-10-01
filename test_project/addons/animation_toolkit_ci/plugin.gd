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
const TOOL_REGISTRY := "res://addons/godot_ai/custom_tools/mcp_tool_registry.gd"
const OP_REGISTRY := "res://addons/godot_ai_animation/registry/op_registry.gd"
const TOOL_SOURCE := "res://addons/godot_ai_animation/plugin.cfg"


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
	# The core reports "importing" while the editor finishes its first scan;
	# writable custom tools correctly refuse dispatch during that window.
	for _attempt in 50:
		if McpConnection.get_readiness() != "importing":
			break
		await get_tree().create_timer(0.1).timeout
	var route_errors := _verify_tool_routes()
	# A core reload removes this addon's entries. The toolkit must notice the
	# missing specs and restore every dispatcher route without an editor restart.
	var registry = load(TOOL_REGISTRY).call("get_instance")
	if registry != null:
		registry.call("unregister_source", TOOL_SOURCE)
		await get_tree().create_timer(1.0).timeout
		route_errors.append_array(_verify_tool_routes())

	# The editor restores its last open scene after plugins enter the tree. On
	# the first startup, that restore can race the earlier open_scene call and
	# leave an unrelated graph fixture active for every suite.
	EditorInterface.open_scene_from_path(TEST_SCENE)
	var clean_scene := false
	for _frame in 60:
		await get_tree().process_frame
		var edited := EditorInterface.get_edited_scene_root()
		if edited != null and edited.scene_file_path == TEST_SCENE:
			clean_scene = true
			break
	if not clean_scene:
		print("CI_SUITE_FAIL: could not activate clean test scene %s" % TEST_SCENE)
		get_tree().quit(1)
		return

	var discovered := _discover_suites()
	var suites: Array = discovered.suites
	var missing: Array = discovered.errors
	var runner = runner_script.new()
	var results: Dictionary = runner.run_suites(
		suites, SUITE_FILTER, "", {"undo_redo": get_undo_redo()}, true,
	)
	results["discovery_errors"] = missing
	results["tool_route_errors"] = route_errors
	print("CI_SUITE_RESULTS=" + JSON.stringify(results))

	var failed := int(results.get("failed", 1))
	var total := int(results.get("total", 0))
	if not missing.is_empty():
		for problem in missing:
			print("CI_SUITE_MISSING: %s" % str(problem))
	if failed == 0 and total > 0 and missing.is_empty() and route_errors.is_empty():
		print("CI_SUITE_PASS")
		get_tree().quit(0)
	else:
		print("CI_SUITE_FAIL")
		get_tree().quit(1)


func _verify_tool_routes() -> Array:
	var errors: Array = []
	var registry_script = load(TOOL_REGISTRY)
	var op_registry = load(OP_REGISTRY)
	if registry_script == null or op_registry == null:
		return ["tool or op registry failed to load"]
	var registry = registry_script.call("get_instance")
	if registry == null:
		return ["Godot AI registry is absent"]
	var dispatcher = registry.get("_dispatcher")
	if dispatcher == null:
		return ["Godot AI dispatcher is absent"]
	var audited_ops := 0
	for family_name in op_registry.call("family_names"):
		if registry.call("get_spec", family_name) == null:
			errors.append("%s was not registered" % family_name)
			continue
		var command := "custom_tool:" + str(family_name)
		if not dispatcher.call("has_command", command):
			errors.append("%s has no dispatcher route" % command)
			continue
		# An unknown op must reach the addon's handler and return its typed
		# validation error. This catches a stale or unmaterializable route.
		var reply: Dictionary = dispatcher.call("_dispatch", {
			"request_id": "ci-route-" + str(family_name),
			"command": command,
			"params": {"op": "__ci_unknown_op__"},
		})
		if str(reply.get("error", {}).get("code", "")) != "VALUE_OUT_OF_RANGE":
			errors.append("%s did not reach its handler: %s" % [command, str(reply)])
		for descriptor in op_registry.call("op_descriptors", family_name):
			var op_name := str(descriptor.name)
			var op_reply: Dictionary = dispatcher.call("_dispatch", {
				"request_id": "ci-op-" + str(family_name) + "-" + op_name,
				"command": command,
				"params": {"op": op_name, "dry_run": true},
			})
			var op_error: Dictionary = op_reply.get("error", {})
			var message := str(op_error.get("message", ""))
			if op_reply.is_empty() or message.begins_with("Unknown op") \
					or str(op_error.get("code", "")) == "INTERNAL_ERROR":
				errors.append("%s op %s did not dispatch cleanly: %s" % [
					command, op_name, str(op_reply)])
			audited_ops += 1
	var quiescence: Dictionary = dispatcher.call("quiesce_for_script_swap")
	if not bool(quiescence.get("ok", false)):
		errors.append("Godot AI cannot quiesce after toolkit calls: %s" % str(quiescence))
	for family_name in ["animation_library", "animation_rig"]:
		var rejected: Dictionary = dispatcher.call("_dispatch", {
			"request_id": "ci-batch-preflight-" + family_name,
			"command": "batch_execute",
			"params": {"undo": true, "commands": [{
				"command": "custom_tool:" + family_name,
				"params": {"op": "__must_not_run__"},
			}]},
		})
		if str(rejected.get("error", {}).get("code", "")) != "CUSTOM_TOOL_NOT_UNDOABLE":
			errors.append("batch undo preflight did not reject %s: %s" % [
				family_name, str(rejected)])
	# Per-project disable state must block a previously materialized wrapper,
	# and re-enabling must reuse the route without an editor restart.
	registry.call("set_tool_enabled", "animation_fx", false)
	var disabled: Dictionary = dispatcher.call("_dispatch", {
		"request_id": "ci-disabled-fx", "command": "custom_tool:animation_fx",
		"params": {"op": "__ci_unknown_op__"},
	})
	if str(disabled.get("error", {}).get("code", "")) != "CUSTOM_TOOL_DISABLED":
		errors.append("disabled FX tool still dispatched: %s" % str(disabled))
	registry.call("set_tool_enabled", "animation_fx", true)
	var enabled_again: Dictionary = dispatcher.call("_dispatch", {
		"request_id": "ci-reenabled-fx", "command": "custom_tool:animation_fx",
		"params": {"op": "__ci_unknown_op__"},
	})
	if str(enabled_again.get("error", {}).get("code", "")) != "VALUE_OUT_OF_RANGE":
		errors.append("re-enabled FX tool did not recover: %s" % str(enabled_again))
	for problem in errors:
		print("CI_TOOL_ROUTE_FAIL: %s" % str(problem))
	if errors.is_empty():
		print("CI_TOOL_ROUTE_PASS: %d families, %d operation dry-run routes" % [
			(op_registry.call("family_names") as Array).size(), audited_ops])
	return errors


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
