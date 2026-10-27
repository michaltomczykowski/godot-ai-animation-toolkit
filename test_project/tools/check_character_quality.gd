extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var results: Array = []
	var structural: Array = []
	for row: Dictionary in manifest.cases:
		for fps in [30, 60, 120]:
			var v := Native.load_case(row, root)
			var clip: Animation = v.clip
			var keys := 0
			var paths: Array = []
			for track in clip.get_track_count():
				var path := clip.track_get_path(track)
				var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(str(path).get_slice(":", 0)))
				if target == null: structural.append(str(row.id) + ": unresolved track " + str(path))
				if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]: structural.append(str(row.id) + ": unexpected track type")
				if target is Skeleton3D and target.find_bone(str(path.get_subname(0))) < 0: structural.append(str(row.id) + ": missing bone")
				keys += clip.track_get_key_count(track)
				paths.append(str(path))
			if keys != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count): structural.append(str(row.id) + ": reported counts differ")
			if clip.loop_mode != Animation.LOOP_LINEAR: structural.append(str(row.id) + ": baseline must loop continuously")
			var feet := {"l": {"anchor": Vector3.ZERO, "active": false, "max_slide": 0.0, "penetration": 0.0, "flips": 0, "normal": Vector3.ZERO}, "r": {"anchor": Vector3.ZERO, "active": false, "max_slide": 0.0, "penetration": 0.0, "flips": 0, "normal": Vector3.ZERO}}
			var trace: Array = []
			var nonfinite := 0
			var max_pose_step := 0.0
			var max_seam_step := 0.0
			var loop_position_error := 0.0
			var loop_rotation_error := 0.0
			var loop_checks := 0
			var initial_poses: Array[Transform3D] = []
			var previous: Array = []
			for index in v.rig.get_bone_count():
				initial_poses.append(v.rig.get_bone_global_pose(index))
				previous.append(initial_poses[index].origin)
			for frame in 6 * fps + 1:
				if frame > 0: Native.advance(v, 1.0 / fps)
				var sample := {"t": float(frame) / fps, "root": Native.values(v.body.global_position), "hip": Native.values(Native.point(v, "hips"))}
				for side: String in feet:
					var foot := Native.point(v, "foot_" + side)
					var f: Dictionary = feet[side]
					var active := Native.contact(v, side)
					if active and not f.active: f.anchor = foot
					if active: f.max_slide = maxf(f.max_slide, Native.flat(foot - f.anchor, v.up).length())
					f.active = active
					f.penetration = maxf(f.penetration, float(v.ground) - foot.dot(v.up))
					var thigh := Native.point(v, "thigh_" + side)
					var knee := Native.point(v, "shin_" + side)
					var axis := (foot - thigh).normalized()
					var pole := knee - thigh - axis * (knee - thigh).dot(axis)
					if pole.length() > float(v.leg) * 0.005:
						var normal := pole.normalized()
						if (f.normal as Vector3).length_squared() > 0.5 and normal.dot(f.normal) < 0.0: f.flips += 1
						f.normal = normal
					if not foot.is_finite(): nonfinite += 1
					sample[side] = {"p": Native.values(foot), "declared_contact": active, "height_from_rest_ankle_plane": foot.dot(v.up) - float(v.ground)}
				for index in v.rig.get_bone_count():
					var pose: Transform3D = v.rig.get_bone_global_pose(index)
					var cycles: float = v.time / clip.length
					if frame > 0 and absf(cycles - roundf(cycles)) < 0.000001:
						loop_checks += 1
						loop_position_error = maxf(loop_position_error, pose.origin.distance_to(initial_poses[index].origin))
						var q := initial_poses[index].basis.get_rotation_quaternion().inverse() * pose.basis.get_rotation_quaternion()
						loop_rotation_error = maxf(loop_rotation_error, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
					if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
					var step: float = pose.origin.distance_to(previous[index])
					max_pose_step = maxf(max_pose_step, step)
					if frame > 0 and fposmod(v.time, clip.length) < 1.0 / fps + 0.000001: max_seam_step = maxf(max_seam_step, step)
					previous[index] = pose.origin
				trace.append(sample)
			var travel: Vector3 = v.body.global_position - v.initial_body
			if max_pose_step <= 0.000001: structural.append(str(row.id) + ": inert skeletal playback")
			var expected: float = float(row.write.speed) * 6.0
			var limit: float = minf(0.02 * float(v.leg), 0.03)
			var metrics := {"id": row.id, "fps": fps, "dt": 1.0 / fps, "frames": 6 * fps + 1, "source_world_up": Native.values(v.up), "leg_length_m": v.leg, "slide_limit_m": limit, "penetration_limit_m": 0.01 * float(v.leg), "root_distance_m": travel.length(), "expected_root_distance_m": expected, "root_error_m": absf(travel.length() - expected), "nonfinite": nonfinite, "max_pose_step_m": max_pose_step, "max_loop_seam_step_m": max_seam_step, "loop_bone_checks": loop_checks, "loop_position_error_m": loop_position_error, "loop_rotation_error_rad": loop_rotation_error, "generation_reach_clamped": row.write.clamped, "feet": {}, "trace": trace}
			var passes: bool = nonfinite == 0 and not bool(row.write.clamped) and metrics.root_error_m < 0.0001 and loop_checks > 0 and loop_position_error <= 0.001 * float(v.leg) and loop_rotation_error <= 0.0001
			for side: String in feet:
				metrics.feet[side] = {"max_declared_stance_slide_m": feet[side].max_slide, "max_rest_ankle_plane_penetration_m": feet[side].penetration, "knee_pole_flips": feet[side].flips}
				passes = passes and feet[side].max_slide <= limit and feet[side].penetration <= 0.01 * float(v.leg) and feet[side].flips == 0
			metrics.thresholds_pass = passes
			results.append(metrics)
			v.scene.free()
	var report := {"source_head": manifest.source_head, "revision": manifest.revision, "runs": results, "structural_failures": structural, "engine_errors": logger.errors, "measurement_contract": "Independent played world-space ankle positions and declared contact markers. Rest ankle plane is not a skinned sole collision test; hip projection is not COM. Baseline thresholds do not grant visual approval."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("CHARACTER_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "structural_failures": structural, "engine_errors": logger.errors}))
	quit(0 if results.size() == 12 and structural.is_empty() and logger.errors.is_empty() else 1)
