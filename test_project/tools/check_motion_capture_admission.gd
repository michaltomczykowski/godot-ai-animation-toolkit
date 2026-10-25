extends SceneTree
const Guard := preload("res://tools/motion_capture_guard.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		if args.size() >= 2: FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"passed":false,"error":"Exactly three user arguments including explicit control required"}))
		quit(1)
		return
	var requested := args[2]
	if requested not in ["positive", "inert_player", "foreign_tree", "assigned_player", "autoplay_player", "playing_player", "active_modifier", "wrong_root_track"]:
		FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"passed":false,"control":requested,"error":"Unknown admission control"}))
		quit(1)
		return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var control := "" if requested == "positive" else requested
	var rows: Array = []
	for row: Dictionary in route.cases:
		var diagnostics := {}
		var errors := Guard.admit(row,control,diagnostics)
		rows.append({"id":row.id,"errors":errors,"writer_diagnostics":diagnostics})
	var okay := true
	for row in rows:
		okay = okay and (row.errors.is_empty() if control.is_empty() or control == "inert_player" else not row.errors.is_empty())
	var report := {"control":requested,"effective_control":control,"rows":rows,"passed":okay,"route_sha256":FileAccess.get_sha256(args[0]),"script_sha256":FileAccess.get_sha256("res://tools/motion_capture_guard.gd")}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report))
	quit(0 if okay else 1)
