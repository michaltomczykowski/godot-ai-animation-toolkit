@tool
extends RefCounted

## Read-only witnesses for the existing matrices; never invokes or repairs a tool.
static func state(fixture: Node, snapshot: Callable, history: UndoRedo, global_history: UndoRedo, playback: Callable = Callable()) -> Dictionary:
	var value := {"snapshot": snapshot.call(fixture), "version": history.get_version(),
		"global_version": global_history.get_version(),
		"editable": EditorInterface.get_edited_scene_root().is_editable_instance(fixture)}
	if playback.is_valid(): value["playback"] = playback.call()
	return value

static func file_hash(path: String) -> String:
	return FileAccess.get_sha256(path) if not path.is_empty() and FileAccess.file_exists(path) else ""

static func emit(row: Dictionary, failed: bool, assertions: int, logger, error_start: int) -> void:
	row["failed_after"] = failed
	row["assertion_count"] = assertions - int(row["assertions_before"])
	row["errors_before"] = error_start
	row["errors_after"] = logger.errors.size()
	row["errors"] = logger.errors.slice(error_start)
	preload("res://tests/operation_history_trace.gd")._emit(row, "animation_rig", "test_" + str(row["suite"]) + ".gd", "rig_scene_history_v1")
