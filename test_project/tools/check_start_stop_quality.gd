extends SceneTree

## Independent one-shot playback and joins to separately saved approved clips.
## No production motion sampler, IK, or bone-pose writes are used here.
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

## Position-only extraction is expressed in the carrier owner's parent frame.
## These checkers do not consume the paired rotation deltas used by bake tools.
static func _carrier_world(owner: Node3D, delta: Vector3) -> Vector3:
	var parent := owner.get_parent_node_3d()
	return parent.global_basis * delta if parent != null and not owner.top_level else delta

static func _actor_schedule_basis(rig: Node3D, owner: Node3D, space: String) -> Dictionary:
	if space == "skeleton_local": return {"basis": rig.global_basis}
	# Historical manifests explicitly used this label. Preserve their stated
	# owner-local convention; new records identify skeleton_local instead.
	if space == "root_motion_node_local": return {"basis": owner.global_basis}
	return {"error": "Unknown or missing actor_translation_space: " + space}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _poses(rig: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in rig.get_bone_count(): result.append(rig.get_bone_global_pose(i))
	return result

func _rotation(a: Transform3D, b: Transform3D) -> Vector3:
	var q := a.basis.get_rotation_quaternion().inverse() * b.basis.get_rotation_quaternion()
	if q.w < 0.0: q = -q
	var axis := Vector3(q.x, q.y, q.z)
	return axis.normalized() * (2.0 * atan2(axis.length(), absf(q.w))) if axis.length() > 0.00000001 else Vector3.ZERO

func _difference(a: Array[Transform3D], b: Array[Transform3D]) -> Vector2:
	var worst := Vector2.ZERO
	if a.size() != b.size(): return Vector2(INF, INF)
	for i in a.size():
		worst.x = maxf(worst.x, a[i].origin.distance_to(b[i].origin))
		worst.y = maxf(worst.y, _rotation(a[i], b[i]).length())
	return worst

func _tree(v: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return v.player
	v.player.active = false
	var tree := AnimationTree.new()
	v.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(v.player)
	tree.root_node = tree.get_path_to(v.player.get_node(v.player.root_node))
	tree.root_motion_track = v.player.root_motion_track
	tree.root_motion_local = v.player.root_motion_local
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = v.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _find(manifest: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in manifest.cases:
		if row.id == id: return row
	return {}

func _join(v: Dictionary, other_row: Dictionary, edge: float, phase: float, entering: bool, dt: float) -> Dictionary:
	var reference := Native.load_case(other_row, root)
	var at: float = phase * reference.clip.length
	reference.player.seek(at, true)
	var center := _poses(reference.rig)
	reference.player.seek(fposmod(at - dt, reference.clip.length), true)
	var reference_before := _poses(reference.rig)
	reference.player.seek(fposmod(at + dt, reference.clip.length), true)
	var reference_after := _poses(reference.rig)
	v.player.seek(edge, true)
	var here := _poses(v.rig)
	var endpoint := _difference(here, center)
	var before: Array[Transform3D]
	var after: Array[Transform3D]
	if entering:
		reference.player.seek(fposmod(at - dt, reference.clip.length), true)
		before = _poses(reference.rig)
		v.player.seek(edge + dt, true)
		after = _poses(v.rig)
	else:
		v.player.seek(edge - dt, true)
		before = _poses(v.rig)
		reference.player.seek(fposmod(at + dt, reference.clip.length), true)
		after = _poses(reference.rig)
	var worst := Vector2.ZERO
	var continuation := Vector2.ZERO
	var bones: Array = []
	for i in here.size():
		var incoming := here[i].origin - before[i].origin
		var outgoing := after[i].origin - here[i].origin
		var position_jump := incoming.distance_to(outgoing)
		var angular_jump := _rotation(before[i], here[i]).distance_to(_rotation(here[i], after[i]))
		var actual_step := outgoing if entering else incoming
		var reference_step := reference_after[i].origin - center[i].origin if entering else center[i].origin - reference_before[i].origin
		var actual_rotation := _rotation(here[i], after[i]) if entering else _rotation(before[i], here[i])
		var reference_rotation := _rotation(center[i], reference_after[i]) if entering else _rotation(reference_before[i], center[i])
		continuation.x = maxf(continuation.x, actual_step.distance_to(reference_step))
		continuation.y = maxf(continuation.y, actual_rotation.distance_to(reference_rotation))
		worst.x = maxf(worst.x, position_jump)
		worst.y = maxf(worst.y, angular_jump)
		bones.append({"bone": v.rig.get_bone_name(i), "position_step_jump_m": position_jump,
			"continuation_position_step_error_m": actual_step.distance_to(reference_step),
			"continuation_rotation_step_error_rad": actual_rotation.distance_to(reference_rotation),
			"rotation_step_jump_rad": angular_jump, "position_velocity_jump_m_s": position_jump / dt,
			"rotation_velocity_jump_rad_s": angular_jump / dt})
	reference.scene.free()
	return {"reference_scene": other_row.scene, "reference_scene_sha256": other_row.scene_sha256,
		"reference_phase": phase, "reference_time_s": at, "endpoint_position_error_m": endpoint.x,
		"max_continuation_position_step_error_m": continuation.x,
		"max_continuation_rotation_step_error_rad": continuation.y,
		"endpoint_rotation_error_rad": endpoint.y, "max_position_step_jump_m": worst.x,
		"max_rotation_step_jump_rad": worst.y, "spacing_s": dt, "bones": bones}

func _check(row: Dictionary, pair: Dictionary, walk: Dictionary, idle: Dictionary, fps: int, mode: String, baseline: bool) -> Dictionary:
	var v := Native.load_case(row, root)
	v.animation_name = row.params.animation_name
	var clip: Animation = v.clip
	var leg: float = v.leg
	var dt := 1.0 / fps
	# The existing commit path appends a stationary extraction tail. Joins use
	# the authored action boundary, not the later storage/finishing boundary.
	var action_duration := float(row.write.get("capture_duration", clip.length))
	var stopping: bool = row.params.op == "walk_stop"
	var phase := float(row.write.get("phase", row.params.get("phase", 0.0)))
	var gait_join := _join(v, walk, 0.0 if stopping else action_duration, phase, stopping, dt)
	var idle_join := _join(v, idle, action_duration if stopping else 0.0, 0.0, not stopping, dt)
	v.player.stop()
	v.player.play(v.animation_name, 0.0, 1.0)
	v.player.advance(0.0)
	var reference := Native.load_case(row, root)
	var extracted: bool = row.params.root_motion
	var driver: Node3D = null
	var paired: Dictionary = {}
	var paired_track := -1
	var actor_animation: Animation = null
	var actor_errors: Array[String] = []
	var actor_schedule_known: bool = row.write.has("actor_translation_keys")
	var schedule_basis := Basis.IDENTITY
	if actor_schedule_known:
		var mapping := _actor_schedule_basis(v.rig, v.body, str(row.write.get("actor_translation_space", "")))
		if mapping.has("error"):
			actor_errors.append(mapping.error)
		else:
			schedule_basis = mapping.basis
		if str(row.write.get("actor_translation_space", "")) == "skeleton_local":
			var reported_scale := float(row.write.get("actor_translation_world_scale", -1.0))
			if absf(reported_scale - v.rig.global_basis.x.length()) > 0.00001:
				actor_errors.append("Actor schedule world scale differs from saved skeleton")
	if not extracted:
		driver = Node3D.new()
		root.add_child(driver)
		v.scene.reparent(driver, true)
		v.body = driver
		v.initial_body = driver.global_position
		if actor_schedule_known:
			actor_animation = Animation.new()
			actor_animation.length = action_duration
			actor_animation.add_track(Animation.TYPE_POSITION_3D)
			var previous_time := -1.0
			var schedule: Array = row.write.actor_translation_keys
			if schedule.size() < 2: actor_errors.append("Actor schedule must contain at least two keys")
			for key: Dictionary in schedule:
				var offset: Array = key.get("offset", [])
				var time := float(key.get("time", -1.0))
				if offset.size() != 3 or not is_finite(time) or time <= previous_time:
					actor_errors.append("Invalid actor schedule key")
					continue
				var value := Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
				if not value.is_finite(): actor_errors.append("Nonfinite actor schedule")
				actor_animation.track_insert_key(0, time, schedule_basis * value)
				previous_time = time
			if previous_time < action_duration - 0.000001: actor_errors.append("Actor schedule ends before action")
		elif baseline:
			# Only old baseline diagnostics use the paired extracted saved track.
			paired = Native.load_case(pair, root)
			paired_track = paired.clip.find_track(paired.player.root_motion_track, Animation.TYPE_POSITION_3D)
	var mixer := _tree(v, mode)
	var errors: Array[String] = []
	errors.append_array(actor_errors)
	if not baseline and (not row.write.has("declared_contacts") or (row.write.declared_contacts as Array).is_empty()): errors.append("Candidate must declare intended support")
	var key_count := 0
	var path_errors: Array[String] = []
	var active_mixers := 0
	for active in v.scene.find_children("*", "AnimationMixer", true, false):
		if active.active: active_mixers += 1
	if active_mixers != 1: errors.append("Expected exactly one active mixer")
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target: Node = v.player.get_node(v.player.root_node).get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null: path_errors.append("Unresolved path " + str(path))
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]: path_errors.append("Unexpected track type")
		if target is Skeleton3D and (path.get_subname_count() != 1 or target.find_bone(str(path.get_subname(0))) < 0): path_errors.append("Unresolved bone " + str(path))
		if not extracted and not target is Skeleton3D: path_errors.append("In-place clip writes actor transform")
		key_count += clip.track_get_key_count(track)
	if not path_errors.is_empty(): errors.append("Invalid track paths/types")
	if key_count != int(row.write.key_count) or clip.get_track_count() != int(row.write.track_count): errors.append("Reported track/key counts differ")
	if clip.get_marker_names().size() != int(row.write.markers): errors.append("Reported marker count differs")
	if clip.loop_mode != Animation.LOOP_NONE: errors.append("Transition must preserve one-shot endpoints")
	if absf(clip.length - float(row.write.length)) > 0.000001: errors.append("Reported duration differs")
	if not clip.has_marker("settled") or absf(clip.get_marker_time("settled") - action_duration) > 0.000001: errors.append("Reported action boundary differs from settled marker")
	var root_track := clip.find_track(mixer.root_motion_track, Animation.TYPE_POSITION_3D)
	if extracted and root_track < 0: errors.append("Extracted root track missing")
	if not extracted and root_track >= 0: errors.append("In-place clip owns extracted translation")
	var expected_root := Vector3.ZERO
	if root_track >= 0: expected_root = _carrier_world(v.body, clip.position_track_interpolate(root_track, clip.length) - clip.position_track_interpolate(root_track, 0.0))
	if not extracted and paired_track >= 0: expected_root = _carrier_world(paired.body, paired.clip.position_track_interpolate(paired_track, paired.clip.length) - paired.clip.position_track_interpolate(paired_track, 0.0))
	if not extracted and actor_animation != null and actor_animation.track_get_key_count(0) >= 2:
		expected_root = actor_animation.position_track_interpolate(0, action_duration) - actor_animation.position_track_interpolate(0, 0.0)
	var feet := {}
	for side in ["l", "r"]:
		feet[side] = {"active": false, "anchor": Vector3.ZERO, "slide": 0.0, "penetration": 0.0,
			"declared_active": -1, "declared_anchor": Vector3.ZERO, "declared_slide": 0.0, "declared_height": 0.0, "declared_frames": 0,
			"normal": Vector3.ZERO, "flips": 0, "frames": 0, "windows": 0}
	var previous := _poses(v.rig)
	var terminal: Array[Transform3D] = []
	var max_reference := Vector2.ZERO
	var hold_error := Vector2.ZERO
	var max_step := Vector2.ZERO
	var endpoint_step := Vector2.ZERO
	var nonfinite := 0
	var root_hold_error := 0.0
	var hold_root := Vector3.ZERO
	var backward := 0.0
	var in_place_root := 0.0
	var frames := ceili((clip.length + 0.5) * fps)
	var trace: Array = []
	for frame in frames + 1:
		if frame > 0:
			var before_root: Vector3 = v.body.global_position
			mixer.advance(dt)
			var delta := mixer.get_root_motion_position()
			if extracted: v.body.position += delta
			else:
				in_place_root = maxf(in_place_root, delta.length())
				if actor_animation != null and actor_animation.track_get_key_count(0) >= 2:
					v.body.global_position = v.initial_body + actor_animation.position_track_interpolate(0, minf(float(frame) / fps, action_duration))
				elif paired_track >= 0:
					var at := minf(float(frame) / fps, clip.length)
					var before := minf(float(frame - 1) / fps, clip.length)
					v.body.global_position += _carrier_world(paired.body, paired.clip.position_track_interpolate(paired_track, at) - paired.clip.position_track_interpolate(paired_track, before))
			backward = maxf(backward, -(v.body.global_position - before_root).dot(v.forward))
		v.time = float(frame) / fps
		reference.player.seek(minf(v.time, clip.length), true)
		var poses := _poses(v.rig)
		var difference := _difference(poses, _poses(reference.rig))
		max_reference.x = maxf(max_reference.x, difference.x)
		max_reference.y = maxf(max_reference.y, difference.y)
		if v.time >= clip.length - 0.000001:
			if terminal.is_empty():
				terminal = poses
				hold_root = v.body.global_position
			else:
				var held := _difference(terminal, poses)
				hold_error.x = maxf(hold_error.x, held.x)
				hold_error.y = maxf(hold_error.y, held.y)
				root_hold_error = maxf(root_hold_error, hold_root.distance_to(v.body.global_position))
		var sample := {"time": v.time, "root": Native.values(v.body.global_position), "feet": {}}
		for side: String in feet:
			var foot := Native.point(v, "foot_" + side)
			var height: float = foot.dot(v.up) - v.ground
			var f: Dictionary = feet[side]
			var declared := -1
			var contacts: Array = row.write.get("declared_contacts", [])
			for i in contacts.size():
				if contacts[i].side == side and v.time >= float(contacts[i].start) - 0.000001 and v.time <= float(contacts[i].end) + 0.000001: declared = i
			if declared >= 0:
				if declared != int(f.declared_active): f.declared_anchor = foot
				f.declared_slide = maxf(float(f.declared_slide), Native.flat(foot - f.declared_anchor, v.up).length())
				f.declared_height = maxf(float(f.declared_height), absf(height))
				f.declared_frames += 1
			f.declared_active = declared
			var on := absf(height) <= 0.01 * leg
			if on and not f.active:
				f.anchor = foot
				f.windows += 1
			if on:
				f.frames += 1
				f.slide = maxf(f.slide, Native.flat(foot - f.anchor, v.up).length())
			f.active = on
			f.penetration = maxf(f.penetration, -height)
			var thigh := Native.point(v, "thigh_" + side)
			var knee := Native.point(v, "shin_" + side)
			var axis := (foot - thigh).normalized()
			var pole := knee - thigh - axis * (knee - thigh).dot(axis)
			if pole.length() > 0.005 * leg:
				var normal := pole.normalized()
				if (f.normal as Vector3).length_squared() > 0.5 and normal.dot(f.normal) < 0.0: f.flips += 1
				f.normal = normal
			sample.feet[side] = {"p": Native.values(foot), "height_from_rest_ankle_plane": height, "observed_contact_band": on, "declared_contact_index": declared}
		for i in poses.size():
			if not poses[i].origin.is_finite() or not poses[i].basis.is_finite(): nonfinite += 1
			var step := _difference([poses[i]], [previous[i]])
			max_step.x = maxf(max_step.x, step.x)
			max_step.y = maxf(max_step.y, step.y)
			if v.time >= clip.length - dt and v.time <= clip.length + dt:
				endpoint_step.x = maxf(endpoint_step.x, step.x)
				endpoint_step.y = maxf(endpoint_step.y, step.y)
		previous = poses
		trace.append(sample)
	var travel: Vector3 = v.body.global_position - v.initial_body
	var root_error := travel.distance_to(expected_root)
	if root_error > 0.0001 or root_hold_error > 0.00001: errors.append("Root travel/terminal hold mismatch")
	if backward > 0.00001: errors.append("Backward root travel")
	if in_place_root > 0.000001: errors.append("In-place extraction output")
	if max_reference.x > 0.001 * leg or max_reference.y > 0.0001: errors.append("Sequential mixer differs from independent engine seek")
	if hold_error.x > 0.00001 or hold_error.y > 0.0001: errors.append("Terminal pose does not hold")
	if nonfinite > 0 or max_step.x < 0.000001: errors.append("Nonfinite/inert skeletal playback")
	var clamp_known: bool = row.write.has("clamped")
	if clamp_known and bool(row.write.clamped): errors.append("Generation reach clamp")
	if not baseline and not clamp_known: errors.append("Generation clamp metadata unavailable")
	if not baseline and not extracted and not actor_schedule_known: errors.append("In-place actor schedule unavailable")
	for join: Dictionary in [gait_join, idle_join]:
		if join.endpoint_position_error_m > 0.00001 or join.endpoint_rotation_error_rad > 0.0001: errors.append("Accepted pose endpoint differs")
		if join.max_continuation_position_step_error_m > 0.005 or join.max_continuation_rotation_step_error_rad > 0.75 * max_step.y + 0.002: errors.append("Played reference continuation differs")
	var metrics := {}
	for side: String in feet:
		var f: Dictionary = feet[side]
		if (not row.write.has("declared_contacts") and f.slide > minf(0.02 * leg, 0.03)) or f.penetration > 0.01 * leg or f.flips > 0 or f.frames == 0: errors.append(side + " contact/slide/penetration/knee failure")
		if row.write.has("declared_contacts") and (f.declared_slide > minf(0.02 * leg, 0.03) or f.declared_height > 0.01 * leg or f.declared_frames == 0): errors.append(side + " declared support failure")
		metrics[side] = {"max_observed_contact_slide_m": f.slide, "max_rest_ankle_plane_penetration_m": f.penetration,
			"max_declared_contact_slide_m": f.declared_slide, "max_declared_contact_height_m": f.declared_height, "declared_contact_frames": f.declared_frames,
			"knee_pole_flips": f.flips, "observed_contact_frames": f.frames, "observed_contact_windows": f.windows}
	var result := {"id": row.id, "fps": fps, "mixer": mode, "frames": frames + 1, "duration_s": clip.length,
		"action_duration_s": action_duration, "reported_terminal_hold_s": row.write.get("root_motion_terminal_hold", null),
		"root_mode": "extracted" if extracted else "in_place", "phase": phase, "leg_length_m": leg,
		"generation_clamp_metadata_known": clamp_known, "generation_reach_clamped": row.write.get("clamped", null),
		"actor_schedule_known": actor_schedule_known, "actor_schedule_source": "extracted root track" if extracted else ("reported actor translation schedule" if actor_schedule_known else "paired extracted saved clip: diagnostic assumption"),
		"active_mixers": active_mixers, "root_distance_m": travel.length(), "expected_root_distance_m": expected_root.length(),
		"root_error_m": root_error, "root_hold_error_m": root_hold_error, "backward_root_step_m": backward,
		"max_in_place_root_delta_m": in_place_root, "max_reference_position_error_m": max_reference.x,
		"max_reference_rotation_error_rad": max_reference.y, "max_pose_step_m": max_step.x, "max_rotation_step_rad": max_step.y,
		"endpoint_step_m": endpoint_step.x, "endpoint_rotation_step_rad": endpoint_step.y, "nonfinite": nonfinite,
		"hold_position_error_m": hold_error.x, "hold_rotation_error_rad": hold_error.y, "gait_join": gait_join,
		"idle_join": idle_join, "feet": metrics, "trace": trace, "path_errors": path_errors,
		"failures": errors, "thresholds_pass": errors.is_empty()}
	v.scene.free()
	if driver != null: driver.free()
	reference.scene.free()
	if not paired.is_empty(): paired.scene.free()
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 4 and args[0] == "--self-check":
		var controls: Array = []
		for path in [args[1], args[2]]:
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			for row: Dictionary in manifest.cases:
				var v := Native.load_case(row, root)
				for fps in [30, 60, 120]:
					for phase in [0.0, 0.137, 0.537]:
						for entering in [false, true]:
							var check := _join(v, row, phase * v.clip.length, phase, entering, 1.0 / fps)
							var mismatch := _join(v, row, fposmod(phase + 0.2, 1.0) * v.clip.length, phase, entering, 1.0 / fps)
							controls.append({"rig": row.id, "reference": manifest.operation, "fps": fps, "phase": phase, "entering": entering,
								"positive_position_error_m": check.max_continuation_position_step_error_m,
								"positive_rotation_error_rad": check.max_continuation_rotation_step_error_rad,
								"negative_endpoint_position_error_m": mismatch.endpoint_position_error_m,
								"negative_endpoint_rotation_error_rad": mismatch.endpoint_rotation_error_rad,
								"passed": check.max_continuation_position_step_error_m < 0.00001 and check.max_continuation_rotation_step_error_rad < 0.0001 and (mismatch.endpoint_position_error_m > 0.00001 or mismatch.endpoint_rotation_error_rad > 0.0001)})
				v.scene.free()
		var passed := controls.size() == 144 and logger.errors.is_empty()
		for control: Dictionary in controls:
			if not control.passed: passed = false
		FileAccess.open(args[3], FileAccess.WRITE).store_string(JSON.stringify({"rows": controls, "passed": passed, "engine_errors": logger.errors}))
		OS.remove_logger(logger)
		print("CONTINUATION_SELF_CHECK=" + JSON.stringify({"rows": controls.size(), "passed": passed}))
		quit(0 if passed else 1)
		return
	if args.size() != 5:
		quit(1)
		return
	var inputs: Array[Dictionary] = []
	for i in 4: inputs.append(JSON.parse_string(FileAccess.get_file_as_string(args[i])))
	var results: Array = []
	var failures: Array = []
	for row: Dictionary in inputs[0].cases:
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var result := _check(row, _find(inputs[1], row.id), _find(inputs[2], row.id), _find(inputs[3], row.id), fps, mode, inputs[0].phase == "baseline")
				results.append(result)
				if not result.thresholds_pass: failures.append("%s/%s/%s: %s" % [row.id, fps, mode, str(result.failures)])
	var expected_cases := int(inputs[0].get("expected_case_count", 4)) if inputs[0].phase == "prototype" else 4
	var report := {"source_head": inputs[0].source_head, "revision": inputs[0].revision, "runs": results,
		"failures": failures, "engine_errors": logger.errors, "passed": inputs[0].cases.size() == expected_cases and results.size() == expected_cases * 6 and failures.is_empty() and logger.errors.is_empty(),
		"measurement_contract": "Independent played reference endpoint and same-interval continuation errors; raw boundary curvature retained. Declared stance slide/height and observed ankle-band motion are distinct; ankle band is not sole collision. Root uses reported in-place schedule; paired track only for old baseline. Numerical checks do not approve visual quality."}
	FileAccess.open(args[4], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("START_STOP_QUALITY_CHECK=" + JSON.stringify({"runs": results.size(), "passed": report.passed, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
