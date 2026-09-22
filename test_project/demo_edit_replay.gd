extends Node2D

## Scratch helper for the edit-demo scenes: replays every autoplaying one-shot
## clip (before/after players) with a gap, so the comparison keeps showing while
## the video records.

@export var gap: float = 0.8


func _ready() -> void:
	for child in get_children():
		if child is AnimationPlayer:
			_cycle(child)


func _cycle(player: AnimationPlayer) -> void:
	var clip := str(player.autoplay)
	var animation := player.get_animation(clip)
	var wait: float = (animation.length if animation != null else 1.0) + gap
	await get_tree().create_timer(wait).timeout
	player.play(clip)
	_cycle(player)
