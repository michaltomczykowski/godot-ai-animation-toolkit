@tool
extends RefCounted

## Pure spine-twist distribution.
##
## Recipes used to hard-code how much of a torso twist each spine bone took, and
## the sum of those factors was neither 1 nor configurable: the idle alone wound
## the torso up to 2.45x the requested `twist`, because the chest was keyed at
## 1.0x plus a 0.3x harmonic while the spine took 0.5x plus 0.15x. On a T-pose
## rest that reads as a spinning spine.
##
## This module makes the split explicit and rig-independent:
##
## - `amplitudes()` returns one signed degree value per chain bone whose sum is
##   the requested total, whatever the chain length, so a parameter means the
##   same thing on a 3-bone and a 6-bone rig.
## - Weights are resampled to the chain length, so callers can pass a profile
##   for one shape and get a sensible one for any other.
## - Negative weights are allowed (a head that stabilises while the hips lead),
##   and `clamp_degrees` caps what any single bone may take, which is the
##   structural guard against a chain corkscrewing.
##
## Pure math: no scene, no Skeleton3D, so tier-1 can cover it headlessly.


## hips, spine, chest, head: the hips take a little, the chest carries the most,
## and the head keeps a small share so it still participates in the twist.
const DEFAULT_WEIGHTS := [0.20, 0.30, 0.35, 0.15]

## Below this, a weights array is treated as cancelling out and is normalized by
## magnitude instead, so a hips-leads/chest-counterrides profile stays usable
## (and keeps the signs its weights asked for).
const _SIGNED_SUM_FLOOR := 0.05


## One signed degree value per chain bone, summing to `total_degrees` (up to the
## clamp). `chain_size` is the number of bones in the spine chain.
static func amplitudes(
	chain_size: int, total_degrees: float, weights: Array = [], spread := 1.0,
	clamp_degrees := 0.0,
) -> Array:
	var out: Array = []
	if chain_size <= 0:
		return out
	var profile := _resample(weights if not weights.is_empty() else DEFAULT_WEIGHTS, chain_size)
	# spread 0 keeps the whole twist on the root bone, spread 1 uses the profile.
	# The blend target is "root only" (1 on the root, 0 above it), not a flat
	# profile - blending towards a flat shape would still spread the twist.
	var keep := clampf(spread, 0.0, 1.0)
	for index in chain_size:
		var root_only := 1.0 if index == 0 else 0.0
		profile[index] = lerpf(root_only, float(profile[index]), keep)
	var signed_sum := 0.0
	var magnitude := 0.0
	for value in profile:
		signed_sum += float(value)
		magnitude += absf(float(value))
	# The divisor normalises the shares to the request, and it must never turn a
	# sign upside down: a counter-rotation profile (hips lead, torso counters) has
	# a NEGATIVE signed sum, and dividing by it flipped every bone's direction.
	# A positive sum divides by itself so the shares add up to the request; a sum
	# that is too small (or negative) divides by magnitude, which keeps the
	# authored signs and nets below the request - the same rule a cancelling
	# profile has always used. The near-zero guard used to be a signed
	# comparison, so it replaced every negative divisor with 1.0 and a hips-led
	# counter-rotation came out with several times the requested twist.
	var divisor := signed_sum if signed_sum >= _SIGNED_SUM_FLOOR else magnitude
	if absf(divisor) < 0.000001:
		divisor = 1.0
	var limit := absf(clamp_degrees)
	for value in profile:
		var degrees := float(value) / divisor * total_degrees
		if limit > 0.0:
			degrees = clampf(degrees, -limit, limit)
		out.append(degrees)
	return out


## `amplitudes()` mapped onto bone names, for callers that just want degrees per
## bone. Chains with a repeated or empty bone name collapse onto the last entry.
static func distribute(
	chain: Array, total_degrees: float, weights: Array = [], spread := 1.0,
	clamp_degrees := 0.0,
) -> Dictionary:
	var out: Dictionary = {}
	if chain.is_empty():
		return out
	var values := amplitudes(chain.size(), total_degrees, weights, spread, clamp_degrees)
	for index in chain.size():
		out[str(chain[index])] = float(values[index])
	return out


## Per-bone sample lag (0..1 of a cycle) for follow-through: the root leads and
## each bone up the chain trails a little more. `base_lag` is the root's lag.
static func lags(chain_size: int, base_lag := 0.0, total_lag := 0.0) -> Array:
	var out: Array = []
	if chain_size <= 0:
		return out
	if chain_size == 1:
		return [base_lag]
	for index in chain_size:
		var position := float(index) / float(chain_size - 1)
		out.append(base_lag + (total_lag - base_lag) * position)
	return out


## Linear resample of a weight profile to `count` entries, so a profile authored
## for one chain shape still works on another. A single entry repeats.
static func _resample(weights: Array, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var source: Array = weights if not weights.is_empty() else DEFAULT_WEIGHTS
	if count == 1:
		return [float(source[0])]
	if source.size() == 1:
		for index in count:
			out.append(float(source[0]))
		return out
	if source.is_empty():
		for index in count:
			out.append(1.0)
		return out
	for index in count:
		var position := float(index) / float(count - 1) * float(source.size() - 1)
		var lower := mini(int(floor(position)), source.size() - 1)
		var upper := mini(lower + 1, source.size() - 1)
		var blend := position - float(lower)
		out.append(lerpf(float(source[lower]), float(source[upper]), blend))
	return out
