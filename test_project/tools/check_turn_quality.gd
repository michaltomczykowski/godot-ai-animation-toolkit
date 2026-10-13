extends SceneTree
## Independent saved engine playback. No generator math, IK or applied poses.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
var control := ""

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _mixer(v: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return v.player
	v.player.active = false
	var tree := AnimationTree.new()
	v.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(v.player)
	tree.root_node = tree.get_path_to(v.player.get_node(v.player.root_node))
	tree.root_motion_track = v.player.root_motion_track
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = v.player.current_animation
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _heading(v: Dictionary, role: String) -> Vector3:
	var index: int = v.indices[role]
	var played: Basis = (v.rig.global_transform * v.rig.get_bone_global_pose(index)).basis.orthonormalized()
	var resting: Basis = (v.rig.global_transform * v.rig.get_bone_global_rest(index)).basis.orthonormalized()
	return Native.flat(played * resting.inverse() * v.forward, v.up).normalized()

func _contact(row: Dictionary, v: Dictionary, side: String) -> bool:
	if not row.write.has("declared_contacts"):
		# Baseline-only observation; missing declarations remain a structural failure.
		return absf(Native.point(v, "foot_" + side).dot(v.up) - float(v.ground)) <= float(v.leg) * 0.0025
	var at := minf(float(v.time), float(row.write.get("capture_duration", v.clip.length)))
	for window: Dictionary in row.write.declared_contacts:
		if str(window.side) == side and at >= float(window.start) - 0.000001 and at <= float(window.end) + 0.000001:
			return true
	return false

func _measure(row: Dictionary, fps: int, mode: String) -> Dictionary:
	row = row.duplicate(true)
	var v := Native.load_case(row, root)
	if v.has("error"): return {"thresholds_pass": false, "failures": [v.error]}
	if not control.is_empty(): _inject_control(row, v)
	var mixer := _mixer(v, mode)
	var failures: Array[String] = []
	var clip: Animation = v.clip
	var action := float(row.write.get("capture_duration", clip.length))
	var requested := float(row.params.get("angle", 90.0)) * (1.0 if row.params.get("direction", "left") == "left" else -1.0)
	var left_offset := Native.rest(v.rig, v.roles, "thigh_l") - Native.rest(v.rig, v.roles, "hips")
	var anatomical_sign := 1.0 if (v.up as Vector3).cross(left_offset).dot(v.forward) >= 0.0 else -1.0
	var expected_heading: Vector3 = Quaternion(v.up, deg_to_rad(requested * anatomical_sign)) * v.forward
	var rest_hip := Native.rest(v.rig, v.roles, "hips")
	var expected_feet := {}
	var feet := {}
	for side in ["l", "r"]:
		expected_feet[side] = rest_hip + Quaternion(v.up, deg_to_rad(requested * anatomical_sign)) * (Native.rest(v.rig, v.roles, "foot_" + side) - rest_hip)
		feet[side] = {"active": false, "anchor": Vector3.ZERO, "heading": Vector3.ZERO,
			"slide": 0.0, "penetration": 0.0, "stance_rotation": 0.0, "flips": 0,
			"pole": Vector3.ZERO, "contact_frames": 0, "max_lift": 0.0, "contact_height": 0.0}
	if clip.loop_mode != Animation.LOOP_NONE: failures.append("turn must remain a one-shot")
	if not row.write.has("declared_contacts"): failures.append("missing declared contact windows")
	if not bool(row.write.get("reach_evaluated", false)): failures.append("missing evaluated reach metadata")
	if bool(row.write.get("clamped", false)): failures.append("generation reach clamp")
	if bool(row.write.get("root_motion", true)) or str(row.write.get("heading_owner", "")) != "skeleton": failures.append("incorrect effective heading ownership report")
	var contact_indices := {"l": 0, "r": 0}
	for window: Dictionary in row.write.get("declared_contacts", []):
		var side := str(window.side)
		contact_indices[side] += 1
		var suffix := "" if int(contact_indices[side]) == 1 else "_%d" % int(contact_indices[side])
		for event in [{"name": "contact." + side.to_upper() + suffix, "time": window.start}, {"name": "toe_off." + side.to_upper() + suffix, "time": window.end}]:
			if not clip.has_marker(event.name) or absf(clip.get_marker_time(event.name) - float(event.time)) > 0.000001: failures.append("saved contact marker differs from report")
	var track_keys := 0
	for i in clip.get_track_count():
		var path := clip.track_get_path(i)
		var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null or path.get_subname_count() != 1:
			failures.append("unresolved track: " + str(path))
		elif target is Skeleton3D and target.find_bone(path.get_subname(0)) < 0:
			failures.append("unresolved bone: " + str(path))
		if clip.track_get_type(i) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]: failures.append("unexpected track type")
		track_keys += clip.track_get_key_count(i)
	if track_keys != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count): failures.append("reported clip counts differ")
	var trace: Array = []
	var previous: Array[Transform3D] = []
	var initial: Array[Transform3D] = []
	var max_pose_step := 0.0
	var max_angle_step := 0.0
	var max_motion := 0.0
	var nonfinite := 0
	var root_position := Vector3.ZERO
	var root_rotation := Quaternion.IDENTITY
	var frames := ceili((maxf(action, clip.length) + 0.3) * fps) + 1
	for frame in frames:
		if frame > 0:
			mixer.advance(1.0 / fps)
			v.time += 1.0 / fps
			root_position += mixer.get_root_motion_position()
			root_rotation = root_rotation * mixer.get_root_motion_rotation()
		var sample := {"t": v.time, "hip_heading": Native.values(_heading(v, "hips")), "feet": {}}
		var hip_delta: Basis = (v.rig.global_transform * v.rig.get_bone_global_pose(v.indices.hips)).basis.orthonormalized() * (v.rig.global_transform * v.rig.get_bone_global_rest(v.indices.hips)).basis.orthonormalized().inverse()
		for side: String in feet:
			var f: Dictionary = feet[side]
			var point := Native.point(v, "foot_" + side)
			var active := _contact(row, v, side)
			var heading := _heading(v, "foot_" + side)
			if active and not f.active:
				f.anchor = point
				f.heading = heading
			if active:
				f.contact_frames += 1
				f.slide = maxf(f.slide, Native.flat(point - f.anchor, v.up).length())
				f.stance_rotation = maxf(f.stance_rotation, absf((f.heading as Vector3).signed_angle_to(heading, v.up)))
			f.active = active
			var height := point.dot(v.up) - float(v.ground)
			if active: f.contact_height = maxf(f.contact_height, absf(height))
			f.penetration = maxf(f.penetration, -height)
			f.max_lift = maxf(f.max_lift, height)
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (point - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > float(v.leg) * 0.005:
				# Compare in the played hip frame so normal accumulated turning is valid.
				var normalized := (hip_delta.inverse() * pole).normalized()
				if (f.pole as Vector3).length_squared() > 0.5 and normalized.dot(f.pole) < 0.0: f.flips += 1
				f.pole = normalized
			sample.feet[side] = {"p": Native.values(point), "height": height, "contact": active, "heading": Native.values(heading)}
		for i in v.rig.get_bone_count():
			var pose: Transform3D = v.rig.get_bone_global_pose(i)
			if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite += 1
			if frame == 0:
				initial.append(pose)
				previous.append(pose)
			else:
				max_pose_step = maxf(max_pose_step, pose.origin.distance_to(previous[i].origin))
				max_angle_step = maxf(max_angle_step, pose.basis.get_rotation_quaternion().angle_to(previous[i].basis.get_rotation_quaternion()))
				max_motion = maxf(max_motion, pose.origin.distance_to(initial[i].origin))
				previous[i] = pose
		trace.append(sample)
	var heading_error := absf(expected_heading.signed_angle_to(_heading(v, "hips"), v.up))
	if heading_error > 0.001: failures.append("wrong settled hip heading")
	if max_motion < 0.001 * float(v.leg): failures.append("inert playback")
	if max_pose_step > 0.25 * float(v.leg) or max_angle_step > 0.75: failures.append("played pose discontinuity")
	if nonfinite > 0: failures.append("nonfinite played pose")
	if root_position.length() > 0.0001 or root_rotation.angle_to(Quaternion.IDENTITY) > 0.0001: failures.append("unexpected extracted actor motion")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		var endpoint_error: float = Native.point(v, "foot_" + side).distance_to(expected_feet[side])
		var foot_heading_error := absf(expected_heading.signed_angle_to(_heading(v, "foot_" + side), v.up))
		metrics[side] = {"stance_slide_m": f.slide, "penetration_m": f.penetration,
			"stance_rotation_rad": f.stance_rotation, "knee_flips": f.flips,
			"contact_frames": f.contact_frames, "max_lift_m": f.max_lift, "max_declared_contact_height_m": f.contact_height,
			"endpoint_position_error_m": endpoint_error, "endpoint_heading_error_rad": foot_heading_error}
		if float(f.slide) > minf(0.02 * float(v.leg), 0.03): failures.append(side + ": stance slide")
		if float(f.penetration) > 0.01 * float(v.leg): failures.append(side + ": penetration")
		if float(f.contact_height) > 0.01 * float(v.leg): failures.append(side + ": declared contact is above ankle band")
		if float(f.stance_rotation) > deg_to_rad(1.0): failures.append(side + ": planted foot rotates")
		if int(f.flips) > 0: failures.append(side + ": knee pole flip")
		if endpoint_error > 0.001 * float(v.leg) or foot_heading_error > 0.001: failures.append(side + ": unfinished foot recovery")
		if int(f.contact_frames) == 0: failures.append(side + ": no contact evidence")
	var result := {"id": row.id, "fps": fps, "mode": mode, "frames": frames,
		"leg_length_m": v.leg, "heading_error_rad": heading_error,
		"max_pose_step_m": max_pose_step, "max_angle_step_rad": max_angle_step,
		"nonfinite": nonfinite, "feet": metrics, "trace": trace,
		"failures": failures, "thresholds_pass": failures.is_empty()}
	v.scene.free()
	return result

func _inject_control(row: Dictionary, v: Dictionary) -> void:
	# Corrupt an isolated animation resource; never a saved scene or bone pose.
	var clip: Animation = v.clip.duplicate(true)
	var name: StringName = row.params.animation_name
	var library: AnimationLibrary = v.player.get_animation_library("")
	library.remove_animation(name)
	library.add_animation(name, clip)
	v.clip = clip
	if control == "missing_contacts":
		row.write.erase("declared_contacts")
	elif control == "inert":
		for track in clip.get_track_count():
			var value: Variant = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track): clip.track_set_key_value(track, key, value)
	elif control == "wrong_heading":
		for track in clip.get_track_count():
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D and clip.track_get_path(track).get_subname(0) == str(v.roles.hips):
				var index := clip.track_get_key_count(track) - 1
				var rest: Basis = v.rig.get_bone_global_rest(v.indices.hips).basis.orthonormalized()
				var delta: Quaternion = (rest.inverse() * Basis(Quaternion(v.up, deg_to_rad(35.0))) * rest).get_rotation_quaternion()
				clip.track_set_key_value(track, index, delta * (clip.track_get_key_value(track, index) as Quaternion))
	elif control == "stance_slide":
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		var skeleton_path: NodePath = v.player.get_node(v.player.root_node).get_path_to(v.rig)
		clip.track_set_path(track, NodePath(str(skeleton_path) + ":" + str(v.roles.foot_r)))
		var rest_position: Vector3 = v.rig.get_bone_pose_position(v.indices.foot_r)
		clip.track_insert_key(track, 0.0, rest_position)
		clip.track_insert_key(track, clip.length * 0.12, rest_position + Vector3.RIGHT * float(v.leg) * 0.08)
		clip.track_insert_key(track, clip.length * 0.18, rest_position)
		clip.track_insert_key(track, clip.length, rest_position)
	elif control == "double_actor_yaw":
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		var path: NodePath = v.player.get_node(v.player.root_node).get_path_to(v.body)
		clip.track_set_path(track, NodePath(str(path) + ":rotation"))
		clip.track_insert_key(track, 0.0, Quaternion.IDENTITY)
		clip.track_insert_key(track, clip.length, Quaternion(v.up, deg_to_rad(45.0)))
	row.write.track_count = clip.get_track_count()
	var count := 0
	for track in clip.get_track_count(): count += clip.track_get_key_count(track)
	row.write.key_count = count
	v.player.stop()
	v.player.clear_caches()
	v.player.play(name, 0.0, 1.0)
	v.player.advance(0.0)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		quit(1)
		return
	control = args[2] if args.size() == 3 else ""
	if control not in ["", "missing_contacts", "inert", "wrong_heading", "stance_slide", "double_actor_yaw"]:
		quit(1)
		return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var runs: Array = []
	for row: Dictionary in route.cases:
		for mode in ["player", "tree"]:
			for fps in [30, 60, 120]: runs.append(_measure(row, fps, mode))
	var passed := runs.size() == 24 and logger.errors.is_empty()
	for run: Dictionary in runs: passed = passed and bool(run.thresholds_pass)
	var report := {"source_head": route.source_head, "revision": route.revision,
		"runs": runs, "engine_errors": logger.errors, "passed": passed, "control": control,
		"contract": "Saved Player/Tree world-space ankle/heading checks at actual FPS. Rest ankle plane is not sole collision; hip is not COM. Numerical pass does not approve visuals."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("TURN_QUALITY_RESULT=" + JSON.stringify({"runs": runs.size(), "passed": passed, "engine_errors": logger.errors}))
	quit(0 if passed else 1)
