extends SceneTree
const Guard := preload("res://tools/motion_capture_guard.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3: quit(1); return
	var route: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var control := args[2]
	var rows: Array = []
	for row: Dictionary in route.cases:
		rows.append({"id":row.id,"errors":Guard.admit(row,control)})
	var okay := true
	for row in rows:
		okay = okay and (row.errors.is_empty() if control.is_empty() else not row.errors.is_empty())
	var report := {"control":control,"rows":rows,"passed":okay,"route_sha256":FileAccess.get_sha256(args[0]),"script_sha256":FileAccess.get_sha256("res://tools/motion_capture_guard.gd")}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report))
	quit(0 if okay else 1)
