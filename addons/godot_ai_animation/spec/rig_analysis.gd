@tool
extends RefCounted

## Pure rig analysis: bone-name role detection (with ranked candidates), rest
## pose classification (T/A), capability checks, sample/contact math and
## rig-profile validation.
##
## Nothing here touches a live skeleton or the editor: handlers pass plain bone
## names, rest directions and sampled heights in, so tier-1 can test every rule
## headlessly and rig/motion ops can share one detection implementation.

const PROFILE_FORMAT := "godot-ai-animation-rig-profile"
const PROFILE_VERSION := 1
const PROFILE_DIR := "res://animation_toolkit/rig_profiles"

## Roles the procedural cycles cannot work without.
const CORE_ROLES := ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r"]
## CORE_ROLES plus the feet the gaits plant.
const LOCOMOTION_ROLES := ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]
## Nice-to-have roles: reported when missing, never fatal.
const OPTIONAL_ROLES := [
	"arm_l", "arm_r", "forearm_l", "forearm_r", "shoulder_l", "shoulder_r",
	"head", "chest", "spine", "toe_l", "toe_r", "eye_l", "eye_r",
]

## Ordered sided-bone branches, mirroring how the recipes have always matched
## names: the first branch whose keywords appear wins. `pairs` entries match
## only when every keyword of the pair is present (the forearm case).
const _SIDED_BRANCHES := [
	{"role": "thigh", "keywords": ["thigh", "upperleg", "upleg"]},
	{"role": "shin", "keywords": ["shin", "calf", "lowerleg"]},
	{"role": "forearm", "keywords": ["forearm"], "pairs": [["arm", "fore"]]},
	{"role": "arm", "keywords": ["upperarm"]},
	{"role": "shoulder", "keywords": ["shoulder", "clavicle"]},
	{"role": "arm", "keywords": ["arm"]},
	{"role": "hand", "keywords": ["hand"]},
	{"role": "foot", "keywords": ["foot", "ankle"]},
	{"role": "toe", "keywords": ["toe"]},
	{"role": "eye", "keywords": ["eye", "lid"]},
]

## Chest falls back spine -> torso, and the keyword beats the bone order.
const _CHEST_KEYWORDS := ["chest", "spine", "torso"]
const _CHEST_SCORE_BASE := 100


## `"l"`/`"r"` when a bone name carries a side marker, `""` otherwise.
static func side_of(bone_name: String) -> String:
	var lower := bone_name.to_lower()
	if lower.ends_with(".l") or lower.ends_with("_l") or lower.ends_with("-l") or lower.contains("left"):
		return "l"
	if lower.ends_with(".r") or lower.ends_with("_r") or lower.ends_with("-r") or lower.contains("right"):
		return "r"
	return ""


## Detect bone roles from names alone.
##
## Returns `{roles, candidates, unmatched}`:
##   roles      — {role: best bone name}
##   candidates — {role: [bone names, best first]}
##   unmatched  — bone names no rule recognised
static func detect_roles(bone_names: Array) -> Dictionary:
	var collected := {}
	var unmatched: Array = []
	var chest_matched := {}
	# Chest prefers a bone that says "chest" over spine/torso fallbacks, and
	# within a keyword the first bone in rig order wins (the long-standing rule).
	for keyword_index in _CHEST_KEYWORDS.size():
		var keyword := str(_CHEST_KEYWORDS[keyword_index])
		for index in bone_names.size():
			var lower := str(bone_names[index]).to_lower()
			if not lower.contains(keyword):
				continue
			var score := _CHEST_SCORE_BASE + keyword_index
			_record(collected, "chest", str(bone_names[index]), score, index)
			chest_matched[str(bone_names[index])] = true
			break
	for index in bone_names.size():
		var name := str(bone_names[index])
		var lower := name.to_lower()
		var matched := chest_matched.has(name)
		var side := side_of(lower)
		if not side.is_empty():
			var classified := _classify_sided(lower)
			if not classified.is_empty():
				_record(collected, "%s_%s" % [str(classified.role), side], name,
					int(classified.score), index)
				matched = true
		for role in ["hips", "pelvis"]:
			if lower.contains(role):
				_record(collected, "hips", name, 0 if role == "hips" else 1, index)
				matched = true
				break
		if lower.contains("head"):
			_record(collected, "head", name, 0, index)
			matched = true
		if lower.contains("spine") and not lower.contains("proxy"):
			_record(collected, "spine", name, 0, index)
			matched = true
		if not matched:
			unmatched.append(name)
	var roles := {}
	var candidates := {}
	for role in collected:
		var entries: Array = collected[role]
		entries.sort_custom(func(a, b):
			if int(a.score) != int(b.score):
				return int(a.score) < int(b.score)
			return int(a.index) < int(b.index))
		var names: Array = []
		for entry in entries:
			names.append(str(entry.name))
		candidates[role] = names
		roles[role] = str(names[0])
	return {"roles": roles, "candidates": candidates, "unmatched": unmatched}


static func _classify_sided(lower: String) -> Dictionary:
	for branch_index in _SIDED_BRANCHES.size():
		var branch: Dictionary = _SIDED_BRANCHES[branch_index]
		var keywords: Array = branch.keywords
		for keyword_index in keywords.size():
			if lower.contains(str(keywords[keyword_index])):
				return {"role": str(branch.role), "score": branch_index * 10 + keyword_index}
		var pairs: Array = branch.get("pairs", [])
		for pair_index in pairs.size():
			var pair: Array = pairs[pair_index]
			var all := true
			for keyword in pair:
				if not lower.contains(str(keyword)):
					all = false
					break
			if all:
				return {"role": str(branch.role), "score": branch_index * 10 + keywords.size() + pair_index}
	return {}


static func _record(collected: Dictionary, role: String, name: String, score: int, index: int) -> void:
	if not collected.has(role):
		collected[role] = []
	(collected[role] as Array).append({"name": name, "score": score, "index": index})


## Classify a rest pose from the skeleton-space upper-arm directions per side.
## `T` = arms out horizontally, `A` = angled down (~45 degrees), `arms_down` =
## already hanging, `unknown` = no resolvable arm.
static func arm_pose(arm_directions: Dictionary) -> Dictionary:
	var angles := {}
	var widest := 0.0
	for side in arm_directions:
		var direction: Vector3 = arm_directions[side]
		if direction.length_squared() < 0.000001:
			continue
		var angle := rad_to_deg(Vector3.DOWN.angle_to(direction.normalized()))
		angles[str(side)] = angle
		widest = maxf(widest, angle)
	if angles.is_empty():
		return {"pose": "unknown", "arm_angle_degrees": 0.0, "per_side": {}}
	var kind := "arms_down"
	if widest >= 65.0:
		kind = "T"
	elif widest >= 20.0:
		kind = "A"
	return {"pose": kind, "arm_angle_degrees": widest, "per_side": angles}


## Which ops this rig can run, from the detected roles alone.
static func capabilities(roles: Dictionary, bone_count: int = 0) -> Dictionary:
	var core := true
	for role in CORE_ROLES:
		if not roles.has(role):
			core = false
			break
	var feet := roles.has("foot_l") and roles.has("foot_r")
	var arms := roles.has("arm_l") and roles.has("arm_r")
	var forearms := roles.has("forearm_l") and roles.has("forearm_r")
	var eyes := roles.has("eye_l") or roles.has("eye_r")
	var locomotion := core and feet
	return {
		"idle_cycle": core,
		"walk_cycle": locomotion,
		"run_cycle": locomotion,
		"strafe_cycle": locomotion,
		"jump": locomotion,
		"turn_cycle": locomotion,
		"walk_start": locomotion,
		"walk_stop": locomotion,
		"squat": locomotion,
		"jumping_jack": core and arms,
		"punch": arms and forearms,
		"blink": eyes,
		"secondary_motion": bone_count >= 3,
		"ik_setup": bone_count >= 2,
		"spring_setup": bone_count >= 2,
		"look_at_setup": bone_count >= 2,
	}


## Missing role names, grouped by what they block.
static func missing_roles(roles: Dictionary) -> Dictionary:
	return {
		"core": _missing_from(roles, CORE_ROLES),
		"locomotion": _missing_from(roles, LOCOMOTION_ROLES),
		"optional": _missing_from(roles, OPTIONAL_ROLES),
	}


static func _missing_from(roles: Dictionary, wanted: Array) -> Array:
	var missing: Array = []
	for role in wanted:
		if not roles.has(role):
			missing.append(role)
	return missing


## Bones whose names mark them as part of the torso chain, used to keep a
## spine walk from wandering into the arms or the root bone.
const _TORSO_KEYWORDS := [
	"hips", "pelvis", "spine", "chest", "torso", "abdomen", "belly", "waist",
	"upperchest", "upper_chest", "rib", "neck", "head",
]

## Longest chain the twist distribution will walk. A real torso is at most
## pelvis + a few spine bones + neck + head; the cap is a runaway guard.
const SPINE_CHAIN_MAX := 8


## The torso chain, hips first and head last, for twist distribution.
##
## `parent_of` maps a bone name to its parent bone name (`""` for a root), so
## this stays headless-testable; a caller with a Skeleton3D builds that map from
## `get_bone_parent`. The walk goes *down* from the hips the way a skeleton is
## built (the pelvis is the root of the torso, the spine hangs below it) and
## follows the real parent links, so every name returned is genuinely
## ancestral - a chain of unrelated bones would twist a limb.
##
## Where the head is detected, the walk follows the head's own ancestry exactly,
## which keeps `upperChest`/`neck` intermediates on rigs that have them. Without
## a head (or on a head that is not below the hips) it takes the first child that
## names itself as torso, so odd intermediates still work while arms do not.
static func spine_chain(parent_of: Dictionary, roles: Dictionary, max_bones := SPINE_CHAIN_MAX) -> Array:
	var children := {}
	for bone in parent_of:
		var parent := str(parent_of[bone])
		if parent.is_empty():
			continue
		if not children.has(parent):
			children[parent] = []
		(children[parent] as Array).append(str(bone))
	# depth from each bone up to the head: 0 is the head itself.
	var depth := {}
	var head := str(roles.get("head", ""))
	if not head.is_empty() and parent_of.has(head):
		var walker := head
		var steps := 0
		while not walker.is_empty() and not depth.has(walker):
			depth[walker] = steps
			steps += 1
			if steps > SPINE_CHAIN_MAX + 2:
				break
			walker = str(parent_of.get(walker, ""))
	var start := str(roles.get("hips", ""))
	if start.is_empty() or not parent_of.has(start):
		start = str(roles.get("chest", ""))
	if start.is_empty() or not parent_of.has(start):
		start = str(roles.get("spine", ""))
	if start.is_empty() or not parent_of.has(start):
		return []
	var chain: Array = [start]
	var current := start
	while chain.size() < maxi(1, max_bones):
		if not head.is_empty() and current == head:
			break
		var next := ""
		var best_depth := 1 << 30
		for child in children.get(current, []):
			var name := str(child)
			if chain.has(name):
				continue
			if depth.has(name) and int(depth[name]) < best_depth:
				best_depth = int(depth[name])
				next = name
		if next.is_empty():
			for child in children.get(current, []):
				if _is_torso_bone(str(child)) and not chain.has(str(child)):
					next = str(child)
					break
		if next.is_empty():
			break
		chain.append(next)
		current = next
	return chain


static func _is_torso_bone(bone_name: String) -> bool:
	var lower := bone_name.to_lower()
	for keyword in _TORSO_KEYWORDS:
		if lower.contains(str(keyword)):
			return true
	return false


## Short, actionable next-op hints for an agent that just read a profile.
static func suggestions(roles: Dictionary, caps: Dictionary) -> Array:
	var out: Array = []
	if caps.get("idle_cycle", false) and caps.get("walk_cycle", false) and caps.get("run_cycle", false):
		out.append("animation_motion character_setup - idle + walk + run and a locomotion tree in one call")
	if caps.get("walk_cycle", false):
		out.append("animation_motion walk_cycle (then run_cycle, jump, turn_cycle, strafe_cycle)")
	if caps.get("blink", false):
		out.append("animation_rig blink")
	if caps.get("jumping_jack", false):
		out.append("animation_rig jumping_jack / squat")
	if caps.get("punch", false):
		out.append("animation_rig punch")
	if not caps.get("walk_cycle", false):
		out.append("pass 'roles' (or save this profile and pass 'profile') to cover the missing locomotion bones")
	out.append("animation_inspect sample - FK-verify foot heights and contacts without rendering")
	return out


## `samples` times evenly covering [0, length] (last sample lands exactly on
## the clip end). One sample means time 0.
static func sample_times(length: float, samples: int) -> Array:
	var out: Array = []
	var count := clampi(samples, 1, 240)
	if count == 1:
		return [0.0]
	for index in count:
		out.append(length * float(index) / float(count - 1))
	return out


## Sample times when the caller gave explicit times: validated, clamped and
## capped. Returns `[]` when nothing usable is left.
static func explicit_times(times: Array, length: float, cap: int = 240) -> Array:
	var out: Array = []
	for value in times:
		if out.size() >= cap:
			break
		var time := clampf(float(value), 0.0, length)
		out.append(time)
	return out


## Windows (start/end) where `heights` stays within `threshold` of the lowest
## height: the ground-contact phases of a foot.
static func contact_windows(times: Array, heights: Array, threshold: float = 0.02) -> Array:
	var windows: Array = []
	if times.is_empty() or heights.size() != times.size():
		return windows
	var lowest := INF
	for height in heights:
		lowest = minf(lowest, float(height))
	var start := -1.0
	for index in times.size():
		var contact := float(heights[index]) <= lowest + threshold
		if contact and start < 0.0:
			start = float(times[index])
		elif not contact and start >= 0.0:
			windows.append({"start": start, "end": float(times[index - 1])})
			start = -1.0
	if start >= 0.0:
		windows.append({"start": start, "end": float(times[times.size() - 1])})
	return windows


## Slide of one foot over `times`, from its world positions: how far it travels
## horizontally while it is on the ground, which is the number that separates a
## planted walk from a moonwalk.
##
## A sample counts as planted when it is within `threshold` of `ground_height` -
## the foot's world height at rest, which is what "on the ground" means for a rig.
## Pass `NAN` (or omit it) to fall back to the lowest height in the clip, but a
## swing arc passes through that minimum twice, so the window then covers the
## swing instead of the stance.
##
## The slide of a window is the **net** horizontal displacement from its first to
## its last planted sample, not the accumulated path: a foot that lifts, swings
## and comes back has a long path and no slide, while a foot that creeps across
## the floor has both. `path` (the accumulated travel) is reported alongside for
## the moonwalk case.
##
## The rig's own frame, shared by the generator and the audit so both measure
## height and ground in the same terms: {up, forward, lateral}.
##
## `up` is the SPINE BONE's axis, not a position delta. A bone's local +Y runs
## head->tail, so the spine's +Y is the direction the character stands in - the
## probe on the fixture rig puts it at (0, 0.9997, -0.026), world up to within
## 1.5 degrees. A hips->head POSITION delta is the wrong source: a pelvis is
## offset sideways, so that vector is not even vertical on a real rig. The chain
## order only supplies the SIGN, which is the one thing the axis cannot know,
## because some rigs author bones tail-first.
##
## `forward` comes from heel to toe and `lateral` across the hips, each made
## perpendicular to the others, so a rig with a leaning rest pose still gets an
## orthonormal frame.
static func rig_frame(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var up := _frame_up(skeleton, roles)
	var forward := _frame_forward(skeleton, roles, up)
	return {"up": up, "forward": forward, "lateral": _frame_lateral(skeleton, roles, up, forward)}


## How far the spine axis may lean before it stops counting as "standing along a
## world axis". A bone axis carries the rig's POSE as well as its convention, and
## a real fixture is authored with a small lean - the probe rig's spine rests at
## (0, 0.9997, -0.026), 1.5 degrees off vertical. Inheriting that into every
## procedural clip is a slouch the author never asked for, and the golden
## measures it: 4.8 degrees of shin change on the walk.
##
## So the axis is read for the CONVENTION (which world axis this rig stands
## along) and snapped when it is already within this tolerance. 10 degrees is
## the gap between the two jobs, not a fudge factor: the conventions that matter
## are 90 degrees apart, so anything closer than 10 is a lean, and anything past
## it keeps its true frame.
const UPRIGHT_SNAP_DEG := 10.0


## The direction "down" points, from the spine bone's axis, signed by the
## hips->head chain. Falls back to world UP when there is no spine to read.
static func _frame_up(skeleton: Skeleton3D, roles: Dictionary) -> Vector3:
	var axis := Vector3.ZERO
	for role in ["spine", "chest", "head"]:
		var index := skeleton.find_bone(str(roles.get(role, "")))
		if index >= 0:
			axis = (skeleton.get_bone_global_rest(index).basis * Vector3.UP).normalized()
			break
	if axis.length_squared() < 0.5:
		return Vector3.UP
	var hips := skeleton.find_bone(str(roles.get("hips", "")))
	var head := skeleton.find_bone(str(roles.get("head", "")))
	if hips >= 0 and head >= 0:
		var chain := skeleton.get_bone_global_rest(head).origin \
			- skeleton.get_bone_global_rest(hips).origin
		if chain.length_squared() > 0.000001 and axis.dot(chain) < 0.0:
			axis = -axis
	return _snap_to_axis(axis)


## Heel to toe, made perpendicular to `up`. A foot's own axis is not used: feet
## point forward on a human rig but sideways on a lot of others.
static func _frame_forward(skeleton: Skeleton3D, roles: Dictionary, up: Vector3) -> Vector3:
	for side in ["l", "r"]:
		var foot := skeleton.find_bone(str(roles.get("foot_" + side, "")))
		var toe := skeleton.find_bone(str(roles.get("toe_" + side, "")))
		if foot < 0 or toe < 0:
			continue
		var direction := skeleton.get_bone_global_rest(toe).origin \
			- skeleton.get_bone_global_rest(foot).origin
		direction -= up * direction.dot(up)
		if direction.length_squared() > 0.000001:
			return direction.normalized()
	return _perpendicular(up)


## Across the hips, made perpendicular to both `up` and `forward`.
static func _frame_lateral(skeleton: Skeleton3D, roles: Dictionary, up: Vector3,
		forward: Vector3) -> Vector3:
	var left := skeleton.find_bone(str(roles.get("thigh_l", "")))
	var right := skeleton.find_bone(str(roles.get("thigh_r", "")))
	if left >= 0 and right >= 0:
		var across := skeleton.get_bone_global_rest(left).origin \
			- skeleton.get_bone_global_rest(right).origin
		across -= up * across.dot(up)
		across -= forward * across.dot(forward)
		if across.length_squared() > 0.000001:
			return across.normalized()
	return _perpendicular(up, forward)


## Snaps to the nearest world axis when already within UPRIGHT_SNAP_DEG of one,
## so a rig that merely leans keeps world-UP numbers while a rig that genuinely
## stands along another axis keeps its own.
static func _snap_to_axis(direction: Vector3) -> Vector3:
	var best := Vector3.UP
	var best_dot := -2.0
	for axis in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT,
			Vector3.BACK, Vector3.FORWARD]:
		var dot := direction.dot(axis)
		if dot > best_dot:
			best_dot = dot
			best = axis
	if best_dot >= cos(deg_to_rad(UPRIGHT_SNAP_DEG)):
		return best
	return direction


## Any unit vector perpendicular to `axis`, and to `other` too when given.
static func _perpendicular(axis: Vector3, other: Vector3 = Vector3.ZERO) -> Vector3:
	var direction := axis.cross(Vector3.FORWARD)
	if direction.length_squared() < 0.000001:
		direction = axis.cross(Vector3.RIGHT)
	if direction.length_squared() < 0.000001:
		return Vector3.RIGHT
	direction = direction.normalized()
	if not other.is_zero_approx():
		direction = (direction - other * other.dot(direction)).normalized()
	return direction


## Returns `{windows, worst, mean, path, contact_time, planted_samples}` where
## `worst` is the largest net displacement inside one contact window (metres),
## `mean` the displacement per second of contact, and `contact_time` the total
## planted duration.
##
## `up` is the rig's up, NOT assumed to be world UP. Height is measured along
## it and sliding is measured across it, so a rig that stands along +Z is
## audited on its own floor instead of being read as a character lying on its
## side. The default keeps the world-Y numbers identical for everyone else.
static func foot_slide(times: Array, positions: Array, threshold: float = 0.02,
		ground_height: float = NAN, up: Vector3 = Vector3.UP) -> Dictionary:
	var out := {"windows": [] as Array, "worst": 0.0, "mean": 0.0, "path": 0.0,
		"contact_time": 0.0, "planted_samples": 0}
	if times.is_empty() or positions.size() != times.size():
		return out
	var axis := up.normalized() if up.length_squared() > 0.000001 else Vector3.UP
	var floor_height := ground_height
	if not is_finite(floor_height):
		floor_height = INF
		for position in positions:
			if position is Vector3:
				floor_height = minf(floor_height, (position as Vector3).dot(axis))
	if not is_finite(floor_height):
		return out
	var windows: Array = []
	var start := -1.0
	var anchor := Vector3.ZERO
	var last_planted := Vector3.ZERO
	var path := 0.0
	var total_net := 0.0
	var total_path := 0.0
	var worst := 0.0
	var planted := 0
	var previous_contact := false
	for index in times.size():
		var position: Vector3 = positions[index]
		var time := float(times[index])
		# Symmetric: a foot well BELOW the floor is not in contact either - the
		# one-sided test called any sunk foot planted.
		var contact: bool = absf(position.dot(axis) - floor_height) <= threshold
		if contact:
			planted += 1
			if start < 0.0:
				start = time
				anchor = position
				last_planted = position
				path = 0.0
			else:
				last_planted = position
				if previous_contact and index > 0:
					# The step from the last planted sample, so a fast creep shows up
					# even at a coarse sample rate.
					var previous: Vector3 = positions[index - 1]
					path += _flat_step(previous, position, axis)
		elif start >= 0.0:
			windows.append(_slide_window(times[index - 1], start, anchor, last_planted, path, axis))
			total_net += _flat_distance(anchor, last_planted, axis)
			total_path += path
			worst = maxf(worst, _flat_distance(anchor, last_planted, axis))
			start = -1.0
			path = 0.0
		previous_contact = contact
	if start >= 0.0:
		windows.append(_slide_window(times[times.size() - 1], start, anchor, last_planted, path, axis))
		total_net += _flat_distance(anchor, last_planted, axis)
		total_path += path
		worst = maxf(worst, _flat_distance(anchor, last_planted, axis))
	# Contact time: the span actually spent planted, not `samples x gap`. The
	# old count over-reported by up to a whole sample period (five samples across
	# one second all planted claimed 1.25 s of contact) and skewed `mean` with it.
	var contact_time := 0.0
	if planted > 0 and times.size() > 1:
		for index in times.size():
			var height: float = (positions[index] as Vector3).dot(axis)
			if absf(height - floor_height) > threshold:
				continue
			# Each planted sample owns the gap to the next sample, bounded by the
			# gap to the previous one, so the total can never exceed the clip.
			var next_index := mini(index + 1, times.size() - 1)
			var previous_index := maxi(index - 1, 0)
			var forward := float(times[next_index]) - float(times[index])
			var backward := float(times[index]) - float(times[previous_index])
			contact_time += minf(forward, backward) if index > 0 else forward
	out["windows"] = windows
	out["worst"] = worst
	out["path"] = total_path
	out["planted_samples"] = planted
	out["contact_time"] = contact_time
	out["mean"] = total_net / contact_time if contact_time > 0.0 else 0.0
	return out


static func _slide_window(end: float, start: float, anchor: Vector3, last: Vector3,
		path: float, axis: Vector3) -> Dictionary:
	return {
		"start": start, "end": end,
		"slide": _flat_distance(anchor, last, axis), "path": path,
	}


## Distance between two points measured ACROSS `axis` - the ground plane, not
## world XZ. With world UP that is the old (x, z) length.
static func _flat_distance(a: Vector3, b: Vector3, axis: Vector3 = Vector3.UP) -> float:
	var step := a - b
	if axis.is_equal_approx(Vector3.UP):
		return Vector2(step.x, step.z).length()
	step -= axis * step.dot(axis)
	return step.length()


static func _flat_step(a: Vector3, b: Vector3, axis: Vector3) -> float:
	return _flat_distance(a, b, axis)


## Validate a loaded/saved profile and return its role map.
static func profile_roles(data) -> Dictionary:
	if not data is Dictionary:
		return {"error": "a rig profile must be a JSON object"}
	var profile: Dictionary = data
	if str(profile.get("format", "")) != PROFILE_FORMAT:
		return {"error": "not a %s file" % PROFILE_FORMAT}
	var raw = profile.get("roles", {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {"error": "the profile has no 'roles' section"}
	var roles := {}
	for role in raw:
		var bone := str((raw as Dictionary)[role])
		if bone.is_empty():
			continue
		roles[str(role)] = bone
	if roles.is_empty():
		return {"error": "the profile has no usable roles"}
	return {"roles": roles}
