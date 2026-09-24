extends SceneTree

## Tier-1 headless checks for the pose solver: rest-relative forward kinematics
## and the analytic two-bone aim solve (reach, pole, base-bend, clamping).
##
##   godot --headless --path test_project --script res://tests/tier1_pose_solver.gd

const PoseSolver := preload("res://addons/godot_ai_animation/spec/pose_solver.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_fk()
	_check_reach()
	_check_pole()
	_check_base_bend()
	_check_clamping()
	_check_validation()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_vec(actual: Vector3, expected: Vector3, message: String, tolerance := 0.001) -> void:
	_expect(actual.distance_to(expected) < tolerance,
		"%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_approx(actual: float, expected: float, message: String, tolerance := 0.001) -> void:
	_expect(absf(actual - expected) < tolerance, "%s (expected %s, got %s)" % [message, expected, actual])


## A three-bone chain hanging down from (0, 1.5, 0): upper (0.3), forearm (0.3),
## hand (0.1 beyond the wrist is not part of the solve).
func _chain() -> Array:
	var down := Basis(Vector3.RIGHT, PI)
	return [
		Transform3D(down, Vector3(0.0, 1.5, 0.0)),
		Transform3D(down, Vector3(0.0, 1.2, 0.0)),
		Transform3D(down, Vector3(0.0, 0.9, 0.0)),
	]


func _deltas() -> Array:
	return [Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY]


func _check_fk() -> void:
	var rest := _chain()
	var posed := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, _deltas())
	_expect_eq(posed.size(), 3, "fk returns one transform per bone")
	_expect_vec((posed[0] as Transform3D).origin, Vector3(0, 1.5, 0), "identity deltas keep the root rest")
	_expect_vec((posed[2] as Transform3D).origin, Vector3(0, 0.9, 0), "identity deltas keep the effector rest")
	var rotated := _deltas()
	rotated[0] = Quaternion(Vector3.UP, deg_to_rad(90.0))
	var swung := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, rotated)
	# The upper bone (pointing down) rotates 90 degrees about Y: down stays down,
	# but the child offsets swing in the XZ plane.
	_expect_vec((swung[0] as Transform3D).origin, Vector3(0, 1.5, 0), "the root origin does not move under rotation")
	_expect_vec((swung[1] as Transform3D).origin, Vector3(0.0, 1.2, 0.0), "a Y rotation of a down bone keeps the offset")
	var lifted := _deltas()
	lifted[0] = Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))
	var bent := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, lifted)
	# Rotating the down-pointing upper bone -90 about X swings the elbow forward.
	_expect((bent[1] as Transform3D).origin.z > 0.25,
		"rotating the root forward moves the elbow forward (%s)" % str((bent[1] as Transform3D).origin))
	var parent_shift := Transform3D(Basis.IDENTITY, Vector3(0.5, 0.0, 0.0))
	var shifted := PoseSolver.fk_chain(rest, parent_shift, _deltas())
	_expect_vec((shifted[0] as Transform3D).origin, Vector3(0.5, 1.5, 0.0), "parent_delta translates the chain")


func _check_reach() -> void:
	var rest := _chain()
	var target := Vector3(0.0, 1.5, 0.5)
	var solved := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), target)
	_expect(not solved.has("error"), "a reachable target solves")
	if solved.has("error"):
		return
	_expect_eq(solved.rotations.size(), 3, "the solve returns a delta per bone")
	var posed := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, solved.rotations)
	_expect_vec((posed[2] as Transform3D).origin, target, "the effector lands on the target")
	_expect(not bool(solved.clamped), "a reachable target is not clamped")
	_expect_approx(float(solved.reach), 0.5, "the reach reports the target distance")
	var kept := solved.rotations[2] as Quaternion
	_expect(kept.is_equal_approx(Quaternion.IDENTITY), "the end bone keeps its base delta")


func _check_pole() -> void:
	var rest := _chain()
	var target := Vector3(0.0, 1.5, 0.5)
	var down := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), target, Vector3(0, -1, 0))
	_expect(not down.has("error"), "a pole hint solves")
	if not down.has("error"):
		_expect(float((down.elbow as Vector3).y) < 1.49,
			"the elbow bends into the pole half-plane (%s)" % str(down.elbow))
	var up := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), target, Vector3(0, 1, 0))
	_expect(not up.has("error"), "the opposite pole solves")
	if not up.has("error"):
		_expect(float((up.elbow as Vector3).y) > 1.51,
			"the opposite pole flips the elbow (%s)" % str(up.elbow))


func _check_base_bend() -> void:
	# A bent base pose (forearm folded back) steers the elbow without a pole hint.
	var rest := _chain()
	var folded := _deltas()
	folded[1] = Quaternion(Vector3.RIGHT, deg_to_rad(-60.0))
	var target := Vector3(0.0, 1.5, 0.5)
	var solved := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, folded, target)
	_expect(not solved.has("error"), "a target solves from a bent base pose")
	if solved.has("error"):
		return
	var posed := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, solved.rotations)
	_expect_vec((posed[2] as Transform3D).origin, target, "the effector lands on the target from a bent base")
	_expect((solved.elbow as Vector3).y < 1.5, "the elbow keeps the base bend side (%s)" % str(solved.elbow))


func _check_clamping() -> void:
	var rest := _chain()
	var far := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), Vector3(0.0, 1.5, 2.0), Vector3(0, 0, -1))
	_expect(not far.has("error"), "a far target still solves")
	if not far.has("error"):
		_expect(bool(far.clamped), "a far target is clamped")
		var posed := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, far.rotations)
		var reach: float = (posed[2] as Transform3D).origin.distance_to(Vector3(0, 1.5, 0))
		_expect_approx(reach, 0.5995, "the clamped reach stops just inside full extension", 0.002)
		_expect((posed[2] as Transform3D).origin.z < 2.0, "the effector falls short of a far target")
	var near := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), Vector3(0.0, 1.5, 0.0002))
	_expect(not near.has("error"), "a very close target still solves")
	if not near.has("error"):
		_expect(bool(near.clamped), "a too-close target is clamped")
		var posed := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, near.rotations)
		_expect((posed[2] as Transform3D).origin.z > 0.0, "the effector stays in front of the root")
	var folded := PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(), Vector3(0.0, 1.5, 0.05))
	_expect(not folded.has("error"), "a folded-arm target solves")
	if not folded.has("error"):
		_expect(not bool(folded.clamped), "a folded-arm target is not clamped")
		var posed_folded := PoseSolver.fk_chain(rest, Transform3D.IDENTITY, folded.rotations)
		_expect_vec((posed_folded[2] as Transform3D).origin, Vector3(0, 1.5, 0.05),
			"the folded arm still lands on the target")


func _check_validation() -> void:
	var rest := _chain()
	var two := [rest[0], rest[1]]
	_expect(PoseSolver.solve_chain(two, Transform3D.IDENTITY, [Quaternion.IDENTITY, Quaternion.IDENTITY],
		Vector3(0, 1, 0.5)).has("error"), "a two-bone chain is refused (needs root/mid/end)")
	_expect(PoseSolver.solve_chain(rest, Transform3D.IDENTITY, [Quaternion.IDENTITY],
		Vector3(0, 1, 0.5)).has("error"), "missing base deltas are refused")
	_expect(PoseSolver.solve_chain(rest, Transform3D.IDENTITY, _deltas(),
		Vector3(0, 1.5, 0)).has("error"), "a target on the chain root is refused")
	var zero := _chain()
	zero[1] = Transform3D((zero[1] as Transform3D).basis, (zero[0] as Transform3D).origin)
	_expect(PoseSolver.solve_chain(zero, Transform3D.IDENTITY, _deltas(),
		Vector3(0, 1.5, 0.5)).has("error"), "zero-length bones are refused")


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
