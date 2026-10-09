extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _angle(q: Quaternion) -> float:
	return rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var runs: Array = []
	for row: Dictionary in manifest.cases:
		for fps in [30, 60, 120]:
			var v := Native.load_case(row, root)
			var ranges := {}
			var trace: Array = []
			var yaw_components := {}
			for role in ["hips", "chest"]:
				var index: int = v.indices[role]
				var delta: Quaternion = v.rig.get_bone_rest(index).basis.get_rotation_quaternion().inverse() * v.rig.get_bone_pose_rotation(index)
				var axis: Vector3 = v.rig.global_basis * v.rig.get_bone_global_rest(index).basis * Vector3(delta.x, delta.y, delta.z)
				yaw_components[role] = axis.dot(v.up)
			for role in ["hips", "chest", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "hand_l", "hand_r"]:
				if not v.indices.has(role): continue
				var index: int = v.indices[role]
				ranges[role] = {"initial": v.rig.get_bone_pose_rotation(index), "previous": v.rig.get_bone_pose_rotation(index), "max_change_deg": 0.0, "max_step_deg": 0.0, "loop_error_deg": 0.0}
			var spatial := {}
			for role in ["hips", "chest", "head"]:
				spatial[role] = {"min_height_m": INF, "max_height_m": -INF,
					"min_pitch_deg": INF, "max_pitch_deg": -INF,
					"min_roll_deg": INF, "max_roll_deg": -INF}
			for frame in fps * 6 + 1:
				if frame > 0: Native.advance(v, 1.0 / fps)
				var sample := {"t": v.time}
				for role: String in spatial:
					var index: int = v.indices[role]
					var rest_basis: Basis = v.rig.global_basis * v.rig.get_bone_global_rest(index).basis
					var played_basis: Basis = v.rig.global_basis * v.rig.get_bone_global_pose(index).basis
					var delta := played_basis * rest_basis.inverse()
					var played_up: Vector3 = delta * v.up
					var height: float = (Native.point(v, role) - v.body.global_position).dot(v.up)
					var pitch := rad_to_deg(atan2(played_up.dot(v.forward), played_up.dot(v.up)))
					var roll := rad_to_deg(atan2(played_up.dot(v.right), played_up.dot(v.up)))
					for field in ["height_m", "pitch_deg", "roll_deg"]:
						var value: float = height if field == "height_m" else (pitch if field == "pitch_deg" else roll)
						spatial[role]["min_" + field] = minf(spatial[role]["min_" + field], value)
						spatial[role]["max_" + field] = maxf(spatial[role]["max_" + field], value)
						sample[role + "_" + field] = value
				for role: String in ranges:
					var index: int = v.indices[role]
					var q: Quaternion = v.rig.get_bone_pose_rotation(index)
					var r: Dictionary = ranges[role]
					r.max_change_deg = maxf(r.max_change_deg, _angle(r.initial.inverse() * q))
					r.max_step_deg = maxf(r.max_step_deg, _angle(r.previous.inverse() * q))
					if frame > 0 and absf(v.time / v.clip.length - roundf(v.time / v.clip.length)) < 0.000001:
						r.loop_error_deg = maxf(r.loop_error_deg, _angle(r.initial.inverse() * q))
					r.previous = q
					sample[role] = [q.x, q.y, q.z, q.w]
				for side in ["l", "r"]:
					var upper := Native.point(v, "forearm_" + side) - Native.point(v, "arm_" + side)
					var lower := Native.point(v, "hand_" + side) - Native.point(v, "forearm_" + side)
					sample["upper_" + side] = Native.values(upper.normalized())
					sample["elbow_" + side] = rad_to_deg(upper.angle_to(lower))
				trace.append(sample)
			for role: String in ranges:
				ranges[role].erase("initial")
				ranges[role].erase("previous")
			runs.append({"id": row.id, "fps": fps, "ranges": ranges, "spatial": spatial, "trace": trace,
				"initial_intrinsic_yaw_components": yaw_components,
				"initial_torso_opposes_hips": float(yaw_components.hips) * float(yaw_components.chest) < 0.0})
			v.scene.free()
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify({"runs": runs, "engine_errors": logger.errors}, "\t"))
	print("UPPER_BODY_CHECK runs=%d errors=%d" % [runs.size(), logger.errors.size()])
	quit(0 if logger.errors.is_empty() else 1)
