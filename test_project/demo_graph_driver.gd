extends Node2D

## Scratch driver for the graph demo scenes: drives AnimationTree parameters on a
## timeline so the recorded video shows state changes, blends and a one-shot.
##
## Modes:
##   "states" - starts the state machine and toggles walking/running conditions
##   "blend"  - ramps the blend-space position and fires a one-shot periodically

@export var mode := "states"
@export var tree_path: NodePath = ^"AnimationTree"
@export var readout_path: NodePath = ^"Readout"

const _WALK_TIME := 2.6
const _RUN_TIME := 2.6
const _IDLE_TIME := 2.4
const _SHOT_INTERVAL := 3.2

var _tree: AnimationTree
var _readout: Label
var _playback: AnimationNodeStateMachinePlayback
var _blend_path := ""
var _request_path := ""
var _elapsed := 0.0
var _phase := ""


func _ready() -> void:
	_tree = get_node_or_null(tree_path)
	_readout = get_node_or_null(readout_path)
	if _tree == null:
		return
	# Activate at runtime: an active AnimationTree also drives the scene while
	# you edit it, so the scene file keeps it off.
	_tree.active = true
	for entry in _tree.get_property_list():
		var name := str(entry.get("name", ""))
		if name.begins_with("parameters/") and name.ends_with("/blend_position"):
			_blend_path = name
		elif name.begins_with("parameters/") and name.ends_with("/request"):
			_request_path = name
	if mode == "states":
		_playback = _tree.get("parameters/playback")
		if _playback != null:
			_playback.start("idle")
		_phase = "idle"


func _process(delta: float) -> void:
	if _tree == null:
		return
	_elapsed += delta
	if mode == "blend":
		_drive_blend()
	elif mode == "states":
		_drive_states()


func _drive_states() -> void:
	var cycle := _WALK_TIME + _RUN_TIME + _WALK_TIME + _IDLE_TIME
	var t := fmod(_elapsed, cycle)
	var phase := "idle"
	if t < _WALK_TIME:
		phase = "walk"
	elif t < _WALK_TIME + _RUN_TIME:
		phase = "run"
	elif t < _WALK_TIME + _RUN_TIME + _WALK_TIME:
		phase = "walk"
	_set_condition("walking", phase != "idle")
	_set_condition("running", phase == "run")
	if _readout != null:
		var current := ""
		if _playback != null:
			current = str(_playback.get_current_node())
		_readout.text = "state: %s  (walking=%s running=%s)" % [
			current, str(phase != "idle").to_lower(), str(phase == "run").to_lower()]


func _set_condition(name: String, value: bool) -> void:
	var path := "parameters/conditions/%s" % name
	for entry in _tree.get_property_list():
		if str(entry.get("name", "")) == path:
			_tree.set(path, value)
			return


func _drive_blend() -> void:
	if _blend_path.is_empty():
		return
	var speed := 1.0 + sin(_elapsed * TAU / 6.0)
	_tree.set(_blend_path, speed)
	if not _request_path.is_empty() and fmod(_elapsed, _SHOT_INTERVAL) < 0.05:
		_tree.set(_request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if _readout != null:
		_readout.text = "speed: %.2f" % speed
