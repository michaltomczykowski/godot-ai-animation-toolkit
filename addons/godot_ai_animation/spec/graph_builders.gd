@tool
extends RefCounted

## Pure builders for the `animation_graph` tool: AnimationNode* graphs built from
## declarative specs, plus a structural dump and a clip-reference validator.
##
## No node or editor access happens here, so the whole graph surface is tier-1
## testable headless. The handler resolves the AnimationPlayer/AnimationTree,
## validates clip names, and commits one undo action.

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

const _MAX_NODES := 64
const _MAX_DEPTH := 8

## Nodes Godot adds implicitly: state machine Start/End markers and the blend
## tree output port. They are structural, not authored states/nodes.
const _IMPLICIT_STATES := ["Start", "End"]
const _IMPLICIT_TREE_NODES := ["output"]

const _ADVANCE_MODES := {
	"disabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED,
	"enabled": AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED,
	"auto": AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
}

const _SWITCH_MODES := {
	"immediate": AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE,
	"sync": AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC,
	"at_end": AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
}

const _STATE_MACHINE_TYPES := {
	"root": AnimationNodeStateMachine.STATE_MACHINE_TYPE_ROOT,
	"nested": AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED,
	"grouped": AnimationNodeStateMachine.STATE_MACHINE_TYPE_GROUPED,
}

const _MIX_MODES := {
	"blend": AnimationNodeOneShot.MIX_MODE_BLEND,
	"add": AnimationNodeOneShot.MIX_MODE_ADD,
}

## Blend-tree node types and how many inputs each takes.
const _TREE_TYPES := {
	"animation": 0,
	"blend2": 2,
	"blend3": 3,
	"add2": 2,
	"add3": 3,
	"one_shot": 1,
	"time_scale": 1,
	"state_machine": 0,
	"blend_space_1d": 0,
	"blend_space_2d": 0,
}


# --- state machine ---------------------------------------------------------

## Build an AnimationNodeStateMachine from
## `{states: [{name, animation, position?}], transitions: [{from, to, ...}]}`.
static func state_machine(spec: Dictionary) -> Dictionary:
	var states: Array = spec.get("states", [])
	var transitions: Array = spec.get("transitions", [])
	if states.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "A state machine needs at least one state")
	var machine := AnimationNodeStateMachine.new()
	machine.set_allow_transition_to_self(bool(spec.get("allow_transition_to_self", false)))
	machine.set_reset_ends(bool(spec.get("reset_ends", false)))
	var type_name := str(spec.get("state_machine_type", "root"))
	if not _STATE_MACHINE_TYPES.has(type_name):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid state_machine_type '%s'. Valid: %s" % [type_name, ", ".join(_STATE_MACHINE_TYPES.keys())])
	machine.set_state_machine_type(_STATE_MACHINE_TYPES[type_name])
	var conditions: Array = []
	var state_names: Array = []
	for index in states.size():
		var state: Dictionary = states[index]
		var name := str(state.get("name", ""))
		var clip := str(state.get("animation", ""))
		if name.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "states[%d] is missing 'name'" % index)
		if state_names.has(name):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Duplicate state name '%s'" % name)
		state_names.append(name)
		var node := AnimationNodeAnimation.new()
		if not clip.is_empty():
			node.animation = StringName(clip)
		var position: Vector2 = _coerce_vector2(state.get("position"), Vector2(float(index) * 240.0, 0.0))
		machine.add_node(StringName(name), node, position)
	for index in transitions.size():
		var transition: Dictionary = transitions[index]
		var from := str(transition.get("from", ""))
		var to := str(transition.get("to", ""))
		if not state_names.has(from) or not state_names.has(to):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"transitions[%d] references unknown states ('%s' -> '%s'). States: %s"
				% [index, from, to, ", ".join(state_names)])
		var link := AnimationNodeStateMachineTransition.new()
		link.xfade_time = float(transition.get("xfade", transition.get("xfade_time", 0.2)))
		link.priority = int(transition.get("priority", 1))
		link.reset = bool(transition.get("reset", true))
		var advance := str(transition.get("advance_mode", "auto"))
		if not _ADVANCE_MODES.has(advance):
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid advance_mode '%s'. Valid: %s" % [advance, ", ".join(_ADVANCE_MODES.keys())])
		link.advance_mode = _ADVANCE_MODES[advance]
		var switch := str(transition.get("switch_mode", "immediate"))
		if not _SWITCH_MODES.has(switch):
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid switch_mode '%s'. Valid: %s" % [switch, ", ".join(_SWITCH_MODES.keys())])
		link.switch_mode = _SWITCH_MODES[switch]
		var condition := str(transition.get("condition", ""))
		if not condition.is_empty():
			link.advance_condition = StringName(condition)
			if not conditions.has(condition):
				conditions.append(condition)
		var expression := str(transition.get("advance_expression", ""))
		if not expression.is_empty():
			link.advance_expression = expression
		machine.add_transition(StringName(from), StringName(to), link)
	return {
		"root": machine,
		"state_count": states.size(),
		"transition_count": transitions.size(),
		"conditions": conditions,
		"issues": _collect_issues(machine, []),
	}


# --- blend space -----------------------------------------------------------

## Build an AnimationNodeBlendSpace1D/2D from
## `{dimensions: 1|2, points: [{animation, position, name?}], min, max, snap}`.
static func blend_space(spec: Dictionary) -> Dictionary:
	var dimensions := int(spec.get("dimensions", 1))
	var points: Array = spec.get("points", [])
	if points.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "A blend space needs at least one point")
	if dimensions != 1 and dimensions != 2:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'dimensions' must be 1 or 2")
	var space: AnimationRootNode
	# `sync` stays the caller's switch, but it now lands on `sync_mode`: the
	# `sync` property is deprecated in 4.7 and its `set_use_sync` setter will go.
	# True is SYNC_MODE_INDEPENDENT (inactive animations advance at weight 0),
	# false is SYNC_MODE_NONE (they freeze).
	var sync_mode: int = AnimationNodeBlendSpace1D.SYNC_MODE_INDEPENDENT \
		if bool(spec.get("sync", true)) else AnimationNodeBlendSpace1D.SYNC_MODE_NONE
	if dimensions == 1:
		var space_1d := AnimationNodeBlendSpace1D.new()
		space_1d.set_min_space(float(spec.get("min", 0.0)))
		space_1d.set_max_space(float(spec.get("max", 1.0)))
		space_1d.set_snap(float(spec.get("snap", 0.1)))
		space_1d.sync_mode = sync_mode
		space = space_1d
	else:
		var space_2d := AnimationNodeBlendSpace2D.new()
		space_2d.set_min_space(_coerce_vector2(spec.get("min"), Vector2.ZERO))
		space_2d.set_max_space(_coerce_vector2(spec.get("max"), Vector2.ONE))
		space_2d.set_snap(_coerce_vector2(spec.get("snap"), Vector2(0.1, 0.1)))
		space_2d.sync_mode = sync_mode
		space = space_2d
	var count := 0
	for index in points.size():
		var point: Dictionary = points[index]
		var clip := str(point.get("animation", ""))
		if clip.is_empty():
			return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "points[%d] is missing 'animation'" % index)
		var node := AnimationNodeAnimation.new()
		node.animation = StringName(clip)
		var name := str(point.get("name", ""))
		if name.is_empty():
			name = clip
		if dimensions == 1:
			(space as AnimationNodeBlendSpace1D).add_blend_point(node, float(point.get("position", 0.0)), -1, StringName(name))
		else:
			(space as AnimationNodeBlendSpace2D).add_blend_point(
				node, _coerce_vector2(point.get("position"), Vector2.ZERO), -1, StringName(name))
		count += 1
	return {
		"root": space,
		"dimensions": dimensions,
		"point_count": count,
		"issues": _collect_issues(space, []),
	}


# --- blend tree ------------------------------------------------------------

## Wrap an existing root (blend space, state machine, tree, clip) in a one-shot
## layer: BlendTree(Base -> Blend2, OneShot -> Shot -> Blend2 -> output).
## Nothing is committed here; the caller writes `root` to an AnimationTree.
static func wrap_one_shot(
	base_root: AnimationNode, animation: String, fadein := 0.1, fadeout := 0.2,
	mix_mode := "blend", autorestart := false,
) -> Dictionary:
	if base_root == null:
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "wrap_one_shot needs a base root node")
	if animation.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "wrap_one_shot needs an animation name")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = fadein
	shot.fadeout_time = fadeout
	shot.autorestart = autorestart
	if mix_mode == "add":
		shot.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	elif mix_mode == "blend":
		shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	else:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid mix_mode '%s'. Valid: blend, add" % mix_mode)
	var clip := AnimationNodeAnimation.new()
	clip.animation = StringName(animation)
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(StringName("Base"), base_root, Vector2(0.0, 0.0))
	tree.add_node(StringName("OneShot"), shot, Vector2(220.0, 0.0))
	tree.add_node(StringName("Shot"), clip, Vector2(220.0, 140.0))
	tree.connect_node(StringName("OneShot"), 0, StringName("Shot"))
	var blend := AnimationNodeBlend2.new()
	tree.add_node(StringName("Blend2"), blend, Vector2(440.0, 0.0))
	tree.connect_node(StringName("Blend2"), 0, StringName("Base"))
	tree.connect_node(StringName("Blend2"), 1, StringName("OneShot"))
	if tree.has_node(StringName("output")):
		tree.connect_node(StringName("output"), 0, StringName("Blend2"))
	return {"root": tree, "node_count": tree.get_node_list().size(), "issues": _collect_issues(tree, [])}


## Build an AnimationNodeBlendTree from a recursive node spec. Nodes are added
## to the graph and wired with connect_node (the API Godot's editor uses).
static func blend_tree(spec: Dictionary) -> Dictionary:
	var state := {
		"tree": AnimationNodeBlendTree.new(),
		"counters": {},
		"connections": [],
		"issues": [],
		"node_count": 0,
		"animation_count": 0,
	}
	var root_name := _add_spec_node(state, spec, Vector2(0.0, 0.0), 0)
	if root_name.is_empty():
		return state.issues[0] if not state.issues.is_empty() else ErrorCodes.make(
			ErrorCodes.INVALID_PARAMS, "Could not build the blend tree")
	var tree: AnimationNodeBlendTree = state.tree
	for connection in state.connections:
		tree.connect_node(StringName(connection.parent), int(connection.index), StringName(connection.child))
	# A blend tree whose `output` node is left unconnected evaluates to nothing:
	# the graph builds, nothing errors, and no pose ever plays. The spec's root is
	# what the tree has to output.
	#
	# This is unconditional rather than "unless already connected" because 4.7
	# exposes NO way to read a connection back (no is_node_connected, no
	# get_node_connection - the dump says so too), so a "check first" test is not
	# possible. It cannot duplicate: a fresh blend tree's `output` has nothing
	# attached, and `_add_spec_node` refuses a spec node named `output` as a
	# duplicate of the implicit one, so no spec can have wired it already.
	var output_name := StringName("output")
	var output_wired := false
	if tree.has_node(output_name):
		tree.connect_node(output_name, 0, StringName(root_name))
		output_wired = true
	return {
		"root": tree,
		"node_count": state.node_count,
		"animation_count": state.animation_count,
		"output_source": root_name if output_wired else "",
		"output_wired": output_wired,
		"issues": state.issues,
	}


static func _add_spec_node(state: Dictionary, spec: Dictionary, position: Vector2, depth: int) -> String:
	if depth > _MAX_DEPTH:
		state.issues.append(ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Blend tree nesting is limited to %d levels" % _MAX_DEPTH))
		return ""
	if state.node_count >= _MAX_NODES:
		state.issues.append(ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Blend trees are limited to %d nodes" % _MAX_NODES))
		return ""
	var type := str(spec.get("type", ""))
	if not _TREE_TYPES.has(type):
		state.issues.append(ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid blend-tree node type '%s'. Valid: %s" % [type, ", ".join(_TREE_TYPES.keys())]))
		return ""
	var inputs: Array = spec.get("inputs", [])
	var expected := int(_TREE_TYPES[type])
	if type != "animation" and type != "state_machine" and type != "blend_space_1d" and type != "blend_space_2d":
		if inputs.size() != expected:
			state.issues.append(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Blend-tree node '%s' needs %d input(s), got %d" % [type, expected, inputs.size()]))
			return ""
	var tree: AnimationNodeBlendTree = state.tree
	var name := str(spec.get("name", ""))
	if name.is_empty():
		var base := _type_label(type)
		state.counters[base] = int(state.counters.get(base, 0)) + 1
		var suffix := int(state.counters[base])
		name = base if suffix == 1 else "%s%d" % [base, suffix]
	if tree.has_node(StringName(name)):
		state.issues.append(ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Duplicate blend-tree node name '%s'" % name))
		return ""
	var node: AnimationNode
	match type:
		"animation":
			var clip := str(spec.get("animation", ""))
			if clip.is_empty():
				state.issues.append(ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
					"An 'animation' node needs 'animation'"))
				return ""
			var animation := AnimationNodeAnimation.new()
			animation.animation = StringName(clip)
			node = animation
			state.animation_count += 1
		"blend2":
			node = AnimationNodeBlend2.new()
		"blend3":
			node = AnimationNodeBlend3.new()
		"add2":
			node = AnimationNodeAdd2.new()
		"add3":
			node = AnimationNodeAdd3.new()
		"one_shot":
			var shot := AnimationNodeOneShot.new()
			shot.fadein_time = float(spec.get("fadein", 0.1))
			shot.fadeout_time = float(spec.get("fadeout", 0.2))
			shot.autorestart = bool(spec.get("autorestart", false))
			var mix := str(spec.get("mix_mode", "blend"))
			if not _MIX_MODES.has(mix):
				state.issues.append(ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
					"Invalid mix_mode '%s'. Valid: %s" % [mix, ", ".join(_MIX_MODES.keys())]))
				return ""
			shot.mix_mode = _MIX_MODES[mix]
			node = shot
		"time_scale":
			node = AnimationNodeTimeScale.new()
		"state_machine":
			var nested := state_machine(spec)
			if nested.has("error"):
				state.issues.append(nested)
				return ""
			node = nested.root
		"blend_space_1d":
			var space_1d := blend_space(spec)
			if space_1d.has("error"):
				state.issues.append(space_1d)
				return ""
			node = space_1d.root
		"blend_space_2d":
			var space_2d := blend_space(spec)
			if space_2d.has("error"):
				state.issues.append(space_2d)
				return ""
			node = space_2d.root
	tree.add_node(StringName(name), node, position)
	state.node_count += 1
	for index in inputs.size():
		var child_name := _add_spec_node(state, inputs[index], position + Vector2(0.0, 120.0 * float(index + 1)), depth + 1)
		if child_name.is_empty():
			return ""
		state.connections.append({"parent": name, "index": index, "child": child_name})
	return name


static func _type_label(type: String) -> String:
	match type:
		"animation":
			return "Animation"
		"blend2":
			return "Blend2"
		"blend3":
			return "Blend3"
		"add2":
			return "Add2"
		"add3":
			return "Add3"
		"one_shot":
			return "OneShot"
		"time_scale":
			return "TimeScale"
		"state_machine":
			return "StateMachine"
		"blend_space_1d":
			return "BlendSpace1D"
		"blend_space_2d":
			return "BlendSpace2D"
	return "Node"


# --- dump ------------------------------------------------------------------

## Structural description of any AnimationNode graph.
static func graph_dump(root: AnimationNode) -> Dictionary:
	if root == null:
		return {}
	if root is AnimationNodeStateMachine:
		return _dump_state_machine(root)
	if root is AnimationNodeBlendTree:
		return _dump_blend_tree(root)
	if root is AnimationNodeBlendSpace1D:
		return _dump_blend_space(root)
	if root is AnimationNodeBlendSpace2D:
		return _dump_blend_space(root)
	if root is AnimationNodeAnimation:
		return {"type": "animation", "animation": str((root as AnimationNodeAnimation).animation)}
	return {"type": "unknown", "class": root.get_class()}


static func _dump_state_machine(machine: AnimationNodeStateMachine) -> Dictionary:
	var states: Array = []
	for state_name in machine.get_node_list():
		if _IMPLICIT_STATES.has(str(state_name)):
			continue
		var node := machine.get_node(state_name)
		states.append({
			"name": str(state_name),
			"position": _serialize_vector2(machine.get_node_position(state_name)),
			"node": graph_dump(node),
		})
	var transitions: Array = []
	for index in machine.get_transition_count():
		var link := machine.get_transition(index)
		transitions.append({
			"from": str(machine.get_transition_from(index)),
			"to": str(machine.get_transition_to(index)),
			"xfade_time": link.xfade_time,
			"advance_mode": _name_of(_ADVANCE_MODES, link.advance_mode),
			"switch_mode": _name_of(_SWITCH_MODES, link.switch_mode),
			"condition": str(link.advance_condition),
			"advance_expression": link.advance_expression,
			"priority": link.priority,
			"reset": link.reset,
		})
	return {
		"type": "state_machine",
		"state_machine_type": _name_of(_STATE_MACHINE_TYPES, machine.get_state_machine_type()),
		"allow_transition_to_self": machine.is_allow_transition_to_self(),
		"reset_ends": machine.are_ends_reset(),
		"state_count": states.size(),
		"transition_count": transitions.size(),
		"states": states,
		"transitions": transitions,
	}


static func _dump_blend_tree(tree: AnimationNodeBlendTree) -> Dictionary:
	var nodes: Array = []
	for node_name in tree.get_node_list():
		if _IMPLICIT_TREE_NODES.has(str(node_name)):
			continue
		var node := tree.get_node(node_name)
		var entry := {
			"name": str(node_name),
			"position": _serialize_vector2(tree.get_node_position(node_name)),
			"input_count": node.get_input_count(),
			"node": graph_dump(node),
		}
		nodes.append(entry)
	return {
		"type": "blend_tree",
		"node_count": nodes.size(),
		"nodes": nodes,
		"note": "connections are not readable from the API - rebuild with blend_tree to change the wiring",
	}


static func _dump_blend_space(space: AnimationNode) -> Dictionary:
	var points: Array = []
	if space is AnimationNodeBlendSpace1D:
		var space_1d := space as AnimationNodeBlendSpace1D
		for index in space_1d.get_blend_point_count():
			points.append({
				"animation": str((space_1d.get_blend_point_node(index) as AnimationNodeAnimation).animation)
					if space_1d.get_blend_point_node(index) is AnimationNodeAnimation else "",
				"position": space_1d.get_blend_point_position(index),
				"name": str(space_1d.get_blend_point_name(index)),
			})
		return {
			"type": "blend_space_1d",
			"point_count": points.size(),
			"min": space_1d.get_min_space(),
			"max": space_1d.get_max_space(),
			"snap": space_1d.get_snap(),
			"points": points,
		}
	var space_2d := space as AnimationNodeBlendSpace2D
	for index in space_2d.get_blend_point_count():
		var point_node := space_2d.get_blend_point_node(index)
		points.append({
			"animation": str((point_node as AnimationNodeAnimation).animation)
				if point_node is AnimationNodeAnimation else "",
			"position": _serialize_vector2(space_2d.get_blend_point_position(index)),
			"name": str(space_2d.get_blend_point_name(index)),
		})
	return {
		"type": "blend_space_2d",
		"point_count": points.size(),
		"min": _serialize_vector2(space_2d.get_min_space()),
		"max": _serialize_vector2(space_2d.get_max_space()),
		"snap": _serialize_vector2(space_2d.get_snap()),
		"points": points,
	}


# --- validation ------------------------------------------------------------

## Every clip referenced anywhere in the graph, in discovery order.
static func animations_in(root: AnimationNode) -> Array:
	var found: Array = []
	_collect_animations(root, found)
	return found


static func _collect_animations(node: AnimationNode, found: Array) -> void:
	if node == null:
		return
	if node is AnimationNodeAnimation:
		var clip := str((node as AnimationNodeAnimation).animation)
		if not clip.is_empty() and not found.has(clip):
			found.append(clip)
		return
	if node is AnimationNodeStateMachine:
		for state_name in (node as AnimationNodeStateMachine).get_node_list():
			_collect_animations((node as AnimationNodeStateMachine).get_node(state_name), found)
		return
	if node is AnimationNodeBlendTree:
		for node_name in (node as AnimationNodeBlendTree).get_node_list():
			_collect_animations((node as AnimationNodeBlendTree).get_node(node_name), found)
		return
	if node is AnimationNodeBlendSpace1D:
		var space_1d := node as AnimationNodeBlendSpace1D
		for index in space_1d.get_blend_point_count():
			_collect_animations(space_1d.get_blend_point_node(index), found)
		return
	if node is AnimationNodeBlendSpace2D:
		var space_2d := node as AnimationNodeBlendSpace2D
		for index in space_2d.get_blend_point_count():
			_collect_animations(space_2d.get_blend_point_node(index), found)
		return


## Structural findings for a graph: clips the player does not have, animation
## nodes with no clip, state machines that cannot move. `clips` empty skips the
## missing-clip check.
static func _collect_issues(root: AnimationNode, clips: Array) -> Array:
	var issues: Array = []
	_walk_issues(root, clips, issues)
	return issues


static func _walk_issues(node: AnimationNode, clips: Array, issues: Array) -> void:
	if node == null:
		return
	if node is AnimationNodeAnimation:
		var clip := str((node as AnimationNodeAnimation).animation)
		if clip.is_empty():
			issues.append({"severity": "warning", "code": "empty_animation",
				"message": "an animation node has no clip assigned"})
		elif not clips.is_empty() and not clips.has(clip):
			issues.append({"severity": "warning", "code": "missing_clip",
				"message": "the graph references clip '%s', which the player does not have" % clip})
		return
	if node is AnimationNodeStateMachine:
		var machine := node as AnimationNodeStateMachine
		if machine.get_node_list().size() > 1 and machine.get_transition_count() == 0:
			issues.append({"severity": "warning", "code": "no_transitions",
				"message": "the state machine has multiple states but no transitions"})
		for state_name in machine.get_node_list():
			_walk_issues(machine.get_node(state_name), clips, issues)
		return
	if node is AnimationNodeBlendTree:
		for node_name in (node as AnimationNodeBlendTree).get_node_list():
			_walk_issues((node as AnimationNodeBlendTree).get_node(node_name), clips, issues)
		return
	if node is AnimationNodeBlendSpace1D:
		var space_1d := node as AnimationNodeBlendSpace1D
		for index in space_1d.get_blend_point_count():
			_walk_issues(space_1d.get_blend_point_node(index), clips, issues)
		return
	if node is AnimationNodeBlendSpace2D:
		var space_2d := node as AnimationNodeBlendSpace2D
		for index in space_2d.get_blend_point_count():
			_walk_issues(space_2d.get_blend_point_node(index), clips, issues)
		return


## Public issue scan with the player's clip list.
static func issues_for(root: AnimationNode, clips: Array) -> Array:
	return _collect_issues(root, clips)


# --- helpers ---------------------------------------------------------------

static func _coerce_vector2(raw: Variant, fallback: Vector2) -> Vector2:
	if raw == null:
		return fallback
	if raw is Vector2:
		return raw
	if raw is Dictionary and raw.has("x") and raw.has("y"):
		return Vector2(float(raw.x), float(raw.y))
	if raw is Array and (raw as Array).size() == 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return fallback


static func _serialize_vector2(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _name_of(table: Dictionary, value: int) -> String:
	for key in table:
		if int(table[key]) == value:
			return str(key)
	return str(value)
