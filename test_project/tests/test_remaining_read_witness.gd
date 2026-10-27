@tool
extends McpTestSuite
const Witness := preload("res://tests/remaining_read_observation.gd")
const Trace := preload("res://tests/operation_history_trace.gd")
var _undo: EditorUndoRedoManager
func suite_name() -> String: return "remaining_read_witness"
func suite_setup(ctx: Dictionary) -> void: _undo=ctx.undo_redo
func test_begin() -> void:
	var value := Witness.marker("test_begin")
	if value.is_empty():
		skip("Only the exact remaining read driver activates this witness")
		return
	assert_true(Witness.active.is_empty(),"one remaining read at a time")
	if not Witness.active.is_empty(): return
	Witness.begin(value,_undo)
	Trace._emit({"op":str(value.request.op),"mode":"remaining_read","phase":"begin","marker":value},str(value.operation).get_slice(".",0),"test_remaining_read_witness.gd","remaining_read_witness_v1")
func test_end() -> void:
	var value := Witness.marker("test_end")
	if value.is_empty():
		skip("Only the exact remaining read driver activates this witness")
		return
	assert_true(not Witness.active.is_empty(),"remaining read began")
	if Witness.active.is_empty(): return
	assert_eq(Witness.active.marker,value,"same immutable remaining read marker")
	if Witness.active.marker!=value: return
	var row := Witness.finish(value,_undo)
	row["phase"]="end"
	Trace._emit(row,str(value.operation).get_slice(".",0),"test_remaining_read_witness.gd","remaining_read_witness_v1")
