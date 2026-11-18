extends Node3D

@export var clip_name := "xbot_walk"

@onready var character: Node3D = $XBot
@onready var player: AnimationPlayer = $WalkAnim
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.position = Vector3(3.2, 1.2, 0.9)
	camera.look_at(Vector3(0, 0.9, 0.9))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	player.play(clip_name)


func _process(_delta: float) -> void:
	character.position += player.get_root_motion_position()
