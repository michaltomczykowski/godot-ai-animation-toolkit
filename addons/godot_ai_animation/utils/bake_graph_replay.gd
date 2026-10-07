@tool
extends RefCounted

## Deterministic commands for a fresh private graph. Never reads or reconstructs
## the source's private current crossfade, travel queue or solver state.
const Errors := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const Json := preload("res://addons/godot_ai_animation/spec/spec_json.gd")
var initial: Dictionary = {}
var starts: Array = []
var events: Array = []
var cursor := 0
var tree: AnimationTree

func configure(source: AnimationTree, params: Dictionary, duration: float) -> Dictionary:
	if source.tree_root == null: return _error("source tree has no root")
	var safe := _check_resource(source.tree_root, {})
	if safe.has("error"): return safe
	var entries := {}
	for entry in source.get_property_list():
		var path := str(entry.name)
		if not path.begins_with("parameters/"): continue
		entries[path] = entry
		var value: Variant = source.get(path)
		if value is AnimationNodeStateMachinePlayback: continue
		if int(entry.usage) & PROPERTY_USAGE_READ_ONLY: continue
		# Requests are consumable commands, not a reproducible initial state.
		if path.ends_with("/request"): value = 0
		elif path.ends_with("/seek_request"): value = -1.0
		elif path.ends_with("/transition_request"): value = ""
		initial[path] = value
	var overrides: Variant = params.get("tree_parameters", {})
	if not overrides is Dictionary: return _error("tree_parameters must be an object")
	for path in overrides:
		var decoded := _parameter(source, entries, path, overrides[path])
		if decoded.has("error"): return decoded
		initial[path] = decoded.value
	var raw_starts: Variant = params.get("tree_starts", [])
	if not raw_starts is Array: return _error("tree_starts must be an array")
	for entry in raw_starts:
		if not entry is Dictionary: return _error("each tree_starts entry must be an object")
		var validated := _state(source, entry.get("playback_path"), entry.get("state"))
		if validated.has("error"): return validated
		if str(entry.state).contains("/"): return _error("start names one state; enter the parent, then travel to Group/Child at t=0")
		starts.append({"action": "start", "path": entry.playback_path, "state": entry.state})
	var raw_events: Variant = params.get("tree_events", [])
	if not raw_events is Array: return _error("tree_events must be an array")
	var previous := 0.0
	for entry in raw_events:
		if not entry is Dictionary: return _error("each tree_events entry must be an object")
		var time: Variant = entry.get("time")
		if not (time is int or time is float) or not is_finite(time) or time < previous or time > duration:
			return _error("tree_events times must be finite, ordered and within the duration")
		previous = time
		var action: Variant = entry.get("action")
		if action == "set":
			var decoded := _parameter(source, entries, entry.get("path"), entry.get("value"))
			if decoded.has("error"): return decoded
			events.append({"time": float(time), "action": action, "path": entry.path, "value": decoded.value})
		elif action in ["start", "travel"]:
			var validated := _state(source, entry.get("path"), entry.get("state"))
			if validated.has("error"): return validated
			if action == "start" and str(entry.state).contains("/"): return _error("start names one state; use travel for Group/Child")
			events.append({"time": float(time), "action": action, "path": entry.path, "state": entry.state})
		else: return _error("tree_events action must be set, start or travel")
	return {"ok": true}

func begin(copy: AnimationTree) -> void:
	tree = copy
	cursor = 0
	for path in initial: tree.set(path, initial[path])
	for command in starts: _command(command)

func advance(delta: float, time: float) -> void:
	# Events at an endpoint take effect after advancing with preceding controls.
	if delta > 0.0: tree.advance(delta)
	var changed := false
	while cursor < events.size() and events[cursor].time <= time + 0.00000001:
		_command(events[cursor])
		cursor += 1
		changed = true
	if changed or delta == 0.0: tree.advance(0.0)

func sample_times(duration: float, fps: int) -> Array:
	var times: Array = []
	for i in int(ceil(duration * fps)) + 1: times.append(minf(float(i) / fps, duration))
	for entry in events:
		if not times.has(entry.time): times.append(entry.time)
	times.sort()
	return times

func _command(command: Dictionary) -> void:
	if command.action == "set": tree.set(command.path, command.value)
	else:
		var playback: AnimationNodeStateMachinePlayback = tree.get(command.path)
		if command.action == "start": playback.start(command.state, true)
		else: playback.travel(command.state, true)

func _parameter(source: AnimationTree, entries: Dictionary, path: Variant, raw: Variant) -> Dictionary:
	if not path is String or not entries.has(path): return _error("unknown tree parameter '%s'" % str(path))
	var entry: Dictionary = entries[path]
	if int(entry.usage) & PROPERTY_USAGE_READ_ONLY or source.get(path) is Resource:
		return _error("parameter '%s' is not a writable value; use tree_starts/events for playback" % path)
	var decoded := Json.decode_value(raw)
	if decoded.has("error"): return decoded
	var value: Variant = decoded.ok
	var expected := int(entry.type)
	if expected == TYPE_INT and value is float and is_finite(value) and value == floor(value): value = int(value)
	if expected == TYPE_STRING_NAME and value is String: value = StringName(value)
	if typeof(value) != expected: return _error("parameter '%s' requires %s" % [path, type_string(expected)])
	if value is float and not is_finite(value): return _error("parameter '%s' must be finite" % path)
	if (value is Vector2 or value is Vector3 or value is Quaternion) and not value.is_finite(): return _error("parameter '%s' must be finite" % path)
	return {"value": value}

func _state(source: AnimationTree, path: Variant, state: Variant) -> Dictionary:
	if not path is String or not path.begins_with("parameters/") or not path.ends_with("/playback"):
		return _error("state commands need a full parameters/.../playback path")
	var known := false
	for entry in source.get_property_list():
		if str(entry.name) == path: known = true
	if not known or not source.get(path) is AnimationNodeStateMachinePlayback: return _error("unknown playback path '%s'" % path)
	var node: AnimationNode = source.tree_root
	var parts: PackedStringArray = [] if path == "parameters/playback" else str(path).trim_prefix("parameters/").trim_suffix("/playback").split("/")
	for part in parts:
		if node is AnimationNodeStateMachine or node is AnimationNodeBlendTree:
			if not node.has_node(part): return _error("playback path '%s' has no graph node '%s'" % [path, part])
			node = node.get_node(part)
		else: return _error("unsupported playback container at '%s'" % path)
	if not node is AnimationNodeStateMachine: return _error("playback path '%s' is not a state machine" % path)
	if node.state_machine_type == AnimationNodeStateMachine.STATE_MACHINE_TYPE_GROUPED:
		return _error("grouped machines must be addressed through their parent playback path")
	if not state is String or state.is_empty(): return _error("state must be a nonempty string")
	# Native parent playback accepts Group/Child targets.
	var state_parts: PackedStringArray = str(state).split("/")
	var machine: AnimationNodeStateMachine = node
	for i in state_parts.size():
		if not machine.has_node(state_parts[i]): return _error("unknown state '%s' at '%s'" % [state, path])
		if i < state_parts.size() - 1:
			var child := machine.get_node(state_parts[i])
			if not child is AnimationNodeStateMachine: return _error("state '%s' is not a nested machine" % state)
			if child.state_machine_type != AnimationNodeStateMachine.STATE_MACHINE_TYPE_GROUPED:
				return _error("nested machines require their own playback path; Group/Child travel is only for grouped machines")
			machine = child
	return {"ok": true}

func _check_resource(resource: Resource, seen: Dictionary) -> Dictionary:
	if seen.has(resource): return {"ok": true}
	seen[resource] = true
	if resource.get_script() != null: return Errors.make(Errors.OPERATION_UNAVAILABLE, "Graph replay cannot reproduce scripted resource " + resource.get_class())
	if resource is AnimationNodeStateMachineTransition and not resource.advance_expression.is_empty():
		return Errors.make(Errors.OPERATION_UNAVAILABLE, "Graph replay cannot reproduce advance_expression; use conditions or explicit events")
	if resource is AnimationNodeStateMachine and resource.state_machine_type == AnimationNodeStateMachine.STATE_MACHINE_TYPE_GROUPED:
		for i in resource.get_transition_count():
			if (resource.get_transition_from(i) == "Start" or resource.get_transition_to(i) == "End") and resource.get_transition(i).advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO:
				return Errors.make(Errors.OPERATION_UNAVAILABLE, "Godot 4.7.2 grouped AUTO boundary transitions fail native condition evaluation; use explicit parent travel and ENABLED boundary transitions")
	for entry in resource.get_property_list():
		if not int(entry.usage) & PROPERTY_USAGE_STORAGE or str(entry.name) == "script": continue
		var checked := _check_value(resource.get(entry.name), seen)
		if checked.has("error"): return checked
	return {"ok": true}

func _check_value(value: Variant, seen: Dictionary) -> Dictionary:
	if value is Resource: return _check_resource(value, seen)
	if value is Array:
		for item in value:
			var checked := _check_value(item, seen)
			if checked.has("error"): return checked
	elif value is Dictionary:
		for key in value:
			var checked := _check_value(value[key], seen)
			if checked.has("error"): return checked
	return {"ok": true}

func _error(message: String) -> Dictionary:
	return Errors.make(Errors.INVALID_PARAMS, "Graph bake: " + message)
