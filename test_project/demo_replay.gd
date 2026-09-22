extends Node2D

## Scratch helper for the preset demo scenes: replays a one-shot clip with a
## gap so the effect keeps showing while the video records.

@export var clip: String = ""
@export var gap: float = 0.9


func _ready() -> void:
	var player: AnimationPlayer = $Anim
	if clip.is_empty():
		clip = str(player.autoplay)
	_cycle(player)


func _cycle(player: AnimationPlayer) -> void:
	var animation := player.get_animation(clip)
	var wait: float = (animation.length if animation != null else 1.0) + gap
	await get_tree().create_timer(wait).timeout
	player.play(clip)
	_cycle(player)
