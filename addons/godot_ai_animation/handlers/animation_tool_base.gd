@tool
extends RefCounted

## Shared plumbing for every toolkit tool handler: editor-undo context, player
## resolution, duplicate-clip detection, and the single-action commit helper.
##
## Extracted from the original presets handler so `generate.gd` and `edit.gd`
## (and future families) share one commit path — and so one Ctrl-Z always
## reverts exactly one tool call.

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

## Set from the `dry_run` param at the start of `run()`: when true the commit
## helpers skip the undo action, so an op can report what it *would* produce
## (used by `animation_inspect(op="dry_run")` and the tools' own `dry_run`).
var _dry_run := false


## Every tool needs the editor undo manager (injected by the addon's
## EditorPlugin, or by the test suite).
func _context_error() -> Dictionary:
	if ToolContext.undo_redo == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY,
			"Godot AI Animation Toolkit is not initialized - enable the 'Godot AI Animation Toolkit' plugin")
	return {}


## Resolve an AnimationPlayer and its default library. Returns `{player, library}`
## (library null when the player has no default library yet) or an error dict.
## Tool calls never auto-create a player.
func _resolve_player(player_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var node := ValueCodec.resolve_scene_path(player_path, scene_root)
	if node == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(player_path, scene_root))
	if not node is AnimationPlayer:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Node at %s is not an AnimationPlayer (got %s)" % [player_path, node.get_class()])
	var player := node as AnimationPlayer
	var library: AnimationLibrary = null
	if player.has_animation_library(""):
		library = player.get_animation_library("")
	return {"player": player, "library": library}


## Resolve the existing animation a generator would replace. Returns
## `{old_anim: Animation|null}` when the name is free or `overwrite` is set,
## or `{error: <error dict>}` when the name is taken and overwrite is off.
static func _existing_animation(library: AnimationLibrary, anim_name: String, overwrite: bool) -> Dictionary:
	if not library.has_animation(anim_name):
		return {"old_anim": null}
	if not overwrite:
		return {"error": ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' already exists. Pass overwrite=true or delete it first." % anim_name)}
	return {"old_anim": library.get_animation(anim_name)}


## Commit one scene-pinned undo action that replaces a set of clips.
##
##   removed — {clip_name: old_animation} clips to take out
##   added   — {clip_name: new_animation} clips to put in
##
## Optional `extra_props` entries are {object, property, value, old} changes
## bundled into the same action (e.g. Control pivot recentering).
func _commit_animation_changes(
	action_label: String,
	player: AnimationPlayer,
	library: AnimationLibrary,
	created_library: bool,
	removed: Dictionary,
	added: Dictionary,
	extra_props: Array = [],
) -> void:
	if _dry_run:
		return
	_create_scene_pinned_action(action_label)
	var undo := ToolContext.undo_redo
	if created_library:
		undo.add_do_method(player, "add_animation_library", "", library)
		undo.add_undo_method(player, "remove_animation_library", "")
		undo.add_do_reference(library)
	for clip_name in removed:
		undo.add_do_method(library, "remove_animation", clip_name)
	for clip_name in added:
		undo.add_do_method(library, "add_animation", clip_name, added[clip_name])
		undo.add_do_reference(added[clip_name])
	for clip_name in added:
		undo.add_undo_method(library, "remove_animation", clip_name)
	for clip_name in removed:
		undo.add_undo_method(library, "add_animation", clip_name, removed[clip_name])
		undo.add_do_reference(removed[clip_name])
	for entry in extra_props:
		undo.add_do_property(entry.object, entry.property, entry.value)
		undo.add_undo_property(entry.object, entry.property, entry.old)
	undo.commit_action()


## Add-or-replace one clip in one action (the generator path).
func _commit_animation_add(
	action_label: String,
	player: AnimationPlayer,
	library: AnimationLibrary,
	created_library: bool,
	anim_name: String,
	anim: Animation,
	old_anim: Animation,
	extra_props: Array = [],
) -> void:
	var removed := {}
	if old_anim != null:
		removed[anim_name] = old_anim
	_commit_animation_changes(action_label, player, library, created_library, removed, {anim_name: anim}, extra_props)


## Open an action pinned to the edited scene's history. The first do-targets
## are scene-owned (player/library/control), and the explicit context keeps the
## action out of GLOBAL_HISTORY so a scene undo finds it.
func _create_scene_pinned_action(action_label: String) -> void:
	ToolContext.undo_redo.create_action(
		action_label, UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root(),
	)
