@tool
extends McpTestSuite
const Rig := preload("res://addons/godot_ai_animation/handlers/rig.gd")
const Stored := preload("res://tests/inspect_read_snapshot.gd")
var _undo: EditorUndoRedoManager
func suite_name() -> String: return "pose_list_directory"
func suite_setup(ctx: Dictionary) -> void: _undo=ctx.undo_redo
func test_selected_directory_type_refuses_without_mutation() -> void:
	if EditorInterface.get_edited_scene_root()==null:
		skip("requires an actual edited scene")
		return
	var directory := "user://pose_list_directory_"+str(Time.get_ticks_usec())
	assert_eq(DirAccess.make_dir_recursive_absolute(directory),OK,"private sentinel directory")
	var path := directory.path_join("sentinel.txt")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string("untouched")
	file.close()
	var original_hash := FileAccess.get_sha256(path)
	var handler := Rig.new()
	var before := Stored.snapshot(_undo)
	for field in ["directory","pose_dir"]:
		for value in [null,[],{},12,0.5,true,false]:
			var request := {"op":"pose_list"}
			request[field]=value
			var result := handler.run(request,null)
			assert_eq(result.get("error",{}).get("code"),"INVALID_PARAMS",field+" rejects selected non-String")
			assert_eq(Stored.snapshot(_undo),before,"typed refusal preserves stored scene/resources/history/files")
			assert_eq(FileAccess.get_sha256(path),original_hash,"typed refusal preserves sentinel bytes")
			var contents := DirAccess.open(directory).get_files()
			assert_eq(contents,PackedStringArray(["sentinel.txt"]),"typed refusal creates no files")
	var listed := handler.run({"op":"pose_list","directory":directory,"pose_dir":[]},null)
	assert_true(listed.has("data"),"ignored legacy wrong type cannot override selected directory")
	assert_eq(listed.get("data",{}).get("pose_count"),0,"non-JSON sentinel is not a pose")
	var missing := handler.run({"op":"pose_list","directory":directory+"_missing"},null)
	assert_eq(missing.get("data",{}).get("exists"),false,"String missing directory stays successful")
	assert_eq(missing.get("data",{}).get("pose_count"),0,"missing directory empty")
	assert_true(handler.run({"op":"pose_list","pose_dir":directory},null).has("data"),"legacy String directory remains supported")
	assert_true(handler.run({"op":"pose_list","directory":""},null).has("data"),"empty String retains successful contract")
	assert_true(handler.run({"op":"pose_list"},null).has("data"),"omitted/default directory remains supported")
	assert_eq(Stored.snapshot(_undo),before,"all String reads preserve scene/resources/history/files")
	assert_eq(FileAccess.get_sha256(path),original_hash,"all reads preserve sentinel")
	assert_eq(DirAccess.remove_absolute(path),OK,"remove private sentinel")
	assert_eq(DirAccess.remove_absolute(directory),OK,"remove private directory")
