@tool
extends McpTestSuite

const GraphTrace := preload("res://tests/graph_history_trace.gd")
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Ops := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Builders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const FIXTURE := preload("res://repair_graph_fixture.tscn")
const CASES := {
	"state_machine": {"states": [{"name": "idle", "animation": "idle"}, {"name": "walk", "animation": "walk"}], "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1}]},
	"blend_space": {"dimensions": 1, "min": 0, "max": 2, "points": [{"animation": "idle", "position": 0}, {"animation": "walk", "position": 1}, {"animation": "run", "position": 2}]},
	"blend_tree": {"root": {"type": "blend2", "inputs": [{"type": "animation", "animation": "idle"}, {"type": "animation", "animation": "walk"}]}},
	"wire": {},
	"locomotion": {"mode": "blend_space"},
	"one_shot_layer": {"animation": "jump", "base": "idle"},
	"additive_lean": {"animation": "lean", "base": "idle"},
}

class ErrorCapture extends Logger:
	var errors: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String,
			rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1:
			errors.append(rationale if not rationale.is_empty() else code)

var _undo: EditorUndoRedoManager
var _dispatcher
var _logger: ErrorCapture

func suite_name() -> String: return "graph_route_history"

func suite_setup(ctx: Dictionary) -> void:
	_undo = ctx.undo_redo
	Context.undo_redo = _undo
	_dispatcher = Registry.get_instance().get("_dispatcher")
	_logger = ErrorCapture.new()
	OS.add_logger(_logger)

func suite_teardown() -> void:
	OS.remove_logger(_logger)

func _call(params: Dictionary) -> Dictionary:
	return _dispatcher.call("_dispatch", {"request_id": "graph-history",
		"command": "custom_tool:animation_graph", "params": params})

func _snapshot(fixture: Node) -> Dictionary:
	var tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
	if tree == null: return {"tree": false}
	var parameters := {}
	for property in tree.get_property_list():
		var path := str(property.name)
		if path.begins_with("parameters/") and not tree.get(path) is Resource:
			parameters[path] = tree.get(path)
	return {"tree": true, "root_class":tree.tree_root.get_class() if tree.tree_root!=null else "", "player_resolves":tree.get_node_or_null(tree.anim_player)==fixture.get_node("AnimationPlayer"), "root": Builders.graph_dump(tree.tree_root),
		"player": str(tree.anim_player), "active": tree.active, "parameters": parameters}

func _seed(fixture: Node) -> void:
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	fixture.add_child(tree)
	tree.owner = fixture
	var root := AnimationNodeAnimation.new()
	root.animation = &"idle"
	tree.tree_root = root
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true

func _own(node: Node, edited_root: Node) -> void:
	node.owner = edited_root
	for child in node.get_children(): _own(child, edited_root)

func _inputs(fixture: Node) -> Dictionary:
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var clips := {}
	for name in player.get_animation_list():
		var animation := player.get_animation(name)
		var tracks: Array = []
		for index in animation.get_track_count():
			var keys: Array = []
			for key in animation.track_get_key_count(index): keys.append({"time":animation.track_get_key_time(index,key),"value":animation.track_get_key_value(index,key),"transition":animation.track_get_key_transition(index,key)})
			tracks.append({"path":str(animation.track_get_path(index)),"type":animation.track_get_type(index),"enabled":animation.track_is_enabled(index),"interpolation":animation.track_get_interpolation_type(index),"keys":keys})
		clips[str(name)]={"length":animation.length,"loop_mode":animation.loop_mode,"tracks":tracks}
	return {"clips":clips,"target_position":fixture.get_node("Character").position,"target_rotation":fixture.get_node("Character").rotation}

func _native_saved(saved: Node, op: String) -> Array:
	var clone := saved.duplicate()
	for mixer in clone.find_children("*","AnimationMixer",true,false):
		mixer.active=false
		mixer.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	EditorInterface.get_edited_scene_root().get_tree().root.add_child(clone)
	var tree := clone.get_node("AnimationTree") as AnimationTree
	var player := clone.get_node("AnimationPlayer") as AnimationPlayer
	var target := clone.get_node("Character") as Node2D
	var samples: Array = []
	if tree.tree_root==null:
		clone.free()
		return samples # New wire creates a binding, no playable root.
	tree.active=true
	tree.advance(0.0)
	if op=="state_machine":
		var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		playback.start("idle")
		tree.advance(0.1)
		samples.append({"stage":"idle","x":target.position.x,"player_playing":player.is_playing(),"clock":"native_saved_tree"})
		assert_true(absf(target.position.x)<=0.01,"native saved idle baseline")
		playback.travel("walk")
	elif op in ["blend_space","locomotion"]: tree.set("parameters/blend_position",1.0)
	elif op=="blend_tree":
		tree.advance(0.1)
		samples.append({"stage":"idle","x":target.position.x,"player_playing":player.is_playing(),"clock":"native_saved_tree"})
		assert_true(absf(target.position.x)<=0.01,"native saved blend idle baseline")
		tree.set("parameters/Blend2/blend_amount",1.0)
	elif op=="one_shot_layer":
		tree.advance(0.1)
		tree.set("parameters/OneShot/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	elif op=="additive_lean": tree.set("parameters/Add2/add_amount",1.0)
	for _frame in 30: tree.advance(1.0/60.0)
	var stage := "walk" if op in ["state_machine","blend_space","blend_tree","locomotion"] else "jump" if op=="one_shot_layer" else "lean" if op=="additive_lean" else "neutral_hold"
	samples.append({"stage":stage,"x":target.position.x,"y":target.position.y,"rotation":target.rotation,"player_playing":player.is_playing(),"clock":"native_saved_tree","frames":30,"dt":1.0/60.0})
	assert_false(player.is_playing(),"native Tree sole playback writer")
	if stage=="walk": assert_true(target.position.x>=20.0,"native saved walk branch")
	elif stage=="jump": assert_true(target.position.y<=-20.0,"native saved jump branch")
	elif stage=="lean": assert_true(target.rotation>=0.05,"native saved lean branch")
	elif stage=="neutral_hold": assert_true(absf(target.position.x)<=0.01 and absf(target.position.y)<=0.01,"native wire seeded idle hold")
	if op in ["blend_space","locomotion"]:
		var walk_x := target.position.x
		tree.set("parameters/blend_position",2.0)
		for _frame in 6: tree.advance(1.0/60.0)
		samples.append({"stage":"run","x":target.position.x,"player_playing":player.is_playing(),"clock":"native_saved_tree","frames":6,"dt":1.0/60.0})
		assert_true(target.position.x>walk_x+10.0,"native saved faster run branch")
	clone.free()
	return samples

func _persist(edited_root: Node, fixture: Node, expected: Dictionary, label: String, op: String="") -> Dictionary:
	var packed := PackedScene.new()
	var pack_result := packed.pack(edited_root)
	assert_eq(pack_result, OK, label + " packs")
	var path := "user://graph_history_%s.tscn" % label
	var save_result := ResourceSaver.save(packed, path)
	assert_eq(save_result, OK, label + " saves")
	var saved := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var found := saved.get_node_or_null(str(fixture.name))
	var snapshot := _snapshot(found) if found!=null else {}
	assert_eq(snapshot, expected, label + " saved state matches")
	var fixture_found := found!=null
	var native := _native_saved(found,op) if found!=null and label.ends_with("_redo") else []
	saved.free()
	return {"path":path,"sha256":FileAccess.get_sha256(path),"pack_result":pack_result,"save_result":save_result,"fixture_found":fixture_found,"snapshot":snapshot,"native":native}

func _matrix(mode: String) -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var global_history := _undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	for op in CASES:
		var assertions_before := _assertion_count
		var failed_before := _failed
		var source_path := ""
		_logger.errors.clear()
		var fixture := FIXTURE.instantiate()
		fixture.name = "GraphHistory"
		if mode in ["replace", "instanced"]: _seed(fixture)
		var peer: Node
		if mode.begins_with("instanced"):
			var packed := PackedScene.new()
			source_path = "user://graph_history_source_%s_%s.tscn" % [op, mode]
			assert_eq(packed.pack(fixture), OK)
			assert_eq(ResourceSaver.save(packed, source_path), OK)
			fixture.free()
			packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			fixture = packed.instantiate()
			peer = packed.instantiate()
			peer.name = "GraphPeer"
			edited_root.add_child(peer)
			peer.owner = edited_root
		else:
			fixture.scene_file_path = ""
		edited_root.add_child(fixture)
		fixture.owner = edited_root
		if not mode.begins_with("instanced"): _own(fixture, edited_root)
		var baseline := _snapshot(fixture)
		var peer_before := _snapshot(peer) if peer != null else {}
		var old_tree := fixture.get_node_or_null("AnimationTree") as AnimationTree
		var old_root: AnimationRootNode = old_tree.tree_root if old_tree != null else null
		var version := history.get_version()
		var global_version := global_history.get_version()
		var params: Dictionary = CASES[op].duplicate(true)
		params.merge({"op": op, "player_path": str(fixture.get_node("AnimationPlayer").get_path()),
			"tree_path": str(fixture.get_path()) + "/AnimationTree", "active": op != "wire"})
		var evidence := {"suite":"graph_route_history","test":{"new":"test_new_graph_scene_history","replace":"test_replaced_graph_scene_history","instanced":"test_instanced_graph_scene_history","instanced_new":"test_instanced_new_graph_scene_history"}[mode],"mode":mode,"op":op,"request":params.duplicate(true),"scene":edited_root.scene_file_path,"before":baseline,"inputs_before":_inputs(fixture),"versions":{"before":version,"global_before":global_version},"failed_before":failed_before,"errors_before":0,"fixture_sha256_before":FileAccess.get_sha256("res://repair_graph_fixture.tscn"),"source_path":source_path,"source_sha256_before":FileAccess.get_sha256(source_path) if not source_path.is_empty() else "","peer_before":peer_before}
		var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var dry := _call(params.merged({"dry_run": true}))
		evidence.dry=dry
		evidence.after_dry=_snapshot(fixture)
		evidence.versions.dry=history.get_version()
		assert_has_key(dry, "data", op + " dry route")
		assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans, op + " dry run leaves no orphan tree")
		assert_eq(_snapshot(fixture), baseline, op + " dry state")
		assert_eq(history.get_version(), version, op + " dry history")
		evidence.invalid_request=params.merged({"player_path":"/Missing"},true)
		evidence.invalid=_call(evidence.invalid_request)
		evidence.after_error=_snapshot(fixture)
		evidence.versions.error=history.get_version()
		assert_is_error(evidence.invalid, "NODE_NOT_FOUND", op + " invalid route")
		assert_eq(_snapshot(fixture), baseline, op + " invalid state")
		assert_eq(history.get_version(), version, op + " invalid history")
		var result := _call(params)
		assert_has_key(result, "data", op + " write " + str(result))
		evidence.write=result
		var generated := _snapshot(fixture)
		evidence.generated=generated
		evidence.versions.write=history.get_version()
		evidence.versions.global_write=global_history.get_version()
		assert_ne(generated, baseline, op + " effect")
		assert_eq(history.get_version(), version + 1, op + " one scene action")
		assert_eq(global_history.get_version(), global_version, op + " no global action")
		evidence.undo_success=history.undo()
		evidence.undone=_snapshot(fixture)
		assert_true(evidence.undo_success, op + " undo")
		assert_eq(_snapshot(fixture), baseline, op + " exact undo")
		if old_tree != null: assert_true(old_tree.tree_root == old_root, op + " original root identity")
		if peer != null: assert_false(edited_root.is_editable_instance(fixture), op + " undo instance editability")
		evidence.persist_undo=_persist(edited_root, fixture, baseline, op + "_" + mode + "_undo",op)
		evidence.redo_success=history.redo()
		evidence.redone=_snapshot(fixture)
		assert_true(evidence.redo_success, op + " redo")
		assert_eq(_snapshot(fixture), generated, op + " exact redo")
		evidence.persist_redo=_persist(edited_root, fixture, generated, op + "_" + mode + "_redo",op)
		evidence.inputs_after=_inputs(fixture)
		evidence.peer_after=_snapshot(peer) if peer!=null else {}
		evidence.source_sha256_after=FileAccess.get_sha256(source_path) if not source_path.is_empty() else ""
		evidence.fixture_sha256_after=FileAccess.get_sha256("res://repair_graph_fixture.tscn")
		assert_eq(evidence.inputs_after,evidence.inputs_before,op+" source inputs unchanged")
		if peer != null:
			assert_eq(_snapshot(peer), peer_before, op + " peer unchanged")
			peer.free()
		fixture.free()
		assert_eq(_logger.errors, [], op + " " + mode + " emits no engine errors")
		evidence.errors_after=_logger.errors.size()
		evidence.errors=_logger.errors.duplicate()
		evidence.failed_after=_failed
		evidence.assertion_count=_assertion_count-assertions_before
		GraphTrace.emit(evidence)

func test_registry_has_a_graph_history_case_for_every_operation() -> void:
	var names: Array = []
	for descriptor in Ops.op_descriptors("animation_graph"): names.append(str(descriptor.name))
	names.sort()
	var cases := CASES.keys()
	cases.append("graph_get")
	cases.sort()
	assert_eq(names, cases)

func test_new_graph_scene_history() -> void: _matrix("new")
func test_replaced_graph_scene_history() -> void: _matrix("replace")
func test_instanced_graph_scene_history() -> void: _matrix("instanced")
func test_instanced_new_graph_scene_history() -> void: _matrix("instanced_new")

func test_graph_get_is_read_only() -> void:
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphReadOnly"
	_seed(fixture)
	edited_root.add_child(fixture)
	fixture.owner = edited_root
	var before := _snapshot(fixture)
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var version := history.get_version()
	assert_has_key(_call({"op": "graph_get", "tree_path": str(fixture.get_node("AnimationTree").get_path())}), "data")
	assert_is_error(_call({"op": "graph_get", "tree_path": "/Missing"}), "NODE_NOT_FOUND")
	assert_eq(_snapshot(fixture), before)
	assert_eq(history.get_version(), version)
	fixture.free()

func test_wire_parameter_validation_and_history() -> void:
	_logger.errors.clear()
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphParameters"
	fixture.scene_file_path = ""
	edited_root.add_child(fixture)
	_own(fixture, edited_root)
	var params: Dictionary = CASES.blend_space.duplicate(true)
	params.merge({"op": "blend_space", "player_path": str(fixture.get_node("AnimationPlayer").get_path()), "active": false})
	assert_has_key(_call(params), "data")
	var tree := fixture.get_node("AnimationTree") as AnimationTree
	var wire := {"op": "wire", "player_path": params.player_path, "parameter_path": "parameters/blend_position", "parameter_value": 1.0, "active": true}
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var baseline := _snapshot(fixture)
	var version := history.get_version()
	var dry := _call(wire.merged({"dry_run": true}))
	assert_has_key(dry, "data")
	assert_eq(dry.data.parameter_set.value, 1.0)
	assert_eq(_snapshot(fixture), baseline)
	assert_eq(history.get_version(), version)
	for invalid in [{"parameter_path": "parameters/missing"}, {"parameter_path": "active"}, {"parameter_value": "wrong"}, {"parameter_value": null}]:
		assert_is_error(_call(wire.merged(invalid, true)), "PROPERTY_NOT_ON_CLASS" if invalid.has("parameter_path") else "WRONG_TYPE")
		assert_eq(_snapshot(fixture), baseline)
		assert_eq(history.get_version(), version)
	assert_has_key(_call(wire), "data")
	assert_eq(tree.get("parameters/blend_position"), 1.0)
	assert_true(tree.active)
	assert_true(history.undo())
	assert_eq(_snapshot(fixture), baseline)
	assert_true(history.redo())
	assert_eq(tree.get("parameters/blend_position"), 1.0)
	assert_true(tree.active)
	fixture.free()
	assert_eq(_logger.errors, [], "parameter write and undo emit no errors")

func test_wire_vector_bool_and_enum_parameters() -> void:
	_logger.errors.clear()
	var edited_root := EditorInterface.get_edited_scene_root()
	var fixture := FIXTURE.instantiate()
	fixture.name = "GraphTypedParameters"
	fixture.scene_file_path = ""
	edited_root.add_child(fixture)
	_own(fixture, edited_root)
	var player_path := str(fixture.get_node("AnimationPlayer").get_path())
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	assert_is_error(_call({"op": "wire", "player_path": player_path, "active": true}), "INVALID_PARAMS")
	assert_false(fixture.has_node("AnimationTree"))
	assert_eq(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans)
	assert_has_key(_call({"op": "blend_space", "player_path": player_path, "dimensions": 2,
		"min": {"x": 0, "y": 0}, "max": {"x": 1, "y": 1},
		"points": [{"animation": "idle", "position": {"x": 0, "y": 0}}, {"animation": "walk", "position": {"x": 1, "y": 0}}]}), "data")
	var tree := fixture.get_node("AnimationTree") as AnimationTree
	var history := _undo.get_history_undo_redo(_undo.get_object_history_id(edited_root))
	var baseline := _snapshot(fixture)
	var wire := {"op": "wire", "player_path": player_path, "parameter_path": "parameters/blend_position", "parameter_value": {"x": 1.0, "y": 0.5}}
	var vector_result := _call(wire)
	assert_has_key(vector_result, "data")
	assert_eq(vector_result.data.parameter_set.value, {"x": 1.0, "y": 0.5})
	assert_eq(tree.get("parameters/blend_position"), Vector2(1.0, 0.5))
	assert_true(history.undo())
	assert_eq(_snapshot(fixture), baseline)
	assert_true(history.redo())
	assert_eq(tree.get("parameters/blend_position"), Vector2(1.0, 0.5))
	var sm: Dictionary = CASES.state_machine.duplicate(true)
	sm.merge({"op": "state_machine", "player_path": player_path})
	# Explicit condition exposes a boolean parameter.
	sm.transitions[0]["condition"] = "walking"
	assert_has_key(_call(sm), "data")
	wire.parameter_path = "parameters/conditions/walking"
	wire.parameter_value = "false"
	assert_is_error(_call(wire), "WRONG_TYPE")
	wire.parameter_value = true
	assert_has_key(_call(wire), "data")
	assert_true(tree.get(wire.parameter_path))
	assert_has_key(_call({"op": "one_shot_layer", "player_path": player_path, "animation": "jump"}), "data")
	wire.parameter_path = "parameters/OneShot/request"
	wire.parameter_value = 1.5
	assert_is_error(_call(wire), "WRONG_TYPE")
	wire.parameter_value = 999
	assert_is_error(_call(wire), "VALUE_OUT_OF_RANGE")
	wire.parameter_value = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	assert_has_key(_call(wire), "data")
	assert_eq(tree.get(wire.parameter_path), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	fixture.free()
	assert_eq(_logger.errors, [], "typed graph parameters emit no errors")
