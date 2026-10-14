@tool
extends EditorPlugin
const Suite := preload("res://tests/test_setup_integration.gd")
const Transforms := preload("res://tests/test_motion_transform.gd")
const ExistingMotion := preload("res://tests/test_animation_motion.gd")
const Runner := preload("res://addons/godot_ai/testing/test_runner.gd")
func _enter_tree() -> void:
	if OS.get_environment("SETUP_INTEGRATION_CI") == "1": _run.call_deferred()
func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://main.tscn")
	for _frame in 30: await get_tree().process_frame
	var runner := Runner.new()
	var selected := [Suite.new(), Transforms.new()]
	var suite_filter := OS.get_environment("SETUP_INTEGRATION_SUITE")
	if suite_filter == "animation_motion": selected = [ExistingMotion.new()]
	var result := runner.run_suites(selected, suite_filter, OS.get_environment("SETUP_INTEGRATION_TEST"), {"undo_redo": get_undo_redo()}, true)
	print("SETUP_INTEGRATION=" + JSON.stringify(result))
	get_tree().quit(0 if int(result.get("failed", 1)) == 0 else 1)
