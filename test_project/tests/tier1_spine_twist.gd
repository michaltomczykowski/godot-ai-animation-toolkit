extends SceneTree

## Tier-1 headless checks for the pure spine-twist distributor: the whole point
## is that a requested total means the same thing on any chain, so most of these
## assert the sum rather than individual values.
##
##   godot --headless --path test_project --script res://tests/tier1_spine_twist.gd

const SpineTwist := preload("res://addons/godot_ai_animation/spec/spine_twist.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_normalisation()
	_check_resampling()
	_check_spread()
	_check_clamp()
	_check_counter_weights()
	_check_distribute()
	_check_lags()
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


func _expect_approx(actual: float, expected: float, message: String, tolerance := 0.001) -> void:
	_expect(absf(actual - expected) < tolerance,
		"%s (expected %f, got %f)" % [message, expected, actual])


func _sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


func _check_normalisation() -> void:
	for size in [1, 2, 3, 4, 5, 6]:
		var values: Array = SpineTwist.amplitudes(size, 20.0)
		_expect_eq(values.size(), size, "amplitudes returns one value per chain bone (size %d)" % size)
		_expect_approx(_sum(values), 20.0,
			"a 20 degree twist sums to 20 on a %d-bone chain" % size)
	_expect_approx(_sum(SpineTwist.amplitudes(0, 20.0)), 0.0, "an empty chain asks for nothing")
	_expect_approx(_sum(SpineTwist.amplitudes(4, -15.0)), -15.0, "a negative total keeps its sign")
	# Explicit weights still normalize to the requested total.
	var custom: Array = SpineTwist.amplitudes(4, 30.0, [1.0, 1.0, 2.0, 0.0])
	_expect_approx(_sum(custom), 30.0, "explicit weights sum to the total")
	_expect_approx(float(custom[0]), 7.5, "weights split proportionally (first bone)")
	_expect_approx(float(custom[2]), 15.0, "the heaviest weight takes the most (third bone)")
	_expect_approx(float(custom[3]), 0.0, "a zero weight opts a bone out")


func _check_resampling() -> void:
	# A four-bone profile resampled to six keeps its shape (monotonic-ish ramp).
	var six: Array = SpineTwist.amplitudes(6, 12.0)
	_expect_eq(six.size(), 6, "the profile resamples to the chain length")
	_expect_approx(_sum(six), 12.0, "a resampled profile still sums to the total")
	_expect(float(six[0]) < float(six[2]), "the resampled profile still rises toward the chest")
	# A two-entry profile on a five-bone chain is a linear ramp.
	var ramp: Array = SpineTwist.amplitudes(5, 10.0, [0.0, 1.0])
	_expect_approx(_sum(ramp), 10.0, "a two-entry ramp sums to the total")
	_expect_approx(float(ramp[0]), 0.0, "a ramp starts at zero")
	_expect_approx(float(ramp[1]), float(ramp[4]) / 4.0, "a ramp is linear (second of five)")
	_expect_true(float(ramp[4]) > float(ramp[3]), "a ramp rises toward the top of the chain")
	# A single weight repeats rather than collapsing.
	var flat: Array = SpineTwist.amplitudes(3, 9.0, [1.0])
	_expect_approx(float(flat[0]), 3.0, "a single weight splits evenly (first)")
	_expect_approx(float(flat[2]), 3.0, "a single weight splits evenly (last)")


func _check_spread() -> void:
	var full: Array = SpineTwist.amplitudes(4, 20.0)
	var none_up: Array = SpineTwist.amplitudes(4, 20.0, [], 0.0)
	_expect_approx(float(none_up[0]), 20.0, "spread 0 keeps the whole twist on the root")
	var rest_of_chain := 0.0
	for index in range(1, none_up.size()):
		rest_of_chain += float(none_up[index])
	_expect_approx(rest_of_chain, 0.0, "spread 0 leaves the rest of the chain still")
	_expect_approx(float(full[0]), float(none_up[0]) * 0.2, "the default profile gives the root a fifth")
	var half: Array = SpineTwist.amplitudes(4, 20.0, [], 0.5)
	_expect_approx(_sum(half), 20.0, "a partial spread still sums to the total")
	_expect(float(half[0]) > float(half[3]), "a partial spread keeps more twist low on the chain")
	var over: Array = SpineTwist.amplitudes(4, 20.0, [], 4.0)
	_expect_approx(_sum(over), 20.0, "spread is clamped, not extrapolated")


func _check_clamp() -> void:
	var clamped: Array = SpineTwist.amplitudes(4, 80.0, [0.1, 0.1, 0.7, 0.1], 1.0, 25.0)
	for index in clamped.size():
		_expect(absf(float(clamped[index])) <= 25.0 + 0.001,
			"bone %d respects the 25 degree clamp (%f)" % [index, float(clamped[index])])
	_expect(float(clamped[2]) > 24.0, "the clamp is reached by the heavy bone")
	var no_clamp: Array = SpineTwist.amplitudes(4, 80.0)
	_expect(float(no_clamp[2]) > 25.0, "without a clamp the heavy bone can take more")
	# The clamp is what stops a chain corkscrewing, so prove the bound holds for a
	# multi-step turn too: two 90 degree steps with a 30 degree cap per bone.
	var per_bone := 0.0
	for _step in 2:
		per_bone += absf(float(SpineTwist.amplitudes(4, 90.0, [0.6, 0.8, 0.4, -0.2], 1.0, 30.0)[1]))
	_expect(per_bone <= 60.0 + 0.001,
		"two steps of a 30 degree capped bone stay within 60 degrees (%f)" % per_bone)


func _check_counter_weights() -> void:
	# A hips-leads / chest-counter profile cancels out, so the sum is normalized
	# by magnitude and every bone still gets a usable value.
	var counter: Array = SpineTwist.amplitudes(4, 20.0, [0.45, -0.3, -0.4, 0.25])
	_expect(float(counter[0]) > 0.0, "a positive weight turns one way")
	_expect(float(counter[2]) < 0.0, "a negative weight turns the other way")
	_expect_true(absf(float(counter[1])) > 0.0, "a counter bone is not silently dropped")
	_expect_approx(_sum(counter), 0.0, "a cancelling profile nets to zero (as authored)")
	# Normalizing by magnitude keeps the hips at their authored share.
	_expect_approx(float(counter[0]) + float(counter[1]) + float(counter[2]) + float(counter[3]), 0.0,
		"the counter profile is self cancelling")
	# A hips-leads profile has a negative signed sum. The old near-zero guard was
	# a signed comparison, so it replaced that divisor with 1.0 and every share
	# came out at full weight - a torso counter-rotating as hard as the hips
	# lead. Normalising by magnitude keeps the authored signs and the scale.
	var leading: Array = SpineTwist.amplitudes(4, 8.0, [0.0, -1.0, -1.0, 0.5])
	_expect(float(leading[1]) < 0.0, "the counter bone still turns the other way (%f)" % float(leading[1]))
	_expect(float(leading[3]) > 0.0, "the stabilising head comes back the first way")
	_expect_approx(float(leading[1]), -3.2,
		"a -1 weight out of a 2.5 magnitude is -0.4 of the request (got %f)" % float(leading[1]))
	_expect_approx(float(leading[3]), 1.6,
		"the head's +0.5 weight is +0.2 of the request (got %f)" % float(leading[3]))
	var scaled: Array = SpineTwist.amplitudes(4, 16.0, [0.0, -1.0, -1.0, 0.5])
	_expect_approx(float(scaled[1]), float(leading[1]) * 2.0, "doubling the request doubles the shares")
	# A positive-sum profile still divides by its own sum, so it adds up exactly.
	var balanced: Array = SpineTwist.amplitudes(4, 10.0, [0.4, 0.3, -0.2, -0.1])
	_expect(float(balanced[0]) > 0.0, "a positive profile keeps its leading sign")
	_expect(float(balanced[2]) < 0.0, "and its counter sign")
	_expect_approx(_sum(balanced), 10.0,
		"a positive-sum profile sums to the request (got %f)" % _sum(balanced))


func _check_distribute() -> void:
	var chain: Array = ["B-hips", "B-spine", "B-chest", "B-head"]
	var degrees: Dictionary = SpineTwist.distribute(chain, 16.0)
	_expect_eq(degrees.size(), 4, "one degree value per named bone")
	_expect_approx(_sum(degrees.values()), 16.0, "named bones sum to the requested total")
	var above_root := 0.0
	for bone in ["B-spine", "B-chest", "B-head"]:
		above_root += float(degrees[bone])
	_expect_true(above_root > float(degrees["B-hips"]),
		"the twist is shared up the chain, not dumped on the hips")
	_expect_true(float(degrees["B-chest"]) >= float(degrees["B-spine"]),
		"the chest carries at least as much as the spine")
	_expect_eq(SpineTwist.distribute([], 10.0).size(), 0, "an empty chain maps to nothing")
	# A rig with no separate spine bone still distributes.
	var short_chain: Array = ["B-hips", "B-chest", "B-head"]
	var short_degrees: Dictionary = SpineTwist.distribute(short_chain, 12.0)
	_expect_eq(short_degrees.size(), 3, "a three-bone chain maps to three bones")
	_expect_approx(_sum(short_degrees.values()), 12.0, "the three-bone chain sums to the total")


func _check_lags() -> void:
	var values: Array = SpineTwist.lags(4, 0.0, 0.2)
	_expect_eq(values.size(), 4, "one lag per chain bone")
	_expect_approx(float(values[0]), 0.0, "the root leads with no lag")
	_expect_approx(float(values[3]), 0.2, "the top of the chain takes the full lag")
	_expect_true(float(values[1]) < float(values[2]), "lag increases up the chain")
	_expect_eq(SpineTwist.lags(1, 0.05, 0.3).size(), 1, "a single-bone chain still has a lag")
	_expect_approx(float(SpineTwist.lags(1, 0.05, 0.3)[0]), 0.05, "a single-bone chain keeps its own lag")
	_expect_eq(SpineTwist.lags(0).size(), 0, "an empty chain has no lags")


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_true(condition: bool, message: String) -> void:
	_expect(condition, message)
