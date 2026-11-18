@tool
extends McpTestSuite

const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Helpers := preload("res://tests/test_rig_bake_restoration.gd")
const Saved := preload("res://tests/bake_saved_matrix.gd")
var helper := Helpers.new()
var dispatcher
var undo: EditorUndoRedoManager
func suite_name() -> String: return "rig_bake_graph"
func suite_setup(ctx: Dictionary) -> void:
	helper.suite_setup(ctx)
	undo = ctx.undo_redo
	Context.undo_redo = undo
	dispatcher = Registry.get_instance().get("_dispatcher")
func suite_teardown() -> void: helper.suite_teardown()
func _call(params: Dictionary) -> Dictionary:
	return dispatcher.call("_dispatch", {"request_id": "bake-graph", "command": "custom_tool:animation_rig", "params": params})
func _leaf(name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node
func _fixture(label: String, kind: String) -> Dictionary:
	var f := helper._fixture(label)
	var library: AnimationLibrary = f.player.get_animation_library("")
	for pair in [["input", 0.0, 0.4], ["other", 0.8, -0.2]]:
		var clip := Animation.new()
		clip.length = 1
		clip.loop_mode = Animation.LOOP_LINEAR
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, "Skeleton:arm")
		clip.track_insert_key(track, 0, Quaternion(Vector3.UP, pair[1]))
		clip.track_insert_key(track, 1, Quaternion(Vector3.UP, pair[2]))
		library.add_animation(pair[0], clip)
	var tree := AnimationTree.new()
	tree.name = "Tree"
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.root.add_child(tree)
	tree.anim_player = tree.get_path_to(f.player)
	if kind.begins_with("state"):
		var machine := AnimationNodeStateMachine.new()
		machine.add_node("Idle", _leaf("input"))
		machine.add_node("Action", _leaf("other"))
		for pair in [["Idle", "Action"], ["Action", "Idle"]]:
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.12
			machine.add_transition(pair[0], pair[1], transition)
		if kind in ["state_nested", "state_grouped"]:
			machine.state_machine_type = AnimationNodeStateMachine.STATE_MACHINE_TYPE_GROUPED if kind == "state_grouped" else AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED
			var parent := AnimationNodeStateMachine.new()
			parent.add_node("Group", machine)
			var entry := AnimationNodeStateMachineTransition.new()
			entry.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED if kind == "state_grouped" else AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			machine.add_transition("Start", "Idle", entry)
			parent.add_transition("Start", "Group", entry.duplicate())
			tree.tree_root = parent
		else: tree.tree_root = machine
	elif kind == "blend1d":
		var blend := AnimationNodeBlendSpace1D.new()
		blend.add_blend_point(_leaf("input"), 0, -1, "Low")
		blend.add_blend_point(_leaf("other"), 1, -1, "High")
		tree.tree_root = blend
	elif kind == "blend2d":
		var blend := AnimationNodeBlendSpace2D.new()
		blend.add_blend_point(_leaf("input"), Vector2.ZERO, -1, "Origin")
		blend.add_blend_point(_leaf("other"), Vector2.RIGHT, -1, "Right")
		blend.add_blend_point(_leaf("other"), Vector2.DOWN, -1, "Down")
		tree.tree_root = blend
	else:
		var blend := AnimationNodeBlendTree.new()
		blend.add_node("Base", _leaf("input"))
		blend.add_node("Layer", _leaf("other"))
		if kind == "oneshot":
			var layer := AnimationNodeOneShot.new()
			layer.fadein_time = 0.05
			layer.fadeout_time = 0.05
			blend.add_node("Mix", layer)
		else:
			var layer := AnimationNodeAdd2.new()
			layer.filter_enabled = true
			layer.set_filter_path("Skeleton:arm", true)
			blend.add_node("Mix", layer)
		blend.add_node("Speed", AnimationNodeTimeScale.new())
		blend.connect_node("Mix", 0, "Base")
		blend.connect_node("Mix", 1, "Layer")
		blend.connect_node("Speed", 0, "Mix")
		blend.connect_node("output", 0, "Speed")
		tree.tree_root = blend
	var initial := {}
	var starts: Array = []
	var events: Array = []
	if kind.begins_with("state"):
		starts = [{"playback_path": "parameters/playback", "state": "Idle"}]
		events = [{"time": 0.07, "action": "travel", "path": "parameters/playback", "state": "Action"}]
		if kind in ["state_nested", "state_grouped"]:
			starts = [{"playback_path": "parameters/playback", "state": "Group"}]
			if kind == "state_nested":
				starts.append({"playback_path": "parameters/Group/playback", "state": "Idle"})
				events = [{"time": 0.07, "action": "travel", "path": "parameters/Group/playback", "state": "Action"}]
			else:
				events = [{"time": 0.0, "action": "travel", "path": "parameters/playback", "state": "Group/Idle"},
					{"time": 0.07, "action": "travel", "path": "parameters/playback", "state": "Group/Action"}]
	elif kind == "blend1d":
		initial = {"parameters/blend_position": 0.25}
		events = [{"time": 0.07, "action": "set", "path": "parameters/blend_position", "value": 0.75}]
	elif kind == "blend2d":
		initial = {"parameters/blend_position": {"kind": "vector2", "x": 0.2, "y": 0.2}}
		events = [{"time": 0.07, "action": "set", "path": "parameters/blend_position", "value": {"kind": "vector2", "x": 0.4, "y": 0.4}}]
	else:
		initial = {"parameters/Speed/scale": 0.8}
		if kind == "additive": initial["parameters/Mix/add_amount"] = 0.3
		events = [{"time": 0.07, "action": "set", "path": "parameters/Speed/scale", "value": 1.3}]
		if kind == "oneshot": events.append({"time": 0.07, "action": "set", "path": "parameters/Mix/request", "value": 1})
	f.tree = tree
	f.initial = initial
	f.starts = starts
	f.events = events
	helper._own(f.root, EditorInterface.get_edited_scene_root())
	return f
func _decode(raw: Variant) -> Variant:
	if raw is Dictionary: return Vector2(raw.x, raw.y)
	return raw
func _begin(f: Dictionary) -> void:
	f.tree.active = true
	for path in f.initial: f.tree.set(path, _decode(f.initial[path]))
	for entry in f.starts: f.tree.get(entry.playback_path).start(entry.state, true)
	f.cursor = 0
	while f.cursor < f.events.size() and f.events[f.cursor].time == 0:
		var event: Dictionary = f.events[f.cursor]
		if event.action == "set": f.tree.set(event.path, _decode(event.value))
		else: f.tree.get(event.path).travel(event.state, true)
		f.cursor += 1
	f.tree.advance(0)
func _public(tree: AnimationTree) -> Dictionary:
	var result := {"active": tree.active, "root": tree.tree_root, "player": tree.anim_player}
	for entry in tree.get_property_list():
		var path := str(entry.name)
		if not path.begins_with("parameters/"): continue
		var value: Variant = tree.get(path)
		if value is AnimationNodeStateMachinePlayback:
			result[path] = [value, value.is_playing(), value.get_current_node(), value.get_current_play_position(), value.get_fading_from_node(), value.get_fading_from_play_position(), value.get_travel_path()]
		else: result[path] = value
	return result
func _case(kind: String, fps: int) -> void:
	var subject := _fixture("BakeGraphSubject", kind)
	var reference := _fixture("BakeGraphReference", kind)
	_begin(subject)
	subject.tree.advance(0.04)
	if kind == "state":
		subject.tree.get("parameters/playback").travel("Action")
		subject.tree.advance(0.02)
		# Keep a queued return while Action is fading in.
		subject.tree.get("parameters/playback").travel("Idle")
	if kind == "state_inactive": subject.tree.active = false
	var state := _public(subject.tree)
	var errors := helper._logger.errors.size()
	var library: AnimationLibrary = subject.player.get_animation_library("")
	var version := helper._history().get_version()
	var params := helper._params(subject)
	params.erase("source_animation")
	params.merge({"source_tree_path": str(subject.tree.get_path()), "duration": 0.205, "fps": fps,
		"tree_parameters": subject.initial, "tree_starts": subject.starts, "tree_events": subject.events}, true)
	var saved := Saved.begin(subject, params, "graph_%s_%d" % [kind, fps])
	var dry := _call(params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", kind + " dry graph bake " + str(dry.get("error", {})))
	assert_eq(helper._history().get_version(), version, "dry history unchanged")
	assert_eq(_public(subject.tree), state, "dry graph state exact")
	var result := _call(params)
	assert_has_key(result, "data", kind + " graph bake " + str(result.get("error", {})))
	if not result.has("data"):
		subject.root.free()
		reference.root.free()
		return
	assert_eq(result.data.player_path, dry.data.player_path, "dry predicts output path")
	assert_eq(_public(subject.tree), state, "written graph state exact")
	assert_eq(subject.player.get_animation_library(""), library, "source library identity")
	var output: AnimationPlayer = EditorInterface.get_edited_scene_root().get_node(NodePath(str(result.data.player_path).trim_prefix("/Main/")))
	assert_false(output.active, "output inactive")
	var baked: Animation = output.get_animation("baked")
	var track := baked.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
	_begin(reference)
	var previous := 0.0
	var cursor: int = reference.cursor
	for sample in baked.track_get_key_count(track):
		var time := baked.track_get_key_time(track, sample)
		if time > previous: reference.tree.advance(time - previous)
		var changed := false
		while cursor < reference.events.size() and reference.events[cursor].time <= time + 0.00000001:
			var event: Dictionary = reference.events[cursor]
			if event.action == "set": reference.tree.set(event.path, _decode(event.value))
			else: reference.tree.get(event.path).travel(event.state, true)
			cursor += 1
			changed = true
		if changed or time == 0: reference.tree.advance(0)
		var actual: Quaternion = baked.track_get_key_value(track, sample)
		assert_true(actual.angle_to(reference.skeleton.get_bone_pose_rotation(0)) < 0.001, "native graph key kind=%s fps=%d t=%.6f" % [kind, fps, time])
		previous = time
	assert_eq(helper._history().get_version(), version + 1, "one output action")
	Saved.state(saved, output, "do")
	assert_true(helper._history().undo(), "output undo")
	Saved.state(saved, output, "undo")
	assert_false(output.is_inside_tree(), "undo removes output")
	assert_eq(_public(subject.tree), state, "undo graph state exact")
	assert_true(helper._history().redo(), "output redo")
	Saved.state(saved, output, "redo")
	Saved.finish(saved)
	assert_true(output.is_inside_tree(), "redo restores output")
	assert_eq(_public(subject.tree), state, "redo graph state exact")
	assert_true(helper._history().undo(), "final output undo")
	assert_eq(helper._logger.errors.size(), errors, "zero graph bake engine errors")
	subject.root.free()
	reference.root.free()
func test_state_machine() -> void:
	for fps in [30, 60, 120]: _case("state", fps)
func test_blend_space_1d() -> void:
	for fps in [30, 60, 120]: _case("blend1d", fps)
func test_blend_space_2d() -> void:
	for fps in [30, 60, 120]: _case("blend2d", fps)
func test_filtered_additive_timescale() -> void:
	for fps in [30, 60, 120]: _case("additive", fps)
func test_one_shot_timescale() -> void:
	for fps in [30, 60, 120]: _case("oneshot", fps)
func test_nested_state_machine() -> void:
	for fps in [30, 60, 120]: _case("state_nested", fps)
func test_grouped_state_machine() -> void:
	for fps in [30, 60, 120]: _case("state_grouped", fps)
func test_inactive_tree() -> void:
	for fps in [30, 60, 120]: _case("state_inactive", fps)

func test_graph_preflight_is_atomic() -> void:
	var f := _fixture("BakeGraphRefusals", "state")
	_begin(f)
	var params := helper._params(f)
	params.erase("source_animation")
	params.source_tree_path = str(f.tree.get_path())
	var state := _public(f.tree)
	var version := helper._history().get_version()
	var orphans := Node.get_orphan_node_ids()
	var errors := helper._logger.errors.size()
	for invalid in [
		{"source_animation": "input"}, {"tree_parameters": []},
		{"tree_parameters": {"parameters/missing": 1}},
		{"tree_starts": [{"playback_path": "parameters/playback", "state": "Missing"}]},
		{"tree_events": [{"time": -1, "action": "set", "path": "parameters/missing", "value": 1}]},
		{"tree_events": [{"time": 0.1, "action": "travel", "path": "parameters/playback", "state": "Action"}, {"time": 0.05, "action": "travel", "path": "parameters/playback", "state": "Idle"}]},
		{"output_player_path": str(f.player.get_path())}, {"fps": 1e100},
		{"duration": 0}, {"duration": "bad"}, {"source_tree_path": false},
		{"tree_events": [{"time": 0.100001, "action": "travel", "path": "parameters/playback", "state": "Action"}]},
	]:
		var result := _call(params.merged(invalid, true))
		assert_has_key(result.get("error", {}), "code", "typed refusal " + str(invalid))
		assert_eq(_public(f.tree), state, "refused graph exact")
		assert_eq(helper._history().get_version(), version, "refused history exact")
		assert_eq(Node.get_orphan_node_ids(), orphans, "refused no orphan nodes")
	assert_eq(helper._logger.errors.size(), errors, "zero preflight engine errors")
	f.root.free()

func test_event_does_not_preblend() -> void:
	for event_time in [0.07, 10.07]: _event_boundary(event_time)
func _event_boundary(event_time: float) -> void:
	var f := _fixture("BakeEventBoundary", "blend1d")
	f.events[0].time = event_time
	var params := helper._params(f)
	params.erase("source_animation")
	params.merge({"source_tree_path": str(f.tree.get_path()), "tree_parameters": f.initial, "tree_events": f.events, "duration": event_time + 0.135}, true)
	var result := _call(params)
	assert_has_key(result, "data", "event boundary bake")
	if result.has("data"):
		var output: AnimationPlayer = f.root.get_node("AnimationBakeOutput")
		var clip := output.get_animation("baked")
		var track := clip.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
		var before_key := -1
		var before := event_time - 0.00004 * maxf(1.0, event_time)
		var observed := before - 0.00001
		for i in clip.track_get_key_count(track):
			if absf(clip.track_get_key_time(track, i) - before) < 0.00000001: before_key = i
		assert_true(before_key >= 0, "pre-event sample present")
		assert_eq(clip.track_get_key_transition(track, before_key), 0.0, "event bridge holds pose")
		_begin(f)
		f.tree.advance(observed)
		var native: Quaternion = f.skeleton.get_bone_pose_rotation(0)
		f.tree.active = false
		f.player.active = false
		output.active = true
		output.play("baked")
		output.advance(0)
		output.advance(observed)
		assert_true(f.skeleton.get_bone_pose_rotation(0).angle_to(native) < 0.001, "no early parameter blend")
		output.seek((before + event_time) * 0.5, true)
		assert_true(f.skeleton.get_bone_pose_rotation(0).angle_to(clip.track_get_key_value(track, before_key)) < 0.001, "played bridge holds preceding pose")
		output.stop()
		assert_true(helper._history().undo(), "boundary bake Undo")
	f.root.free()
