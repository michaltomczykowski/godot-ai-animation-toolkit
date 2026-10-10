extends SceneTree

## Compare original r004 saved clips with default-style clips through native
## playback, never generated keys or hand-applied bone poses.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _reference_label() -> String:
	return "accepted r004"

func _report_label() -> String:
	return "WALK_DEFAULT_PARITY"

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var rows: Array = []
	var failures: Array = []
	for row: Dictionary in candidate.cases:
		var old: Dictionary = {}
		for item: Dictionary in reference.cases:
			if item.id == row.id: old = item
		if old.is_empty():
			failures.append("Missing reference rig " + str(row.id))
			continue
		for fps in [30, 60, 120]:
			var a := Native.load_case(old, root)
			var b := Native.load_case(row, root)
			var position_error := 0.0
			var rotation_error := 0.0
			var root_error := 0.0
			for frame in 6 * fps + 1:
				if frame > 0:
					Native.advance(a, 1.0 / fps)
					Native.advance(b, 1.0 / fps)
				root_error = maxf(root_error, a.body.global_position.distance_to(b.body.global_position))
				for index in a.rig.get_bone_count():
					var name: String = a.rig.get_bone_name(index)
					var other: int = b.rig.find_bone(name)
					if other < 0:
						failures.append("Missing candidate bone " + name)
						continue
					var pa: Transform3D = a.rig.global_transform * a.rig.get_bone_global_pose(index)
					var pb: Transform3D = b.rig.global_transform * b.rig.get_bone_global_pose(other)
					position_error = maxf(position_error, pa.origin.distance_to(pb.origin))
					var delta := pa.basis.get_rotation_quaternion().inverse() * pb.basis.get_rotation_quaternion()
					rotation_error = maxf(rotation_error, 2.0 * atan2(Vector3(delta.x, delta.y, delta.z).length(), absf(delta.w)))
			var passed := position_error <= 0.00001 and rotation_error <= 0.0001 and root_error <= 0.00001
			rows.append({"rig": row.id, "fps": fps, "frames": 6 * fps + 1,
				"max_position_error": position_error, "max_rotation_error": rotation_error,
				"max_root_error": root_error, "passed": passed})
			if not passed: failures.append("%s/%s differs from %s" % [row.id, fps, _reference_label()])
			a.scene.free()
			b.scene.free()
	var report := {"rows": rows, "failures": failures, "engine_errors": logger.errors,
		"passed": rows.size() == 12 and failures.is_empty() and logger.errors.is_empty(),
		"reference_source": reference.source_head, "candidate_source": candidate.source_head}
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print(_report_label() + " " + JSON.stringify(report))
	quit(0 if report.passed else 1)
