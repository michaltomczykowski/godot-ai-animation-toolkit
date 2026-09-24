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
## Returns `{windows, worst, mean, path, contact_time, planted_samples}` where
## `worst` is the largest net displacement inside one contact window (metres),
## `mean` the displacement per second of contact, and `contact_time` the total
## planted duration.
static func foot_slide(times: Array, positions: Array, threshold: float = 0.02,
		ground_height: float = NAN) -> Dictionary:
	var out := {"windows": [] as Array, "worst": 0.0, "mean": 0.0, "path": 0.0,
		"contact_time": 0.0, "planted_samples": 0}
	if times.is_empty() or positions.size() != times.size():
		return out
	var floor_height := ground_height
	if not is_finite(floor_height):
		floor_height = INF
		for position in positions:
			if position is Vector3:
				floor_height = minf(floor_height, (position as Vector3).y)
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
		var contact: bool = position.y <= floor_height + threshold
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
					path += Vector2(position.x - previous.x, position.z - previous.z).length()
		elif start >= 0.0:
			windows.append(_slide_window(times[index - 1], start, anchor, last_planted, path))
			total_net += _flat_distance(anchor, last_planted)
			total_path += path
			worst = maxf(worst, _flat_distance(anchor, last_planted))
			start = -1.0
			path = 0.0
		previous_contact = contact
	if start >= 0.0:
		windows.append(_slide_window(times[times.size() - 1], start, anchor, last_planted, path))
		total_net += _flat_distance(anchor, last_planted)
		total_path += path
		worst = maxf(worst, _flat_distance(anchor, last_planted))
	# Contact time: every planted sample owns the average gap to its neighbour,
	# so a coarse sample rate cannot understate how long the foot was down.
	var period := 0.0
	if times.size() > 1:
		period = (float(times[times.size() - 1]) - float(times[0])) / float(times.size() - 1)
	var contact_time := float(planted) * period
	out["windows"] = windows
	out["worst"] = worst
	out["path"] = total_path
	out["planted_samples"] = planted
	out["contact_time"] = contact_time
	out["mean"] = total_net / contact_time if contact_time > 0.0 else 0.0
	return out


static func _slide_window(end: float, start: float, anchor: Vector3, last: Vector3, path: float) -> Dictionary:
	return {
		"start": start, "end": end,
		"slide": _flat_distance(anchor, last), "path": path,
	}


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
