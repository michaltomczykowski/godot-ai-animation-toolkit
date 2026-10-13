@tool
extends RefCounted
## Turn-local world targets. The generator consumes these; playback checks don't.
const Drivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")

static func _smooth(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))

static func _pulse(t: float) -> float:
	if t <= 0.0 or t >= 1.0: return 0.0
	return sin(PI * t) * sin(PI * t)

static func _foot(ctx: Dictionary, side: String, from: float, to: float, local: float,
		begin: float, end: float, yaw_sign: float) -> Dictionary:
	var u := clampf((local - begin) / (end - begin), 0.0, 1.0)
	var heading := lerpf(from, to, _smooth(u))
	var lift := float(ctx.config.foot_lift) * _pulse(u)
	var yaw := Quaternion(ctx.up, deg_to_rad(heading * yaw_sign))
	var ankle: Vector3 = ctx.hips_origin + Basis(yaw) * ((ctx.legs[side].ankle as Vector3) - (ctx.hips_origin as Vector3)) + (ctx.up as Vector3) * lift
	return {"ankle": ankle, "yaw": yaw, "lift": lift}

static func build(ctx: Dictionary, yaw_sign: float) -> Dictionary:
	var config: Dictionary = ctx.config
	var requested := float(config.turn_angle) * (1.0 if ctx.direction == "left" else -1.0)
	var count := float(config.steps)
	if not is_finite(requested) or absf(requested) < 0.001:
		return {"error": "Turn angle must be finite and nonzero"}
	if not is_finite(count) or count != floorf(count) or count < 1.0 or count > 8.0:
		return {"error": "Turn steps must be an integer from 1 to 8"}
	var steps := int(count)
	var per_step := requested / steps
	if absf(per_step) > 100.0:
		return {"error": "Turn angle needs more pivot steps; keep each requested step at or below 100 degrees"}
	if not is_finite(float(config.foot_lift)) or float(config.foot_lift) <= 0.0:
		return {"error": "Turn foot_lift must be finite and positive so moving feet can release contact"}
	var period := float(ctx.length) / steps
	var intervals := maxi(ceili(period * maxf(float(ctx.samples), 120.0)), 4)
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var lateral: Vector3 = ctx.lateral
	var leg_length := 0.5 * (float(ctx.legs.l.upper) + float(ctx.legs.l.lower) + float(ctx.legs.r.upper) + float(ctx.legs.r.lower))
	var scale := float(ctx.get("distance_scale", 1.0))
	var feet_heading := {"l": 0.0, "r": 0.0}
	var samples: Array = []
	var contacts: Array = []
	var markers: Array = []
	var base_drop := 0.0
	var extra_drop := 0.0
	for side in ["l", "r"]:
		var leg: Dictionary = ctx.legs[side]
		var reach := float(leg.upper) + float(leg.lower) - 0.001 - 0.00005 * leg_length
		if float(leg.upper) <= 0.001 or float(leg.lower) <= 0.001 or reach <= absf(float(leg.upper) - float(leg.lower)) + 0.001:
			return {"error": "Turn requires usable measured upper/lower leg lengths"}
		var offset: Vector3 = (leg.ankle as Vector3) - (leg.hip as Vector3)
		var horizontal := (offset - up * offset.dot(up)).length()
		if horizontal >= reach: return {"error": "Turn rest stance exceeds horizontal leg reach"}
		base_drop = maxf(base_drop, -offset.dot(up) - sqrt(reach * reach - horizontal * horizontal))
	for step in steps:
		var start := float(step) * per_step
		var goal := start + per_step
		var leading := "l" if (requested > 0.0) == (step % 2 == 0) else "r"
		var supporting := "r" if leading == "l" else "l"
		var last := step == steps - 1
		var suffix := "" if step == 0 else "_%d" % (step + 1)
		markers.append({"name": "anticipate" + suffix, "time": (step + 0.12) * period})
		markers.append({"name": "step" + suffix, "time": (step + 0.40) * period})
		markers.append({"name": "settle" + suffix, "time": (step + (0.94 if last else 0.82)) * period})
		for side in ["l", "r"]:
			var begin := 0.18 if side == leading else 0.68
			var end := 0.62 if side == leading else 0.94
			if side != leading and not last:
				contacts.append({"side": side, "start": step * period, "end": (step + 1.0) * period})
			else:
				contacts.append({"side": side, "start": step * period, "end": (step + begin) * period})
				contacts.append({"side": side, "start": (step + end) * period, "end": (step + 1.0) * period})
		for index in intervals + 1:
			if step > 0 and index == 0: continue
			var local := float(index) / intervals
			var anticipate := -0.025 * per_step * _pulse(local / 0.24)
			var yaw := start + per_step * _smooth((local - 0.12) / 0.56) + anticipate
			var world := Quaternion(up, deg_to_rad(yaw * yaw_sign))
			var primary := _pulse(local / 0.68)
			var recovery := _pulse((local - 0.64) / 0.36) if last else 0.0
			var target_feet := {}
			for side in ["l", "r"]:
				var begin := 0.18 if side == leading else 0.68
				var end := 0.62 if side == leading else 0.94
				var final: float = goal if side == leading or last else feet_heading[side]
				target_feet[side] = _foot(ctx, side, float(feet_heading[side]), final, local, begin, end, yaw_sign)
				if side != leading and not last:
					target_feet[side] = _foot(ctx, side, float(feet_heading[side]), float(feet_heading[side]), 0.0, begin, end, yaw_sign)
			var support: Vector3 = ctx.hips_origin + Basis(Quaternion(up, deg_to_rad(float(feet_heading[supporting]) * yaw_sign))) * ((ctx.legs[supporting].ankle as Vector3) - (ctx.hips_origin as Vector3))
			var newly_planted: Vector3 = ctx.hips_origin + Basis(Quaternion(up, deg_to_rad(goal * yaw_sign))) * ((ctx.legs[leading].ankle as Vector3) - (ctx.hips_origin as Vector3))
			var offset := (support - (ctx.hips_origin as Vector3)).slide(up) * (0.35 * primary) + (newly_planted - (ctx.hips_origin as Vector3)).slide(up) * (0.35 * recovery) - up * (0.015 * scale * (primary + recovery))
			var roll := deg_to_rad(1.5 * (primary - recovery) * (1.0 if supporting == "l" else -1.0))
			var hips_basis := Basis(Quaternion(Basis(world) * forward, roll)) * Basis(world)
			var envelope := _pulse(local)
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				var hip: Vector3 = ctx.hips_origin + offset + hips_basis * ((leg.hip as Vector3) - (ctx.hips_origin as Vector3))
				var diff: Vector3 = (target_feet[side].ankle as Vector3) - hip
				var reach := float(leg.upper) + float(leg.lower) - 0.001 - 0.00005 * leg_length
				var horizontal := diff.slide(up).length()
				if horizontal >= reach: return {"error": "Turn target exceeds horizontal reach; use smaller angles or more steps"}
				var needed := maxf(0.0, -diff.dot(up) - sqrt(reach * reach - horizontal * horizontal))
				if envelope < 0.000001:
					base_drop = maxf(base_drop, needed)
				else:
					extra_drop = maxf(extra_drop, maxf(0.0, needed - base_drop) / envelope)
			samples.append({"time": (step + local) * period, "local": local, "yaw": yaw,
				"world": world, "hips_basis": hips_basis, "offset": offset,
				"feet": target_feet, "envelope": envelope, "leading": leading,
				"pulse": primary - recovery, "look": (per_step * 0.12 * yaw_sign) * _pulse(local / 0.72),
				"forward_axis": Basis(world) * forward, "lateral_axis": Basis(world) * lateral})
		feet_heading[leading] = goal
		if last: feet_heading[supporting] = goal
	if base_drop + extra_drop > 0.12 * leg_length:
		return {"error": "Turn needs too much pelvis lowering; reduce angle/foot lift or use more steps"}
	for sample: Dictionary in samples:
		sample.offset -= up * (base_drop + extra_drop * float(sample.envelope))
	var merged: Array = []
	for side in ["l", "r"]:
		for window: Dictionary in contacts:
			if str(window.side) != side: continue
			if not merged.is_empty() and str(merged[-1].side) == side and is_equal_approx(float(merged[-1].end), float(window.start)):
				merged[-1].end = window.end
			else:
				merged.append(window.duplicate())
		var index := 0
		for window: Dictionary in merged:
			if str(window.side) != side: continue
			index += 1
			var suffix := "" if index == 1 else "_%d" % index
			markers.append({"name": "contact." + side.to_upper() + suffix, "time": window.start})
			markers.append({"name": "toe_off." + side.to_upper() + suffix, "time": window.end})
	return {"samples": samples, "contacts": merged, "markers": markers,
		"angle": requested, "steps": steps, "step_angle": per_step,
		"pelvis_base_drop_m": base_drop, "pelvis_reach_drop_m": extra_drop,
		"recovery_steps": 1, "footfalls": steps + 1}
