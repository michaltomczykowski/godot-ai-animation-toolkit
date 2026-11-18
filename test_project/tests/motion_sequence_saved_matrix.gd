@tool
extends RefCounted
const PATH := "user://motion_sequence_saved_matrix.json"
static var rows: Array = []
static func reset() -> void:
	rows.clear()
	flush()
static func flush() -> void:
	FileAccess.open(PATH, FileAccess.WRITE).store_string(JSON.stringify({"format": 1, "cases": rows}))
static func scene(label: String, state: String) -> String:
	var path := "user://motion_sequence_%s_%s.tscn" % [label, state]
	var packed := PackedScene.new()
	if packed.pack(EditorInterface.get_edited_scene_root()) != OK or ResourceSaver.save(packed, path) != OK: return ""
	return path
static func finish(row: Dictionary) -> void:
	for index in range(rows.size() - 1, -1, -1):
		if rows[index].id == row.id: rows.remove_at(index)
	rows.append(row)
	flush()
