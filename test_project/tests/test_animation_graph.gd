@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const GraphHandler := preload("res://addons/godot_ai_animation/handlers/graph.gd")

## Tests for the animation_graph tool (state machines, blend spaces, blend
## trees, wire, graph_get, locomotion, layers).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: GraphHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_graph"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = GraphHandler.new()


func suite_teardown() -> void:
	pass


# --- helpers ---------------------------------------------------------------

func _add_player(player_name: String, clips: Array = ["idle", "walk", "run"]) -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ""
	var player := AnimationPlayer.new()
	player.name = player_name
	var library := AnimationLibrary.new()
	for clip_name in clips:
		var spec := ClipSpec.make(1.0, Animation.LOOP_LINEAR)
		ClipSpec.add_value_track(spec, "Sprite:position", [
			{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
			{"time": 1.0, "value": Vector2(10, 0), "transition": 1.0},
		])
		library.add_animation(clip_name, SpecBuilder.to_animation(spec))
	player.add_animation_library("", library)
	scene_root.add_child(player)
	player.set_owner(scene_root)
	return "/" + scene_root.name + "/" + player_name


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _scene_root_name() -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	return scene_root.name if scene_root != null else ""


func _find_tree() -> AnimationTree:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	var trees: Array = scene_root.find_children("*", "AnimationTree", true, false)
	return trees[0] as AnimationTree if not trees.is_empty() else null


func _has_param_ending(params: Variant, suffix: String) -> bool:
	for path in (params as Array):
		if str(path).ends_with(suffix):
			return true
	return false


## Player with idle/walk/run plus cleanup bookkeeping.
func _rig(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	_add_player(prefix + "Sprite", ["idle", "walk", "run"])
	var player_path := _add_player(prefix + "Player", ["idle", "walk", "run"])
	if player_path.is_empty():
		return {"error": "no player"}
	return {"player_path": player_path, "prefix": prefix}


func _teardown(rig: Dictionary) -> void:
	var tree := _find_tree()
	if tree != null:
		_remove_node("/" + _scene_root_name() + "/" + str(tree.name))
	if rig.has("player_path"):
		_remove_node(rig.player_path)
	_remove_node("/" + _scene_root_name() + "/" + str(rig.get("prefix", "")) + "Sprite")


func _sm_params(rig: Dictionary) -> Dictionary:
	return {
		"op": "state_machine",
		"player_path": rig.player_path,
		"states": [
			{"name": "idle", "animation": "idle"},
			{"name": "walk", "animation": "walk"},
		],
		"transitions": [
			{"from": "idle", "to": "walk", "xfade": 0.2, "condition": "walking"},
			{"from": "walk", "to": "idle", "xfade": 0.2, "advance_expression": "!walking"},
		],
	}


# --- rollup ----------------------------------------------------------------

func test_rollup_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "teleport"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "state_machine")
	assert_contains(unknown.error.message, "blend_tree")


# --- state machines --------------------------------------------------------

func test_state_machine_creates_tree_and_parameters() -> void:
	var rig := _rig("GraphSm")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run(_sm_params(rig), null)
	assert_has_key(result, "data")
	var tree := _find_tree()
	assert_true(tree != null, "the AnimationTree is created")
	assert_false(tree.active, "the tree stays inactive by default (an active tree drives the scene at edit time)")
	assert_true(tree.get_node_or_null(tree.anim_player) is AnimationPlayer, "anim_player resolves")
	assert_true(tree.tree_root is AnimationNodeStateMachine, "the root is a state machine")
	var machine := tree.tree_root as AnimationNodeStateMachine
	assert_true(machine.has_node(StringName("idle")) and machine.has_node(StringName("walk")),
		"both states exist")
	assert_eq(machine.get_transition_count(), 2)
	assert_true(_has_param_ending(result.data.parameters, "/playback"), "a playback parameter is exposed")
	assert_true(_has_param_ending(result.data.parameters, "conditions/walking"),
		"the condition is exposed as a parameter (%s)" % str(result.data.parameters))
	assert_eq((result.data.issues as Array).size(), 0, "no issues for known clips")
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(_find_tree() == null, "one undo removes the created tree")
	_teardown(rig)


func test_state_machine_replaces_existing_root() -> void:
	var rig := _rig("GraphReplace")
	if rig.has("error"):
		skip(rig.error)
		return
	var first := _handler.run(_sm_params(rig), null)
	assert_has_key(first, "data")
	var tree := _find_tree()
	var old_root := tree.tree_root
	var second := _handler.run({
		"op": "state_machine", "player_path": rig.player_path, "tree_path": "/" + _scene_root_name() + "/" + str(tree.name),
		"states": [{"name": "run", "animation": "run"}],
		"transitions": [],
	}, null)
	assert_has_key(second, "data")
	assert_eq(_find_tree().tree_root.get_node_list().size(), 3, "the new root replaces the old one (Start/End/run)")
	var did_undo := editor_undo(_undo_redo)
	assert_true(did_undo, "undo should succeed")
	assert_true(_find_tree().tree_root == old_root, "undo restores the previous root")
	_teardown(rig)


# --- blend spaces / trees --------------------------------------------------

func test_blend_space_1d_and_2d() -> void:
	var rig := _rig("GraphSpace")
	if rig.has("error"):
		skip(rig.error)
		return
	var flat := _handler.run({
		"op": "blend_space", "player_path": rig.player_path, "dimensions": 1,
		"points": [
			{"animation": "idle", "position": 0.0},
			{"animation": "walk", "position": 1.0},
			{"animation": "run", "position": 2.0},
		],
		"min": 0.0, "max": 2.0,
	}, null)
	assert_has_key(flat, "data")
	assert_eq(int(flat.data.point_count), 3)
	assert_true(_find_tree().tree_root is AnimationNodeBlendSpace1D, "the root is a 1D blend space")
	assert_true(_has_param_ending(flat.data.parameters, "/blend_position"), "a blend_position parameter is exposed")
	var planar := _handler.run({
		"op": "blend_space", "player_path": rig.player_path, "dimensions": 2,
		"points": [
			{"animation": "idle", "position": {"x": 0, "y": 0}},
			{"animation": "run", "position": {"x": 1, "y": 0}},
			{"animation": "walk", "position": {"x": 0, "y": 1}},
		],
		"min": {"x": -1, "y": -1}, "max": {"x": 1, "y": 1},
	}, null)
	assert_has_key(planar, "data")
	var space := _find_tree().tree_root as AnimationNodeBlendSpace2D
	assert_true(space != null and space.get_blend_point_count() == 3, "three 2D points")
	_teardown(rig)


func test_blend_space_uses_sync_mode_not_the_deprecated_sync_flag() -> void:
	var rig := _rig("GraphSync")
	if rig.has("error"):
		skip(rig.error)
		return
	for dimensions in [1, 2]:
		var result := _handler.run({
			"op": "blend_space", "player_path": rig.player_path, "dimensions": dimensions,
			"points": [
				{"animation": "idle", "position": 0.0 if dimensions == 1 else {"x": 0, "y": 0}},
				{"animation": "walk", "position": 1.0 if dimensions == 1 else {"x": 1, "y": 1}},
			],
			"sync": dimensions == 1,
		}, null)
		assert_has_key(result, "data")
		var space := _find_tree().tree_root as AnimationRootNode
		assert_true(space != null, "a %dD blend space is built" % dimensions)
		var want := AnimationNodeBlendSpace1D.SYNC_MODE_INDEPENDENT if dimensions == 1 \
			else AnimationNodeBlendSpace1D.SYNC_MODE_NONE
		# `get` rather than a typed access: sync_mode belongs to the blend-space
		# subclasses, not to the AnimationRootNode base.
		assert_eq(int(space.get("sync_mode")), want,
			"%dD: sync=%s lands on SYNC_MODE %d" % [dimensions, str(dimensions == 1), want])
	_teardown(rig)


func test_blend_tree_nested() -> void:
	var rig := _rig("GraphTree")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({
		"op": "blend_tree", "player_path": rig.player_path,
		"root": {
			"type": "one_shot", "fadein": 0.1, "fadeout": 0.2,
			"inputs": [{"type": "blend2", "inputs": [
				{"type": "animation", "animation": "idle"},
				{"type": "animation", "animation": "walk"},
			]}],
		},
	}, null)
	assert_has_key(result, "data")
	var tree := _find_tree().tree_root as AnimationNodeBlendTree
	assert_true(tree != null, "the root is a blend tree")
	assert_true(tree.has_node(StringName("OneShot")) and tree.has_node(StringName("Blend2")),
		"both nodes exist (%s)" % str(tree.get_node_list()))
	assert_eq(int(result.data.node_count), 4)
	assert_true(_has_param_ending(result.data.parameters, "/request"), "the one-shot request parameter is exposed")
	_teardown(rig)


# --- wire / graph_get ------------------------------------------------------

func test_wire_with_create_false_never_creates_a_tree() -> void:
	# `create` was advertised but ignored, so the "is it already wired?" check
	# created the very tree the caller was asking about.
	var rig := _rig("GraphNoCreate")
	if rig.has("error"):
		skip(rig.error)
		return
	var wanted := "/" + _scene_root_name() + "/GraphNoCreateTree"
	var refused := _handler.run({
		"op": "wire", "player_path": rig.player_path, "tree_path": wanted, "create": false,
	}, null)
	assert_is_error(refused, ErrorCodes.NODE_NOT_FOUND)
	var scene_root := EditorInterface.get_edited_scene_root()
	assert_true(ValueCodec.resolve_scene_path(wanted, scene_root) == null,
		"create=false put no AnimationTree in the scene")
	assert_true(_find_tree() == null, "and no tree appeared anywhere")
	# The default still creates, so the refusal is about the flag and not the op.
	var created := _handler.run({
		"op": "wire", "player_path": rig.player_path, "tree_path": wanted,
	}, null)
	assert_has_key(created, "data")
	assert_true(ValueCodec.resolve_scene_path(wanted, scene_root) is AnimationTree,
		"without the flag the tree is created as documented")
	# Once it exists, create=false succeeds against the same path.
	var reused := _handler.run({
		"op": "wire", "player_path": rig.player_path, "tree_path": wanted, "create": false,
	}, null)
	assert_has_key(reused, "data")
	assert_false(bool(reused.data.created), "create=false reuses the existing tree")
	_teardown(rig)


func test_wire_creates_tree_and_sets_parameter() -> void:
	var rig := _rig("GraphWire")
	if rig.has("error"):
		skip(rig.error)
		return
	var created := _handler.run({"op": "wire", "player_path": rig.player_path}, null)
	assert_has_key(created, "data")
	assert_true(bool(created.data.created), "wire reports the creation")
	assert_true(_find_tree() != null, "the tree exists")
	var built := _handler.run(_sm_params(rig), null)
	assert_has_key(built, "data")
	var condition_path := ""
	for path in built.data.parameters:
		if str(path).ends_with("conditions/walking"):
			condition_path = str(path)
	assert_false(condition_path.is_empty(), "the condition parameter exists")
	var wired := _handler.run({
		"op": "wire", "player_path": rig.player_path,
		"parameter_path": condition_path, "parameter_value": true,
	}, null)
	assert_has_key(wired, "data")
	assert_true(bool(_find_tree().get(condition_path)), "the parameter value is applied")
	assert_false(_find_tree().active, "wire leaves the tree inactive by default")
	var activated := _handler.run({
		"op": "wire", "player_path": rig.player_path, "active": true,
	}, null)
	assert_has_key(activated, "data")
	assert_true(_find_tree().active, "active=true opts in")
	_find_tree().active = false
	var extra_path := "/" + _scene_root_name() + "/ExtraTree"
	var extra := _handler.run({
		"op": "wire", "player_path": rig.player_path, "tree_path": extra_path,
	}, null)
	assert_has_key(extra, "data")
	assert_true(bool(extra.data.created), "a tree at an explicit path is created")
	var extra_node := ValueCodec.resolve_scene_path(extra_path, EditorInterface.get_edited_scene_root())
	assert_true(extra_node is AnimationTree, "the tree exists at the requested path")
	var bad_parent := _handler.run({
		"op": "wire", "player_path": rig.player_path, "tree_path": "/" + _scene_root_name() + "/Nope/Deep",
	}, null)
	assert_is_error(bad_parent, ErrorCodes.NODE_NOT_FOUND)
	_remove_node(extra_path)
	_teardown(rig)


func test_graph_get_dumps_and_flags() -> void:
	var rig := _rig("GraphGet")
	if rig.has("error"):
		skip(rig.error)
		return
	_handler.run(_sm_params(rig), null)
	var dump := _handler.run({"op": "graph_get", "player_path": rig.player_path}, null)
	assert_has_key(dump, "data")
	assert_eq(str(dump.data.root.type), "state_machine")
	assert_eq(int(dump.data.root.state_count), 2)
	assert_eq(int(dump.data.root.transition_count), 2)
	assert_true((dump.data.animations as Array).has("idle"), "referenced clips are listed")
	var healthy_codes := _codes(dump.data.issues)
	assert_true(healthy_codes.is_empty() or healthy_codes == ["inactive_tree"],
		"a healthy graph only reports the inactive-tree info (%s)" % str(healthy_codes))
	# An inactive tree is reported.
	_find_tree().active = false
	var inactive := _handler.run({"op": "graph_get", "player_path": rig.player_path}, null)
	var inactive_codes := _codes(inactive.data.issues)
	assert_true(inactive_codes.has("inactive_tree"), "inactive trees are flagged (%s)" % str(inactive_codes))
	_find_tree().active = true
	# A graph that references a clip the player does not have.
	_handler.run({
		"op": "state_machine", "player_path": rig.player_path,
		"states": [{"name": "ghost", "animation": "ghost_clip"}],
		"transitions": [],
	}, null)
	var missing := _handler.run({"op": "graph_get", "player_path": rig.player_path}, null)
	assert_true(_codes(missing.data.issues).has("missing_clip"), "missing clips are flagged")
	_teardown(rig)


func _codes(issues: Variant) -> Array:
	var codes: Array = []
	for issue in (issues as Array):
		codes.append(str(issue.code))
	return codes


# --- ready-made setups -----------------------------------------------------

func test_locomotion_blend_space_and_state_machine() -> void:
	var rig := _rig("GraphLoco")
	if rig.has("error"):
		skip(rig.error)
		return
	var space := _handler.run({"op": "locomotion", "player_path": rig.player_path}, null)
	assert_has_key(space, "data")
	assert_eq(str(space.data.mode), "blend_space")
	assert_eq(int(space.data.point_count), 3)
	assert_true(_has_param_ending(space.data.parameters, "/blend_position"), "the speed parameter is exposed")
	var machine := _handler.run({
		"op": "locomotion", "player_path": rig.player_path, "mode": "state_machine", "start": "idle",
	}, null)
	assert_has_key(machine, "data")
	assert_eq(str(machine.data.mode), "state_machine")
	assert_eq(int(machine.data.transition_count), 4)
	var root_machine := _find_tree().tree_root as AnimationNodeStateMachine
	var auto_modes := 0
	for index in root_machine.get_transition_count():
		if root_machine.get_transition(index).advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO:
			auto_modes += 1
	assert_eq(auto_modes, 4,
		"condition transitions must be AUTO: Godot only evaluates conditions in auto mode")
	assert_true((machine.data.conditions as Array).has("walking") and (machine.data.conditions as Array).has("running"),
		"the walking/running conditions exist")
	assert_contains(str(machine.data.start_hint), "idle")
	var bad := _handler.run({"op": "locomotion", "player_path": rig.player_path, "mode": "teleport"}, null)
	assert_is_error(bad, ErrorCodes.VALUE_OUT_OF_RANGE)
	_teardown(rig)


func test_one_shot_layer_wraps_the_root() -> void:
	var rig := _rig("GraphShot")
	if rig.has("error"):
		skip(rig.error)
		return
	_handler.run(_sm_params(rig), null)
	var result := _handler.run({
		"op": "one_shot_layer", "player_path": rig.player_path, "animation": "run",
		"fadein": 0.1, "fadeout": 0.25,
	}, null)
	assert_has_key(result, "data")
	var tree := _find_tree().tree_root as AnimationNodeBlendTree
	assert_true(tree != null, "the root becomes a blend tree")
	assert_true(tree.has_node(StringName("Base")) and tree.has_node(StringName("OneShot")),
		"the base and the shot exist (%s)" % str(tree.get_node_list()))
	var shot := tree.get_node(StringName("OneShot")) as AnimationNodeOneShot
	assert_true(shot != null and is_equal_approx(shot.fadeout_time, 0.25), "the shot keeps its fade settings")
	assert_true(_has_param_ending(result.data.parameters, "/request"), "the request parameter is exposed")
	assert_true(tree.get_node(StringName("Shot")) is AnimationNodeAnimation,
		"the shot clip is wired as the one-shot's child node")
	assert_true(str((tree.get_node(StringName("Shot")) as AnimationNodeAnimation).animation) == "run",
		"the shot child carries the requested clip")
	var layered := _handler.run({"op": "additive_lean", "player_path": rig.player_path, "animation": "walk"}, null)
	assert_has_key(layered, "data")
	assert_true(_has_param_ending(layered.data.parameters, "/add_amount"), "the additive amount is exposed")
	_teardown(rig)


func test_dry_run_does_not_create_a_tree() -> void:
	var rig := _rig("GraphDry")
	if rig.has("error"):
		skip(rig.error)
		return
	var params := _sm_params(rig)
	params["dry_run"] = true
	var result := _handler.run(params, null)
	assert_has_key(result, "data")
	assert_true(bool(result.data.dry_run), "dry_run is reported")
	assert_true(_find_tree() == null, "no tree is created")
	assert_false((result.data.parameters_preview as Array).is_empty(), "a parameter preview is returned")
	_teardown(rig)


func test_validation_errors() -> void:
	var rig := _rig("GraphBad")
	if rig.has("error"):
		skip(rig.error)
		return
	var no_states := _handler.run({
		"op": "state_machine", "player_path": rig.player_path, "states": [],
	}, null)
	assert_is_error(no_states, ErrorCodes.MISSING_REQUIRED_PARAM)
	var bad_tree := _handler.run({
		"op": "blend_tree", "player_path": rig.player_path, "root": {"type": "blend2", "inputs": []},
	}, null)
	assert_is_error(bad_tree, ErrorCodes.INVALID_PARAMS)
	var no_points := _handler.run({
		"op": "blend_space", "player_path": rig.player_path, "points": [],
	}, null)
	assert_is_error(no_points, ErrorCodes.MISSING_REQUIRED_PARAM)
	var no_root := _handler.run({
		"op": "one_shot_layer", "player_path": rig.player_path, "animation": "run",
	}, null)
	assert_is_error(no_root, ErrorCodes.MISSING_REQUIRED_PARAM)
	assert_contains(no_root.error.message, "base")
	_teardown(rig)


func test_registry_matches_graph_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_GRAPH)
	assert_false(info.is_empty(), "the graph family is registered")
	var op_enum: Array = info.schema.properties.op.enum
	assert_eq(op_enum.size(), 8, "the graph schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(info.schema.properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the graph description fits the custom-tool cap")
