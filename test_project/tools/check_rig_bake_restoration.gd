extends SceneTree
const Native := preload("res://tools/modifier_native_reference.gd")

## Independent engine playback. No toolkit, clip-spec or editor-test imports.
class Errors extends Logger:
	var values: Array = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _traces: Array) -> void:
		if type != 1: values.append(rationale if not rationale.is_empty() else code)
class FinalPose extends SkeletonModifier3D:
	var poses: Array = []
	var count := 0
	func _process_modification_with_delta(_delta: float) -> void:
		poses.clear()
		var rig := get_skeleton()
		for i in rig.get_bone_count(): poses.append({"p": rig.get_bone_pose_position(i), "q": rig.get_bone_pose_rotation(i), "s": rig.get_bone_pose_scale(i)})
		count += 1
var failures: Array = []
var logger := Errors.new()
var saved_states := 0
var played_states := 0
var key_samples := 0
var intermediate_samples := 0
var worst := {"position": 0.0, "rotation": 0.0, "scale": 0.0}
var native_approximation := {"position": 0.0, "rotation": 0.0, "scale": 0.0}
var approximation_peak := {}
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _load(path: String) -> Node:
	if path.is_empty() or not ResourceLoader.exists(path):
		failures.append("missing scene " + path)
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return null
	var scene := packed.instantiate()
	for mixer in scene.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
		mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for rig in scene.find_children("*", "Skeleton3D", true, false): rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(scene)
	return scene
func _value(value: Variant) -> Variant:
	if value is Dictionary and value.get("kind") == "vector2": return Vector2(value.x, value.y)
	return value
func _times(p: Dictionary) -> Array:
	var times: Array = []
	for i in int(ceil(float(p.duration) * int(p.fps))) + 1: times.append(minf(float(i) / int(p.fps), float(p.duration)))
	for event in p.get("tree_events", []):
		if not times.has(float(event.time)): times.append(float(event.time))
	times.sort()
	var seen := {}
	for event in p.get("tree_events", []):
		var time := float(event.time)
		if time <= 0 or seen.has(time): continue
		seen[time] = true
		var previous := 0.0
		for key in times:
			if key < time: previous = maxf(previous, key)
		times.append(time - minf(0.00004 * maxf(1.0, absf(time)), (time - previous) * 0.5))
	times.sort()
	return times
func _event_bridge(p: Dictionary, from: float, to: float) -> bool:
	for event in p.get("tree_events", []):
		if absf(float(event.time) - to) < 0.00000001 and to - from <= 0.000041 * maxf(1.0, absf(to)): return true
	return false
func _consume(owner: Node3D, mixer: AnimationMixer, initial_scale: Vector3, accum: Vector3) -> Vector3:
	owner.quaternion = (owner.quaternion * mixer.get_root_motion_rotation()).normalized()
	var frame: Quaternion = owner.quaternion if mixer.root_motion_local else mixer.get_root_motion_rotation_accumulator().inverse() * owner.quaternion
	owner.position += frame * mixer.get_root_motion_position()
	accum += mixer.get_root_motion_scale()
	owner.scale = initial_scale * accum
	return accum
func _poses(rig: Skeleton3D) -> Array:
	var values: Array = []
	for i in rig.get_bone_count(): values.append({"p": rig.get_bone_pose_position(i), "q": rig.get_bone_pose_rotation(i), "s": rig.get_bone_pose_scale(i)})
	return values
func _difference(a: Dictionary, b: Dictionary, label: String) -> void:
	var q: Quaternion = (a.q as Quaternion).inverse() * (b.q as Quaternion)
	var errors := {"position": (a.p as Vector3).distance_to(b.p), "rotation": 2 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)), "scale": (a.s as Vector3).distance_to(b.s)}
	for channel in errors:
		worst[channel] = maxf(worst[channel], errors[channel])
		_check(is_finite(errors[channel]) and errors[channel] <= (0.001 if channel == "rotation" else 0.0001), label + " " + channel + " error=" + str(errors[channel]))
func _body(body: Node3D) -> Dictionary: return {"p": body.position, "q": body.quaternion, "s": body.scale}
func _native(row: Dictionary, intermediate: bool = false) -> Array:
	var scene := _load(row.source)
	if scene == null: return []
	var player := scene.get_node(row.source_player) as AnimationPlayer
	var rig := scene.get_node(row.skeleton) as Skeleton3D
	var body := scene.get_node(row.movement_owner) as Node3D
	var tree := scene.get_node(row.tree) as AnimationTree if not str(row.tree).is_empty() else null
	var mixer: AnimationMixer = tree if tree != null else player
	for configuration in row.get("modifiers", []):
		var old := scene.get_node(configuration.path) as SkeletonModifier3D
		var native := Native.replace(configuration, old.get_parent(), old)
		native.influence = float(configuration.params.get("influence", 1))
		Native.finish(native)
	var witness := FinalPose.new()
	rig.add_child(witness)
	player.speed_scale = 1
	player.playback_auto_capture = false
	if tree != null:
		for entry in tree.get_property_list():
			var path := str(entry.name)
			if path.ends_with("/request"): tree.set(path, 0)
			elif path.ends_with("/seek_request"): tree.set(path, -1.0)
			elif path.ends_with("/transition_request"): tree.set(path, "")
		for path in row.params.get("tree_parameters", {}): tree.set(path, _value(row.params.tree_parameters[path]))
		for start in row.params.get("tree_starts", []): tree.get(start.playback_path).start(start.state, true)
		tree.active = true
	else:
		player.active = true
		player.play(str(row.params.get("source_animation", "input")))
	var events: Array = row.params.get("tree_events", [])
	var cursor := 0
	var previous := 0.0
	var result: Array = []
	var initial_scale := body.scale
	var accum := Vector3.ONE
	var required: Array = []
	for candidate in scene.find_children("*", "Skeleton3D", true, false):
		if candidate == rig or candidate.is_ancestor_of(rig) or rig.is_ancestor_of(candidate): required.append(candidate)
	var times := _times(row.params)
	if intermediate:
		for i in times.size() - 1: times.append((float(times[i]) + float(times[i + 1])) * 0.5)
		times.sort()
	for time in times:
		if time > previous and (tree != null or player.is_playing()):
			mixer.advance(time - previous)
			if not mixer.root_motion_track.is_empty() and row.params.get("root_motion_mode", "preserve") != "pose_only": accum = _consume(body, mixer, initial_scale, accum)
		var changed := false
		while cursor < events.size() and float(events[cursor].time) <= time + 0.00000001:
			var event: Dictionary = events[cursor]
			if event.action == "set": tree.set(event.path, _value(event.value))
			elif event.action == "start": tree.get(event.path).start(event.state, true)
			else: tree.get(event.path).travel(event.state, true)
			cursor += 1
			changed = true
		if time == 0 or changed: mixer.advance(0)
		if time == 0:
			for candidate in required:
				for child in candidate.get_children():
					if child is SpringBoneSimulator3D and child.active: child.reset()
		var count := witness.count
		for candidate in required:
			candidate.advance(time - previous)
			candidate.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		_check(witness.count == count + 1, row.id + " required native capture t=" + str(time))
		result.append({"time": time, "poses": witness.poses.duplicate(true), "body": _body(body)})
		previous = time
	scene.free()
	return result
func _play(row: Dictionary, state: String, reference: Array) -> void:
	var scene := _load(str(row.states[state]))
	if scene == null: return
	saved_states += 1
	var output := scene.get_node_or_null(row.output) as AnimationPlayer
	if state == "undo":
		if row.get("undo_existing", false):
			_check(output != null and output.has_animation(row.params.animation_name), row.id + " Undo restores overwritten clip")
			if output != null and output.has_animation(row.params.animation_name):
				var old := output.get_animation(row.params.animation_name)
				_check(is_equal_approx(old.length, 0.7) and old.get_track_count() == 1 and old.track_get_key_count(0) == 1 and (old.track_get_key_value(0, 0) as Quaternion).is_equal_approx(Quaternion(Vector3.UP, 0.9)), row.id + " native old clip restored")
		else: _check(output == null or not output.has_animation(row.params.animation_name), row.id + " Undo removes generated output")
		scene.free()
		return
	_check(output != null and output.has_animation(row.params.animation_name), row.id + " " + state + " output/clip present")
	if output == null or not output.has_animation(row.params.animation_name):
		scene.free()
		return
	_check(not output.active and not output.is_playing(), row.id + " output stored inactive")
	for modifier in scene.find_children("*", "SkeletonModifier3D", true, false): modifier.active = false
	var rig := scene.get_node(row.skeleton) as Skeleton3D
	var body := scene.get_node(row.movement_owner) as Node3D
	var clip := output.get_animation(row.params.animation_name)
	var origin := output.get_node(output.root_node)
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target := origin.get_node_or_null(NodePath(path.get_concatenated_names()))
		_check(target is Node3D, row.id + " track resolves " + str(path))
		if target is Skeleton3D: _check(path.get_subname_count() == 1 and target.find_bone(path.get_subname(0)) >= 0, row.id + " bone path " + str(path))
		_check(clip.track_get_key_count(track) == reference.size(), row.id + " all key samples track=" + str(track))
		for i in mini(clip.track_get_key_count(track), reference.size()): _check(absf(clip.track_get_key_time(track, i) - float(reference[i].time)) < 0.000001, row.id + " key time")
	output.active = true
	output.play(row.params.animation_name)
	var previous := 0.0
	var initial_scale := body.scale
	var accum := Vector3.ONE
	for sample in reference:
		output.advance(float(sample.time) - previous)
		if sample.time > 0 and not output.root_motion_track.is_empty(): accum = _consume(body, output, initial_scale, accum)
		var poses := _poses(rig)
		_check(poses.size() == sample.poses.size(), row.id + " bone count")
		for i in mini(poses.size(), sample.poses.size()): _difference(poses[i], sample.poses[i], row.id + " " + state + " bone=" + str(i) + " t=" + str(sample.time))
		_difference(_body(body), sample.body, row.id + " " + state + " body t=" + str(sample.time))
		key_samples += 1
		previous = sample.time
	# Engine interpolation against independently evaluated native key poses.
	for i in reference.size() - 1:
		var a: Dictionary = reference[i]
		var b: Dictionary = reference[i + 1]
		output.seek((float(a.time) + float(b.time)) * 0.5, true)
		var poses := _poses(rig)
		var weight := 0.0 if _event_bridge(row.params, a.time, b.time) else 0.5
		for bone in poses.size():
			var expected := {"p": (a.poses[bone].p as Vector3).lerp(b.poses[bone].p, weight), "q": (a.poses[bone].q as Quaternion).slerp(b.poses[bone].q, weight), "s": (a.poses[bone].s as Vector3).lerp(b.poses[bone].s, weight)}
			_difference(poses[bone], expected, row.id + " interpolated bone=" + str(bone))
		intermediate_samples += 1
	played_states += 1
	scene.free()
func _run() -> void:
	var path := "user://rig_bake_saved_matrix.json"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var rows: Array = manifest.get("cases", []) if manifest is Dictionary else []
	var required := {}
	for fps in [30, 60, 120]:
		for layout in ["locked", "editable", "missing_library", "local_library", "overwrite"]: required["storage_%s_%d" % [layout, fps]] = true
		for kind in ["two_bone", "ccdik", "fabrik", "spline", "look", "twist", "spring", "retarget", "ordered_look_spring", "ordered_spring_look"]:
			for weight in 3: required["modifier_%s_%d_%d" % [kind, weight, fps]] = true
		for kind in ["state", "blend1d", "blend2d", "additive", "oneshot", "state_nested", "state_grouped", "state_inactive"]: required["graph_%s_%d" % [kind, fps]] = true
		for mode in ["preserve", "pose_only", "apply"]:
			for graph in [false, true]:
				for local in [false, true]:
					for looping in [false, true]: required["root_%s_%s_%s_%s_%d" % [mode, graph, local, looping, fps]] = true
	var found := {}
	for row in rows:
		_check(required.has(row.id) and not found.has(row.id), "unexpected/duplicate case " + row.id)
		found[row.id] = true
		var reference := _native(row)
		_check(reference.size() == _times(row.params).size(), row.id + " native samples present")
		var native_intermediate := _native(row, true)
		_check(native_intermediate.size() == reference.size() * 2 - 1, row.id + " native intermediate samples present")
		for i in reference.size() - 1:
			if native_intermediate.size() <= i * 2 + 1: break
			# The infinitesimal bridge of an instantaneous source jump has no
			# continuously interpolated native equivalent; report normal motion.
			if _event_bridge(row.params, reference[i].time, reference[i + 1].time): continue
			for bone in reference[i].poses.size():
				var a: Dictionary = reference[i].poses[bone]
				var b: Dictionary = reference[i + 1].poses[bone]
				var actual: Dictionary = native_intermediate[i * 2 + 1].poses[bone]
				var q: Quaternion = (a.q as Quaternion).slerp(b.q, 0.5).inverse() * (actual.q as Quaternion)
				native_approximation.position = maxf(native_approximation.position, (a.p as Vector3).lerp(b.p, 0.5).distance_to(actual.p))
				var angle := 2 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))
				if angle > native_approximation.rotation:
					approximation_peak = {"case": row.id, "bone": bone, "from": reference[i].time, "to": reference[i + 1].time}
				native_approximation.rotation = maxf(native_approximation.rotation, angle)
				native_approximation.scale = maxf(native_approximation.scale, (a.s as Vector3).lerp(b.s, 0.5).distance_to(actual.s))
		for state in ["do", "undo", "redo"]:
			if not row.get("states", {}).has(state): failures.append(row.id + " missing state " + state)
			else: _play(row, state, reference)
	for id in required: _check(found.has(id), "missing required case " + id)
	_check(rows.size() == 201 and saved_states == 603 and played_states == 402, "complete 201-case / 603-state matrix")
	OS.remove_logger(logger)
	print("RIG_BAKE_RESTORATION_RUNTIME=" + JSON.stringify({"cases": rows.size(), "saved_states": saved_states, "played_states": played_states, "key_samples": key_samples, "intermediate_samples": intermediate_samples, "worst_error": worst, "native_motion_approximation": native_approximation, "approximation_peak": approximation_peak, "manifest_path": ProjectSettings.globalize_path(path), "failures": failures, "engine_errors": logger.values}))
	quit(0 if failures.is_empty() and logger.values.is_empty() else 1)
