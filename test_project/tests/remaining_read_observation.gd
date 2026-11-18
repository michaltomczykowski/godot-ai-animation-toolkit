@tool
extends RefCounted
## Dedicated remaining-read activation; leaves inspect admission unchanged.
const Stored := preload("res://tests/inspect_read_snapshot.gd")
static var active: Dictionary = {}
static func marker(test: String) -> Dictionary:
	var directory := OS.get_environment("TOOLKIT_OPERATION_TRACE_DIR")
	var path := directory.path_join("active-remaining-read.json")
	var span_path := directory.path_join("active-public-test-run.json")
	if directory.is_empty() or not FileAccess.file_exists(path) or not FileAccess.file_exists(span_path): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	var span = JSON.parse_string(FileAccess.get_file_as_string(span_path))
	if not value is Dictionary or not span is Dictionary: return {}
	if span.get("request") != {"suite":"remaining_read_witness","test_name":test,"verbose":true}: return {}
	if value.get("context_sha256") != span.get("context_sha256") or value.get("run_id") != span.get("run_id"): return {}
	if value.get("context_sha256") != FileAccess.get_sha256(OS.get_environment("TOOLKIT_OPERATION_CONTEXT")): return {}
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != value.get("scene"): return {}
	if value.get("operation") not in ["animation_rig.rig_get","animation_rig.pose_list","animation_graph.graph_get"] or value.get("stage") not in ["valid","refusal"]: return {}
	return value
static func graph() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var tree := root.get_node_or_null("AnimationTree") as AnimationTree
	var player := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if tree == null or player == null or not tree.tree_root is AnimationNodeStateMachine: return {"unavailable":true}
	var machine := tree.tree_root as AnimationNodeStateMachine
	var states: Array = []
	var implicit: Array = []
	for name in machine.get_node_list():
		var node := machine.get_node(name)
		if str(name) in ["Start","End"]:
			implicit.append(str(name))
		else:
			states.append({"name":str(name),"class":node.get_class(),"animation":str(node.animation) if node is AnimationNodeAnimation else ""})
	var edges: Array = []
	for index in machine.get_transition_count():
		var link := machine.get_transition(index)
		edges.append({"from":str(machine.get_transition_from(index)),"to":str(machine.get_transition_to(index)),"class":link.get_class(),"xfade":link.xfade_time,"advance_mode":link.advance_mode,"switch_mode":link.switch_mode,"condition":str(link.advance_condition),"expression":link.advance_expression,"priority":link.priority,"reset":link.reset})
	return {"tree_class":tree.get_class(),"root_class":machine.get_class(),"tree_path":str(root.get_path_to(tree)),"player_path":str(root.get_path_to(player)),"player_resolved":tree.get_node_or_null(tree.anim_player)==player,"anim_player":str(tree.anim_player),"active":tree.active,"states":states,"implicit_states":implicit,"transitions":edges}
static func begin(value: Dictionary, undo: EditorUndoRedoManager) -> void:
	var logger := Stored.Errors.new()
	OS.add_logger(logger)
	active={"marker":value.duplicate(true),"logger":logger,"before":Stored.snapshot(undo)}
	if value.operation=="animation_graph.graph_get": active["graph_before"]=graph()
static func finish(value: Dictionary, undo: EditorUndoRedoManager) -> Dictionary:
	var row := {"op":str(value.request.op),"mode":"remaining_read","marker":value,"begin_marker":active.marker,"before":active.before,"after":Stored.snapshot(undo),"snapshot_schema":"stored_graph_v1"}
	if value.operation=="animation_graph.graph_get":
		row["graph_before"]=active.graph_before
		row["graph_after"]=graph()
	var source := "res://repair_graph_fixture.tscn" if value.operation=="animation_graph.graph_get" else "res://repair_rig_fixture.tscn"
	row["fixture_path"]=source
	row["fixture_sha256"]=FileAccess.get_sha256(source)
	row["errors_before"]=0
	row["errors_after"]=active.logger.entries.size()
	row["errors"]=active.logger.entries.duplicate(true)
	OS.remove_logger(active.logger)
	active.clear()
	return row
