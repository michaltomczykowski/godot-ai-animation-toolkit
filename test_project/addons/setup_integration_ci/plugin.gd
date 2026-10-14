@tool
extends EditorPlugin
const Suite := preload("res://tests/test_setup_integration.gd")
const Runner := preload("res://addons/godot_ai/testing/test_runner.gd")
func _enter_tree() -> void:
	if OS.get_environment("SETUP_INTEGRATION_CI") == "1": _run.call_deferred()
func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://main.tscn")
	for _frame in 30: await get_tree().process_frame
	var runner := Runner.new()
	var result := runner.run_suites([Suite.new()], "", "", {"undo_redo": get_undo_redo()}, true)
	print("SETUP_INTEGRATION=" + JSON.stringify(result))
	get_tree().quit(0 if int(result.get("failed", 1)) == 0 else 1)
