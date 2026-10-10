@tool
extends McpTestSuite

## Every rig clip writer through Godot AI, with engine-owned history snapshots.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Pose := preload("res://tests/test_rig_pose_history.gd")
const Clips := preload("res://tests/test_edit_route_history.gd")
const Playback := preload("res://tests/test_rig_bake_state.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const WRITERS := ["pose_to_clip", "walk_cycle", "idle_breathing", "blink", "jumping_jack", "squat", "punch", "bake_pose_sequence"]
const ROLES := {"hips": "hips", "spine": "spine", "chest": "chest", "head": "head", "arm_l": "arm_L", "arm_r": "arm_R", "forearm_l": "forearm_L", "forearm_r": "forearm_R", "thigh_l": "thigh_L", "thigh_r": "thigh_R", "shin_l": "shin_L", "shin_r": "shin_R", "foot_l": "foot_L", "foot_r": "foot_R"}
var _undo: EditorUndoRedoManager
var _dispatcher
var _pose := Pose.new()
var _clips := Clips.new()
var _playback := Playback.new()
var _logger: Capture.ErrorCapture
func suite_name() -> String: return "rig_clip_history"
func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func suite_teardown() -> void: OS.remove_logger(_logger)
func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "rig-clip-history", "command": "custom_tool:animation_rig", "params": params})
func _snapshot(node: Node) -> Dictionary:
	var result := _pose._snapshot(node)
	result.players = {}
	for name in ["AnimationPlayer", "OtherPlayer"]:
		var player := node.get_node("Playback/" + name) as AnimationPlayer
		result.players[name] = {"clips": _clips._clips(player), "libraries": player.get_animation_library_list(), "root": player.root_node, "autoplay": player.autoplay, "callback": player.callback_mode_process, "speed": player.speed_scale}
	return result
func _animation(kind: String, angle: float) -> Animation:
	var anim := Animation.new()
	anim.length = 1.0
	var track := anim.add_track(Animation.TYPE_ROTATION_3D if kind == "3d" else Animation.TYPE_VALUE)
	anim.track_set_path(track, "Skeleton:hips" if kind == "3d" else "Skeleton/arm_L:rotation")
	anim.track_insert_key(track, 0.0, Quaternion(Vector3.RIGHT, angle) if kind == "3d" else angle)
	anim.track_insert_key(track, 1.0, Quaternion(Vector3.RIGHT, angle + 0.6) if kind == "3d" else angle + 0.6)
	return anim
func _seed(kind: String, mode: String) -> Node:
	var fixture := Node3D.new()
	fixture.name = "RigClipHistory"
	var character := Node3D.new()
	character.name = "Character"
	character.position = Vector3(2, 0, 3)
	fixture.add_child(character)
	if kind == "3d":
		var skeleton := Skeleton3D.new()
		skeleton.name = "Skeleton"
		character.add_child(skeleton)
		var records := [["hips", "", Vector3(0, 1.1, 0)], ["spine", "hips", Vector3(0, 0.3, 0)], ["chest", "spine", Vector3(0, 0.2, 0)], ["head", "chest", Vector3(0, 0.3, 0)], ["eye", "head", Vector3(0.05, 0.1, 0.1)]]
		for side in ["L", "R"]:
			var sign_value := 1.0 if side == "L" else -1.0
			records.append_array([["thigh_" + side, "hips", Vector3(sign_value * 0.2, -0.1, 0)], ["shin_" + side, "thigh_" + side, Vector3(0, 0.5, 0)], ["foot_" + side, "shin_" + side, Vector3(0, 0.5, 0)], ["arm_" + side, "chest", Vector3(sign_value * 0.2, 0.15, 0)], ["forearm_" + side, "arm_" + side, Vector3(0, 0.35, 0)], ["hand_" + side, "forearm_" + side, Vector3(0, 0.3, 0)]])
		for record in records:
			skeleton.add_bone(record[0])
			var i := skeleton.find_bone(record[0])
			if record[1] != "": skeleton.set_bone_parent(i, skeleton.find_bone(record[1]))
			var basis := Basis(Vector3.BACK, -PI / 2 if record[0] == "arm_L" else PI / 2) if str(record[0]).begins_with("arm_") else Basis.IDENTITY
			if str(record[0]).begins_with("thigh_"): basis = Basis(Vector3.BACK, PI)
			var rest := Transform3D(basis, record[2])
			skeleton.set_bone_rest(i, rest)
			skeleton.set_bone_pose_position(i, rest.origin + Vector3(0.02, 0.03, 0))
			skeleton.set_bone_pose_rotation(i, (basis.get_rotation_quaternion() * Quaternion(Vector3.BACK, 0.03)).normalized())
			skeleton.set_bone_pose_scale(i, Vector3(1.1, 0.9, 1.05))
			skeleton.set_bone_meta(i, &"authored", "preserve")
		# Match the authored source's t=0.2 pose before packing the instance.
		# A transient seek on a locked instance is not a saved authoring override.
		skeleton.set_bone_pose_rotation(skeleton.find_bone("hips"), Quaternion(Vector3.RIGHT, 0.22))
	else:
		var skeleton := Skeleton2D.new()
		skeleton.name = "Skeleton"
		character.add_child(skeleton)
		for name in ["arm_L", "untouched"]:
			var bone := Bone2D.new()
			bone.name = name
			bone.set_autocalculate_length_and_angle(false)
			bone.set_length(12)
			bone.rest = Transform2D(0.2, Vector2(2, 3))
			bone.transform = Transform2D(0.3, Vector2(2.1, 3.2))
			bone.scale = Vector2(1.1, 0.9)
			skeleton.add_child(bone)
			if name == "arm_L": bone.rotation = 0.22
	var playback := Node.new()
	playback.name = "Playback"
	fixture.add_child(playback)
	for name in ["AnimationPlayer", "OtherPlayer"]:
		var player := AnimationPlayer.new()
		player.name = name
		player.root_node = "../../Character"
		player.speed_scale = 0.8 if name == "AnimationPlayer" else 1.0
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		playback.add_child(player)
		var named := AnimationLibrary.new()
		named.add_animation("input", _animation(kind, 0.1))
		named.add_animation("next", _animation(kind, 0.3))
		player.add_animation_library("source", named)
		if mode != "missing_library" or name == "OtherPlayer":
			var library := AnimationLibrary.new()
			library.add_animation("unrelated", _animation(kind, 0.7))
			if mode == "overwrite": library.add_animation("generated", _animation(kind, 1.0))
			player.add_animation_library("", library)
	_pose._checks._own(fixture, fixture)
	return fixture
func _params(op: String, kind: String) -> Dictionary:
	var params := {"op": op, "duration": 1.0, "loop_mode": "none", "roles": ROLES.duplicate(), "spine_chain": ["spine", "chest", "head"]}
	if op == "pose_to_clip":
		var make_pose := func(angle: float) -> Dictionary:
			return {"rest_relative": true, "bones": {"arm_L": {"rotation": {"kind": "quaternion", "z": sin(angle / 2), "w": cos(angle / 2)}}}}
		params.keys = [{"time": 0.0, "pose": make_pose.call(0.0)}, {"time": 1.0, "pose": make_pose.call(0.6)}]
	elif op == "blink": params.merge({"bones": ["eye"], "closed_scale": 0.1})
	elif op == "bake_pose_sequence": params.merge({"source_animation": "source/input", "bones": ["hips"], "fps": 4, "scales": true})
	elif op == "squat": params.bob = 0.2
	return params
func _persist(fixture: Node, expected: Dictionary, label: String) -> void:
	var packed := PackedScene.new()
	assert_eq(packed.pack(EditorInterface.get_edited_scene_root()), OK, label + " pack")
	var path := "user://rig_clip_history_%s.tscn" % label
	assert_eq(ResourceSaver.save(packed, path), OK, label + " save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var actual := _snapshot(reopened.get_node(str(fixture.name)))
	assert_true(_pose._same(actual, expected), label + " persisted exact scene " + str(_pose._checks._differences(actual, expected)))
	reopened.free()
func _case(op: String, kind: String, mode: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var label := "%s_%s_%s" % [mode, kind, op]
	var fixture := _seed(kind, mode)
	var peer: Node
	var source_path := "user://rig_clip_source_%s.tscn" % label
	var source_bytes := PackedByteArray()
	if mode in ["instanced", "editable"]:
		var packed := PackedScene.new()
		assert_eq(packed.pack(fixture), OK, label + " source pack")
		assert_eq(ResourceSaver.save(packed, source_path), OK, label + " source save")
		source_bytes = FileAccess.get_file_as_bytes(source_path)
		fixture.free()
		packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		fixture = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer.name = "RigClipPeer"
		root.add_child(peer)
		peer.owner = root
	root.add_child(fixture)
	fixture.owner = root
	if mode not in ["instanced", "editable"]: _pose._checks._own(fixture, root)
	if mode == "editable": root.set_editable_instance(fixture, true)
	var player := fixture.get_node("Playback/AnimationPlayer") as AnimationPlayer
	# Pause with a queue, non-default speed and non-rest source pose before every writer.
	player.play("source/input", -1, 1.7)
	player.seek(0.2, true)
	player.queue("source/next")
	player.pause()
	player.speed_scale = 0.8
	var baseline := _snapshot(fixture)
	var source_expected := _snapshot(peer) if peer != null else {}
	var before_player := _playback._player_state(player)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var version := history.get_version()
	var global_version := global_history.get_version()
	var errors := _logger.errors.size()
	var original_library := player.get_animation_library("") if player.has_animation_library("") else null
	var named_library := player.get_animation_library("source")
	var original_clips := {}
	if original_library != null:
		for name in original_library.get_animation_list(): original_clips[str(name)] = original_library.get_animation(name)
	var params := _params(op, kind)
	params.merge({"player_path": str(player.get_path()), "skeleton_path": str(fixture.get_node("Character/Skeleton").get_path()), "animation_name": "generated", "overwrite": mode == "overwrite"})
	var orphans := Node.get_orphan_node_ids()
	assert_has_key(_call(params.merged({"dry_run": true})), "data", label + " dry")
	assert_eq(Node.get_orphan_node_ids(), orphans, label + " dry no orphan nodes")
	assert_true(_pose._same(_snapshot(fixture), baseline), label + " dry exact scene")
	assert_true(_pose._same(_playback._player_state(player), before_player), label + " dry playback")
	assert_has_key(_call(params.merged({"player_path": "/Missing"}, true)).get("error", {}), "code", label + " rejected typed")
	assert_eq(Node.get_orphan_node_ids(), orphans, label + " rejected no orphan nodes")
	assert_true(_pose._same(_snapshot(fixture), baseline), label + " rejected exact scene")
	assert_eq(history.get_version(), version, label + " dry/rejected no history")
	assert_eq(root.is_editable_instance(fixture), mode == "editable", label + " dry/rejected permissions")
	assert_has_key(_call(params), "data", label + " write")
	# A new scene action discards the previous Redo branch. Its detached bake
	# outputs/carriers can be freed legitimately; new orphan IDs are still leaks.
	var after_commit := Node.get_orphan_node_ids()
	var added: Array = []
	var freed: Array = []
	for id in after_commit:
		if not orphans.has(id): added.append(id)
	for id in orphans:
		if not after_commit.has(id): freed.append(id)
	assert_eq(added, [], label + " write no new orphan nodes " + str(added))
	if not freed.is_empty(): print("RIG_CLIP_FREED_PRIOR_REDO=" + JSON.stringify({"case": label, "freed": freed.size(), "added": added.size()}))
	orphans = after_commit
	var generated := _snapshot(fixture)
	var generated_clip := player.get_animation("generated")
	assert_true(generated_clip != null and generated_clip.get_track_count() > 0, label + " effective clip")
	assert_true(_pose._same(generated.children, baseline.children), label + " source rig unchanged")
	assert_true(_pose._same(_playback._player_state(player), before_player), label + " write playback")
	assert_true(_pose._same(generated.players.OtherPlayer, baseline.players.OtherPlayer), label + " other player unchanged")
	assert_true(player.get_animation_library("source") == named_library, label + " named library identity")
	for name in ["source/input", "source/next", "unrelated"]:
		if baseline.players.AnimationPlayer.clips.has(name):
			assert_true(_pose._same(generated.players.AnimationPlayer.clips[name], baseline.players.AnimationPlayer.clips[name]), label + " unchanged clip " + name)
	for field in ["root", "autoplay", "callback", "speed"]:
		assert_eq(generated.players.AnimationPlayer[field], baseline.players.AnimationPlayer[field], label + " unchanged player " + field)
	assert_eq(history.get_version(), version + 1, label + " one scene action")
	assert_eq(global_history.get_version(), global_version, label + " zero global actions")
	assert_has_key(_call(params.merged({"overwrite": false}, true)).get("error", {}), "code", label + " overwrite refusal")
	assert_has_key(_call(params.merged({"overwrite": false, "dry_run": true}, true)).get("error", {}), "code", label + " dry overwrite refusal")
	assert_eq(Node.get_orphan_node_ids(), orphans, label + " refused no orphan nodes")
	assert_true(_pose._same(_playback._player_state(player), before_player), label + " refused playback")
	assert_true(_pose._same(_snapshot(fixture), generated), label + " refused exact scene")
	assert_eq(history.get_version(), version + 1, label + " refusal no action")
	assert_true(history.undo(), label + " undo")
	assert_true(_pose._same(_snapshot(fixture), baseline), label + " exact undo")
	assert_true(_pose._same(_playback._player_state(player), before_player), label + " undo playback")
	assert_eq(player.has_animation_library(""), original_library != null, label + " original library existence")
	if original_library != null:
		assert_true(player.get_animation_library("") == original_library, label + " library identity undo")
		for name in original_clips: assert_true(original_library.get_animation(name) == original_clips[name], label + " clip identity undo " + name)
	assert_eq(root.is_editable_instance(fixture), mode == "editable", label + " permission undo")
	_persist(fixture, baseline, label + "_undo")
	assert_true(history.redo(), label + " redo")
	assert_true(player.get_animation("generated") == generated_clip, label + " generated identity redo")
	assert_true(_pose._same(_snapshot(fixture), generated), label + " exact redo")
	assert_true(_pose._same(_playback._player_state(player), before_player), label + " redo playback")
	_persist(fixture, generated, label + "_redo")
	if peer != null:
		assert_true(_pose._same(_snapshot(peer), source_expected), label + " peer isolated")
		assert_eq(FileAccess.get_file_as_bytes(source_path), source_bytes, label + " source file bytes")
		var pristine := (ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		assert_true(_pose._same(_snapshot(pristine), source_expected), label + " fresh source isolated")
		assert_true(player.get_animation_library("") != peer.get_node("Playback/AnimationPlayer").get_animation_library(""), label + " local library isolated")
		pristine.free()
		peer.free()
	assert_eq(_logger.errors.size(), errors, label + " zero engine errors " + str(_logger.errors.slice(errors)))
	fixture.free()
func _matrix(mode: String) -> void:
	for op in WRITERS: _case(op, "3d", mode)
	_case("pose_to_clip", "2d", mode)
	print("RIG_CLIP_MATRIX_COMPLETED=" + mode)
func test_local_history() -> void: _matrix("local")
func test_overwrite_history() -> void: _matrix("overwrite")
func test_missing_library_history() -> void: _matrix("missing_library")
func test_instanced_history() -> void: _matrix("instanced")
func test_editable_history() -> void: _matrix("editable")
func test_registry_writers_covered() -> void:
	var excluded := ["pose_apply", "pose_blend", "pose_save", "pose_list", "rig_get", "rig_chain"]
	var names := Ops.op_names("animation_rig").filter(func(name): return not excluded.has(name))
	var expected := WRITERS.duplicate()
	names.sort()
	expected.sort()
	assert_eq(names, expected, "every advertised clip writer has a matrix case")
