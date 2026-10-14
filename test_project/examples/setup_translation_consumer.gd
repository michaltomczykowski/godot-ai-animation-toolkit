extends Node3D
## Attach to the character translation owner selected by character_setup.
## Set tree_path to the returned AnimationTree path. This example owns manual
## graph evaluation and translation; do not add another player/controller writer.
@export var tree_path: NodePath
@export var speed_parameter := "parameters/blend_position"
@export var jump_request_parameter := ""
@export var requested_speed := 0.0
var tree: AnimationTree

func _ready() -> void:
	tree = get_node(tree_path) as AnimationTree
	assert(tree != null and not tree.root_motion_track.is_empty())
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

func _physics_process(delta: float) -> void:
	tree.set(speed_parameter, requested_speed)
	# A jump with authored forward displacement starts from idle: blending a
	# moving base may add travel. The public runtime gate measures that contract.
	if not jump_request_parameter.is_empty() and Input.is_action_just_pressed("jump"):
		tree.set(speed_parameter, 0.0)
		requested_speed = 0.0
		tree.set(jump_request_parameter, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	tree.advance(delta)
	# Extraction is in the owner's local orientation. Its parent's transform
	# converts this local position change to world movement exactly once.
	position += quaternion * tree.get_root_motion_position()
