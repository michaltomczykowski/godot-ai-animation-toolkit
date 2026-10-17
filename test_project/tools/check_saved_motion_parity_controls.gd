extends SceneTree
const Parity := preload("res://tools/saved_motion_parity.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var driver: Script = load("res://tools/check_motion_alias_parity.gd")
	check(driver != null and driver.can_instantiate(), "saved route parity driver compiles")
	for fps in [30,60,120]:
		for mode in ["player","tree"]:
			for corruption in ["", "key", "loop", "binding", "metadata"]:
				var a := fixture()
				var b := fixture()
				match corruption:
					"key": b.clip.track_set_key_value(1,1,Vector3(0,1.14,0))
					"loop": b.clip.loop_mode = Animation.LOOP_LINEAR
					"binding": b.player.root_motion_track = NodePath()
					"metadata": b.metadata.root_motion = false
				var result := Parity.played(a,b,fps,mode)
				check(result.passed == corruption.is_empty(), "native parity control " + corruption + "/" + mode + "/" + str(fps))
				if corruption == "key": check(float(result.position_error_m) > 0.001, "changed key has played effect")
				if corruption == "binding": check(not result.extraction_metadata_exact, "cached equal world motion cannot hide different extraction binding")
				a.scene.free()
				b.scene.free()
	var a := fixture()
	for corruption in ["path", "type", "interpolation", "enabled", "marker", "transition"]:
		var copy := a.clip.duplicate(true) as Animation
		match corruption:
			"path": copy.track_set_path(1,NodePath("Owner/Skeleton:shin"))
			"type":
				copy.remove_track(1)
				var track := copy.add_track(Animation.TYPE_SCALE_3D)
				copy.track_set_path(track,NodePath("Owner/Skeleton:hips"))
				copy.track_insert_key(track,0.0,Vector3.ONE)
			"interpolation": copy.track_set_interpolation_type(1,Animation.INTERPOLATION_NEAREST)
			"enabled": copy.track_set_enabled(1,false)
			"marker":
				copy.remove_marker("takeoff")
				copy.add_marker("takeoff",0.3)
			"transition": copy.track_set_key_transition(1,1,0.5)
		check(not Parity.same_channels(a.clip,copy), "exact resource rejects " + corruption)
	a.scene.free()
	print("SAVED_MOTION_PARITY_CONTROLS="+JSON.stringify({"checks":checks,"failures":failures}))
	print("TIER1 PASS" if failures.is_empty() else "TIER1 FAIL")
	quit(0 if failures.is_empty() else 1)

func fixture() -> Dictionary:
	var scene := Node3D.new()
	scene.basis = Basis(Vector3(1,2,3).normalized(),0.3).scaled(Vector3.ONE*1.5)
	root.add_child(scene)
	var body := Node3D.new()
	body.name = "Owner"
	body.position = Vector3(0.2,0,1)
	body.basis = Basis(Vector3.UP,0.7)
	scene.add_child(body)
	var rig := Skeleton3D.new()
	rig.name = "Skeleton"
	body.add_child(rig)
	rig.add_bone("hips")
	rig.set_bone_rest(0,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	rig.add_bone("shin")
	rig.set_bone_parent(1,0)
	rig.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,-0.5,0)))
	var player := AnimationPlayer.new()
	player.name = "Player"
	scene.add_child(player)
	player.root_node = NodePath("..")
	player.root_motion_track = NodePath("Owner:position")
	player.root_motion_local = true
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := Animation.new()
	clip.length = 1.0
	var track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track,NodePath("Owner:position"))
	clip.track_insert_key(track,0.0,body.position)
	clip.track_insert_key(track,1.0,body.position+Vector3(0,0,-0.4))
	track = clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track,NodePath("Owner/Skeleton:hips"))
	clip.track_insert_key(track,0.0,Vector3(0,1,0))
	clip.track_insert_key(track,0.5,Vector3(0,1.1,0))
	clip.track_insert_key(track,1.0,Vector3(0,1,0))
	clip.add_marker("takeoff",0.25)
	clip.add_marker("land",0.75)
	var library := AnimationLibrary.new()
	library.add_animation("probe",clip)
	player.add_animation_library("",library)
	player.play("probe")
	player.advance(0.0)
	return {"scene":scene,"body":body,"rig":rig,"player":player,"clip":clip,"animation_name":"probe","initial_body":body.global_position,
		"metadata":{"root_motion":true,"root_motion_requested":true,"translation_owner":"actor_root","world_scale":1.5}}
