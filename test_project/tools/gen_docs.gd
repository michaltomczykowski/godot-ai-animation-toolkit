extends SceneTree

## Renders docs/op-index.md from the op registry. Run through tools/gen_docs.ps1
## (or directly):
##
##   godot --headless --path test_project --script res://tools/gen_docs.gd

const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")


func _init() -> void:
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var docs_dir := repo_root.path_join("docs")
	if not DirAccess.dir_exists_absolute(docs_dir):
		DirAccess.make_dir_recursive_absolute(docs_dir)
	var path := docs_dir.path_join("op-index.md")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("GEN_DOCS_FAIL: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(OpRegistry.render_markdown())
	file.close()
	print("GEN_DOCS_WRITE %s" % path)
	quit(0)
