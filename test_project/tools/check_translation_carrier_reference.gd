extends SceneTree
## Coordinate controls only: no authored fixtures, poses, production generator,
## editor, rendering, backend or external endpoint.
const Transition := preload("res://tools/check_start_stop_quality.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for path in ["res://tools/check_transition_preview_parity.gd", "res://tools/check_transition_sequence_review.gd", "res://tools/render_motion_sequence_history.gd", "res://tools/check_run_quality.gd"]:
		var script: Script = load(path)
		check(script != null and script.can_instantiate(), "changed consumer compiles without launching " + path)
	for scale_value in [0.5, 1.0, 2.0]:
		var parent := Node3D.new()
		parent.basis = Basis(Vector3(1,2,3).normalized(), 0.67).scaled(Vector3.ONE*scale_value)
		parent.position = Vector3(2,1,-3)
		root.add_child(parent)
		var owner := Node3D.new()
		owner.basis = Basis(Vector3.UP, 0.71)
		owner.position = Vector3(1,0,2)
		parent.add_child(owner)
		var rig := Node3D.new()
		rig.basis = Basis(Vector3.RIGHT, 0.83)
		owner.add_child(rig)
		var local := Vector3(0.1,0,-0.6)
		var expected := rig.global_basis*local
		var carrier := parent.global_basis.inverse()*expected
		var before := owner.global_position
		owner.position += carrier
		check((owner.global_position-before).distance_to(expected) < 0.000001, "direct carrier applies exactly one parent conversion")
		check(Transition._carrier_world(owner, carrier).distance_to(expected) < 0.000001, "saved carrier endpoint converts to world")
		var wrong := parent.global_basis*(owner.quaternion*carrier)
		check(wrong.distance_to(expected) > 0.01, "old quaternion multiplication corrupts rotated actor")
		var schedule := Transition._actor_schedule_basis(rig, owner, "skeleton_local")
		check((schedule.basis*local).distance_to(expected) < 0.000001, "skeleton-local schedule includes world scale once")
		check(absf((schedule.basis*local).length()-local.length()*scale_value) < 0.000001, "uniform world scale not omitted or doubled")
		var legacy := Transition._actor_schedule_basis(rig, owner, "root_motion_node_local")
		check((legacy.basis*local).distance_to(owner.global_basis*local) < 0.000001, "historical explicitly labeled owner-local schedule")
		check(Transition._actor_schedule_basis(rig, owner, "").has("error"), "unidentified schedule frame refuses")
		owner.top_level = true
		check(Transition._carrier_world(owner, local).distance_to(local) < 0.000001, "top-level carrier has no parent conversion")
		parent.free()
	print("TRANSLATION_CARRIER_REFERENCE=" + JSON.stringify({"checks":checks,"failures":failures}))
	print("TIER1 PASS" if failures.is_empty() else "TIER1 FAIL")
	quit(0 if failures.is_empty() else 1)
