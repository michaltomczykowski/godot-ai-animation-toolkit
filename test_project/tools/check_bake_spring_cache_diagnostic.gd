extends "res://tools/check_saved_bake_capture.gd"
## Causal observation only: exact saved source warmed/tight/private-copy startup.
## Does not generate a clip, replace a modifier, or approve any schedule.
const Sandbox:=preload("res://addons/godot_ai_animation/utils/evaluation_sandbox.gd")
var strategy:="direct-warm"
var current_side:="source"
var sandbox:RefCounted
var original:Node
func _loading_frames()->int:return 2 if strategy=="direct-warm" else 0
func _open_scene(path:String):
	original=_load(path)
	if strategy!="sandbox-tight" or current_side!="source":return original
	# Source load/cache has settled; production duplicate is then entered and sampled synchronously.
	await process_frame
	await process_frame
	sandbox=Sandbox.new()
	var opened:Dictionary=sandbox.open(original)
	_check(not opened.has("error"),"actual production sandbox open "+str(opened))
	return sandbox.scene
func _close_scene(scene:Node)->void:
	if sandbox!=null:
		sandbox.close();sandbox=null
		original.free();original=null
	else:scene.free();original=null
func _run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[1]):push_error("new manifest/report required");quit(1);return
	media_manifest=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if media_manifest.get("state")!="current_public_inputs_staged_native_capture_pending":push_error("current anchor required");quit(1);return
	for path in media_manifest.files:_check(FileAccess.get_sha256(path)==media_manifest.files[path].sha256,"dependency before "+str(path))
	for variant in ["direct-warm","direct-tight","sandbox-tight"]:
		strategy=variant
		for row:Dictionary in media_manifest.cases:
			if row.id not in ["modifier_spring_1_60","modifier_ordered_spring_look_1_60"]:continue
			for take in 2:
				for side in ["source","redo"]:
					current_side=side
					var run:Dictionary=await _replay(row,side,take,false,false)
					run.strategy=strategy;media_runs.append(run)
	for path in media_manifest.files:_check(FileAccess.get_sha256(path)==media_manifest.files[path].sha256,"dependency after "+str(path))
	var report:={"kind":"saved_bake_spring_cache_causal_diagnostic","manifest_sha256":FileAccess.get_sha256(args[0]),"script_sha256":FileAccess.get_sha256("res://tools/check_bake_spring_cache_diagnostic.gd"),"sandbox_sha256":FileAccess.get_sha256("res://addons/godot_ai_animation/utils/evaluation_sandbox.gd"),"runs":media_runs,"failures":failures,"engine_errors":logger.values,"passed":failures.is_empty() and logger.values.is_empty(),"scope":"Raw configuration/cache/played source versus saved bake diagnosis only. No parity or media approval."}
	var file:=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close();OS.remove_logger(logger)
	quit(0 if report.passed else 1)
