@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## AnimationTree authoring — the `animation_graph` tool.
##
## Builds AnimationNode* graphs (state machines, blend spaces, blend trees),
## wires them to an AnimationPlayer through an AnimationTree, dumps existing
## graphs, and ships three ready-made setups (`locomotion`, `one_shot_layer`,
## `additive_lean`). Every mutating call is ONE scene-pinned undo action; the
## graph math itself lives in `spec/graph_builders.gd` and is tier-1 tested.

const GraphBuilders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const _DEFAULT_TREE_NAME := "AnimationTree"


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	var result := _dispatch(params)
	if _dry_run and result.has("data"):
		result.data["dry_run"] = true
		result.data["undoable"] = false
	return result


func _dispatch(params: Dictionary) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"state_machine":
			return graph_state_machine(params)
		"blend_space":
			return graph_blend_space(params)
		"blend_tree":
			return graph_blend_tree(params)
		"wire":
			return graph_wire(params)
		"graph_get":
			return graph_get(params)
		"locomotion":
			return graph_locomotion(params)
		"one_shot_layer":
			return graph_one_shot_layer(params)
		"additive_lean":
			return graph_additive_lean(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_GRAPH))])


# ============================================================================
# Builders
# ============================================================================

## Build a state machine as the tree root.
func graph_state_machine(params: Dictionary) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	var built := GraphBuilders.state_machine(params)
	if built.has("error"):
		return built
	built["issues"] = (built.issues as Array) + GraphBuilders.issues_for(built.root, context.clips)
	var extra := {
		"state_count": int(built.state_count),
		"transition_count": int(built.transition_count),
		"conditions": built.conditions,
		"states": _state_names(built.root),
	}
	if params.has("start"):
		extra["start_state"] = str(params.get("start"))
		extra["start_hint"] = "at runtime call get_node(tree).get(\"%s\").start(\"%s\")" % [
			_playback_path(context, built.root), str(params.get("start"))]
	return _commit_graph(context, built.root, "MCP: Animation state machine", extra)


## Build a blend space (1D or 2D) as the tree root.
func graph_blend_space(params: Dictionary) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	var built := GraphBuilders.blend_space(params)
	if built.has("error"):
		return built
	built["issues"] = (built.issues as Array) + GraphBuilders.issues_for(built.root, context.clips)
	return _commit_graph(context, built.root, "MCP: Animation blend space", {
		"dimensions": int(built.dimensions),
		"point_count": int(built.point_count),
	})


## Build a blend tree from a recursive spec.
func graph_blend_tree(params: Dictionary) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	var spec = params.get("root")
	if not spec is Dictionary or (spec as Dictionary).is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"blend_tree needs 'root': a node spec like {\"type\": \"blend2\", \"inputs\": [...]}")
	var built := GraphBuilders.blend_tree(spec)
	if built.has("error"):
		return built
	if not (built.issues as Array).is_empty():
		return built.issues[0]
	built["issues"] = GraphBuilders.issues_for(built.root, context.clips)
	return _commit_graph(context, built.root, "MCP: Animation blend tree", {
		"node_count": int(built.node_count),
		"animation_count": int(built.animation_count),
	})


## Ensure an AnimationTree exists for the player (and optionally set a parameter).
func graph_wire(params: Dictionary) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	var extra := {}
	if params.has("parameter_path"):
		var path := str(params.get("parameter_path", ""))
		if path.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'parameter_path' must not be empty")
		if context.tree == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Cannot set '%s': no AnimationTree exists yet (call wire without parameter_path first)" % path)
		extra["parameter_path"] = path
		extra["parameter_value"] = params.get("parameter_value")
	return _commit_graph(context, null, "MCP: Wire AnimationTree", extra)


## Dump an existing graph (and flag references the player cannot satisfy).
func graph_get(params: Dictionary) -> Dictionary:
	var tree_path := str(params.get("tree_path", ""))
	var player_path := str(params.get("player_path", ""))
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var tree: AnimationTree = null
	var player: AnimationPlayer = null
	if not tree_path.is_empty():
		var node := ValueCodec.resolve_scene_path(tree_path, scene_root)
		if node == null:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(tree_path, scene_root))
		if not node is AnimationTree:
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"Node at %s is not an AnimationTree (got %s)" % [tree_path, node.get_class()])
		tree = node
	else:
		if not player_path.is_empty():
			var resolved := _resolve_player(player_path)
			if resolved.has("error"):
				return resolved
			player = resolved.player
		tree = _find_tree(player)
		if tree == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"No AnimationTree found in the edited scene (pass tree_path, or build one with wire)")
	var clips: Array = []
	var player_for_clips := player
	if player_for_clips == null:
		player_for_clips = _player_of_tree(tree)
	if player_for_clips != null:
		clips = _clip_names(player_for_clips)
	var issues: Array = []
	if tree.tree_root != null:
		issues = GraphBuilders.issues_for(tree.tree_root, clips)
	if not tree.active:
		issues.append({"severity": "info", "code": "inactive_tree",
			"message": "the AnimationTree is not active, so nothing will play"})
	var anim_player_path := str(tree.anim_player)
	var anim_player_valid := tree.get_node_or_null(tree.anim_player) is AnimationPlayer
	if anim_player_path.is_empty() or not anim_player_valid:
		issues.append({"severity": "error", "code": "anim_player_unresolved",
			"message": "anim_player does not resolve to an AnimationPlayer (%s)" % anim_player_path})
	return {"data": {
		"tree_path": ValueCodec.from_node(tree, scene_root),
		"active": tree.active,
		"anim_player": anim_player_path,
		"anim_player_resolved": anim_player_valid,
		"root": GraphBuilders.graph_dump(tree.tree_root),
		"animations": GraphBuilders.animations_in(tree.tree_root),
		"parameters": _parameter_paths(tree),
		"playback_paths": _playback_paths(tree),
		"issues": issues,
	}}


# ============================================================================
# Ready-made setups
# ============================================================================

## Locomotion from three clips: a 1D blend space on speed (default) or a state
## machine driven by `walking` / `running` bool parameters.
func graph_locomotion(params: Dictionary) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	var idle := str(params.get("idle", "idle"))
	var walk := str(params.get("walk", "walk"))
	var run := str(params.get("run", "run"))
	var mode := str(params.get("mode", "blend_space"))
	if mode == "state_machine":
		var built := GraphBuilders.state_machine({
			"states": [
				{"name": "idle", "animation": idle},
				{"name": "walk", "animation": walk, "position": {"x": 240, "y": 0}},
				{"name": "run", "animation": run, "position": {"x": 480, "y": 0}},
			],
			"transitions": [
				{"from": "idle", "to": "walk", "xfade": 0.2, "advance_mode": "auto", "condition": "walking"},
				{"from": "walk", "to": "idle", "xfade": 0.2, "advance_mode": "auto", "advance_expression": "!walking"},
				{"from": "walk", "to": "run", "xfade": 0.2, "advance_mode": "auto", "condition": "running"},
				{"from": "run", "to": "walk", "xfade": 0.2, "advance_mode": "auto", "advance_expression": "!running"},
			],
		})
		if built.has("error"):
			return built
		built["issues"] = (built.issues as Array) + GraphBuilders.issues_for(built.root, context.clips)
		var extra := {
			"mode": mode,
			"state_count": int(built.state_count),
			"transition_count": int(built.transition_count),
			"conditions": built.conditions,
			"states": _state_names(built.root),
			"start_state": str(params.get("start", "idle")),
		}
		extra["start_hint"] = "at runtime call get_node(tree).get(\"%s\").start(\"%s\")" % [
			_playback_path(context, built.root), str(params.get("start", "idle"))]
		return _commit_graph(context, built.root, "MCP: Locomotion state machine", extra)
	if mode != "blend_space":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid locomotion mode '%s'. Valid: blend_space, state_machine" % mode)
	var built_space := GraphBuilders.blend_space({
		"dimensions": 1,
		"points": [
			{"animation": idle, "position": 0.0, "name": "idle"},
			{"animation": walk, "position": 1.0, "name": "walk"},
			{"animation": run, "position": 2.0, "name": "run"},
		],
		"min": 0.0,
		"max": 2.0,
		"snap": 0.01,
		"sync": true,
	})
	if built_space.has("error"):
		return built_space
	built_space["issues"] = (built_space.issues as Array) + GraphBuilders.issues_for(built_space.root, context.clips)
	return _commit_graph(context, built_space.root, "MCP: Locomotion blend space", {
		"mode": mode,
		"point_count": int(built_space.point_count),
		"clips": [idle, walk, run],
	})


## Layer a one-shot (jump/attack/hit) on top of the existing tree root.
func graph_one_shot_layer(params: Dictionary) -> Dictionary:
	var layer := _build_layer(params, "one_shot")
	if layer.has("error"):
		return layer
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = float(params.get("fadein", 0.1))
	shot.fadeout_time = float(params.get("fadeout", 0.2))
	shot.autorestart = bool(params.get("autorestart", false))
	var mix := str(params.get("mix_mode", "blend"))
	if mix == "add":
		shot.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	elif mix == "blend":
		shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	else:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid mix_mode '%s'. Valid: blend, add" % mix)
	var animation := AnimationNodeAnimation.new()
	animation.animation = StringName(str(params.get("animation", "")))
	var wrapped := _wrap_root(layer, shot, AnimationNodeBlend2.new(), {
		"layer_child": animation,
		"base_clip": str(params.get("base", "")),
	})
	if wrapped.has("error"):
		return wrapped
	wrapped.issues = (wrapped.issues as Array) + GraphBuilders.issues_for(wrapped.root, layer.clips)
	return _commit_graph(layer, wrapped.root, "MCP: One-shot layer", {
		"animation": str(params.get("animation", "")),
		"node_count": int(wrapped.node_count),
		"request_parameter": _first_matching(_parameter_paths_preview(wrapped.root), "/request"),
	})


## Additively layer a lean/clip on top of the existing tree root.
func graph_additive_lean(params: Dictionary) -> Dictionary:
	var layer := _build_layer(params, "additive_lean")
	if layer.has("error"):
		return layer
	var lean := AnimationNodeAnimation.new()
	lean.animation = StringName(str(params.get("animation", "")))
	var wrapped := _wrap_root(layer, lean, AnimationNodeAdd2.new(), {
		"layer_child": null,
		"base_clip": str(params.get("base", "")),
	})
	if wrapped.has("error"):
		return wrapped
	wrapped.issues = (wrapped.issues as Array) + GraphBuilders.issues_for(wrapped.root, layer.clips)
	return _commit_graph(layer, wrapped.root, "MCP: Additive layer", {
		"animation": str(params.get("animation", "")),
		"node_count": int(wrapped.node_count),
		"amount_parameter": _first_matching(_parameter_paths_preview(wrapped.root), "/add_amount"),
	})


## Shared context for the layer ops: player, tree, clips, plus the existing root.
func _build_layer(params: Dictionary, label: String) -> Dictionary:
	var context := _graph_context(params)
	if context.has("error"):
		return context
	if str(params.get("animation", "")).is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "%s needs 'animation'" % label)
	context["existing_root"] = context.tree.tree_root if context.tree != null else null
	return context


## Wrap `existing_root` (or a base clip) with `layer_node` through `combiner`.
func _wrap_root(context: Dictionary, layer_node: AnimationNode, combiner: AnimationNode, options: Dictionary) -> Dictionary:
	var existing_root: AnimationNode = context.get("existing_root")
	var base_node: AnimationNode = null
	if existing_root != null:
		base_node = existing_root
	else:
		var base_clip := str(options.get("base_clip", ""))
		if base_clip.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
				"The tree has no root yet - pass 'base' (the clip to layer onto)")
		var animation := AnimationNodeAnimation.new()
		animation.animation = StringName(base_clip)
		base_node = animation
	var tree := AnimationNodeBlendTree.new()
	var base_name := "Base"
	var layer_name := str(context.get("layer_name", "Layer"))
	var combiner_name := "Blend2" if combiner is AnimationNodeBlend2 else "Add2"
	tree.add_node(StringName(base_name), base_node, Vector2(0.0, 0.0))
	tree.add_node(StringName(layer_name), layer_node, Vector2(220.0, 0.0))
	var layer_child: AnimationNode = options.get("layer_child")
	if layer_child != null:
		tree.add_node(StringName("Shot"), layer_child, Vector2(220.0, 140.0))
		tree.connect_node(StringName(layer_name), 0, StringName("Shot"))
	tree.add_node(StringName(combiner_name), combiner, Vector2(440.0, 0.0))
	tree.connect_node(StringName(combiner_name), 0, StringName(base_name))
	tree.connect_node(StringName(combiner_name), 1, StringName(layer_name))
	if tree.has_node(StringName("output")):
		tree.connect_node(StringName("output"), 0, StringName(combiner_name))
	return {"root": tree, "node_count": tree.get_node_list().size(), "issues": []}


# ============================================================================
# Helpers
# ============================================================================

## Resolve player + (optional) tree + clip names for a graph op.
func _graph_context(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	# `create: false` is the documented way to ask "is this already wired?" without
	# putting a tree in the scene. It used to be accepted and ignored, so the call
	# created the very node the caller was checking for.
	var may_create := bool(params.get("create", true))
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var tree_path := str(params.get("tree_path", ""))
	var tree: AnimationTree = null
	var tree_parent: Node = null
	if not tree_path.is_empty():
		var scene_root := EditorInterface.get_edited_scene_root()
		var node := ValueCodec.resolve_scene_path(tree_path, scene_root)
		if node != null:
			if not node is AnimationTree:
				return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
					"Node at %s is not an AnimationTree (got %s)" % [tree_path, node.get_class()])
			tree = node
		else:
			if not may_create:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"No AnimationTree at %s and create=false" % tree_path)
			var parent := ValueCodec.resolve_scene_path(tree_path.get_base_dir(), scene_root)
			if parent == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"Cannot create an AnimationTree at %s: parent '%s' not found" % [tree_path, tree_path.get_base_dir()])
			tree = AnimationTree.new()
			tree.name = tree_path.get_file()
			tree_parent = parent
	else:
		tree = _find_tree(player)
		if tree == null:
			var scene_root := EditorInterface.get_edited_scene_root()
			var parent: Node = player.get_parent() if player.get_parent() != null else scene_root
			var parent_path := str(params.get("parent_path", ""))
			if not parent_path.is_empty():
				parent = ValueCodec.resolve_scene_path(parent_path, scene_root)
				if parent == null:
					return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
						ValueCodec.format_node_error(parent_path, scene_root))
			tree = AnimationTree.new()
			tree.name = str(params.get("name", _DEFAULT_TREE_NAME))
			tree_parent = parent
	return {
		"player": player,
		"player_path": player_path,
		"tree": tree,
		"tree_parent": tree_parent,
		"tree_created": tree_parent != null,
		"active": bool(params.get("active", false)),
		"clips": _clip_names(player),
		"layer_name": str(params.get("name", "OneShot" if str(params.get("op", "")) == "one_shot_layer" else "Lean")),
	}


func _find_tree(player: AnimationPlayer) -> AnimationTree:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	var trees: Array = scene_root.find_children("*", "AnimationTree", true, false)
	if player != null:
		for node in trees:
			var tree := node as AnimationTree
			if tree.get_node_or_null(tree.anim_player) == player:
				return tree
	if not trees.is_empty():
		return trees[0] as AnimationTree
	return null


func _player_of_tree(tree: AnimationTree) -> AnimationPlayer:
	var node := tree.get_node_or_null(tree.anim_player)
	return node as AnimationPlayer


func _clip_names(player: AnimationPlayer) -> Array:
	var names: Array = []
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		if library == null:
			continue
		for clip_name in library.get_animation_list():
			names.append(str(clip_name))
	return names


func _state_names(root: AnimationNode) -> Array:
	var names: Array = []
	if root is AnimationNodeStateMachine:
		for state_name in (root as AnimationNodeStateMachine).get_node_list():
			var label := str(state_name)
			if label == "Start" or label == "End":
				continue
			names.append(label)
	return names


## All parameters the tree exposes (sorted), e.g. parameters/conditions/walking.
func _parameter_paths(tree: AnimationTree) -> Array:
	var paths: Array = []
	for entry in tree.get_property_list():
		var name := str(entry.get("name", ""))
		if name.begins_with("parameters/"):
			paths.append(name)
	paths.sort()
	return paths


func _playback_paths(tree: AnimationTree) -> Array:
	var paths: Array = []
	for path in _parameter_paths(tree):
		if str(path).ends_with("/playback"):
			paths.append(path)
	return paths


func _playback_path_preview(root: AnimationNode) -> String:
	return "parameters/%s/playback" % _root_label(root)


func _playback_path(context: Dictionary, root: AnimationNode) -> String:
	if context.has("tree") and context.tree != null and not _dry_run:
		for path in _playback_paths(context.tree):
			return str(path)
	return _playback_path_preview(root)


static func _root_label(root: AnimationNode) -> String:
	if root is AnimationNodeStateMachine:
		return "StateMachine"
	if root is AnimationNodeBlendSpace1D:
		return "BlendSpace1D"
	if root is AnimationNodeBlendSpace2D:
		return "BlendSpace2D"
	if root is AnimationNodeBlendTree:
		return "BlendTree"
	return "Animation"


## Parameter paths a *not-yet-committed* root would expose (best effort preview).
func _parameter_paths_preview(root: AnimationNode) -> Array:
	var label := _root_label(root)
	var paths: Array = []
	if root is AnimationNodeStateMachine:
		for name in (root as AnimationNodeStateMachine).get_node_list():
			var node := (root as AnimationNodeStateMachine).get_node(name)
			if node is AnimationNodeAnimation and str((node as AnimationNodeAnimation).animation).is_empty():
				continue
		paths.append("parameters/conditions/<name>")
		paths.append("parameters/%s/playback" % label)
	elif root is AnimationNodeBlendSpace1D:
		paths.append("parameters/%s/blend_position" % label)
	elif root is AnimationNodeBlendSpace2D:
		paths.append("parameters/%s/blend_position" % label)
	elif root is AnimationNodeBlendTree:
		for node_name in (root as AnimationNodeBlendTree).get_node_list():
			var node := (root as AnimationNodeBlendTree).get_node(node_name)
			if node is AnimationNodeOneShot:
				paths.append("parameters/%s/request" % node_name)
			elif node is AnimationNodeAdd2:
				paths.append("parameters/%s/add_amount" % node_name)
			elif node is AnimationNodeBlend2:
				paths.append("parameters/%s/blend_amount" % node_name)
	return paths


static func _first_matching(paths: Array, suffix: String) -> String:
	for path in paths:
		if str(path).ends_with(suffix):
			return str(path)
	return ""


## Path from the tree to the player. A tree created during context resolution is
## still detached, so the path is derived from its intended parent.
func _anim_player_path(context: Dictionary, tree: AnimationTree) -> NodePath:
	if tree.get_parent() != null:
		return tree.get_path_to(context.player)
	var parent: Node = context.get("tree_parent", null)
	if parent == null:
		return NodePath()
	var relative := str(parent.get_path_to(context.player))
	if relative.is_empty():
		return NodePath("..")
	return NodePath("../" + relative)


## Commit the built root as one undo action (or report it for a dry run).
func _commit_graph(context: Dictionary, root: AnimationNode, action_label: String, extra: Dictionary) -> Dictionary:
	var tree: AnimationTree = context.tree
	var created := bool(context.get("tree_created", false)) or tree.get_parent() == null
	var scene_root := EditorInterface.get_edited_scene_root()
	var old_root: AnimationRootNode = tree.tree_root if not created else null
	var old_anim_player := tree.anim_player
	var old_active := tree.active
	var parameter_path := str(extra.get("parameter_path", ""))
	var parameter_value = extra.get("parameter_value")
	if not _dry_run:
		_create_scene_pinned_action(action_label)
		var undo := ToolContext.undo_redo
		if created:
			var parent: Node = context.get("tree_parent", null)
			if parent == null:
				parent = scene_root
			undo.add_do_method(parent, "add_child", tree, true)
			undo.add_undo_method(parent, "remove_child", tree)
			undo.add_do_method(tree, "set_owner", scene_root)
			undo.add_do_reference(tree)
		if root != null:
			undo.add_do_property(tree, "tree_root", root)
			undo.add_undo_property(tree, "tree_root", old_root)
		var wanted_player := _anim_player_path(context, tree)
		if tree.anim_player != wanted_player:
			undo.add_do_property(tree, "anim_player", wanted_player)
			undo.add_undo_property(tree, "anim_player", old_anim_player)
		var want_active := bool(context.get("active", false))
		if tree.active != want_active:
			undo.add_do_property(tree, "active", want_active)
			undo.add_undo_property(tree, "active", old_active)
		if not parameter_path.is_empty():
			var old_value = tree.get(parameter_path)
			undo.add_do_property(tree, parameter_path, parameter_value)
			undo.add_undo_property(tree, parameter_path, old_value)
		undo.commit_action()
	var tree_label := ""
	if created and context.get("tree_parent", null) != null:
		tree_label = ValueCodec.from_node(context.tree_parent, scene_root) + "/" + str(tree.name)
	else:
		tree_label = ValueCodec.from_node(tree, scene_root)
	var data := {
		"player_path": str(context.player_path),
		"tree_path": tree_label,
		"created": created,
		"tree_root": _root_label(root) if root != null else _root_label(tree.tree_root),
		"active": bool(context.get("active", false)),
		"active_note": "an active AnimationTree also drives the scene while you edit it" if bool(context.get("active", false)) else "inactive: pass active=true (or enable the tree) when the scene is ready",
		"animations": GraphBuilders.animations_in(root) if root != null else GraphBuilders.animations_in(tree.tree_root),
		"issues": extra.get("issues", []),
		"undoable": true,
	}
	var cleaned := extra.duplicate()
	cleaned.erase("parameter_path")
	cleaned.erase("parameter_value")
	cleaned.erase("issues")
	data.merge(cleaned, true)
	if not _dry_run and tree.get_parent() != null:
		var parameters := _parameter_paths(tree)
		data["parameters"] = parameters
		var playbacks := _playback_paths(tree)
		data["playback_paths"] = playbacks
		if data.has("start_state") and not playbacks.is_empty():
			data["start_hint"] = "at runtime call get_node(tree).get(\"%s\").start(\"%s\")" % [
				playbacks[0], str(data.start_state)]
		if not parameter_path.is_empty():
			data["parameter_set"] = {"path": parameter_path, "value": parameter_value}
		for key in ["request_parameter", "amount_parameter"]:
			if data.has(key) and str(data[key]).begins_with("parameters/"):
				data[key] = _first_matching(parameters, "/" + str(data[key]).get_file())
	else:
		data["parameters_preview"] = _parameter_paths_preview(root)
	return {"data": data}
