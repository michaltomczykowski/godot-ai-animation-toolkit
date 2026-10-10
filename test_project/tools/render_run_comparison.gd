extends "res://tools/render_walk_comparison.gd"

func _comparison_title(candidate: Dictionary, row: Dictionary, angle_name: String) -> String:
	return "RUN QUALITY REVIEW | %s | %s | %s | Godot 4.7.2" % [row.label, angle_name, candidate.profile]

func _comparison_status(frame: int, reference: Dictionary, row: Dictionary) -> String:
	return "t %05.2fs | L/R speed %.2f/%.2f m/s | loop %.3f/%.3fs | travel %.2f/%.2fm | declared %s/%s" % [float(frame) / 60.0,
		reference.write.speed, row.write.speed, views[0].clip.length, views[1].clip.length,
		views[0].body.global_position.distance_to(views[0].initial_body), views[1].body.global_position.distance_to(views[1].initial_body),
		_phase_label(views[0]), _phase_label(views[1])]

func _phase_label(view: Dictionary) -> String:
	var contacts := ("L" if Native.contact(view, "l") else "") + ("R" if Native.contact(view, "r") else "")
	return contacts if not contacts.is_empty() else "FLIGHT"

func _comparison_footer() -> String:
	return "Green: declared contact | Amber: swing | FLIGHT: no declared support | Magenta: hip projection (not COM) | Blue: extracted travel" if diagnostic else "Saved clips | one extracted-root consumer | 60 FPS playback | baseline LEFT, ordinary candidate RIGHT | awaiting approval"
