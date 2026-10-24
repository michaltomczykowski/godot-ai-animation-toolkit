extends SceneTree

## Saved engine playback only. No motion specs, IK or hand-applied bone poses.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
var control := ""

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
	tree.root_motion_local = view.player.root_motion_local
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = view.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _check(row: Dictionary, fps: int, mode: String) -> Dictionary:
	row = row.duplicate(true)
	var v := Native.load_case(row, root)
	if v.has("error"):
		return {"thresholds_pass": false, "failures": [v.error]}
	v.animation_name = row.params.animation_name
	if not control.is_empty(): _inject_control(row, v)
	var reference := Native.load_case(row, root)
	if reference.has("error"):
		v.scene.free()
		return {"thresholds_pass": false, "failures": [reference.error]}
	var mixer := _tree(v, mode)
	var clip: Animation = v.clip
	var errors: Array[String] = []
	var extracted := bool(row.params.root_motion)
	var driver: Node3D = null
	if not extracted:
		# Gameplay translation belongs to a parent outside the visual player's
		# animated subtree. A linked tree can reset cached visual transforms
		# from other clips even when this in-place clip has no actor track.
		driver = Node3D.new()
		root.add_child(driver)
		v.scene.reparent(driver, true)
		v.body = driver
		v.initial_body = driver.global_position
	var leg: float = v.leg
	var speed: float = row.write.speed
	var root_track := clip.find_track(mixer.root_motion_track, Animation.TYPE_POSITION_3D)
	var expected_travel := Vector3.ZERO
	var cycle_contract_error := 0.0
	if extracted and root_track >= 0:
		# Six seconds can end part-way through a nonlinear root cycle. Read the
		# saved native interpolation for phase, and independently check its net
		# cycle travel against the public speed/direction contract.
		var first := clip.position_track_interpolate(root_track, 0.0)
		var last := clip.position_track_interpolate(root_track, clip.length)
		var parent: Node3D = v.body.get_parent_node_3d()
		var parent_basis: Basis = parent.global_basis if parent != null and not v.body.top_level else Basis.IDENTITY
		var cycles := floorf(6.0 / clip.length)
		expected_travel = parent_basis * ((last - first) * cycles + clip.position_track_interpolate(root_track, fposmod(6.0, clip.length)) - first)
		var left := Native.flat(Native.rest(v.rig, v.roles, "foot_l") - Native.rest(v.rig, v.roles, "foot_r"), v.up).normalized()
		var direction := left * (1.0 if str(row.params.get("direction", "left")) == "left" else -1.0)
		cycle_contract_error = (parent_basis * (last - first)).distance_to(direction * speed * clip.length)
	var anatomical_left := Native.flat(Native.rest(v.rig, v.roles, "foot_l") - Native.rest(v.rig, v.roles, "foot_r"), v.up).normalized()
	var travel_axis := anatomical_left * (1.0 if str(row.params.get("direction", "left")) == "left" else -1.0)
	if not extracted: expected_travel = travel_axis * speed * 6.0
	var minimum_foot_gap := INF
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
	if clip.loop_mode != Animation.LOOP_LINEAR: errors.append("Strafe must loop continuously")
	for side in ["L", "R"]:
		for label in ["contact.", "toe_off."]:
			if not clip.has_marker(label + side): marker_errors.append("Missing " + label + side)
	if not marker_errors.is_empty(): errors.append("Incomplete contact markers")
	if extracted and mixer.root_motion_track.is_empty(): errors.append("Extracted root track missing")
	if extracted and root_track < 0: errors.append("Extracted position track missing")
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
				v.body.position += delta
			else:
				# In-place bones need a caller-owned actor velocity for world planting.
				# Observe inert clip/root output before applying that single owner.
				zero_root_error = maxf(zero_root_error, delta.length())
				clip_owner_error = maxf(clip_owner_error, before.distance_to(v.body.global_position))
				v.body.global_position += travel_axis * speed * dt
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
		minimum_foot_gap = minf(minimum_foot_gap, (Native.point(v, "foot_l") - Native.point(v, "foot_r")).dot(anatomical_left))
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
			var step: float = (v.rig.global_basis * (pose.origin - previous[index])).length()
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
	var root_error := travel.distance_to(expected_travel)
	var forward_drift := absf(travel.dot(v.forward))
	var slide_limit := minf(0.02 * leg, 0.03)
	if not path_errors.is_empty(): errors.append("Invalid track paths/types")
	if nonfinite > 0: errors.append("Nonfinite played poses")
	if bool(row.write.clamped): errors.append("Generation reach clamp")
	if root_error >= 0.0001: errors.append("Root/actor travel mismatch")
	if cycle_contract_error >= 0.0001: errors.append("Root cycle differs from reported speed/direction")
	if zero_root_error > 0.000001 or clip_owner_error > 0.000001: errors.append("In-place clip owns translation")
	if seams == 0: errors.append("No crossed loop seam coverage")
	if max_reference.x > 0.001 * leg or max_reference.y > 0.0001: errors.append("Repeated engine pose differs at fractional phase")
	if max_pose_step <= 0.000001: errors.append("Inert skeletal playback")
	if minimum_foot_gap <= 0.0: errors.append("Left/right feet cross or collapse during lateral stepping")
	if forward_drift > 0.0001: errors.append("Strafe drifts forward")
	if max_pose_step * fps > 6.0 * leg: errors.append("Played bone discontinuity")
	if not row.params.has("overrides") and not row.params.has("arm_down"):
		for side in arms:
			var arm: Dictionary = arms[side]
			if arm.max_upper_up_dot >= -0.8 or arm.max_elbow_deg - arm.min_elbow_deg < 1.0 or arm.wrist_excursion_rad < 0.005:
				errors.append(side + " ordinary arm hang/follow-through failure")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if f.slide > slide_limit or f.penetration > 0.01 * leg or f.contact_height > 0.01 * leg or f.flips > 0 or f.contacts < 2:
			errors.append(side + " contact/slide/penetration/knee failure")
		metrics[side] = {"max_declared_stance_slide_m": f.slide, "max_rest_ankle_plane_penetration_m": f.penetration,
			"max_declared_contact_height_m": f.contact_height, "knee_pole_flips": f.flips,
			"declared_contact_frames": f.declared_frames, "observed_contact_band_frames": f.observed_frames, "contact_windows": f.contacts}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "root_mode": "extracted" if extracted else "in_place_actor_driver",
		"actor_translation_owner": "extracted track target" if extracted else "unanimated gameplay parent outside the visual mixer subtree",
		"frames": 6 * fps + 1, "dt": dt, "leg_length_m": leg, "period_s": clip.length,
		"slide_limit_m": slide_limit, "penetration_limit_m": 0.01 * leg,
		"root_distance_m": travel.length(), "expected_root_distance_m": expected_travel.length(), "root_error_m": root_error,
		"root_cycle_contract_error_m": cycle_contract_error,
		"minimum_signed_lateral_foot_gap_m": minimum_foot_gap, "forward_drift_m": forward_drift,
		"max_in_place_root_delta_m": zero_root_error, "max_in_place_clip_translation_m": clip_owner_error,
		"max_reference_position_error_m": max_reference.x, "max_reference_rotation_error_rad": max_reference.y,
		"crossed_loop_seams": seams, "max_pose_step_m": max_pose_step, "max_seam_step_m": seam_step,
		"max_skeletal_speed_legs_per_s": max_pose_step * fps / leg,
		"nonfinite": nonfinite, "generation_reach_clamped": row.write.clamped, "active_mixers": active_mixers,
		"declared_flight_frames": declared_flight_frames, "observed_flight_frames": flight_frames,
		"observed_flight_windows": flight_windows, "feet": metrics, "trace": trace,
		"path_errors": path_errors, "marker_errors": marker_errors, "failures": errors, "thresholds_pass": errors.is_empty()}
	for side in arms: arms[side].erase("wrist_initial")
	result["arms"] = arms
	v.scene.free()
	if driver != null: driver.free()
	reference.scene.free()
	return result

func _inject_control(row: Dictionary, v: Dictionary) -> void:
	var name := str(row.params.animation_name)
	var library_name := name.get_slice("/", 0) if name.contains("/") else ""
	# A saved scene can share an external library. Rebind a private library as
	# well as a private clip before changing either resource in a control.
	var library: AnimationLibrary = v.player.get_animation_library(library_name).duplicate(true)
	v.player.remove_animation_library(library_name)
	v.player.add_animation_library(library_name, library)
	library.remove_animation(name.get_slice("/", 1) if name.contains("/") else name)
	v.clip = v.clip.duplicate(true)
	library.add_animation(name.get_slice("/", 1) if name.contains("/") else name, v.clip)
	var clip: Animation = v.clip
	if control == "missing_contacts":
		clip.remove_marker("contact.L")
	elif control == "missing_root_track":
		var track := clip.find_track(v.player.root_motion_track, Animation.TYPE_POSITION_3D)
		if track >= 0: clip.remove_track(track)
	elif control == "pose_pop":
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or clip.track_get_path(track).get_subname(0) != str(v.roles.hips): continue
			var index := clip.track_find_key(track, 0.4 * clip.length, Animation.FIND_MODE_APPROX)
			if index >= 0:
				var parent: int = v.rig.get_bone_parent(v.indices.hips)
				var basis_value: Basis = v.rig.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
				clip.track_set_key_value(track, index, (clip.track_get_key_value(track, index) as Vector3) + basis_value.inverse() * v.rig.global_basis.inverse() * v.up * float(v.leg) * 0.3)
	elif control == "inert":
		for track in clip.get_track_count():
			var value: Variant = clip.track_get_key_value(track, 0)
			for key in clip.track_get_key_count(track): clip.track_set_key_value(track, key, value)
	elif control in ["double_travel", "reverse_travel"]:
		var track := clip.find_track(v.player.root_motion_track, Animation.TYPE_POSITION_3D)
		if track >= 0:
			var first: Vector3 = clip.track_get_key_value(track, 0)
			var factor := 2.0 if control == "double_travel" else -1.0
			for key in clip.track_get_key_count(track):
				clip.track_set_key_value(track, key, first + ((clip.track_get_key_value(track, key) as Vector3) - first) * factor)
	elif control == "stance_slide":
		var track := clip.add_track(Animation.TYPE_POSITION_3D)
		var path: NodePath = v.player.get_node(v.player.root_node).get_path_to(v.rig)
		clip.track_set_path(track, NodePath(str(path) + ":" + str(v.roles.foot_r)))
		var rest_position: Vector3 = v.rig.get_bone_pose_position(v.indices.foot_r)
		# The trailing right foot is planted through the first left step.
		var parent: int = v.rig.get_bone_parent(v.indices.foot_r)
		var parent_basis: Basis = v.rig.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
		var shift: Vector3 = parent_basis.inverse() * v.rig.global_basis.inverse() * v.forward * float(v.leg) * 0.12
		for event in [[0.0, 0.0], [0.15, 1.0], [0.35, 0.0], [1.0, 0.0]]:
			clip.track_insert_key(track, float(event[0]) * clip.length, rest_position + shift * float(event[1]))
	row.write.track_count = clip.get_track_count()
	var count := 0
	for track in clip.get_track_count(): count += clip.track_get_key_count(track)
	row.write.key_count = count
	v.player.stop()
	v.player.clear_caches()
	v.player.play(name)
	v.player.advance(0.0)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	control = args[3] if args.size() > 3 else ""
	if control not in ["", "missing_contacts", "inert", "double_travel", "reverse_travel", "stance_slide", "missing_root_track", "pose_pop"]:
		quit(1)
		return
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
				if not result.get("thresholds_pass", false): failures.append("%s/%s/%s: %s" % [row.id, fps, mode, str(result.get("failures", ["Invalid check result"]))])
	var expected := 4 * 3 * modes.size()
	var report := {"source_head": manifest.source_head, "revision": manifest.revision,
		"control": control,
		"route_sha256": FileAccess.get_sha256(args[0]),
		"checker_sha256": FileAccess.get_sha256("res://tools/check_strafe_quality.gd"),
		"native_helper_sha256": FileAccess.get_sha256("res://tools/character_quality_native.gd"),
		"runs": results, "failures": failures, "engine_errors": logger.errors,
		"passed": results.size() == expected and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Independent saved engine playback, world-space ankle contact/flight and one actor translation owner. Rest ankle plane is not skinned sole collision. In-place world planting uses caller-owned constant velocity; observed contact band differs from marker timing. Numerical checks do not approve visual quality."}
	FileAccess.open(args[1], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("STRAFE_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
