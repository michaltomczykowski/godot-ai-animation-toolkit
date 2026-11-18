@tool
extends RefCounted

## Export complete public-route states for the independent engine checker.
const MANIFEST := "user://rig_bake_saved_matrix.json"
static var rows: Array = []
static func reset() -> void:
	rows.clear()
	flush()
static func flush() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "cases": rows}))
static func save(label: String, state: String) -> String:
	var path := "user://bake_matrix_%s_%s.tscn" % [label, state]
	var packed := PackedScene.new()
	if packed.pack(EditorInterface.get_edited_scene_root()) != OK or ResourceSaver.save(packed, path) != OK: return ""
	return path
static func begin(f: Dictionary, params: Dictionary, label: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	return {"id": label, "params": params.duplicate(true), "source": save(label, "source"),
		"source_player": str(root.get_path_to(f.player)), "skeleton": str(root.get_path_to(f.skeleton)),
		"tree": str(root.get_path_to(f.tree)) if f.has("tree") and params.has("source_tree_path") else "",
		"movement_owner": str(root.get_path_to(f.root)), "states": {}}
static func state(row: Dictionary, output: AnimationPlayer, label: String) -> void:
	row.output = str(EditorInterface.get_edited_scene_root().get_path_to(output)) if label != "undo" else row.get("output", "")
	row.states[label] = save(row.id, label)
static func finish(row: Dictionary) -> void:
	for i in range(rows.size() - 1, -1, -1):
		if rows[i].id == row.id: rows.remove_at(i)
	rows.append(row)
	flush()
