extends "res://tools/render_walk_comparison.gd"

func _comparison_title(candidate: Dictionary, row: Dictionary, angle_name: String) -> String:
	return "RUN QUALITY REVIEW | %s | %s | %s | Godot 4.7.2" % [row.label, angle_name, candidate.profile]
