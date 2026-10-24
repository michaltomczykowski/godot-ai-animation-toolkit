extends "res://tools/render_character_quality.gd"

## Standing contacts are observed ankle heights, not absent gait annotations.
func _contact(view: Dictionary, side: String) -> bool:
	var target := Native.rest(view.rig, view.roles, "foot_" + side)
	return absf((Native.point(view, "foot_" + side) - target).dot(view.up)) <= 0.01 * float(view.leg)

func _baseline_title(manifest: Dictionary, row: Dictionary) -> String:
	return "IDLE BASELINE | %s | %s | Godot 4.7.2 | %s" % [row.label, manifest.profile, str(manifest.source_head).left(7)]

func _baseline_status(frame: int, view: Dictionary) -> String:
	var observed := ("L " if _contact(view, "l") else "") + ("R" if _contact(view, "r") else "")
	return "%s | time %05.2f s | period %.2f s | expected support L R | observed %s | drift %.2f mm" % ["DIAGNOSTIC" if diagnostic else "CLEAN", float(frame) / 60.0, view.clip.length, observed, 1000.0 * view.body.global_position.distance_to(view.initial_body)]

func _baseline_footer() -> String:
	return "Green: observed ankle contact band | Amber: outside band | Magenta: hip projection (not COM)" if diagnostic else "Native saved idle clips | fixed front/side cameras | continuous 60 FPS | stationary rest-sole floor"
