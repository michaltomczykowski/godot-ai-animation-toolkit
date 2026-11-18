@tool
extends RefCounted
const Trace := preload("res://tests/operation_history_trace.gd")
static func emit(row: Dictionary) -> void:
	Trace._emit(row,row.family,"test_motion_sequence_history.gd","motion_sequence_history_v1")
