extends SceneTree
const Space := preload("res://addons/godot_ai_animation/spec/motion_space.gd")
class Errors extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _trace: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
var logger := Errors.new()
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	OS.add_logger(logger)
	for scale_value in [0.5, 1.0, 2.0]:
		var geometry := Space.geometry(Basis(Vector3(1,2,3).normalized(), 0.6).scaled(Vector3.ONE * scale_value))
		check(not geometry.has("error") and absf(float(geometry.world_scale)-scale_value)<0.000001, "rotated positive uniform geometry")
		var config := {"bob": 0.02, "jump_height": 0.12, "jump_distance": 0.3, "jump_crouch": 0.24, "foot_lift": 0.05, "arm_swing": 30.0}
		Space.local_config(config, {"bob":0.02, "height":0.12, "distance":0.3}, {}, scale_value)
		check(absf(float(config.bob)*scale_value-0.02)<0.000001 and absf(float(config.jump_height)*scale_value-0.12)<0.000001 and absf(float(config.jump_distance)*scale_value-0.3)<0.000001, "explicit metric controls")
		check(config.jump_crouch==0.24 and config.foot_lift==0.05 and config.arm_swing==30.0, "omitted defaults and angular controls intact")
		var reported := Space.world_metrics({"speed":0.3, "distance":0.4, "clamp_shortfall_m":0.001, "steps":2, "reference_window_s":0.2}, scale_value)
		check(reported.speed==0.3*scale_value and reported.distance==0.4*scale_value and reported.steps==2 and reported.reference_window_s==0.2, "world metric report")
		for fps in [30,60,120]: _native(scale_value, fps)
	for bad in [Basis.from_scale(Vector3(1,2,1)), Basis.from_scale(Vector3(-1,1,1)), Basis.from_scale(Vector3(0,1,1)), Basis(Vector3(1,0,0), Vector3(0.2,1,0), Vector3(0,0,1))]:
		check(Space.geometry(bad).has("error"), "unsupported effective geometry refuses")
	check(logger.errors.is_empty(), "no engine errors")
	OS.remove_logger(logger)
	print("TIER1_MOTION_SPACE=" + JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures}))
	print("TIER1 PASS" if failures.is_empty() else "TIER1 FAIL")
	quit(0 if failures.is_empty() else 1)
func _native(scale_value: float, fps: int) -> void:
	var parent := Node3D.new()
	parent.position = Vector3(4,2,-3)
	parent.basis = Basis(Vector3(1,2,3).normalized(), 0.4).scaled(Vector3.ONE * scale_value)
	root.add_child(parent)
	var owner := Node3D.new()
	owner.name = "Owner"
	owner.position = Vector3(2,0,1)
	owner.basis = Basis(Vector3.UP, 0.7)
	parent.add_child(owner)
	var nested := Node3D.new()
	nested.basis = Basis(Vector3.RIGHT, -0.3)
	owner.add_child(nested)
	var skeleton := Skeleton3D.new()
	nested.add_child(skeleton)
	var player := AnimationPlayer.new()
	owner.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.root_node = NodePath("..")
	player.root_motion_track = NodePath(".:position")
	player.root_motion_local = true
	var clip := Animation.new()
	clip.length = 1.01
	var track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track, NodePath(".:position"))
	var desired_world_distance := 0.3
	var local_motion := Vector3(0,0,-desired_world_distance/scale_value)
	var mapping := Space.root_basis(owner, skeleton)
	var start_position := owner.position
	var start_world := owner.global_position
	var expected_world: Vector3 = skeleton.global_basis * local_motion
	clip.track_insert_key(track,0.0,start_position)
	clip.track_insert_key(track,1.0,start_position+mapping*local_motion)
	clip.track_insert_key(track,1.01,start_position+mapping*local_motion)
	var library := AnimationLibrary.new()
	library.add_animation("probe",clip)
	player.add_animation_library("",library)
	player.play("probe")
	player.advance(0.0)
	for step in fps:
		player.advance(1.0/fps)
		owner.position += player.get_root_motion_position()
	var world_travel := owner.global_position-start_world
	check(world_travel.distance_to(expected_world)<0.00001 and absf(world_travel.length()-desired_world_distance)<0.00001, "native world travel scale%.2f fps%d" % [scale_value,fps])
	parent.free()
