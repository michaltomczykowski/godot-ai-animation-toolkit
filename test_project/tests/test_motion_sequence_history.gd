@tool
extends McpTestSuite

## Public-tool regressions and the required saved history matrix.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Seed := preload("res://tests/test_rig_clip_history.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const Saved := preload("res://tests/motion_sequence_saved_matrix.gd")
const Reference := preload("res://tools/motion_sequence_native_reference.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const MotionHandler := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const MOTIONS := ["walk_cycle", "run_cycle", "idle_cycle", "jump", "turn_cycle", "strafe_cycle", "walk_start", "walk_stop", "cycle_walk", "cycle_run", "cycle_idle"]
const SEQUENCES := ["gap", "partial", "saved_pose", "inline_pose", "rooted", "self_overwrite"]
var _seed := Seed.new()
var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: Capture.ErrorCapture

func suite_name() -> String: return "motion_sequence_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
	Saved.reset()
	DirAccess.make_dir_recursive_absolute("res://animation_toolkit/poses")
func _pose_json() -> Dictionary:
	return {"rest_relative": true, "bones": {"arm_L": {"rotation": {"kind": "quaternion", "x": sin(0.3), "w": cos(0.3)}}}}
func _seed_clip(path: String, kind: int, a: Variant, b: Variant, curved: bool = false) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	var index := clip.add_track(kind)
	clip.track_set_path(index, NodePath(path))
	clip.track_insert_key(index, 0.0, a, 2.0 if curved else 1.0)
	clip.track_insert_key(index, 0.4, a.slerp(b, 0.4) if a is Quaternion else a.lerp(b, 0.4))
	clip.track_insert_key(index, 1.0, b)
	clip.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC if curved else Animation.INTERPOLATION_LINEAR)
	clip.add_marker(&"cue", 0.3)
	clip.set_marker_color(&"cue", Color(0.8, 0.3, 0.2))
	return clip
func _prepare_inputs(fixture: Node, group: String, variant: String) -> void:
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var lib := player.get_animation_library("source")
	lib.add_animation("first", _seed_clip("Skeleton:hips", Animation.TYPE_ROTATION_3D, Quaternion(Vector3.RIGHT, 0.1), Quaternion(Vector3.RIGHT, 0.7), true))
	lib.add_animation("second", _seed_clip("Skeleton:arm_L", Animation.TYPE_ROTATION_3D, Quaternion(Vector3.RIGHT, 0.6), Quaternion(Vector3.RIGHT, -0.4), true))
	var position := _seed_clip("Skeleton:hips", Animation.TYPE_POSITION_3D, Vector3(0, 1.1, 0), Vector3(0.04, 1.15, 0))
	var scale := _seed_clip("Skeleton:hips", Animation.TYPE_SCALE_3D, Vector3.ONE, Vector3(1.05, 0.95, 1.0))
	position.copy_track(0, lib.get_animation("first"))
	scale.copy_track(0, lib.get_animation("first"))
	if group == "secondary":
		var target := player.get_animation_library("")
		target.remove_animation("unrelated")
		target.add_animation("unrelated", lib.get_animation("first").duplicate(true))
		var skeleton := fixture.get_node("Character/Skeleton") as Skeleton3D
		for name in ["hand_L", "hand_R"]:
			var index := skeleton.find_bone(name)
			var rest := skeleton.get_bone_rest(index)
			rest.basis = Basis(Vector3.RIGHT if name == "hand_L" else Vector3.BACK, 0.7)
			skeleton.set_bone_rest(index, rest)
			skeleton.set_bone_pose_rotation(index, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, 0.03))
	if group == "sequence" and variant == "rooted":
		for name in ["first", "second"]:
			var root_clip := _seed_clip(".:position", Animation.TYPE_POSITION_3D, Vector3(2, 0, 3), Vector3(2.1, 0, 3.5 if name == "first" else 3.8))
			root_clip.copy_track(0, lib.get_animation(name))
		player.root_motion_track = ".:position"
		player.root_motion_local = true
	if group == "sequence" and variant == "saved_pose":
		FileAccess.open("res://animation_toolkit/poses/matrix_history_pose.json", FileAccess.WRITE).store_string(JSON.stringify(_pose_json()))
	# A locked instance cannot serialize transient preview overrides. Make its
	# paused control clip reproduce the authored input exactly, including channels
	# introduced by other library clips and their native cache baselines.
	var rig := fixture.get_node("Character/Skeleton") as Skeleton3D
	var input := lib.get_animation("input")
	for bone in rig.get_bone_count():
		var path := NodePath("Skeleton:" + rig.get_bone_name(bone))
		for entry in [[Animation.TYPE_POSITION_3D, rig.get_bone_pose_position(bone)], [Animation.TYPE_ROTATION_3D, rig.get_bone_pose_rotation(bone)], [Animation.TYPE_SCALE_3D, rig.get_bone_pose_scale(bone)]]:
			if input.find_track(path, entry[0]) >= 0: continue
			var index := input.add_track(entry[0])
			input.track_set_path(index, path)
			input.track_insert_key(index, 0.0, entry[1])
			input.track_insert_key(index, 1.0, entry[1])
func _case_params(fixture: Node, group: String, variant: String, mode: String, fps: int) -> Dictionary:
	var params := _params(fixture, variant)
	params.samples = fps
	params.overwrite = mode == "overwrite"
	if group == "motion":
		if variant.begins_with("cycle_"):
			params.op = "cycle"
			params.preset = variant.trim_prefix("cycle_")
		params.root_motion = variant in ["walk_cycle", "run_cycle", "strafe_cycle", "walk_start", "walk_stop", "cycle_walk", "cycle_run"]
		params.loop_mode = "linear" if variant in ["walk_cycle", "run_cycle", "idle_cycle", "strafe_cycle", "cycle_walk", "cycle_run", "cycle_idle"] else "none"
	elif group == "secondary":
		params.op = "secondary_motion"
		params.animation_name = "unrelated"
		params.bones = ["hand_L"] if variant == "single" else ["hand_L", "hand_R"]
		params.stiffness = 120.0
		params.damping = 12.0
	else:
		params.op = "compose"
		params.duration = 1.6
		params.segments = [{"start": 0.0, "duration": 0.6, "source_animation": "source/first"}, {"start": 0.8, "duration": 0.8, "source_animation": "source/second"}]
		if variant in ["partial", "rooted", "self_overwrite"]:
			params.duration = 1.4
			params.segments = [{"start": 0.0, "duration": 1.0, "source_animation": "source/first"}, {"start": 0.6, "duration": 0.8, "source_animation": "source/second", "fade_in": 0.2}]
		if variant == "rooted":
			params.segments[0].source_start = 0.1
			params.segments[0].source_end = 0.9
			params.segments[1].source_start = 0.2
			params.segments[1].source_end = 0.8
			params.segments[1].contacts = [{"name": "impact", "time": 0.3}]
		elif variant in ["saved_pose", "inline_pose"]:
			params.segments = [{"start": 0.0, "duration": 0.6, "source_animation": "source/first"}, {"start": 0.5, "duration": 0.6, "fade_in": 0.1}, {"start": 1.0, "duration": 0.6, "source_animation": "source/second", "fade_in": 0.1}]
			if variant == "saved_pose": params.segments[1].pose_name = "matrix_history_pose"
			else: params.segments[1].pose = _pose_json()
		if variant == "self_overwrite" and mode == "overwrite": params.segments[0].source_animation = "generated"
	return params
func _snapshot(fixture: Node) -> Dictionary:
	var snapshot := _seed._snapshot(fixture)
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	snapshot.mixer = {"extraction": player.root_motion_track, "local": player.root_motion_local, "active": player.active, "deterministic": player.deterministic}
	return snapshot
func _persist(row: Dictionary, state: String, expected: Dictionary, fixture: Node) -> void:
	var path := Saved.scene(row.id, state)
	assert_true(not path.is_empty(), row.id + " saved " + state)
	row.states[state] = path
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var actual := _snapshot(reopened.get_node("MotionSequenceHistory"))
	assert_true(_seed._pose._same(actual, expected), row.id + " persisted " + state + " " + str(_seed._pose._checks._differences(actual, expected)))
	reopened.free()
func _case(group: String, variant: String, mode: String, fps: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var fixture := _seed._seed("3d", mode)
	fixture.name = "MotionSequenceHistory"
	_prepare_inputs(fixture, group, variant)
	var label := "%s_%s_%s_%d" % [group, variant, mode, fps]
	var peer: Node
	var source_bytes := PackedByteArray()
	var instance_file := "user://motion_sequence_instance_%s.tscn" % label
	if mode in ["instanced", "editable"]:
		var packed := PackedScene.new()
		assert_eq(packed.pack(fixture), OK, label + " instance pack")
		assert_eq(ResourceSaver.save(packed, instance_file), OK, label + " instance save")
		source_bytes = FileAccess.get_file_as_bytes(instance_file)
		fixture.free()
		packed = ResourceLoader.load(instance_file, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer.name = "MotionSequencePeer"
		root.add_child(peer)
		peer.owner = root
	root.add_child(fixture)
	fixture.owner = root
	if mode not in ["instanced", "editable"]: _seed._pose._checks._own(fixture, root)
	if mode == "editable": root.set_editable_instance(fixture, true)
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	player.play("source/input", 0.0, -1.7, true)
	player.seek(0.2, true)
	player.set_section(0.1, 0.9)
	player.queue("source/next")
	player.pause()
	var playback := _seed._playback._player_state(player)
	var params := _case_params(fixture, group, variant, mode, fps)
	var family := "animation_sequence" if group == "sequence" else "animation_motion"
	var baseline := _snapshot(fixture)
	var peer_before := _snapshot(peer) if peer != null else {}
	var library := player.get_animation_library("") if player.has_animation_library("") else null
	var named := player.get_animation_library("source")
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var orphan_ids := Node.get_orphan_node_ids()
	var row := {"id": label, "group": group, "variant": variant, "mode": mode, "fps": fps, "params": params.duplicate(true), "pose_json": _pose_json(), "source": Saved.scene(label, "source"), "states": {}}
	var dry := _call(family, params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", label + " dry " + str(dry.get("error", {})))
	assert_eq(Node.get_orphan_node_ids(), orphan_ids, label + " dry exact orphans")
	assert_true(_seed._pose._same(_snapshot(fixture), baseline), label + " dry exact scene")
	assert_true(_seed._pose._same(_seed._playback._player_state(player), playback), label + " dry exact playback")
	assert_has_key(_call(family, params.merged({"player_path": "/Missing"}, true)).get("error", {}), "code", label + " typed refusal")
	assert_eq(Node.get_orphan_node_ids(), orphan_ids, label + " refusal exact orphans")
	assert_eq(history.get_version(), version, label + " no read/refusal history")
	var result := _call(family, params)
	assert_has_key(result, "data", label + " write " + str(result.get("error", {})))
	if not result.has("data"):
		if peer != null: peer.free()
		fixture.free()
		return
	for id in Node.get_orphan_node_ids(): assert_true(orphan_ids.has(id), label + " no new orphan " + str(id))
	row.reported = result.data.duplicate(true)
	var generated := _snapshot(fixture)
	var clip := player.get_animation(params.animation_name)
	assert_true(clip.get_track_count() > 0, label + " nonempty output")
	assert_true(_seed._pose._same(generated.children, baseline.children), label + " authored hierarchy unchanged")
	assert_true(_seed._pose._same(_seed._playback._player_state(player), playback), label + " write playback unchanged")
	assert_true(player.get_animation_library("source") == named, label + " source library identity")
	assert_eq(history.get_version(), version + 1, label + " exactly one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global action")
	row.reference = "user://motion_sequence_%s_reference.tres" % label
	var source_scene := (ResourceLoader.load(row.source, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.get_tree().root.add_child(source_scene)
	var reference := Reference.build(source_scene.get_node("MotionSequenceHistory"), params, group, row.pose_json, clip)
	source_scene.free()
	assert_true(reference != null, label + " independent reference")
	assert_eq(ResourceSaver.save(reference, row.reference), OK, label + " saved reference")
	_persist(row, "do", generated, fixture)
	assert_true(history.undo(), label + " native undo")
	assert_true(_seed._pose._same(_snapshot(fixture), baseline), label + " undo exact " + str(_seed._pose._checks._differences(_snapshot(fixture), baseline)))
	assert_true(_seed._pose._same(_seed._playback._player_state(player), playback), label + " undo playback")
	assert_true((player.get_animation_library("") if player.has_animation_library("") else null) == library, label + " undo library identity")
	assert_eq(root.is_editable_instance(fixture), mode == "editable", label + " undo permission")
	_persist(row, "undo", baseline, fixture)
	assert_true(history.redo(), label + " native redo")
	assert_true(player.get_animation(params.animation_name) == clip, label + " redo output identity")
	assert_true(_seed._pose._same(_snapshot(fixture), generated), label + " redo exact")
	assert_true(_seed._pose._same(_seed._playback._player_state(player), playback), label + " redo playback")
	_persist(row, "redo", generated, fixture)
	if peer != null:
		assert_true(_seed._pose._same(_snapshot(peer), peer_before), label + " peer immutable")
		assert_eq(FileAccess.get_file_as_bytes(instance_file), source_bytes, label + " source bytes immutable")
		peer.free()
	assert_eq(_logger.errors.size(), errors, label + " no engine errors " + str(_logger.errors.slice(errors)))
	Saved.finish(row)
	fixture.free()
func _matrix(group: String, mode: String) -> void:
	var variants := MOTIONS if group == "motion" else SEQUENCES if group == "sequence" else ["single", "branches"]
	for variant in variants:
		for fps in [30, 60, 120]: _case(group, variant, mode, fps)
	print("MOTION_SEQUENCE_MATRIX_COMPLETED=" + group + ":" + mode)
func test_motion_local() -> void: _matrix("motion", "local")
func test_motion_locked() -> void: _matrix("motion", "instanced")
func test_motion_editable() -> void: _matrix("motion", "editable")
func test_motion_missing_library() -> void: _matrix("motion", "missing_library")
func test_motion_overwrite() -> void: _matrix("motion", "overwrite")
func test_secondary_local() -> void: _matrix("secondary", "local")
func test_secondary_locked() -> void: _matrix("secondary", "instanced")
func test_secondary_editable() -> void: _matrix("secondary", "editable")
func test_sequence_local() -> void: _matrix("sequence", "local")
func test_sequence_locked() -> void: _matrix("sequence", "instanced")
func test_sequence_editable() -> void: _matrix("sequence", "editable")
func test_sequence_missing_library() -> void: _matrix("sequence", "missing_library")
func test_sequence_overwrite() -> void: _matrix("sequence", "overwrite")
func test_registry_writers_covered() -> void:
	var names := Ops.op_names("animation_motion")
	names.erase("character_setup")
	var covered := ["walk_cycle", "run_cycle", "idle_cycle", "jump", "turn_cycle", "strafe_cycle", "walk_start", "walk_stop", "cycle", "secondary_motion"]
	names.sort()
	covered.sort()
	assert_eq(names, covered, "every motion writer represented or retained setup gate")
	assert_eq(Ops.op_names("animation_sequence"), ["compose"], "all sequence writers covered")
func suite_teardown() -> void:
	OS.remove_logger(_logger)
	DirAccess.remove_absolute("res://animation_toolkit/poses/matrix_history_pose.json")
func _call(family: String, params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "motion-sequence-history", "command": "custom_tool:" + family, "params": params})
func _fixture() -> Node:
	var fixture := _seed._seed("3d", "local")
	fixture.name = "MotionSequenceHistory"
	var root := EditorInterface.get_edited_scene_root()
	root.add_child(fixture)
	_seed._pose._checks._own(fixture, root)
	return fixture
func _params(fixture: Node, op: String) -> Dictionary:
	return {"op": op, "player_path": str(fixture.get_node("Playback/AnimationPlayer").get_path()), "skeleton_path": str(fixture.get_node("Character/Skeleton").get_path()), "animation_name": "generated", "duration": 1.0, "samples": 30, "roles": Seed.ROLES, "spine_chain": ["spine", "chest", "head"]}

func test_busy_destination_is_atomic() -> void:
	var fixture := _fixture()
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	player.play("source/input")
	player.seek(0.2, true)
	var params := _params(fixture, "walk_cycle")
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(EditorInterface.get_edited_scene_root()))
	var version := history.get_version()
	var before := _seed._snapshot(fixture)
	var orphan_ids := Node.get_orphan_node_ids()
	for dry in [true, false]:
		var result := _call("animation_motion", params.merged({"dry_run": dry}))
		assert_eq(str(result.get("error", {}).get("code", "")), "OPERATION_UNAVAILABLE", "playing destination refused " + str(result))
		assert_true(_seed._pose._same(before, _seed._snapshot(fixture)), "busy exact scene")
		assert_eq(Node.get_orphan_node_ids(), orphan_ids, "busy no allocations")
		assert_eq(history.get_version(), version, "busy no history")
	fixture.free()

func test_secondary_rotated_rest_keeps_native_initial_pose() -> void:
	var fixture := _fixture()
	var skeleton := fixture.get_node("Character/Skeleton") as Skeleton3D
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var index := skeleton.find_bone("hand_L")
	var rest := skeleton.get_bone_rest(index)
	rest.basis = Basis(Vector3.RIGHT, 0.7)
	skeleton.set_bone_rest(index, rest)
	var authored := Quaternion(Vector3.RIGHT, 0.73)
	skeleton.set_bone_pose_rotation(index, authored)
	var params := _params(fixture, "secondary_motion")
	params.merge({"animation_name": "unrelated", "bones": ["hand_L"], "stiffness": 120.0, "damping": 12.0}, true)
	var before := _seed._snapshot(fixture)
	var result := _call("animation_motion", params)
	assert_has_key(result, "data", "secondary succeeds " + str(result))
	if result.has("data"):
		var animation := player.get_animation("unrelated")
		var track := animation.find_track("Skeleton:hand_L", Animation.TYPE_ROTATION_3D)
		assert_true(track >= 0, "secondary track resolves")
		if track >= 0: assert_true(animation.rotation_track_interpolate(track, 0).angle_to(authored) < 0.001, "native initial pose survives nonidentity rest: " + str(animation.rotation_track_interpolate(track, 0)))
	assert_true(_seed._pose._same(before.children, _seed._snapshot(fixture).children), "secondary live authored pose unchanged")
	fixture.free()

func test_sequence_missing_channel_enters_from_authored_pose() -> void:
	var fixture := _fixture()
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Character/Skeleton") as Skeleton3D
	var authored := skeleton.get_bone_pose_rotation(skeleton.find_bone("arm_L"))
	var animation := Animation.new()
	animation.length = 1.0
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, "Skeleton:arm_L")
	animation.track_insert_key(track, 0.0, Quaternion(Vector3.RIGHT, 0.6))
	animation.track_insert_key(track, 1.0, Quaternion(Vector3.RIGHT, 0.8))
	player.get_animation_library("source").add_animation("later", animation)
	var params := _params(fixture, "compose")
	params.duration = 1.4
	params.segments = [{"start": 0.0, "duration": 1.0, "source_animation": "source/input"}, {"start": 0.6, "duration": 0.8, "source_animation": "source/later", "fade_in": 0.2}]
	var result := _call("animation_sequence", params)
	assert_has_key(result, "data", "compose succeeds " + str(result))
	if result.has("data"):
		var output := player.get_animation("generated")
		var output_track := output.find_track("Skeleton:arm_L", Animation.TYPE_ROTATION_3D)
		assert_true(output_track >= 0, "incoming channel exists")
		if output_track >= 0:
			assert_true(output.rotation_track_interpolate(output_track, 0.3).angle_to(authored) < 0.001, "missing channel holds authored pose before entry")
			assert_true(output.rotation_track_interpolate(output_track, 0.6).angle_to(authored) < 0.001, "incoming fade starts at authored pose")
	fixture.free()
