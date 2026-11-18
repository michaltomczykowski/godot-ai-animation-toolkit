@tool
extends RefCounted
const Trace := preload("res://tests/operation_history_trace.gd")
static func emit(row: Dictionary) -> void:
	Trace._emit(row,"animation_graph","test_graph_route_history.gd","graph_history_v1")
