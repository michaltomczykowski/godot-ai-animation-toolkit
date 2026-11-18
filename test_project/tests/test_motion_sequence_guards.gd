@tool
extends McpTestSuite

const Matrix := preload("res://tests/test_motion_sequence_history.gd")
const Sampler := preload("res://addons/godot_ai_animation/utils/secondary_clip_sampler.gd")
var helper := Matrix.new()
class ScriptedClip extends Animation:
	static var constructed := 0
	func _init() -> void: constructed += 1
class ScriptedPayload extends Resource:
	static var constructed := 0
	func _init() -> void: constructed += 1
func suite_name() -> String: return "motion_sequence_guards"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _history() -> UndoRedo:
	return helper._undo.get_history_undo_redo(helper._undo.get_object_history_id(EditorInterface.get_edited_scene_root()))
func _refusal(fixture: Node, family: String, params: Dictionary, code: String = "") -> void:
	var before := helper._snapshot(fixture)
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var state := helper._seed._playback._player_state(player)
	var ids := Node.get_orphan_node_ids()
	var version := _history().get_version()
	var errors := helper._logger.errors.size()
	for dry in [true, false]:
		var result := helper._call(family, params.merged({"dry_run": dry}, true))
		assert_has_key(result.get("error", {}), "code", "typed refusal " + str(result))
		if not code.is_empty(): assert_eq(result.get("error", {}).get("code"), code, "specific refusal")
		assert_true(helper._seed._pose._same(before, helper._snapshot(fixture)), "exact refused scene")
		assert_true(helper._seed._pose._same(state, helper._seed._playback._player_state(player)), "exact refused playback")
		assert_eq(_history().get_version(), version, "refused history")
		assert_eq(Node.get_orphan_node_ids(), ids, "refused exact orphans")
	assert_eq(helper._logger.errors.size(), errors, "refused without engine errors")
func test_active_tree_and_playing_guards() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "secondary", "single")
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var tree := AnimationTree.new()
	tree.name = "ActiveTree"
	f.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := AnimationNodeAnimation.new()
	clip.animation = "source/input"
	tree.tree_root = clip
	tree.active = true
	for group in ["motion", "secondary", "sequence"]:
		var variant := "walk_cycle" if group == "motion" else "single" if group == "secondary" else "partial"
		var family := "animation_sequence" if group == "sequence" else "animation_motion"
		var params := helper._case_params(f, group, variant, "local", 30)
		_refusal(f, family, params, "OPERATION_UNAVAILABLE")
		tree.active = false
		player.play("source/input")
		player.speed_scale = 0.0
		_refusal(f, family, params, "OPERATION_UNAVAILABLE")
		player.pause()
		tree.active = true
	f.free()
func test_incompatible_extraction_refusal() -> void:
	var f := helper._fixture()
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var clip := helper._seed_clip(".:position", Animation.TYPE_POSITION_3D, Vector3.ZERO, Vector3.FORWARD)
	player.get_animation_library("source").add_animation("travel", clip)
	_refusal(f, "animation_motion", helper._params(f, "walk_cycle").merged({"root_motion": true}, true), "OPERATION_UNAVAILABLE")
	f.free()
func test_malformed_numeric_inputs_are_atomic() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "secondary", "single")
	for group in ["motion", "secondary", "sequence"]:
		var variant := "walk_cycle" if group == "motion" else "single" if group == "secondary" else "partial"
		var family := "animation_sequence" if group == "sequence" else "animation_motion"
		var p := helper._case_params(f, group, variant, "local", 30)
		for field in (["samples", "stiffness", "damping"] if group == "secondary" else ["samples", "duration"]):
			_refusal(f, family, p.merged({field: []}, true), "INVALID_PARAMS")
			_refusal(f, family, p.merged({field: NAN}, true))
		if group == "motion":
			_refusal(f, family, p.merged({"overrides": {"stride": {}}}, true), "INVALID_PARAMS")
			_refusal(f, family, p.merged({"overrides": {"planted": "false"}}, true), "INVALID_PARAMS")
		elif group == "secondary":
			for bones in [42, ["hand_L", "hand_L"], [null], ["Missing"], ["hips"]]:
				_refusal(f, family, p.merged({"bones": bones}, true))
		else:
			for field in ["start", "duration", "fade_in", "source_start", "source_end"]:
				var malformed := p.duplicate(true)
				malformed.segments[1][field] = {}
				_refusal(f, family, malformed, "INVALID_PARAMS")
			var malformed := p.duplicate(true)
			malformed.segments[1].contacts = [{"name": "impact", "time": INF}]
			_refusal(f, family, malformed, "INVALID_PARAMS")
	f.free()
func test_sequence_boundaries_and_extraction_refusals() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "sequence", "partial")
	var p := helper._case_params(f, "sequence", "partial", "local", 30)
	p.segments.append({"start": 0.7, "duration": 0.6, "source_animation": "source/first", "fade_in": 0.1})
	_refusal(f, "animation_sequence", p, "OPERATION_UNAVAILABLE")
	p = helper._case_params(f, "sequence", "partial", "local", 30)
	p.segments[1].start = 0.60001
	_refusal(f, "animation_sequence", p, "OPERATION_UNAVAILABLE")
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	player.root_motion_track = "Skeleton:hips"
	_refusal(f, "animation_sequence", helper._case_params(f, "sequence", "partial", "local", 30), "OPERATION_UNAVAILABLE")
	f.free()
func test_secondary_events_and_short_endpoint_refusal() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "secondary", "single")
	var p := helper._case_params(f, "secondary", "single", "local", 30)
	var clip: Animation = f.get_node("Playback/AnimationPlayer").get_animation("unrelated")
	clip.length = 1.000001
	_refusal(f, "animation_motion", p, "OPERATION_UNAVAILABLE")
	clip.length = 1.0
	var event := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(event, ".")
	clip.track_insert_key(event, 0.5, {"method": "set_visible", "args": [false]})
	_refusal(f, "animation_motion", p, "OPERATION_UNAVAILABLE")
	f.free()
func test_late_secondary_failure_cleans_private_scene() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "secondary", "single")
	var before := helper._snapshot(f)
	var ids := Node.get_orphan_node_ids()
	var version := _history().get_version()
	var result := Sampler.capture(EditorInterface.get_edited_scene_root(), f.get_node("Character/Skeleton"), f.get_node("Playback/AnimationPlayer"), "unrelated", ["hand_L"], [0.0, 0.1, 0.205], 2)
	assert_eq(result.get("error", {}).get("code"), "OPERATION_UNAVAILABLE", "late failure typed")
	assert_true(result.get("error", {}).get("message", "").contains("sample 2"), "late failure identifies sample")
	assert_true(helper._seed._pose._same(before, helper._snapshot(f)), "late failure exact scene")
	assert_eq(_history().get_version(), version, "late failure history unchanged")
	assert_eq(Node.get_orphan_node_ids(), ids, "late failure frees all private nodes")
	f.free()
func test_secondary_rotation_frame_covariance() -> void:
	var fixtures: Array = []
	var clips: Array = []
	var frame := Quaternion(Vector3(0.3, 0.7, 0.2).normalized(), 1.1)
	for rotated in [false, true]:
		var f := helper._fixture()
		f.name = "CovarianceRotated" if rotated else "CovarianceOriginal"
		fixtures.append(f)
		helper._prepare_inputs(f, "secondary", "branches")
		var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
		var source := player.get_animation("unrelated")
		if rotated:
			var track := source.find_track("Skeleton:hips", Animation.TYPE_ROTATION_3D)
			for key in source.track_get_key_count(track): source.track_set_key_value(track, key, frame * source.track_get_key_value(track, key))
		var made := helper._call("animation_motion", helper._case_params(f, "secondary", "branches", "local", 60))
		assert_has_key(made, "data", "covariant source generated")
		clips.append(player.get_animation("unrelated"))
	var worst := 0.0
	for name in ["hand_L", "hand_R"]:
		var a: Animation = clips[0]
		var b: Animation = clips[1]
		var ai := a.find_track(NodePath("Skeleton:" + name), Animation.TYPE_ROTATION_3D)
		var bi := b.find_track(NodePath("Skeleton:" + name), Animation.TYPE_ROTATION_3D)
		for step in 61:
			var difference := a.rotation_track_interpolate(ai, float(step) / 60).inverse() * b.rotation_track_interpolate(bi, float(step) / 60)
			worst = maxf(worst, 2.0 * atan2(Vector3(difference.x, difference.y, difference.z).length(), absf(difference.w)))
	assert_true(worst < 0.001, "spring dynamics use one frame; local rotations invariant under common parent rotation " + str(worst))
	for f in fixtures: f.free()
func test_sequence_abrupt_boundaries_use_native_holds() -> void:
	for at in [0.07, 10.07]:
		var f := helper._fixture()
		helper._prepare_inputs(f, "sequence", "partial")
		var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
		for name in ["first", "second"]:
			var clip := player.get_animation("source/" + name)
			for track in range(clip.get_track_count() - 1, 0, -1): clip.remove_track(track)
			clip.track_set_path(0, "Skeleton:arm_L")
			for key in clip.track_get_key_count(0): clip.track_set_key_value(0, key, Quaternion.IDENTITY if name == "first" else Quaternion(Vector3.RIGHT, 0.8))
		var p := helper._params(f, "compose")
		p.samples = 4
		p.duration = at + 0.2
		p.segments = [{"start": 0.0, "duration": at, "source_animation": "source/first"}, {"start": at, "duration": 0.2, "source_animation": "source/second"}]
		var result := helper._call("animation_sequence", p)
		assert_has_key(result, "data", "abrupt sequence succeeds " + str(result))
		if result.has("data"):
			var output := player.get_animation("generated")
			assert_true(output.rotation_track_interpolate(0, at - 0.001).angle_to(Quaternion.IDENTITY) < 0.001, "no early whole-frame blend")
			assert_true(output.rotation_track_interpolate(0, at).angle_to(Quaternion(Vector3.RIGHT, 0.8)) < 0.001, "impact on requested boundary")
			assert_eq(result.data.duration, output.length, "reported duration matches output")
		f.free()
func test_native_nearest_and_easing_sources() -> void:
	for interpolation in [Animation.INTERPOLATION_NEAREST, Animation.INTERPOLATION_CUBIC]:
		var f := helper._fixture()
		var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
		var clip := helper._seed_clip("Skeleton:arm_L", Animation.TYPE_ROTATION_3D, Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, 0.8), true)
		clip.track_set_interpolation_type(0, interpolation)
		player.get_animation_library("source").add_animation("curve", clip)
		var p := helper._params(f, "compose")
		p.segments = [{"start": 0.0, "duration": 1.0, "source_animation": "source/curve"}]
		var result := helper._call("animation_sequence", p)
		assert_has_key(result, "data", "native source accepted " + str(result))
		if result.has("data"):
			var output := player.get_animation("generated")
			for time in ([0.0, 0.399, 0.4, 0.7, 0.999, 1.0] if interpolation == Animation.INTERPOLATION_NEAREST else [0.0, 0.1, 0.4, 0.7, 1.0]):
				var q := output.rotation_track_interpolate(0, time).inverse() * clip.rotation_track_interpolate(0, time)
				assert_true(2 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w)) < 0.001, "source engine interpolation/easing retained " + str(time))
		f.free()
func test_rooted_sequence_delivers_last_native_delta() -> void:
	for fps in [30, 60, 120]:
		var f := helper._fixture()
		helper._prepare_inputs(f, "sequence", "rooted")
		var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
		var p := helper._case_params(f, "sequence", "rooted", "local", fps)
		p.duration = 1.405
		p.segments[1].duration = 0.805
		var result := helper._call("animation_sequence", p)
		assert_has_key(result, "data", "rooted sequence generated")
		if result.has("data"):
			var clip := player.get_animation("generated")
			var index := clip.find_track(".:position", Animation.TYPE_POSITION_3D)
			var expected := clip.position_track_interpolate(index, clip.length) - clip.position_track_interpolate(index, 0.0)
			player.speed_scale = 1.0
			player.playback_auto_capture = false
			player.play("generated", 0.0, 1.0)
			player.advance(0)
			var travel := Vector3.ZERO
			var ticks := 0
			while player.is_playing() and ticks < 300:
				player.advance(1.0 / fps)
				travel += player.get_root_motion_position()
				ticks += 1
			assert_true(travel.distance_to(expected) < 0.0001, "single owner receives complete trajectory at native FPS " + str(fps) + " error=" + str(travel.distance_to(expected)))
		f.free()
func test_scripted_sources_refused_before_construction() -> void:
	var f := helper._fixture()
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var clip := ScriptedClip.new()
	clip.length = 1.0
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, "Skeleton:hips")
	clip.track_insert_key(track, 0, Quaternion.IDENTITY)
	clip.track_insert_key(track, 1, Quaternion(Vector3.RIGHT, 0.2))
	player.get_animation_library("").remove_animation("unrelated")
	player.get_animation_library("").add_animation("unrelated", clip)
	var count := ScriptedClip.constructed
	_refusal(f, "animation_motion", helper._params(f, "secondary_motion").merged({"animation_name": "unrelated", "bones": ["hand_L"]}, true), "OPERATION_UNAVAILABLE")
	_refusal(f, "animation_sequence", helper._params(f, "compose").merged({"segments": [{"start": 0, "duration": 1, "source_animation": "unrelated"}]}, true), "OPERATION_UNAVAILABLE")
	assert_eq(ScriptedClip.constructed, count, "source constructor never duplicated")
	f.free()
func test_source_payload_refused_before_duplication() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "sequence", "partial")
	var player := f.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var clip := player.get_animation("source/first")
	var track := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(track, ".")
	var payload := ScriptedPayload.new()
	clip.track_insert_key(track, 0.0, {"method": "set_meta", "args": ["payload", payload]})
	var count := ScriptedPayload.constructed
	for enabled in [false, true]:
		clip.track_set_enabled(track, enabled)
		_refusal(f, "animation_sequence", helper._case_params(f, "sequence", "partial", "local", 30), "WRONG_TYPE")
	assert_eq(ScriptedPayload.constructed, count, "key resource constructor never duplicated")
	f.free()
func test_secondary_extreme_and_degenerate_sources() -> void:
	var f := helper._fixture()
	helper._prepare_inputs(f, "secondary", "single")
	var p := helper._case_params(f, "secondary", "single", "local", 30)
	_refusal(f, "animation_motion", p.merged({"stiffness": 1.0e308}, true), "OPERATION_UNAVAILABLE")
	var clip: Animation = f.get_node("Playback/AnimationPlayer").get_animation("unrelated")
	var index := clip.find_track("Skeleton:hips", Animation.TYPE_SCALE_3D)
	clip.track_set_key_value(index, 1, Vector3.ZERO)
	_refusal(f, "animation_motion", p, "OPERATION_UNAVAILABLE")
	f.free()
