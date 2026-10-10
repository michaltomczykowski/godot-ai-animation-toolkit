extends SceneTree

## Saved engine playback only. No motion specs, IK or hand-applied bone poses.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _pose_error(a: Skeleton3D, b: Skeleton3D) -> Vector2:
	var worst := Vector2.ZERO
	for index in a.get_bone_count():
		var other := b.find_bone(a.get_bone_name(index))
		if other < 0: return Vector2(INF, INF)
		var left := a.get_bone_global_pose(index)
		var right := b.get_bone_global_pose(other)
		var q := left.basis.get_rotation_quaternion().inverse() * right.basis.get_rotation_quaternion()
		worst.x = maxf(worst.x, left.origin.distance_to(right.origin))
		worst.y = maxf(worst.y, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
	return worst

func _tree(view: Dictionary, name: String) -> AnimationMixer:
	if name == "player": return view.player
	view.player.active = false
	var tree := AnimationTree.new()
	view.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(view.player)
	tree.root_node = tree.get_path_to(view.player.get_node(view.player.root_node))
	tree.root_motion_track = view.player.root_motion_track
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = view.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _check(row: Dictionary, fps: int, mode: String) -> Dictionary:
	var v := Native.load_case(row, root)
	v.animation_name = row.params.animation_name
	var reference := Native.load_case(row, root)
	var mixer := _tree(v, mode)
	var clip: Animation = v.clip
	var errors: Array[String] = []
	var extracted := bool(row.params.root_motion)
	var leg: float = v.leg
	var speed: float = row.write.speed
	var max_reference := Vector2.ZERO
	var zero_root_error := 0.0
	var clip_owner_error := 0.0
	var marker_errors: Array[String] = []
	var path_errors: Array[String] = []
	var key_count := 0
	var active_mixers := 0
	for active in v.scene.find_children("*", "AnimationMixer", true, false):
		if active.active: active_mixers += 1
	if active_mixers != 1: errors.append("Expected exactly one active mixer")
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null: path_errors.append("Unresolved path " + str(path))
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			path_errors.append("Unexpected type " + str(path))
		if target is Skeleton3D and (path.get_subname_count() != 1 or target.find_bone(str(path.get_subname(0))) < 0):
			path_errors.append("Unresolved bone " + str(path))
		if not extracted and not target is Skeleton3D: path_errors.append("In-place clip writes actor transform")
		key_count += clip.track_get_key_count(track)
	if key_count != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count):
		errors.append("Reported track/key counts differ")
	if clip.loop_mode != Animation.LOOP_LINEAR: errors.append("Run must loop continuously")
	for side in ["L", "R"]:
		for label in ["contact.", "toe_off.", "passing."]:
			if not clip.has_marker(label + side): marker_errors.append("Missing " + label + side)
	if not marker_errors.is_empty(): errors.append("Incomplete contact markers")
	if extracted and mixer.root_motion_track.is_empty(): errors.append("Extracted root track missing")
	# A player may retain an extraction binding for a different saved clip.
	# It only owns this clip's translation when that track actually exists here.
	if not extracted and clip.find_track(mixer.root_motion_track, Animation.TYPE_POSITION_3D) >= 0:
		errors.append("In-place clip retains an active extraction track")
	var feet := {}
	for side in ["l", "r"]:
		feet[side] = {"active": false, "anchor": Vector3.ZERO, "slide": 0.0,
			"penetration": 0.0, "contact_height": 0.0, "normal": Vector3.ZERO,
			"flips": 0, "declared_frames": 0, "observed_frames": 0, "contacts": 0}
	var nonfinite := 0
	var flight_frames := 0
	var declared_flight_frames := 0
	var flight_windows := 0
	var in_flight := false
	var seams := 0
	var max_pose_step := 0.0
	var seam_step := 0.0
	var previous: Array[Vector3] = []
	for index in v.rig.get_bone_count(): previous.append(v.rig.get_bone_global_pose(index).origin)
	var trace: Array = []
	var arms := {}
	for side in ["l", "r"]:
		arms[side] = {"max_upper_up_dot": -1.0, "min_elbow_deg": 180.0, "max_elbow_deg": 0.0,
			"wrist_initial": v.rig.get_bone_pose_rotation(v.indices["hand_" + side]), "wrist_excursion_rad": 0.0}
	var dt := 1.0 / fps
	for frame in 6 * fps + 1:
		var crossed := false
		if frame > 0:
			var before: Vector3 = v.body.global_position
			mixer.advance(dt)
			var delta := mixer.get_root_motion_position()
			if extracted:
				v.body.position += v.body.quaternion * delta
			else:
				# In-place bones need a caller-owned actor velocity for world planting.
				# Observe inert clip/root output before applying that single owner.
				zero_root_error = maxf(zero_root_error, delta.length())
				clip_owner_error = maxf(clip_owner_error, before.distance_to(v.body.global_position))
				v.body.global_position += v.forward * speed * dt
			var previous_time: float = v.time
			v.time = float(frame) / fps
			crossed = floori(v.time / clip.length) > floori(previous_time / clip.length)
			if crossed: seams += 1
		# A separately loaded engine player evaluates matching fractional phase.
		# No frame has to land exactly on a nonintegral loop boundary.
		reference.player.seek(fposmod(v.time, clip.length), true)
		var difference := _pose_error(v.rig, reference.rig)
		max_reference.x = maxf(max_reference.x, difference.x)
		max_reference.y = maxf(max_reference.y, difference.y)
		var declared_air := true
		var observed_air := true
		var sample := {"time": v.time, "root": Native.values(v.body.global_position), "feet": {}}
		for side: String in feet:
			var f: Dictionary = feet[side]
			var foot := Native.point(v, "foot_" + side)
			var height: float = foot.dot(v.up) - v.ground
			var active := Native.contact(v, side) if marker_errors.is_empty() else false
			if active and not f.active:
				f.anchor = foot
				f.contacts += 1
			if active:
				f.slide = maxf(f.slide, Native.flat(foot - f.anchor, v.up).length())
				f.contact_height = maxf(f.contact_height, absf(height))
				f.declared_frames += 1
			if absf(height) <= 0.01 * leg: f.observed_frames += 1
			declared_air = declared_air and not active
			observed_air = observed_air and height > 0.01 * leg
			f.active = active
			f.penetration = maxf(f.penetration, -height)
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > 0.005 * leg:
				var normal := pole.normalized()
				if (f.normal as Vector3).length_squared() > 0.5 and normal.dot(f.normal) < 0.0: f.flips += 1
				f.normal = normal
			sample.feet[side] = {"p": Native.values(foot), "height_from_rest_ankle_plane": height, "declared_contact": active}
		if declared_air: declared_flight_frames += 1
		if observed_air:
			flight_frames += 1
			if not in_flight: flight_windows += 1
		in_flight = observed_air
		for index in v.rig.get_bone_count():
			var pose: Transform3D = v.rig.get_bone_global_pose(index)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
			var step := pose.origin.distance_to(previous[index])
			max_pose_step = maxf(max_pose_step, step)
			if crossed: seam_step = maxf(seam_step, step)
			previous[index] = pose.origin
		for side: String in arms:
			var upper := (Native.point(v, "forearm_" + side) - Native.point(v, "arm_" + side)).normalized()
			var fore := (Native.point(v, "hand_" + side) - Native.point(v, "forearm_" + side)).normalized()
			var a: Dictionary = arms[side]
			a.max_upper_up_dot = maxf(a.max_upper_up_dot, upper.dot(v.up))
			var bend := rad_to_deg(acos(clampf(upper.dot(fore), -1.0, 1.0)))
			a.min_elbow_deg = minf(a.min_elbow_deg, bend)
			a.max_elbow_deg = maxf(a.max_elbow_deg, bend)
			var wrist: Quaternion = v.rig.get_bone_pose_rotation(v.indices["hand_" + side])
			var q: Quaternion = (a.wrist_initial as Quaternion).inverse() * wrist
			a.wrist_excursion_rad = maxf(a.wrist_excursion_rad, 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)))
		trace.append(sample)
	var travel: Vector3 = v.body.global_position - v.initial_body
	var root_error := travel.distance_to(v.forward * speed * 6.0)
	var slide_limit := minf(0.02 * leg, 0.03)
	if not path_errors.is_empty(): errors.append("Invalid track paths/types")
	if nonfinite > 0: errors.append("Nonfinite played poses")
	if bool(row.write.clamped): errors.append("Generation reach clamp")
	if root_error >= 0.0001: errors.append("Root/actor travel mismatch")
	if zero_root_error > 0.000001 or clip_owner_error > 0.000001: errors.append("In-place clip owns translation")
	if seams == 0: errors.append("No crossed loop seam coverage")
	if max_reference.x > 0.001 * leg or max_reference.y > 0.0001: errors.append("Repeated engine pose differs at fractional phase")
	if max_pose_step <= 0.000001: errors.append("Inert skeletal playback")
	if flight_windows < 2 or declared_flight_frames == 0: errors.append("No repeated observed and declared flight")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide > slide_limit or f.penetration > 0.01 * leg or f.contact_height > 0.01 * leg or f.flips > 0 or f.contacts < 2:
			errors.append(side + " contact/slide/penetration/knee failure")
		metrics[side] = {"max_declared_stance_slide_m": f.slide, "max_rest_ankle_plane_penetration_m": f.penetration,
			"max_declared_contact_height_m": f.contact_height, "knee_pole_flips": f.flips,
			"declared_contact_frames": f.declared_frames, "observed_contact_band_frames": f.observed_frames, "contact_windows": f.contacts}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "root_mode": "extracted" if extracted else "in_place_actor_driver",
		"frames": 6 * fps + 1, "dt": dt, "leg_length_m": leg, "period_s": clip.length,
		"slide_limit_m": slide_limit, "penetration_limit_m": 0.01 * leg,
		"root_distance_m": travel.length(), "expected_root_distance_m": speed * 6.0, "root_error_m": root_error,
		"max_in_place_root_delta_m": zero_root_error, "max_in_place_clip_translation_m": clip_owner_error,
		"max_reference_position_error_m": max_reference.x, "max_reference_rotation_error_rad": max_reference.y,
		"crossed_loop_seams": seams, "max_pose_step_m": max_pose_step, "max_seam_step_m": seam_step,
		"nonfinite": nonfinite, "generation_reach_clamped": row.write.clamped, "active_mixers": active_mixers,
		"declared_flight_frames": declared_flight_frames, "observed_flight_frames": flight_frames,
		"observed_flight_windows": flight_windows, "feet": metrics, "trace": trace,
		"path_errors": path_errors, "marker_errors": marker_errors, "failures": errors, "thresholds_pass": errors.is_empty()}
	for side in arms: arms[side].erase("wrist_initial")
	result["arms"] = arms
	v.scene.free()
	reference.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var modes: Array = ["player"] if args.size() > 2 and args[2] == "baseline" else ["player", "tree"]
	var results: Array = []
	var failures: Array = []
	for row: Dictionary in manifest.cases:
		if not row.get("passed", false):
			failures.append(str(row.id) + ": invalid public route")
			continue
		for fps in [30, 60, 120]:
			for mode: String in modes:
				var result := _check(row, fps, mode)
				results.append(result)
				if not result.thresholds_pass: failures.append("%s/%s/%s: %s" % [row.id, fps, mode, str(result.failures)])
	var expected := 4 * 3 * modes.size()
	var report := {"source_head": manifest.source_head, "revision": manifest.revision,
		"runs": results, "failures": failures, "engine_errors": logger.errors,
		"passed": results.size() == expected and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Independent saved engine playback, world-space ankle contact/flight and one actor translation owner. Rest ankle plane is not skinned sole collision. In-place world planting uses caller-owned constant velocity; observed contact band differs from marker timing. Numerical checks do not approve visual quality."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("RUN_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
