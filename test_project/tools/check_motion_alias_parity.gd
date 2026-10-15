extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
const Parity := preload("res://tools/saved_motion_parity.gd")
var logger := Native.CaptureErrors.new()
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected dedicated route JSON, cycle route JSON and fresh output JSON")
		quit(1)
		return
	if FileAccess.file_exists(args[2]):
		push_error("Preserve previous parity evidence; choose a fresh output")
		quit(1)
		return
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var fresh: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var problems: Array[String] = []
	var rows: Array = []
	if not old.get("passed",false) or not fresh.get("passed",false): problems.append("Both public routes must pass")
	if old.get("source_head","") != fresh.get("source_head","") or str(old.get("source_head","")).is_empty(): problems.append("Exact source heads differ or are missing")
	if old.get("operation") != fresh.get("operation") or old.get("profile") != fresh.get("profile") or old.get("root_mode") != fresh.get("root_mode"): problems.append("Route operation/style/ownership differs")
	var previous_by_id := {}
	for previous: Dictionary in old.cases:
		if previous_by_id.has(previous.id): problems.append("Duplicate reference rig")
		previous_by_id[previous.id] = previous
	var seen := {}
	for row: Dictionary in fresh.cases:
		if seen.has(row.id) or not previous_by_id.has(row.id):
			problems.append("Duplicate or unmatched alias rig")
			continue
		seen[row.id] = true
		var previous: Dictionary = previous_by_id[row.id]
		var expected_preset: String = {"turn_cycle":"turn","strafe_cycle":"strafe","jump":"jump"}.get(str(old.get("operation")),"")
		if expected_preset.is_empty() or row.params.get("op") != "cycle" or row.params.get("preset") != expected_preset or previous.params.get("op") != old.get("operation"): problems.append("Expected actual dedicated versus matching cycle preset invocations")
		var a_params: Dictionary = previous.params.duplicate(true)
		var b_params: Dictionary = row.params.duplicate(true)
		a_params.erase("op")
		b_params.erase("op")
		b_params.erase("preset")
		if a_params != b_params: problems.append("Dedicated and cycle request controls differ")
		if row.roles != previous.roles or not row.write.has("root_motion") or not previous.write.has("root_motion"): problems.append("Rig roles or extraction metadata missing/different")
		if FileAccess.get_sha256(row.scene) != row.scene_sha256 or FileAccess.get_sha256(previous.scene) != previous.scene_sha256:
			problems.append("Saved scene hash changed")
			continue
		for fps in [30,60,120]:
			for mode in ["player","tree"]:
				var a := Native.load_case(previous,root)
				var b := Native.load_case(row,root)
				if a.has("error") or b.has("error"):
					problems.append("Saved scene did not load")
					if a.has("scene"): a.scene.free()
					if b.has("scene"): b.scene.free()
					continue
				a.animation_name = previous.params.animation_name
				b.animation_name = row.params.animation_name
				a.metadata = previous.write
				b.metadata = row.write
				var result := Parity.played(a,b,fps,mode)
				result.id = row.id
				rows.append(result)
				a.scene.free()
				b.scene.free()
	if seen.size() != previous_by_id.size() or seen.size() != 4: problems.append("All four matched rigs required")
	var passed := problems.is_empty() and rows.size() == seen.size()*6 and logger.errors.is_empty()
	for row: Dictionary in rows: passed = passed and row.passed
	var report := {"passed":passed,"runs":rows,"failures":problems,"engine_errors":logger.errors,
		"reference_source":old.get("source_head"),"fresh_source":fresh.get("source_head"),
		"reference_route_sha256":FileAccess.get_sha256(args[0]),"alias_route_sha256":FileAccess.get_sha256(args[1]),
		"parity_helper_sha256":FileAccess.get_sha256("res://tools/saved_motion_parity.gd"),"native_helper_sha256":FileAccess.get_sha256("res://tools/character_quality_native.gd"),
		"scope":"Exact saved channels/extraction and native playback equivalence; not motion quality or visual approval"}
	FileAccess.open(args[2],FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("MOTION_ALIAS_PARITY="+JSON.stringify({"passed":passed,"runs":rows.size(),"failures":problems,"engine_errors":logger.errors}))
	quit(0 if passed else 1)
