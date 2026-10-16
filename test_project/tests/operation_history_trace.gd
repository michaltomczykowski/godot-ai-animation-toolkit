@tool
extends RefCounted

## Optional raw evidence only. The Python public wrapper owns the active span;
## this helper never invokes an operation or alters test assertion state.
static func emit_fx(row: Dictionary) -> void:
	var context_path := OS.get_environment("TOOLKIT_OPERATION_CONTEXT")
	var trace_dir := OS.get_environment("TOOLKIT_OPERATION_TRACE_DIR")
	if context_path.is_empty() and trace_dir.is_empty(): return
	var active_path := trace_dir.path_join("active-public-test-run.json")
	if not FileAccess.file_exists(active_path):
		# Full editor suite runs outside the public collector remain ordinary tests.
		return
	var span: Variant = JSON.parse_string(FileAccess.get_file_as_string(active_path))
	if not span is Dictionary or span.get("context_sha256") != FileAccess.get_sha256(context_path):
		push_error("FX history evidence has a foreign public test span")
		return
	var stem := "%s-editor-%s-%s" % [span.run_id, OS.get_process_id(), Time.get_ticks_usec()]
	var event := {"schema_version": 1, "kind": "editor_history_assertions",
		"context_sha256": span.context_sha256, "run_id": span.run_id,
		"id": stem + ":1", "sequence": 1,
		"time_ns": int(Time.get_unix_time_from_system() * 1000000000.0),
		"driver": "test_fx_route_history.gd", "route": "public_test_run_inner_dispatch",
		"operation": "animation_fx." + str(row.op), "validator": "fx_history_v1",
		"test_run_begin_id": span.begin_id, "row": _safe(row)}
	var file := FileAccess.open(trace_dir.path_join(stem + ".jsonl"), FileAccess.WRITE)
	if file == null:
		push_error("FX history evidence file could not be written")
		return
	file.store_line(JSON.stringify(event))
	file.close()

static func _safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)] = _safe(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(_safe(item))
		return out
	if value is Vector2: return {"type": "Vector2", "x": value.x, "y": value.y}
	if value is Vector3: return {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
	if value is Color: return {"type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
	if value is NodePath or value is StringName: return str(value)
	return value
