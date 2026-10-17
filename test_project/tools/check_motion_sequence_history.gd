extends SceneTree
const Reference := preload("res://tools/motion_sequence_native_reference.gd")

## Fresh engine playback; no production addon or test scripts are imported.
const MOTIONS := ["walk_cycle", "run_cycle", "idle_cycle", "jump", "turn_cycle", "strafe_cycle", "walk_start", "walk_stop", "cycle_walk", "cycle_run", "cycle_idle"]
const SEQUENCES := ["gap", "partial", "saved_pose", "inline_pose", "rooted", "self_overwrite"]
var failures: Array = []
var cases := 0
var saved_states := 0
var playback_runs := 0
var key_samples := 0
var intermediate_samples := 0
var worst := {"position": 0.0, "rotation": 0.0, "scale": 0.0, "root_delta": 0.0}
var approximation := {"position": 0.0, "rotation": 0.0, "scale": 0.0}
var approximation_samples := 0
var travel_runs := 0
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String) -> void:
	if not ok and failures.size() < 150: failures.append(label)
func _load(path: String) -> Node:
	if not ResourceLoader.exists(path):
		_check(false, "missing scene " + path)
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return null
	var scene := packed.instantiate()
	for node in scene.find_children("*", "AnimationMixer", true, false):
		node.active = false
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for node in scene.find_children("*", "SkeletonModifier3D", true, false): node.active = false
	root.add_child(scene)
	return scene
func _player(scene: Node) -> AnimationPlayer: return scene.get_node("MotionSequenceHistory/Playback/AnimationPlayer")
func _pose(target: Node, path: NodePath, type: int) -> Variant:
	if target is Skeleton3D:
		var i: int = target.find_bone(str(path.get_subname(0)))
		return target.get_bone_pose_position(i) if type == Animation.TYPE_POSITION_3D else target.get_bone_pose_rotation(i) if type == Animation.TYPE_ROTATION_3D else target.get_bone_pose_scale(i)
	return target.position if type == Animation.TYPE_POSITION_3D else target.quaternion if type == Animation.TYPE_ROTATION_3D else target.scale
func _track_targets(player: AnimationPlayer, animation: Animation, label: String) -> Array:
	var targets: Array = []
	var base := player.get_node(player.root_node)
	for i in animation.get_track_count():
		var path := animation.track_get_path(i)
		var target := base.get_node_or_null(NodePath(path.get_concatenated_names()))
		var kind := animation.track_get_type(i)
		_check(target is Node3D and kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D], label + " valid native track " + str(path))
		if target is Skeleton3D: _check(path.get_subname_count() == 1 and target.find_bone(str(path.get_subname(0))) >= 0, label + " valid bone " + str(path))
		_check(animation.track_get_key_count(i) >= 2, label + " nonempty track")
		var previous := -1.0
		for key in animation.track_get_key_count(i):
			var at := animation.track_get_key_time(i, key)
			var value: Variant = animation.track_get_key_value(i, key)
			_check(is_finite(at) and at > previous and at >= 0 and at <= animation.length + 0.000001, label + " finite ordered time")
			_check(value.is_finite() and (not value is Quaternion or value.is_normalized()), label + " finite normalized value")
			previous = at
		targets.append(target)
	return targets
func _start(player: AnimationPlayer, clip_name: String) -> void:
	player.stop()
	player.speed_scale = 1.0
	player.active = true
	player.playback_auto_capture = false
	player.play(clip_name, 0.0, 1.0)
	player.advance(0.0)
func _angle(a: Quaternion, b: Quaternion) -> float:
	var q := a.inverse() * b
	return 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))
func _contract(row: Dictionary, source: Node, output: Animation) -> void:
	var label := str(row.id)
	var reported: Dictionary = row.get("reported", {})
	_check(not reported.is_empty(), label + " required reported output")
	var keys := 0
	for track in output.get_track_count(): keys += output.track_get_key_count(track)
	_check(reported.get("track_count", -1) == output.get_track_count() and reported.get("key_count", -1) == keys, label + " reported counts")
	if row.group == "motion": _check(absf(float(reported.get("length", -1)) - output.length) < 0.000001, label + " reported duration")
	if row.group != "sequence": return
	_check(absf(float(reported.get("duration", -1)) - output.length) < 0.000001, label + " reported duration")
	var fixture := source.get_node("MotionSequenceHistory")
	var segments := Reference.prepared_sequence(fixture, row.params, row.pose_json)
	var channels := {}
	var annotations: Array = []
	var boundaries: Array = [0.0, float(row.params.duration)]
	for segment in segments:
		boundaries.append_array([segment.start, segment.start + segment.span, segment.start + segment.fade])
		var clip: Animation = segment.clip
		for track in clip.get_track_count():
			if clip.track_is_enabled(track): channels["%d|%s" % [clip.track_get_type(track), clip.track_get_path(track)]] = true
		for marker in clip.get_marker_names():
			var at := clip.get_marker_time(marker)
			if at >= segment.from and at <= segment.to:
				annotations.append({"name": str(marker), "time": segment.start + segment.span * (at - segment.from) / (segment.to - segment.from), "color": clip.get_marker_color(marker)})
	var raw_segments: Array = row.params.segments.duplicate(true)
	raw_segments.sort_custom(func(a, b): return a.start < b.start)
	# Production preserves source/contact insertion order within each segment.
	annotations.clear()
	for index in segments.size():
		var segment: Dictionary = segments[index]
		for marker in segment.clip.get_marker_names():
			var at: float = segment.clip.get_marker_time(marker)
			if at >= segment.from and at <= segment.to: annotations.append({"name": str(marker), "time": segment.start + segment.span * (at - segment.from) / (segment.to - segment.from), "color": segment.clip.get_marker_color(marker)})
		for contact in raw_segments[index].get("contacts", []): annotations.append({"name": "contact_" + str(contact.name), "time": segment.start + float(contact.time), "color": Color(0.2, 0.9, 0.3)})
	_check(channels.size() == output.get_track_count(), label + " independently required channel count")
	for track in output.get_track_count():
		var key := "%d|%s" % [output.track_get_type(track), output.track_get_path(track)]
		_check(channels.has(key), label + " required channel " + key)
		channels.erase(key)
		for boundary in boundaries:
			var found := false
			for i in output.track_get_key_count(track):
				if absf(output.track_get_key_time(track, i) - float(boundary)) < 0.000001: found = true
			_check(found, label + " required boundary " + str(boundary))
	_check(channels.is_empty(), label + " no missing source channel")
	_check(reported.get("sample_count", -1) == output.track_get_key_count(0), label + " reported samples")
	_check(reported.get("contact_markers", -1) == annotations.size() and output.get_marker_names().size() == annotations.size(), label + " markers complete")
	var used := {}
	for annotation in annotations:
		var suffix := 0
		var name: String = annotation.name
		while used.has(name):
			suffix += 1
			name = str(annotation.name) + "_" + str(suffix)
		used[name] = true
		_check(output.has_marker(name), label + " required marker " + name)
		if output.has_marker(name):
			_check(absf(output.get_marker_time(name) - annotation.time) < 0.000001 and output.get_marker_color(name).is_equal_approx(annotation.color), label + " marker time/color " + name)
func _approximate(row: Dictionary, source: Node, output: Animation) -> void:
	if row.group == "motion": return # Existing native motion/contact gates remain required.
	var fixture := source.get_node("MotionSequenceHistory")
	var segments := Reference.prepared_sequence(fixture, row.params, row.pose_json) if row.group == "sequence" else []
	var times: Array = []
	var track := 0 if row.group == "sequence" else output.find_track(NodePath("Skeleton:" + str(row.params.bones[0])), Animation.TYPE_ROTATION_3D)
	for key in output.track_get_key_count(track):
		var at := output.track_get_key_time(track, key)
		if key > 0:
			var earlier := output.track_get_key_time(track, key - 1)
			if at - earlier > 0.001: times.append((at + earlier) * 0.5)
		times.append(at)
	var dense: Animation = Reference._secondary(fixture, row.params, output, times) if row.group == "secondary" else null
	for i in output.get_track_count():
		if row.group == "secondary" and not str(output.track_get_path(i).get_subname(0)) in row.params.bones: continue
		for key in range(1, output.track_get_key_count(i)):
			var a := output.track_get_key_time(i, key - 1)
			var b := output.track_get_key_time(i, key)
			if b - a <= 0.001 or a >= float(row.params.get("duration", output.length)): continue
			var at := (a + b) * 0.5
			var path := output.track_get_path(i)
			var kind := output.track_get_type(i)
			var wanted: Variant = Reference._timeline(segments, path, kind, at, Reference._baseline(fixture, path, kind)) if row.group == "sequence" else Reference._value(dense, dense.find_track(path, kind), at)
			var actual: Variant = Reference._value(output, i, at)
			var error: float = _angle(actual, wanted) if kind == Animation.TYPE_ROTATION_3D else actual.distance_to(wanted)
			var field := "rotation" if kind == Animation.TYPE_ROTATION_3D else "position" if kind == Animation.TYPE_POSITION_3D else "scale"
			approximation[field] = maxf(approximation[field], error)
			approximation_samples += 1
func _travel(row: Dictionary, scene: Node, state: String, fps: int) -> void:
	var player := _player(scene)
	var name: String = row.params.animation_name
	var clip := player.get_animation(name)
	var index := clip.find_track(player.root_motion_track, Animation.TYPE_POSITION_3D)
	if clip.loop_mode != Animation.LOOP_NONE or index < 0 or player.root_motion_track.is_empty(): return
	var origin := player.get_node(player.root_node) as Node3D
	var position := origin.position
	var expected := clip.position_track_interpolate(index, clip.length) - clip.position_track_interpolate(index, 0.0)
	_start(player, name)
	var travel := Vector3.ZERO
	for tick in ceili(clip.length * fps) + 2:
		if not player.is_playing(): break
		player.advance(1.0 / fps)
		travel += player.get_root_motion_position()
		_check(origin.position.is_equal_approx(position), str(row.id) + state + " extraction has one owner")
	_check(travel.distance_to(expected) <= 0.0001, str(row.id) + state + " complete native travel at " + str(fps))
	travel_runs += 1
func _play(row: Dictionary, state: String, fps: int, reference: Animation) -> void:
	var label := str(row.id) + ":" + state + ":play" + str(fps)
	var actual_scene := _load(row.states[state])
	var expected_scene := _load(row.source)
	if actual_scene == null or expected_scene == null:
		if actual_scene != null: actual_scene.free()
		if expected_scene != null: expected_scene.free()
		return
	playback_runs += 1
	var actual := _player(actual_scene)
	var expected := _player(expected_scene)
	var name: String = row.params.animation_name
	if state == "undo":
		var source := _player(expected_scene)
		_check(actual.has_animation(name) == source.has_animation(name), label + " undo clip presence")
		_check(actual.root_motion_track == source.root_motion_track and actual.root_motion_local == source.root_motion_local, label + " original extraction")
		name = name if source.has_animation(name) else "source/input"
		var clip: Animation = source.get_animation(name)
		_check(actual.get_animation(name).length == clip.length, label + " original length")
		_check(actual.get_animation(name).get_track_count() == clip.get_track_count(), label + " original track count")
	else:
		_check(actual.has_animation(name), label + " generated clip saved")
		if not actual.has_animation(name):
			actual_scene.free()
			expected_scene.free()
			return
		if not expected.has_animation_library(""): expected.add_animation_library("", AnimationLibrary.new())
		var library := expected.get_animation_library("")
		if library.has_animation(name): library.remove_animation(name)
		library.add_animation(name, reference.duplicate(true))
		expected.root_motion_track = actual.root_motion_track
		expected.root_motion_local = actual.root_motion_local
	var animation := actual.get_animation(name)
	var oracle := expected.get_animation(name)
	_check(animation.get_track_count() == oracle.get_track_count(), label + " complete reference tracks")
	var actual_targets := _track_targets(actual, animation, label)
	var expected_targets := _track_targets(expected, oracle, label + ":reference")
	var times: Array = [0.0, animation.length]
	var key_marks: Array = []
	for step in range(1, ceili(animation.length * fps)): times.append(float(step) / fps)
	for i in animation.get_track_count():
		var marks := {}
		for key in animation.track_get_key_count(i):
			var at := animation.track_get_key_time(i, key)
			marks[roundi(at * 100000000.0)] = true
			if not times.has(at): times.append(at)
			if key > 0:
				var midpoint := (at + animation.track_get_key_time(i, key - 1)) * 0.5
				if not times.has(midpoint): times.append(midpoint)
		key_marks.append(marks)
	times.sort()
	_start(actual, name)
	_start(expected, name)
	var previous := 0.0
	for time in times:
		if time > 0.0:
			actual.advance(time - previous)
			expected.advance(time - previous)
		previous = time
		var delta_error := actual.get_root_motion_position().distance_to(expected.get_root_motion_position())
		worst.root_delta = maxf(worst.root_delta, delta_error)
		_check(delta_error <= 0.0001, label + " root delta " + str(time))
		for i in mini(actual_targets.size(), expected_targets.size()):
			var path := animation.track_get_path(i)
			var kind := animation.track_get_type(i)
			_check(path == oracle.track_get_path(i) and kind == oracle.track_get_type(i), label + " reference target/type")
			var a: Variant = _pose(actual_targets[i], path, kind)
			var b: Variant = _pose(expected_targets[i], path, kind)
			var difference: Quaternion = a.inverse() * b if kind == Animation.TYPE_ROTATION_3D else Quaternion.IDENTITY
			var error: float = 2.0 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w)) if kind == Animation.TYPE_ROTATION_3D else a.distance_to(b)
			var field := "position" if kind == Animation.TYPE_POSITION_3D else "rotation" if kind == Animation.TYPE_ROTATION_3D else "scale"
			worst[field] = maxf(worst[field], error)
			_check(error <= (0.001 if field == "rotation" else 0.0001), label + " played " + field + " " + str(time) + " error " + str(error))
			var at_key: bool = key_marks[i].has(roundi(time * 100000000.0))
			if at_key: key_samples += 1
			else: intermediate_samples += 1
	actual_scene.free()
	expected_scene.free()
func _run() -> void:
	var logger := Capture.new()
	OS.add_logger(logger)
	var required := {}
	for group in ["motion", "secondary", "sequence"]:
		var variants := MOTIONS if group == "motion" else SEQUENCES if group == "sequence" else ["single", "branches"]
		var layouts := ["local", "instanced", "editable"] if group == "secondary" else ["local", "instanced", "editable", "missing_library", "overwrite"]
		for variant in variants:
			for mode in layouts:
				for fps in [30, 60, 120]: required["%s_%s_%s_%d" % [group, variant, mode, fps]] = true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://motion_sequence_saved_matrix.json"))
	if not raw is Dictionary:
		_check(false, "required manifest missing")
	else:
		for row in raw.get("cases", []):
			_check(required.has(row.id), "unique required case " + str(row.id))
			required.erase(row.id)
			cases += 1
			var reference := ResourceLoader.load(row.reference, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
			_check(reference != null, "required reference " + str(row.id))
			if reference == null: continue
			var source := _load(row.source)
			var generated := _load(row.states.get("do", ""))
			if source != null and generated != null:
				var output := _player(generated).get_animation(str(row.params.animation_name))
				_contract(row, source, output)
				_approximate(row, source, output)
			if generated != null: generated.free()
			if source != null:
				source.free()
			for state in ["do", "undo", "redo"]:
				_check(row.states.has(state) and ResourceLoader.exists(row.states[state]), "required saved state " + str(row.id) + state)
				saved_states += 1
				for fps in [30, 60, 120]: _play(row, state, fps, reference)
				if state != "undo":
					for fps in [30, 60, 120]:
						var scene := _load(row.states[state])
						if scene != null:
							_travel(row, scene, state, fps)
							scene.free()
	_check(required.is_empty(), "missing required IDs " + str(required.keys()))
	_check(cases == 273 and saved_states == 819 and playback_runs == 2457, "complete required counts")
	OS.remove_logger(logger)
	_check(approximation_samples > 1000 and travel_runs >= 100, "required continuous and single-owner samples")
	print("MOTION_SEQUENCE_HISTORY_RUNTIME=" + JSON.stringify({"cases": cases, "saved_states": saved_states, "playback_runs": playback_runs, "travel_runs": travel_runs, "key_samples": key_samples, "intermediate_samples": intermediate_samples, "worst": worst, "continuous_approximation": approximation, "approximation_samples": approximation_samples, "manifest_path": ProjectSettings.globalize_path("user://motion_sequence_saved_matrix.json"), "failures": failures, "engine_errors": logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
