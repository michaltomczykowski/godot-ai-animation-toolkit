extends Node3D

## Fixed-camera review of a saved Godot AI-generated X Bot clip. The sole
## AnimationPlayer owns the skeleton, while this script consumes extracted
## root motion on its character owner after the player advances.
@export var clip_name := "jump"
@export_enum("side", "front") var camera_mode := "side"

@onready var character: Node3D = $MotionXBot/XBot
@onready var player: AnimationPlayer = $MotionXBot/WalkAnim
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	if camera_mode == "front":
		camera.position = Vector3(0.6, 1.6, 4.0)
		camera.look_at(Vector3(0.0, 0.9, 0.0))
	else:
		camera.position = Vector3(3.2, 1.4, 1.1)
		camera.look_at(Vector3(0.25, 0.9, 0.45))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	player.play(clip_name)


func _process(_delta: float) -> void:
	character.position += player.get_root_motion_position()
