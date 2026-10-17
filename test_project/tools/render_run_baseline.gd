extends "res://tools/render_character_quality.gd"

func _baseline_title(manifest: Dictionary, row: Dictionary) -> String:
	return "RUN BASELINE | %s | %s | Godot 4.7.2 | %s" % [row.label, manifest.revision, str(manifest.source_head).left(7)]
