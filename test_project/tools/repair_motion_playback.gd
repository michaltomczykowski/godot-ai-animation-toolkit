extends Node3D

## Local review fixture: apply AnimationPlayer's extracted root delta to the
## same character owner whose position track produced it.
@onready var character: Node3D = $Dummy
@onready var player: AnimationPlayer = $WalkAnim


func _process(_delta: float) -> void:
	character.position += player.get_root_motion_position()
