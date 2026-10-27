@tool
extends McpTestSuite
const Witness := preload("res://tests/inspect_read_snapshot.gd")
const Trace := preload("res://tests/operation_history_trace.gd")
var _undo: EditorUndoRedoManager
func suite_name() -> String: return "inspect_read_witness"
func suite_setup(ctx: Dictionary) -> void: _undo = ctx.undo_redo
func test_begin() -> void:
 var value := Witness.marker("test_begin")
 if value.is_empty():
  skip("Only the exact public read driver may activate the witness")
  return
 assert_true(Witness.active.is_empty(), "one read witness at a time")
 if not Witness.active.is_empty(): return
 Witness.begin(value, _undo)
 var row := {"op": str(value.request.op), "marker": value, "phase": "begin"}
 Trace._emit(row, "animation_inspect", "test_inspect_read_witness.gd", "inspect_read_witness_v1")
func test_end() -> void:
 var value := Witness.marker("test_end")
 if value.is_empty():
  skip("Only the exact public read driver may activate the witness")
  return
 assert_true(not Witness.active.is_empty(), "read witness began")
 if Witness.active.is_empty(): return
 assert_eq(Witness.active.marker, value, "same immutable read marker")
 if Witness.active.marker != value: return
 var row := Witness.finish(value, _undo)
 row["phase"] = "end"
 Trace._emit(row, "animation_inspect", "test_inspect_read_witness.gd", "inspect_read_witness_v1")
