extends "res://tools/render_setup_quality.gd"
## Actual JSON numeric representation must survive native schedule admission.
func _run() -> void:
	var recording := {"contract":"saved_setup_v1","fps":60,"size":[1920,1080],"fresh_scene_per_take":true,"camera":"fixed_front_side","condition":"half_walk_run","route_sha256":"a".repeat(64),"planner_sha256":"b".repeat(64)}
	var schedule := {"recording":recording,"cases":[]}
	for id in ["dummy","xbot","short","zup_tall"]:
		schedule.cases.append({"id":id,"write":{"clips":{},"root_motion":true,"speed_values":{"walk":1.0,"run":2.0}},"render_spec":{"condition":"half_walk_run","frames_per_take":180,"takes":2,"speed_mps":1.5,"controller_speed_mps":0.0,"jump_fire_at_frame":-1}})
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(schedule))
	var failures: Array[String] = []
	if not _schedule_error(decoded).is_empty(): failures.append("Valid JSON roundtrip refused: "+_schedule_error(decoded))
	for dimensions in [[1920.5,1080],[1920,1080.5],[1920,1080,1],["1920",1080]]:
		var bad := decoded.duplicate(true)
		bad.recording.size=dimensions
		if _schedule_error(bad).is_empty(): failures.append("Malformed dimensions accepted: "+str(dimensions))
	for field in ["takes","frames_per_take","controller_speed_mps"]:
		var bad := decoded.duplicate(true)
		bad.cases[0].render_spec[field]=1
		if _schedule_error(bad).is_empty(): failures.append("Invalid "+field+" accepted")
	if not logger.errors.is_empty(): failures.append("Engine errors: "+str(logger.errors))
	print("TIER1_SETUP_RECORDING="+JSON.stringify({"passed":failures.is_empty(),"checks":8,"failures":failures}))
	OS.remove_logger(logger)
	print("TIER1 PASS" if failures.is_empty() else "TIER1 FAIL")
	quit(0 if failures.is_empty() else 1)
