@tool
extends RefCounted
## Jump-only physical timeline and reachable skeleton-space targets.
const GRAVITY_WORLD := 9.81
const INTERVAL_BUDGET := 1200
## A solver's 1 mm numerical reach margin is not a stable neutral knee bend.
## Keep deliberate jump-only slack through push-off and catch; otherwise knee
## velocity grows sharply near extension even with continuous hip velocity.
const NEUTRAL_KNEE_DROP_FRACTION := 0.025

static func timing(height_world: float, requested_length: float, duration_explicit: bool, rate: float) -> Dictionary:
	if not is_finite(height_world) or height_world <= 0.0:
		return {"error": "Jump height must be finite and positive"}
	if not is_finite(requested_length) or requested_length <= 0.0 or not is_finite(rate) or rate <= 0.0:
		return {"error": "Jump duration and sampling must be finite and positive"}
	var flight := 2.0 * sqrt(2.0 * height_world / GRAVITY_WORLD)
	var length := requested_length if duration_explicit else maxf(1.0, flight / 0.55)
	if flight > 0.68 * length + 0.0000001:
		return {"error": "Jump flight needs %.6f seconds; explicit duration must be at least %.6f seconds" % [flight, flight / 0.68]}
	var takeoff := 0.22 * length
	var land := takeoff + flight
	var absorb := land + 0.5 * (length - land)
	var events := [0.0, 0.12 * length, takeoff, takeoff + 0.5 * flight, land, absorb, length]
	var counts: Array[int] = []
	var total := 0
	for i in events.size() - 1:
		var count := maxi(2 if i in [2, 3] else 1, ceili((float(events[i + 1]) - float(events[i])) * rate))
		counts.append(count)
		total += count
	if total > INTERVAL_BUDGET:
		return {"error": "Jump event sampling exceeds the 1200-interval motion budget; lower samples or shorten duration"}
	return {"length": length, "flight_time": flight, "takeoff_time": takeoff,
		"apex_time": takeoff + 0.5 * flight, "landing_time": land,
		"landing_absorb_time": absorb, "recovery_end_time": length,
		"gravity_world": GRAVITY_WORLD, "flight_intervals": counts[2] + counts[3],
		"sampling_intervals": total, "effective_samples": float(total) / length,
		"events": events, "segment_intervals": counts}

static func hermite(a: float, velocity_a: float, b: float, velocity_b: float, at: float, span: float) -> float:
	var t := clampf(at / span, 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	return (2.0*t3 - 3.0*t2 + 1.0)*a + (t3 - 2.0*t2 + t)*span*velocity_a + (-2.0*t3 + 3.0*t2)*b + (t3 - t2)*span*velocity_b

static func smooth(at: float) -> float:
	var t := clampf(at, 0.0, 1.0)
	return t*t*t*(10.0 + t*(-15.0 + 6.0*t))

static func vertical(at: float, plan: Dictionary, height: float, crouch: float, world_scale: float) -> float:
	var launch := sqrt(2.0 * GRAVITY_WORLD * height * world_scale) / world_scale
	var anticipate := 0.12 * float(plan.length)
	if at <= anticipate:
		return hermite(0.0, 0.0, -crouch, 0.0, at, anticipate)
	if at <= float(plan.takeoff_time):
		return hermite(-crouch, 0.0, 0.0, launch, at - anticipate, float(plan.takeoff_time) - anticipate)
	if at <= float(plan.landing_time):
		var flight_at := at - float(plan.takeoff_time)
		return launch * flight_at - 0.5 * GRAVITY_WORLD / world_scale * flight_at * flight_at
	if at <= float(plan.landing_absorb_time):
		return hermite(0.0, -launch, -0.85*crouch, 0.0, at - float(plan.landing_time), float(plan.landing_absorb_time) - float(plan.landing_time))
	return hermite(-0.85*crouch, 0.0, 0.0, 0.0, at - float(plan.landing_absorb_time), float(plan.length) - float(plan.landing_absorb_time))

static func build(ctx: Dictionary, lean_sign: float) -> Dictionary:
	var config: Dictionary = ctx.config
	var height := float(config.get("jump_height", 0.5))
	var crouch := float(config.get("jump_crouch", 0.24))
	var distance := float(config.get("jump_distance", 0.0))
	var scale := float(ctx.get("world_scale", 1.0))
	if not is_finite(scale) or scale <= 0.0 or not is_finite(crouch) or crouch < 0.0 or not is_finite(distance):
		return {"error": "Jump requires positive uniform world scale, nonnegative crouch and finite distance"}
	var plan := timing(height * scale, float(ctx.length), true, float(ctx.samples))
	if plan.has("error"): return plan
	var times: Array[float] = [0.0]
	for segment in plan.segment_intervals.size():
		for index in range(1, int(plan.segment_intervals[segment]) + 1):
			times.append(lerpf(float(plan.events[segment]), float(plan.events[segment + 1]), float(index) / int(plan.segment_intervals[segment])))
	var up: Vector3 = ctx.up
	var length := float(plan.length)
	var leg_length := 0.5 * (float(ctx.legs.l.upper) + float(ctx.legs.l.lower) + float(ctx.legs.r.upper) + float(ctx.legs.r.lower))
	var tuck := minf(0.05 * leg_length, 0.15 * height)
	var samples: Array = []
	var neutral_drop := NEUTRAL_KNEE_DROP_FRACTION * leg_length
	var drop := neutral_drop
	for at in times:
		var air := clampf((at - float(plan.takeoff_time)) / float(plan.flight_time), 0.0, 1.0)
		var y := vertical(at, plan, height, crouch, scale)
		var airborne := at > float(plan.takeoff_time) and at < float(plan.landing_time)
		var foot_y := y + tuck * pow(sin(PI * air), 2.0) if airborne else 0.0
		var travel: Vector3 = ctx.forward * (distance * smooth(air))
		var recovery := clampf((at - float(plan.landing_time)) / (length - float(plan.landing_time)), 0.0, 1.0)
		# Anticipation builds slowly; arm reversal occupies the full push and
		# first half of flight. Neither arm amplitude nor lean overrides change.
		var swing := -0.6 * smooth(at / (0.12*length)) if at <= 0.12*length else lerpf(-0.6, 1.0, smooth((at - 0.12*length) / (float(plan.apex_time) - 0.12*length)))
		if at > float(plan.apex_time): swing = lerpf(1.0, -0.25, smooth((at - float(plan.apex_time)) / (float(plan.landing_absorb_time) - float(plan.apex_time))))
		if at > float(plan.landing_absorb_time): swing = lerpf(-0.25, 0.0, smooth((at - float(plan.landing_absorb_time)) / (length - float(plan.landing_absorb_time))))
		var body := 0.5 * pow(sin(PI * clampf(at / float(plan.takeoff_time), 0.0, 1.0)), 2.0)
		if airborne: body = -0.15 * pow(sin(PI * air), 2.0)
		if at >= float(plan.landing_time): body = 0.45 * pow(sin(PI * recovery), 2.0)
		var world := Quaternion(ctx.lateral, deg_to_rad(body * float(config.get("lean", 6.0)) * lean_sign))
		var rooted := bool(ctx.get("root_motion", false)) and not is_zero_approx(distance)
		var offset := up * y + (Vector3.ZERO if rooted else travel)
		var feet := {}
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var upper := float(leg.upper)
			var lower := float(leg.lower)
			var maximum := upper + lower - 0.001 - maxf(0.00005*leg_length, 0.000002)
			if upper <= 0.001 or lower <= 0.001 or maximum <= absf(upper-lower) + 0.001:
				return {"error": "Jump requires usable measured upper/lower leg lengths"}
			var hip: Vector3 = ctx.hips_origin + offset + Basis(world) * ((leg.hip as Vector3) - (ctx.hips_origin as Vector3))
			var ankle: Vector3 = leg.ankle + up*foot_y + (Vector3.ZERO if rooted else travel)
			var diff := ankle - hip
			var horizontal := diff.slide(up).length()
			if horizontal >= maximum: return {"error": "Jump rest stance exceeds horizontal leg reach"}
			drop = maxf(drop, -diff.dot(up) - sqrt(maximum*maximum - horizontal*horizontal))
			feet[side] = ankle
		samples.append({"time": at, "offset": offset, "world": world, "feet": feet, "travel": travel,
			"air": air, "airborne": airborne, "swing": swing, "body": body,
			"bend": float(config.get("elbow", 12.0)) + 15.0*pow(sin(PI*clampf(at/length, 0.0, 1.0)), 2.0)})
	if drop > 0.12*leg_length: return {"error": "Jump needs excessive neutral pelvis lowering; inspect leg roles and rest pose"}
	for sample: Dictionary in samples:
		sample.offset -= up*drop
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var hip: Vector3 = ctx.hips_origin + sample.offset + Basis(sample.world as Quaternion)*((leg.hip as Vector3) - (ctx.hips_origin as Vector3))
			var reach := hip.distance_to(sample.feet[side])
			if not is_finite(reach) or reach <= absf(float(leg.upper)-float(leg.lower)) + 0.001 or reach >= float(leg.upper)+float(leg.lower)-0.001:
				return {"error": "Jump target is unreachable during push/flight/absorption; reduce crouch or inspect leg geometry"}
	var markers := [{"name":"grounded", "time":0.0}, {"name":"takeoff", "time":plan.takeoff_time},
		{"name":"apex", "time":plan.apex_time}, {"name":"land", "time":plan.landing_time},
		{"name":"landing_absorb", "time":plan.landing_absorb_time}, {"name":"recovery_end", "time":length}]
	var contacts: Array = []
	for side in ["l", "r"]:
		contacts.append({"side":side, "start":0.0, "end":plan.takeoff_time, "start_marker":"grounded", "end_marker":"takeoff"})
		contacts.append({"side":side, "start":plan.landing_time, "end":length, "start_marker":"land", "end_marker":"recovery_end"})
	var marker_events: Array = []
	for marker: Dictionary in markers:
		var events: Array = [marker.name]
		match str(marker.name):
			"grounded": events.append_array(["contact.L", "contact.R"])
			"takeoff": events.append_array(["toe_off.L", "toe_off.R"])
			"land": events.append_array(["contact.L_2", "contact.R_2"])
			"recovery_end": events.append_array(["toe_off.L_2", "toe_off.R_2"])
		marker_events.append({"name":marker.name, "time":marker.time, "events":events})
	plan.merge({"samples":samples, "markers":markers, "contacts":contacts, "marker_events":marker_events,
		"pelvis_base_drop_m":drop, "neutral_knee_drop_m":neutral_drop,
		"neutral_knee_drop_fraction":NEUTRAL_KNEE_DROP_FRACTION}, true)
	return plan
