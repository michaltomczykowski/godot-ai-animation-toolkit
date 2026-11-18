extends Node3D
## Replay a saved one-shot after a short hold. Continuous clips loop natively.

@export var repeat_one_shot := true

@onready var _player: AnimationPlayer = $AnimationPlayer
var _clip: StringName
var _restart_in := 0.0


func _ready() -> void:
	for clip in _player.get_animation_list():
		if clip != "RESET":
			_clip = clip
			break
	if _clip.is_empty():
		set_process(false)
		return
	if repeat_one_shot:
		_player.animation_finished.connect(_hold)
	replay()


func replay() -> void:
	_restart_in = 0.0
	_player.stop()
	_player.play(_clip)
	_player.advance(0.0)


func _hold(_name: StringName) -> void:
	_restart_in = 0.72


func _process(delta: float) -> void:
	if _restart_in <= 0.0:
		return
	_restart_in -= delta
	if _restart_in <= 0.0:
		replay()
