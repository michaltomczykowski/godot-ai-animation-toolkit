extends SceneTree
## Compare played world-space motion with the previously reviewed saved idle.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _ranges(view: Dictionary, fps: int) -> Dictionary:
	var bounds := {"head_yaw_deg": Vector2(INF, -INF), "chest_yaw_deg": Vector2(INF, -INF),
		"head_pitch_deg": Vector2(INF, -INF), "pelvis_sway_m": Vector2(INF, -INF)}
	var rest_basis := {}
	for role in ["head", "chest"]:
		rest_basis[role] = (view.rig.global_transform * view.rig.get_bone_global_rest(view.indices[role])).basis
	for frame in int(round(view.clip.length * 2.0 * fps)) + 1:
		if frame > 0: Native.advance(view, 1.0 / fps)
		for role in ["head", "chest"]:
			var basis: Basis = (view.rig.global_transform * view.rig.get_bone_global_pose(view.indices[role])).basis
			var facing: Vector3 = (basis * (rest_basis[role] as Basis).inverse() * view.forward).normalized()
			var key := str(role) + "_yaw_deg"
			var yaw := rad_to_deg(atan2(facing.dot(view.right), facing.dot(view.forward)))
			bounds[key] = Vector2(minf(bounds[key].x, yaw), maxf(bounds[key].y, yaw))
			if role == "head":
				var pitch := rad_to_deg(asin(clampf(facing.dot(view.up), -1.0, 1.0)))
				bounds.head_pitch_deg = Vector2(minf(bounds.head_pitch_deg.x, pitch), maxf(bounds.head_pitch_deg.y, pitch))
		var sway := Native.point(view, "hips").dot(view.right)
		bounds.pelvis_sway_m = Vector2(minf(bounds.pelvis_sway_m.x, sway), maxf(bounds.pelvis_sway_m.y, sway))
	var result := {}
	for key in bounds:
		result[key] = float(bounds[key].y - bounds[key].x)
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var rows: Array = []
	var passed := true
	for row: Dictionary in candidate.cases:
		var reference: Dictionary = {}
		for item: Dictionary in previous.cases:
			if item.id == row.id: reference = item
		if reference.is_empty():
			passed = false
			continue
		for fps in [30, 60, 120]:
			var before := Native.load_case(reference, root)
			var after := Native.load_case(row, root)
			var old_ranges := _ranges(before, fps)
			var new_ranges := _ranges(after, fps)
			var ok := true
			for key in new_ranges:
				ok = ok and is_finite(new_ranges[key]) and is_finite(old_ranges[key])
			# Absolute played ranges establish that visible motion increased, rather
			# than relying on a larger config value or a different static pose.
			ok = ok and new_ranges.head_yaw_deg > old_ranges.head_yaw_deg * 1.1
			ok = ok and new_ranges.chest_yaw_deg > old_ranges.chest_yaw_deg * 1.05
			ok = ok and new_ranges.pelvis_sway_m > old_ranges.pelvis_sway_m * 1.1
			rows.append({"id": row.id, "fps": fps, "previous": old_ranges, "candidate": new_ranges, "passed": ok})
			passed = passed and ok
			before.scene.free()
			after.scene.free()
	passed = passed and rows.size() == 12 and logger.errors.is_empty()
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify({"passed": passed,
		"previous_source": previous.source_head, "source_head": candidate.source_head,
		"rows": rows, "engine_errors": logger.errors}))
	OS.remove_logger(logger)
	print("IDLE_REVISION_RANGES=%d passed=%s" % [rows.size(), passed])
	quit(0 if passed else 1)
