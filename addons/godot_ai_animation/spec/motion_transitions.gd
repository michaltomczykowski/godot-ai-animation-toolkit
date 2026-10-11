@tool
extends RefCounted

const Reference := preload("res://addons/godot_ai_animation/spec/motion_transition_reference.gd")
const Specs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
const Drivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")

static func _refusal(reason: String) -> Dictionary:
	return {"keys": {}, "meta": {"reach_error": reason}}

static func _root_distance(time: float, length: float, window: float, speed: float, stopping: bool) -> float:
	var middle := length - 2.0 * window
	var t := clampf(time, 0.0, length)
	if stopping:
		if t <= window: return speed * t
		if t >= length - window: return 0.5 * speed * length
		var u := (t - window) / middle
		return speed * (window + middle * (u - u * u * u + 0.5 * u * u * u * u))
	if t <= window: return 0.0
	if t >= length - window: return speed * (0.5 * middle + t - (length - window))
	var u := (t - window) / middle
	return speed * middle * (u * u * u - 0.5 * u * u * u * u)

static func _hermite(a: Vector3, b: Vector3, va: Vector3, vb: Vector3, time: float, span: float) -> Vector3:
	var u := clampf(time, 0.0, 1.0)
	return a * (2.0 * u * u * u - 3.0 * u * u + 1.0) + b * (-2.0 * u * u * u + 3.0 * u * u) \
		+ va * span * (u * u * u - 2.0 * u * u + u) + vb * span * (u * u * u - u * u)

static func _swing(plan: Dictionary, time: float, up: Vector3, clearance: float, band: float) -> Vector3:
	var a: Vector3 = plan.a
	var b: Vector3 = plan.b
	if time <= float(plan.begin): return a
	if time >= float(plan.end): return b
	var span := float(plan.end) - float(plan.begin)
	var u := (time - float(plan.begin)) / span
	var va: Vector3 = plan.va
	var vb: Vector3 = plan.vb
	var ground: float = plan.ground
	var a_air := a.dot(up) - ground > band or (va - up * va.dot(up)).length() > 0.001
	var b_air := b.dot(up) - ground > band or (vb - up * vb.dot(up)).length() > 0.001
	var begin := 0.0 if a_air else 0.2
	var end := 1.0 if b_air else 0.8
	var travel := clampf((u - begin) / (end - begin), 0.0, 1.0)
	var horizontal := _hermite(a - up * a.dot(up), b - up * b.dot(up),
		va - up * va.dot(up), vb - up * vb.dot(up), travel, span * (end - begin))
	var vertical := _hermite(up * a.dot(up), up * b.dot(up), up * va.dot(up), up * vb.dot(up), u, span)
	var lift := 16.0 * u * u * (1.0 - u) * (1.0 - u) * clearance
	return horizontal + vertical + up * lift

static func _walk_foot(ctx: Dictionary, reference: Dictionary, side: String, time: float) -> Transform3D:
	return Reference.global_pose(reference.rest, Reference.sample(reference, time), str(ctx.legs[side].foot), {})

static func _contacts(phase: float, length: float, window: float, period: float, stance: float,
		stopping: bool, plans: Dictionary, support: String) -> Array:
	var result: Array = []
	for side in ["l", "r"]:
		var intervals: Array = []
		var idle_begin := length - window if stopping else 0.0
		intervals.append({"start": idle_begin, "end": idle_begin + window, "source": "idle reference"})
		var plan: Dictionary = plans[side]
		if not stopping or side == support:
			intervals.append({"start": window, "end": float(plan.begin), "source": "planned support"})
		intervals.append({"start": float(plan.end), "end": length - window, "source": "planned landing"})
		var begin := 0.0 if stopping else length - window
		var end := window if stopping else length
		var clock_offset := phase * period - (0.0 if stopping else length) + (0.0 if side == "l" else 0.5 * period)
		var cuts: Array[float] = [begin, end]
		for cycle in range(floori((begin + clock_offset) / period) - 1, ceili((end + clock_offset) / period) + 2):
			for event in [0.0, stance]:
				var at: float = (cycle + event) * period - clock_offset
				if at > begin + 0.000001 and at < end - 0.000001: cuts.append(at)
		cuts.sort()
		for i in cuts.size() - 1:
			var mid := 0.5 * (cuts[i] + cuts[i + 1])
			if fposmod((mid + clock_offset) / period, 1.0) < stance:
				intervals.append({"start": cuts[i], "end": cuts[i + 1], "source": "walk reference"})
		intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.start) < float(b.start))
		var merged: Array = []
		for interval: Dictionary in intervals:
			if float(interval.end) - float(interval.start) <= 0.000001: continue
			if not merged.is_empty() and float(interval.start) <= float(merged[-1].end) + 0.000001:
				merged[-1].end = maxf(float(merged[-1].end), float(interval.end))
				merged[-1].source = "planned/reference support"
			else:
				interval["side"] = side
				merged.append(interval)
		result.append_array(merged)
	return result

static func _markers(contacts: Array, length: float) -> Array:
	var markers: Array = [{"name": "settled", "time": length}]
	var counts := {"l": 0, "r": 0}
	for contact: Dictionary in contacts:
		var side := str(contact.side)
		var suffix := "%s.%d" % [side.to_upper(), counts[side]]
		counts[side] += 1
		var events: Array = [{"name": "contact." + suffix, "time": float(contact.start)}]
		# Terminal support continues into idle/gait. Ending the action is not a
		# toe-off, and Godot stores only one marker at an exact time.
		if float(contact.end) < length - 0.000001:
			events.append({"name": "toe_off." + suffix, "time": float(contact.end)})
		for event: Dictionary in events:
			var existing := -1
			for i in markers.size():
				if absf(float(markers[i].time) - float(event.time)) < 0.000001: existing = i
			if existing >= 0: markers[existing].name += "+" + str(event.name)
			else: markers.append(event)
	return markers

static func build(ctx: Dictionary, stopping: bool, gait: Dictionary, idle: Dictionary) -> Dictionary:
	var length := float(ctx.length)
	var period := float(gait.length)
	var phase := float(ctx.phase)
	var window := minf(0.2, 0.2 * length)
	var middle := length - 2.0 * window
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var speed := float(gait.meta.speed)
	var leg_length := Specs.measured_leg(ctx)
	var clearance := float(ctx.config.foot_lift)
	if not bool(ctx.get("foot_lift_explicit", false)): clearance = maxf(clearance, 0.04 * leg_length)
	var walk_ref := Reference.build(gait)
	var idle_ref := Reference.build(idle)
	var rest: Dictionary = (gait.ctx.rest as Dictionary).duplicate()
	rest.merge(idle.ctx.rest, true)
	var handover := window if stopping else length - window
	var gait_time := phase * period + handover - (0.0 if stopping else length)
	var root_end := forward * (0.5 * speed * length)
	var root_handover := forward * _root_distance(handover, length, window, speed, stopping)
	var stance := float(gait.config.stance)
	var support := ""
	var remaining := -1.0
	for side in ["l", "r"]:
		var p := fposmod(gait_time / period + (0.0 if side == "l" else 0.5), 1.0)
		if p < stance and stance - p > remaining:
			remaining = stance - p
			support = side
	if support.is_empty(): return _refusal("Transition handover has no stance foot; increase the walk stance fraction or change phase")
	var plans := {}
	for side in ["l", "r"]:
		var foot := _walk_foot(ctx, walk_ref, side, gait_time)
		var epsilon := 1.0 / 1200.0
		var velocity := (_walk_foot(ctx, walk_ref, side, gait_time + epsilon).origin - _walk_foot(ctx, walk_ref, side, gait_time - epsilon).origin) / (2.0 * epsilon) + forward * speed
		var standing := Reference.global_pose(rest, Reference.sample(idle_ref, 0.0), str(ctx.legs[side].foot), {}).origin
		var first: bool = side != support if stopping else side == support
		plans[side] = {"a": foot.origin + root_handover if stopping else standing,
			"b": standing + root_end if stopping else foot.origin + root_handover,
			"va": velocity if stopping and first else Vector3.ZERO,
			"vb": velocity if not stopping and not first else Vector3.ZERO,
			"begin": window if first else window + 0.55 * middle,
			"end": window + 0.48 * middle if first else length - window,
			"ground": (ctx.legs[side].ankle as Vector3).dot(up)}
	var samples: Array = []
	var drop_amplitude := 0.0
	var times := Drivers.sample_times(length, float(ctx.samples))
	for time_value in times:
		var time := float(time_value)
		var u := clampf((time - window) / middle, 0.0, 1.0)
		var weight := Drivers.smoothstep(u)
		if stopping: weight = 1.0 - weight
		var walk_channels := Reference.sample(walk_ref, phase * period + time - (0.0 if stopping else length))
		var idle_channels := Reference.sample(idle_ref, time - (length if stopping else 0.0))
		var channels := Reference.blend(idle_channels, walk_channels, weight)
		var root_at := forward * _root_distance(time, length, window, speed, stopping)
		var globals := {}
		var targets := {}
		var orientations := {}
		var envelope := sin(PI * u) * sin(PI * u)
		var interior := time > window + 0.000001 and time < length - window - 0.000001
		if interior:
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				var target := _swing(plans[side], time, up, clearance, 0.01 * leg_length) - root_at
				targets[side] = target
				var hip := Reference.global_pose(rest, channels, str(leg.thigh), globals).origin
				var offset := target - hip
				var horizontal := (offset - up * offset.dot(up)).length()
				var reach := float(leg.upper) + float(leg.lower) - 0.001 - 0.00005 * leg_length
				if horizontal >= reach: return _refusal("Transition step exceeds horizontal leg reach; shorten duration or lower reference speed")
				var available := sqrt(maxf(reach * reach - horizontal * horizontal, 0.0))
				var needed := maxf(0.0, -offset.dot(up) - available)
				drop_amplitude = maxf(drop_amplitude, needed / maxf(envelope, 0.000001))
				var walk_basis := Reference.global_pose(rest, walk_channels, str(leg.foot), {}).basis.get_rotation_quaternion()
				var idle_basis := Reference.global_pose(rest, idle_channels, str(leg.foot), {}).basis.get_rotation_quaternion()
				orientations[side] = Basis(idle_basis.slerp(walk_basis, weight).normalized())
		samples.append({"time": time, "channels": channels, "root": root_at, "targets": targets,
			"orientations": orientations, "envelope": envelope, "interior": interior})
	if drop_amplitude > 0.18 * leg_length:
		return _refusal("Transition support transfer needs %.3f m extra pelvis drop (limit %.3f m); shorten duration or lower reference speed" % [drop_amplitude, 0.18 * leg_length])
	var keys := {}
	var actor_keys: Array = []
	var clamped := bool(gait.meta.get("clamped", false)) or bool(idle.meta.get("clamped", false))
	var shortfall := maxf(float(gait.meta.get("clamp_shortfall_m", 0.0)), float(idle.meta.get("clamp_shortfall_m", 0.0)))
	var evaluated := 0
	var clamps := 0
	for sample: Dictionary in samples:
		var channels: Dictionary = sample.channels
		var time := float(sample.time)
		if sample.interior:
			var hips := str(ctx.hips)
			channels[hips]["position"] = (channels[hips].get("position", Vector3.ZERO) as Vector3) - (ctx.hips_parent_basis as Basis).inverse() * up * drop_amplitude * float(sample.envelope)
			var cache := {}
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				var hip := Reference.global_pose(rest, channels, str(leg.thigh), cache).origin
				var solved := Drivers.solve_leg(hip, sample.targets[side], float(leg.upper), float(leg.lower), Specs._rest_bend(ctx, leg, forward))
				evaluated += 1
				if solved.clamped:
					clamped = true
					clamps += 1
					shortfall = maxf(shortfall, float(solved.shortfall))
				var parent := str(rest[str(leg.thigh)].parent)
				var parent_basis := Reference.global_pose(rest, channels, parent, cache).basis
				var parent_rest: Basis = rest[parent].global if not parent.is_empty() else Basis.IDENTITY
				var thigh := Drivers.aim_delta(parent_basis, parent_rest, Specs._rest_basis(ctx, str(leg.thigh)), (solved.knee - hip).normalized(), leg.knee - leg.hip)
				var shin := Drivers.aim_delta(thigh.global, Specs._rest_basis(ctx, str(leg.thigh)), Specs._rest_basis(ctx, str(leg.shin)), (solved.effective_ankle - solved.knee).normalized(), leg.ankle - leg.knee)
				channels[str(leg.thigh)]["rotation"] = thigh.delta
				channels[str(leg.shin)]["rotation"] = shin.delta
				channels[str(leg.foot)]["rotation"] = Drivers.hold_global_delta(shin.global, Specs._rest_basis(ctx, str(leg.shin)), Specs._rest_basis(ctx, str(leg.foot)), sample.orientations[side])
		for bone in channels:
			if channels[bone].has("rotation"): Specs._append_rotation(keys, bone, time, channels[bone].rotation)
			if channels[bone].has("position"): Specs._append_position(keys, bone, time, channels[bone].position)
		if bool(ctx.root_motion): Specs._append_position(keys, "__root_motion__", time, sample.root)
		var at: Vector3 = sample.root
		actor_keys.append({"time": time, "offset": [at.x, at.y, at.z]})
	if clamped: return _refusal("Transition leg solve exceeded reachable geometry by %.6f m; shorten duration or lower reference speed" % shortfall)
	Specs._mark_one_shot(keys)
	var contacts := _contacts(phase, length, window, period, stance, stopping, plans, support)
	return {"keys": keys, "markers": _markers(contacts, length), "meta": {
		"phase": phase, "speed": speed, "clamped": clamped, "clamp_shortfall_m": shortfall,
		"clamped_leg_samples": clamps, "evaluated_leg_samples": evaluated, "reach_evaluated": evaluated > 0,
		"gait_reference_clamped": bool(gait.meta.get("clamped", false)), "idle_reference_clamped": bool(idle.meta.get("clamped", false)),
		"gait_reference_period_s": period, "gait_reference_samples": float(gait.rate),
		"idle_reference_period_s": float(idle.length), "idle_reference_samples": float(idle.rate),
		"step_lift_used_m": clearance, "gait_foot_lift_used_m": float(gait.ctx.get("foot_lift_scaled", 0.05)),
		"pelvis_reach_drop_m": drop_amplitude, "reference_window_s": window, "handover_support": support,
		"declared_contacts": contacts,
		"actor_translation_keys": actor_keys, "actor_translation_space": "root_motion_node_local",
		"actor_translation_owner": "root_extraction_consumer" if bool(ctx.root_motion) else "gameplay_parent"}}
