extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Quaternion: return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
	if a is Vector3: return a.x == b.x and a.y == b.y and a.z == b.z
	return a == b
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var new: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var failures: Array = []
	var rows: Array = []
	for row: Dictionary in new.cases:
		var reference: Dictionary = {}
		for item: Dictionary in old.cases:
			if item.id == row.id: reference = item
		var a := Native.load_case(reference, root)
		var b := Native.load_case(row, root)
		var changed: Array = []
		var keys := 0
		if a.clip.get_track_count() != b.clip.get_track_count(): changed.append("track count")
		for track in mini(a.clip.get_track_count(), b.clip.get_track_count()):
			if a.clip.track_get_path(track) != b.clip.track_get_path(track) or a.clip.track_get_type(track) != b.clip.track_get_type(track): changed.append("track path/type")
			if a.clip.track_get_key_count(track) != b.clip.track_get_key_count(track): changed.append("key count")
			for key in mini(a.clip.track_get_key_count(track), b.clip.track_get_key_count(track)):
				keys += 1
				if not _equal(a.clip.track_get_key_value(track, key), b.clip.track_get_key_value(track, key)): changed.append("key value %d/%d" % [track, key])
				if a.clip.track_get_key_transition(track, key) != b.clip.track_get_key_transition(track, key): changed.append("key transition")
				# Only the duplicate terminal-hold key moves later. Every authored
				# action key remains exact, including the unchanged root trajectory.
				if key < a.clip.track_get_key_count(track) - 1 and a.clip.track_get_key_time(track, key) != b.clip.track_get_key_time(track, key): changed.append("authored key time")
		rows.append({"rig": row.id, "keys_compared": keys, "changes": changed, "passed": changed.is_empty()})
		if not changed.is_empty(): failures.append(str(row.id) + ": " + str(changed))
		a.scene.free()
		b.scene.free()
	var report := {"rows": rows, "failures": failures, "engine_errors": logger.errors,
		"passed": rows.size() == 4 and failures.is_empty() and logger.errors.is_empty()}
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("TRANSITION_TAIL_PARITY=" + JSON.stringify(report))
	quit(0 if report.passed else 1)
