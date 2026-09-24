@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const LibraryHandler := preload("res://addons/godot_ai_animation/handlers/library.gd")

## Tests for the animation_library tool (templates + JSON clip specs).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

const LIBRARY := "res://tests/tmp_library.json"
const SPEC := "res://tests/tmp_spec.json"
const DUMMY := "res://models/human_dummy/HumanCharacterDummy_F.fbx"

var _handler: LibraryHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_library"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = LibraryHandler.new()


func suite_teardown() -> void:
	_remove_file(LIBRARY)
	_remove_file(SPEC)


# --- helpers ---------------------------------------------------------------

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _add_player(player_name: String, clips: Array = []) -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ""
	var player := AnimationPlayer.new()
	player.name = player_name
	var library := AnimationLibrary.new()
	for clip_name in clips:
		library.add_animation(clip_name, _make_clip())
	player.add_animation_library("", library)
	scene_root.add_child(player)
	player.set_owner(scene_root)
	return "/" + scene_root.name + "/" + player_name


func _make_clip() -> Animation:
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "Sprite:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 1.0, "value": Vector2(20, 0), "transition": 1.0},
	])
	return SpecBuilder.to_animation(spec)


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _add_sibling(node: Node, sibling_name: String) -> Node:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	node.name = sibling_name
	scene_root.add_child(node)
	node.owner = scene_root
	return node


func _rig(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	_add_sibling(Node2D.new(), prefix + "Target")
	_add_sibling(Node2D.new(), prefix + "Target2")
	var player_path := _add_player("LibPlayer" + prefix)
	if player_path.is_empty():
		return {"error": "no player"}
	return {
		"player_path": player_path,
		"target": "/" + scene_root.name + "/" + prefix + "Target",
		"target2": "/" + scene_root.name + "/" + prefix + "Target2",
	}


func _teardown(rig: Dictionary) -> void:
	if rig.has("player_path"):
		_remove_node(rig.player_path)
	if rig.has("target"):
		_remove_node(rig.target)
	if rig.has("target2"):
		_remove_node(rig.target2)
	_remove_file(LIBRARY)
	_remove_file(SPEC)


func _fetch_anim(player_path: String, anim_name: String) -> Animation:
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(player_path, scene_root) as AnimationPlayer
	if player == null or not player.has_animation(anim_name):
		return null
	return player.get_animation(anim_name)


# --- rollup ----------------------------------------------------------------

func test_rollup_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "borrow"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "template_save")
	assert_contains(unknown.error.message, "spec_apply")


# --- templates -------------------------------------------------------------

func test_template_save_list_and_delete() -> void:
	var saved := _handler.run({
		"op": "template_save", "name": "press", "tool": "animation_presets",
		"forward_op": "bounce", "intensity": 0.25, "duration": 0.5,
		"description": "button press", "library_path": LIBRARY,
	}, null)
	assert_has_key(saved, "data")
	assert_eq(str(saved.data.tool), "animation_presets")
	assert_eq(str(saved.data.op), "bounce")
	assert_eq(int(saved.data.param_count), 2)
	assert_false(bool(saved.data.undoable), "file writes report as not undoable")
	var listed := _handler.run({"op": "template_list", "library_path": LIBRARY}, null)
	assert_has_key(listed, "data")
	assert_eq(int(listed.data.template_count), 1)
	var entry: Dictionary = listed.data.templates[0]
	assert_eq(str(entry.name), "press")
	assert_eq(str(entry.op), "bounce")
	assert_eq(str(entry.description), "button press")
	assert_true(is_equal_approx(float(entry.params.intensity), 0.25), "params are stored")
	var deleted := _handler.run({"op": "template_delete", "name": "press", "library_path": LIBRARY}, null)
	assert_has_key(deleted, "data")
	assert_eq(int(deleted.data.template_count), 0)
	var empty := _handler.run({"op": "template_list", "library_path": LIBRARY}, null)
	assert_eq(int(empty.data.template_count), 0)
	assert_true(bool(empty.data.exists), "the library file still exists")


func test_template_save_overwrite_and_validation() -> void:
	var first := _handler.run({
		"op": "template_save", "name": "pulse_slow", "tool": "animation_presets",
		"forward_op": "pulse", "duration": 1.5, "library_path": LIBRARY,
	}, null)
	assert_has_key(first, "data")
	var duplicate := _handler.run({
		"op": "template_save", "name": "pulse_slow", "tool": "animation_presets",
		"forward_op": "pulse", "duration": 0.4, "library_path": LIBRARY,
	}, null)
	assert_is_error(duplicate, ErrorCodes.INVALID_PARAMS)
	var replaced := _handler.run({
		"op": "template_save", "name": "pulse_slow", "tool": "animation_presets",
		"forward_op": "pulse", "duration": 0.4, "library_path": LIBRARY, "overwrite": true,
	}, null)
	assert_has_key(replaced, "data")
	assert_true(bool(replaced.data.overwritten), "overwrite replaces the template")
	assert_true(is_equal_approx(float(replaced.data.params.duration), 0.4), "the new params win")
	var unknown_op := _handler.run({
		"op": "template_save", "name": "nope", "tool": "animation_presets",
		"forward_op": "wobble", "library_path": LIBRARY,
	}, null)
	assert_is_error(unknown_op, ErrorCodes.VALUE_OUT_OF_RANGE)
	var unknown_tool := _handler.run({
		"op": "template_save", "name": "nope", "tool": "animation_edit",
		"forward_op": "retime", "library_path": LIBRARY,
	}, null)
	assert_is_error(unknown_tool, ErrorCodes.VALUE_OUT_OF_RANGE)
	_remove_file(LIBRARY)


func test_template_apply_creates_clip_and_undoes() -> void:
	var rig := _rig("Apply")
	if rig.has("error"):
		skip(rig.error)
		return
	var saved := _handler.run({
		"op": "template_save", "name": "drift_wide", "tool": "animation_presets",
		"forward_op": "drift", "player_path": rig.player_path, "target_path": rig.target,
		"axis": "x", "distance": 120, "duration": 1.5, "loop_mode": "pingpong",
		"library_path": LIBRARY,
	}, null)
	assert_has_key(saved, "data")
	var applied := _handler.run({
		"op": "template_apply", "name": "drift_wide", "library_path": LIBRARY,
		"target_path": rig.target2, "animation_name": "wide",
	}, null)
	assert_has_key(applied, "data")
	assert_eq(str(applied.data.template), "drift_wide")
	assert_eq(str(applied.data.animation_name), "wide")
	assert_eq(str(applied.data.applied_tool), "animation_presets")
	var anim := _fetch_anim(rig.player_path, "wide")
	assert_true(anim != null, "the template built the clip")
	assert_eq(str(anim.track_get_path(0)), "ApplyTarget2:position",
		"the override retargets the clip (%s)" % str(anim.track_get_path(0)))
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(_fetch_anim(rig.player_path, "wide") == null, "one undo removes the applied clip")
	_teardown(rig)


func test_template_apply_dry_run_and_missing() -> void:
	var rig := _rig("DryApply")
	if rig.has("error"):
		skip(rig.error)
		return
	_handler.run({
		"op": "template_save", "name": "bounce_small", "tool": "animation_presets",
		"forward_op": "bounce", "player_path": rig.player_path, "target_path": rig.target,
		"intensity": 0.1, "library_path": LIBRARY,
	}, null)
	var dry := _handler.run({
		"op": "template_apply", "name": "bounce_small", "library_path": LIBRARY, "dry_run": true,
	}, null)
	assert_has_key(dry, "data")
	assert_true(bool(dry.data.dry_run), "dry_run is reported")
	assert_true(_fetch_anim(rig.player_path, "bounce") == null, "dry_run creates no clip")
	var missing := _handler.run({
		"op": "template_apply", "name": "ghost", "library_path": LIBRARY,
	}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	assert_contains(missing.error.message, "bounce_small")
	var delete_missing := _handler.run({
		"op": "template_delete", "name": "ghost", "library_path": LIBRARY,
	}, null)
	assert_is_error(delete_missing, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


# --- specs -----------------------------------------------------------------

func test_spec_export_and_import() -> void:
	var rig := _rig("Spec")
	if rig.has("error"):
		skip(rig.error)
		return
	_add_player("LibSpecSource", [])
	var source_path := "/" + _scene_root_name() + "/LibSpecSource"
	var scene_root := EditorInterface.get_edited_scene_root()
	var source := ValueCodec.resolve_scene_path(source_path, scene_root) as AnimationPlayer
	source.get_animation_library("").add_animation("walk", _make_clip())
	var exported := _handler.run({
		"op": "spec_export", "player_path": source_path, "animation_name": "walk",
		"path": SPEC, "overwrite": true,
	}, null)
	assert_has_key(exported, "data")
	assert_true(FileAccess.file_exists(SPEC), "the spec file is written")
	var imported := _handler.run({"op": "spec_import", "path": SPEC}, null)
	assert_has_key(imported, "data")
	assert_eq(int(imported.data.track_count), 1)
	assert_eq(int(imported.data.key_count), 2)
	assert_true(is_equal_approx(float(imported.data.length), 1.0), "the length round-trips")
	assert_eq(str(imported.data.paths[0]), "Sprite:position")
	assert_true((imported.data.issues as Array).is_empty(), "an exported spec has no issues")
	var again := _handler.run({
		"op": "spec_export", "player_path": source_path, "animation_name": "walk",
		"path": SPEC, "overwrite": false,
	}, null)
	assert_is_error(again, ErrorCodes.INVALID_PARAMS)
	_remove_node(source_path)
	_teardown(rig)


func test_spec_apply_with_remap_and_overwrite() -> void:
	var rig := _rig("Apply2")
	if rig.has("error"):
		skip(rig.error)
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	var source_path := "/" + _scene_root_name() + "/LibApply2Source"
	_add_player("LibApply2Source", [])
	var source := ValueCodec.resolve_scene_path(source_path, scene_root) as AnimationPlayer
	source.get_animation_library("").add_animation("walk", _make_clip())
	_handler.run({
		"op": "spec_export", "player_path": source_path, "animation_name": "walk",
		"path": SPEC, "overwrite": true,
	}, null)
	var applied := _handler.run({
		"op": "spec_apply", "player_path": rig.player_path, "path": SPEC,
		"target_path": rig.target2, "animation_name": "walk_copy",
	}, null)
	assert_has_key(applied, "data")
	assert_eq(str(applied.data.target_path), "Apply2Target2",
		"the resolved track path is reported (%s)" % str(applied.data.target_path))
	var anim := _fetch_anim(rig.player_path, "walk_copy")
	assert_true(anim != null, "the spec built a clip")
	assert_eq(str(anim.track_get_path(0)), "Apply2Target2:position",
		"tracks are remapped (%s)" % str(anim.track_get_path(0)))
	assert_true((applied.data.issues as Array).is_empty(), "a remapped spec resolves")
	var collision := _handler.run({
		"op": "spec_apply", "player_path": rig.player_path, "path": SPEC,
		"target_path": rig.target2, "animation_name": "walk_copy",
	}, null)
	assert_is_error(collision, ErrorCodes.INVALID_PARAMS)
	var replaced := _handler.run({
		"op": "spec_apply", "player_path": rig.player_path, "path": SPEC,
		"target_path": rig.target2, "animation_name": "walk_copy", "overwrite": true,
	}, null)
	assert_has_key(replaced, "data")
	assert_true(bool(replaced.data.overwritten), "overwrite replaces the clip")
	var unresolved := _handler.run({
		"op": "spec_apply", "player_path": rig.player_path, "path": SPEC,
		"animation_name": "walk_elsewhere", "overwrite": true,
	}, null)
	assert_has_key(unresolved, "data")
	assert_true(not (unresolved.data.issues as Array).is_empty(),
		"applying without a remap flags the missing node")
	_remove_node(source_path)
	_teardown(rig)


func test_spec_apply_inline_and_validation() -> void:
	var rig := _rig("Inline")
	if rig.has("error"):
		skip(rig.error)
		return
	var inline := {
		"format": "godot-ai-animation-clip", "version": 1, "length": 0.5, "loop_mode": 0,
		"markers": [],
		"tracks": [{
			"type": Animation.TYPE_VALUE, "path": "LibInlineTarget:scale", "enabled": true,
			"interp": Animation.INTERPOLATION_LINEAR, "update_mode": Animation.UPDATE_CONTINUOUS,
			"keys": [
				{"time": 0.0, "value": {"kind": "vector2", "x": 1, "y": 1}, "transition": 1.0},
				{"time": 0.5, "value": {"kind": "vector2", "x": 1.5, "y": 1.5}, "transition": 1.0},
			],
		}],
	}
	var applied := _handler.run({
		"op": "spec_apply", "player_path": rig.player_path, "spec": inline,
		"animation_name": "inline_clip",
	}, null)
	assert_has_key(applied, "data")
	var anim := _fetch_anim(rig.player_path, "inline_clip")
	assert_true(anim != null, "the inline spec built a clip")
	assert_true(is_equal_approx(anim.length, 0.5), "the inline length is used")
	var missing := _handler.run({"op": "spec_import", "path": "res://tests/definitely_missing.json"}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	var no_source := _handler.run({"op": "spec_import"}, null)
	assert_is_error(no_source, ErrorCodes.MISSING_REQUIRED_PARAM)
	var malformed := _handler.run({
		"op": "spec_import",
		"spec": {"format": "something-else", "tracks": []},
	}, null)
	assert_is_error(malformed, ErrorCodes.INVALID_PARAMS)
	_teardown(rig)


func _scene_root_name() -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	return scene_root.name if scene_root != null else ""


# --- motion / rig templates ------------------------------------------------

func _find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owners(child, owner)


func _dummy_rig(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	if not ResourceLoader.exists(DUMMY):
		return {"error": "the human dummy asset is missing"}
	var root: Node = (load(DUMMY) as PackedScene).instantiate()
	root.name = prefix + "Dummy"
	scene_root.add_child(root)
	_assign_owners(root, scene_root)
	var skeleton := _find_of_type(root, "Skeleton3D") as Skeleton3D
	var player := _find_of_type(root, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		_remove_node("/" + scene_root.name + "/" + str(root.name))
		return {"error": "the dummy has no skeleton/player"}
	return {
		"root_path": "/" + scene_root.name + "/" + str(root.name),
		"skeleton_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(skeleton)),
		"player_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(player)),
		"skeleton": skeleton,
		"player": player,
	}


func test_template_motion_and_rig_calls() -> void:
	var rig := _dummy_rig("LibMotion")
	if rig.has("error"):
		skip(rig.error)
		return
	var saved := _handler.run({
		"op": "template_save", "name": "slow_sneak", "tool": "animation_motion",
		"forward_op": "walk_cycle", "duration": 1.2, "style": "sneaky", "loop_mode": "linear",
		"library_path": LIBRARY,
	}, null)
	assert_true(saved.has("data"), "motion template saves: %s" % str(saved))
	assert_eq(str(saved.data.tool), "animation_motion")
	assert_eq(str(saved.data.op), "walk_cycle")
	var applied := _handler.run({
		"op": "template_apply", "name": "slow_sneak", "library_path": LIBRARY,
		"player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "sneak", "overwrite": true,
	}, null)
	assert_true(applied.has("data"), "motion template applies: %s" % str(applied))
	assert_eq(str(applied.data.applied_tool), "animation_motion")
	assert_true(_fetch_anim(rig.player_path, "sneak") != null, "the motion clip is built")
	var recipe_saved := _handler.run({
		"op": "template_save", "name": "jack", "tool": "animation_rig",
		"forward_op": "jumping_jack", "duration": 1.0, "loop_mode": "linear",
		"library_path": LIBRARY,
	}, null)
	assert_true(recipe_saved.has("data"), "rig template saves: %s" % str(recipe_saved))
	var recipe_applied := _handler.run({
		"op": "template_apply", "name": "jack", "library_path": LIBRARY,
		"player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"animation_name": "jack", "overwrite": true,
	}, null)
	assert_true(recipe_applied.has("data"), "rig template applies: %s" % str(recipe_applied))
	assert_eq(str(recipe_applied.data.applied_tool), "animation_rig")
	assert_true(_fetch_anim(rig.player_path, "jack") != null, "the recipe clip is built")
	assert_true(editor_undo(_undo_redo), "undo should succeed")
	assert_true(_fetch_anim(rig.player_path, "jack") == null, "one undo removes the recipe clip")
	_remove_node(rig.root_path)
	_remove_file(LIBRARY)
	_remove_file(SPEC)


func test_registry_matches_library_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_LIBRARY)
	assert_false(info.is_empty(), "the library family is registered")
	var op_enum: Array = info.schema.properties.op.enum
	assert_eq(op_enum.size(), 7, "the library schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(info.schema.properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the library description fits the custom-tool cap")
