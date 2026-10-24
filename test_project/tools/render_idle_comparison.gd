extends "res://tools/render_walk_comparison.gd"

func _contact(view: Dictionary, side: String) -> bool:
	var target := Native.rest(view.rig, view.roles, "foot_" + side)
	return absf((Native.point(view, "foot_" + side) - target).dot(view.up)) <= 0.01 * float(view.leg)

func _comparison_title(candidate: Dictionary, row: Dictionary, angle_name: String) -> String:
	return "IDLE %s | %s | %s | Godot 4.7.2" % [str(candidate.revision).to_upper(), row.label, angle_name]

func _support(view: Dictionary) -> String:
	return ("L" if _contact(view, "l") else "-") + ("R" if _contact(view, "r") else "-")

func _comparison_status(frame: int, _reference: Dictionary, _row: Dictionary) -> String:
	return "%s | time %05.2f s | periods %.2f / %.2f s | expected support L R | observed %s / %s | drift %.2f / %.2f mm" % ["DIAGNOSTIC" if diagnostic else "CLEAN", float(frame) / 60.0, views[0].clip.length, views[1].clip.length, _support(views[0]), _support(views[1]), 1000.0 * views[0].body.global_position.distance_to(views[0].initial_body), 1000.0 * views[1].body.global_position.distance_to(views[1].initial_body)]

func _comparison_footer() -> String:
	return "Green: observed ankle contact band | Amber: outside band | Magenta: hip projection (not COM)" if diagnostic else "Original saved idle clips | fixed matched cameras | continuous 60 FPS | candidate requires human review"
