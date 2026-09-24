extends Node

## Driver for demo_character_setup.tscn.
##
## Walks the rig along a circle at the speed the locomotion blend space is set
## to and fires the jump request on a schedule, so the recorded segment shows
## idle -> walk -> run blending plus the one-shot layering over the gait.
## Ground travel comes from the tree's root motion (the hips track wired by
## `character_setup`), and `blend_position` is fed exactly like the returned
## apply snippet does in a game.

## Times (seconds) at which the jump one-shot is requested.
const JUMP_AT := [4.5, 7.4]
const RADIUS := 1.9
const SPEED_RAMP := 2.5

@export var rig_path: NodePath = ^"../Rig"
@export var tree_path: NodePath = ^"../AnimationTree"
@export var readout_path: NodePath = ^"../Ui/Readout"
@export var skeleton_path: NodePath = ^"../Rig/Dummy/Skeleton3D"

var _rig: Node3D
var _tree: AnimationTree
var _readout: Label
var _blend_path := ""
var _request_path := ""
var _facing_offset := 0.0
var _speed := 0.0
var _angle := 0.0
var _elapsed := 0.0


func _ready() -> void:
	_rig = get_node_or_null(rig_path)
	_tree = get_node_or_null(tree_path)
	_readout = get_node_or_null(readout_path)
	if _tree != null:
		# The scene keeps the tree inactive (an active tree also drives the scene
		# while you edit it); a game enables it at runtime, like this.
		_tree.active = true
		for entry in _tree.get_property_list():
			var property := str(entry.get("name", ""))
			if property.begins_with("parameters/") and property.ends_with("/blend_position"):
				_blend_path = property
			elif property.begins_with("parameters/") and property.ends_with("/request"):
				_request_path = property
	var skeleton := get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton != null:
		var foot := skeleton.find_bone("B-foot.L")
		var toe := skeleton.find_bone("B-toe.L")
		if foot >= 0 and toe >= 0:
			var forward: Vector3 = skeleton.get_bone_global_rest(toe).origin \
				- skeleton.get_bone_global_rest(foot).origin
			forward.y = 0.0
			if forward.length_squared() > 0.000001:
				_facing_offset = -atan2(forward.normalized().x, forward.normalized().z)
	_place_rig(0.0)


func _process(delta: float) -> void:
	if _tree == null or _blend_path.is_empty():
		return
	_elapsed += delta
	var target := _target_speed(_elapsed)
	_speed = move_toward(_speed, target, delta * SPEED_RAMP)
	_tree.set(_blend_path, _speed)
	for jump_at in JUMP_AT:
		if _elapsed >= jump_at and _elapsed - delta < jump_at and not _request_path.is_empty():
			_tree.set(_request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# Root motion from the blended clips advances the rig along the circle, so the
	# visible ground speed always matches the current blend.
	var motion: Vector3 = _tree.get_root_motion_position()
	var travel := sqrt(motion.x * motion.x + motion.z * motion.z)
	_place_rig(travel)
	if _readout != null:
		_readout.text = "speed %.2f m/s   ·   %s = %.2f   ·   jump: %s" % [
			_speed, _blend_path.get_file(), _speed,
			"armed" if not _request_path.is_empty() else "none"]


## 0-11.5 s schedule: idle, walk, run, walk, idle.
static func _target_speed(t: float) -> float:
	if t < 1.6:
		return 0.0
	if t < 4.2:
		return 1.4
	if t < 6.7:
		return 4.0
	if t < 9.2:
		return 1.4
	return 0.0


func _place_rig(travel: float) -> void:
	if _rig == null:
		return
	_angle += travel / RADIUS
	var position := Vector3(sin(_angle), 0.0, cos(_angle)) * RADIUS
	var tangent := Vector3(cos(_angle), 0.0, -sin(_angle))
	_rig.position = position
	_rig.rotation.y = atan2(tangent.x, tangent.z) + _facing_offset
