extends SceneTree
const Plan := preload("res://addons/godot_ai_animation/spec/motion_jump_plan.gd")
const Specs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
const Drivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _init() -> void:
	for world_scale in [0.5, 1.0, 2.0]:
		var timing := Plan.timing(0.5*world_scale, 1.0, false, 60.0)
		check(not timing.has("error"), "default timing")
		check(absf(float(timing.flight_time)-2.0*sqrt(2.0*0.5*world_scale/9.81)) < 0.0000001, "world ballistic flight")
		check(absf(float(timing.length)-maxf(1.0, float(timing.flight_time)/0.55)) < 0.0000001, "omitted duration")
		check(float(timing.flight_intervals) >= 4.0, "four flight intervals")
		check(absf(Plan.vertical(timing.apex_time, timing, 0.5, 0.24, world_scale)-0.5) < 0.000001, "physical apex height")
		for boundary in [timing.takeoff_time, timing.landing_time]:
			var epsilon := 0.000001
			var y := Plan.vertical(boundary, timing, 0.5, 0.24, world_scale)
			var left := (y-Plan.vertical(boundary-epsilon, timing, 0.5, 0.24, world_scale))/epsilon
			var right := (Plan.vertical(boundary+epsilon, timing, 0.5, 0.24, world_scale)-y)/epsilon
			check(absf(left-right) < 0.001, "ground/flight endpoint velocity")
	for style in ["responsive", "grounded", "relaxed", "heavy", "sneaky"]:
		for scale_value in [0.5, 1.0, 2.0]:
			var ctx := context(Basis.IDENTITY, 60.0, true, 0.5)
			ctx.config = Specs.jump_config(style)
			ctx.config.jump_distance = 0.5
			ctx.world_scale = scale_value
			ctx.length = Plan.timing(float(ctx.config.jump_height)*scale_value, 1.0, false, 60.0).length
			var output := Specs.jump_keys(ctx)
			check(not output.meta.has("reach_error"), "style/uniform-world-scale reach")
			if not output.meta.has("reach_error"):
				check(absf(float(output.meta.gravity_world)-9.81) < 0.000001, "world gravity remains exact")
	var reach_ctx := context(Basis.IDENTITY, 60.0, true, 0.5)
	var reach_plan := Plan.build(reach_ctx, 1.0)
	check(float(reach_plan.pelvis_base_drop_m) > 0.001, "neutral pelvis avoids exact-extension clamp")
	check(absf(float(reach_plan.neutral_knee_drop_m)-0.025*0.8) < 0.000001 and reach_plan.neutral_knee_drop_fraction == 0.025, "deliberate measured-leg knee slack")
	check(float(reach_plan.pelvis_base_drop_m) >= float(reach_plan.neutral_knee_drop_m), "reach correction never removes neutral slack")
	for sample: Dictionary in reach_plan.samples:
		if float(sample.time) > float(reach_plan.takeoff_time) and float(sample.time) < float(reach_plan.apex_time):
			var pelvis_height := (sample.offset as Vector3).dot(Vector3.UP) + float(reach_plan.pelvis_base_drop_m)
			var ankle_height := ((sample.feet.l as Vector3) - (reach_ctx.legs.l.ankle as Vector3)).dot(Vector3.UP)
			check(ankle_height + 0.000001 >= pelvis_height, "airborne feet follow full pelvis rise")
	for rate in [4.0, 60.0, 120.0]:
		for frame in [Basis.IDENTITY, Basis(Vector3.RIGHT, PI*0.5), Basis(Vector3(1,2,3).normalized(), 0.71)]:
			for rooted in [false, true]:
				for distance in [0.0, 0.5]:
					var ctx := context(frame, rate, rooted, distance)
					var plan := Plan.build(ctx, 1.0)
					check(not plan.has("error"), "reachable plan " + str(plan.get("error", "")))
					if plan.has("error"): continue
					check(plan.samples.size() == int(plan.sampling_intervals)+1 and plan.samples.size() <= 1201, "sampling budget and count")
					check(plan.markers.size() == 6 and plan.contacts.size() == 4, "shared physical event/contact counts")
					check(plan.contacts[0].start_marker == plan.contacts[2].start_marker and plan.contacts[0].end_marker == plan.contacts[2].end_marker, "both feet share saved markers")
					check("contact.L" in plan.marker_events[0].events and "contact.R" in plan.marker_events[0].events, "shared saved marker retains both foot events")
					check((plan.samples[-1].travel as Vector3).distance_to((ctx.forward as Vector3)*distance) < 0.000001 and (plan.samples[0].travel as Vector3).is_zero_approx(), "forward displacement endpoints")
					for sample: Dictionary in plan.samples:
						for side in ["l", "r"]:
							var leg: Dictionary = ctx.legs[side]
							var hip: Vector3 = ctx.hips_origin + sample.offset + Basis(sample.world as Quaternion)*((leg.hip as Vector3)-(ctx.hips_origin as Vector3))
							var solved := Drivers.solve_leg(hip, sample.feet[side], leg.upper, leg.lower, ctx.forward)
							check(not solved.clamped, "every planned solve reachable")
							if not bool(sample.airborne):
								var expected: Vector3 = leg.ankle + (Vector3.ZERO if rooted else sample.travel)
								check((sample.feet[side] as Vector3).distance_to(expected) < 0.000001, "anchored contact")
					var generated := Specs.jump_keys(ctx)
					check(not generated.meta.has("reach_error"), "generator consumes reachable plan")
					if generated.meta.has("reach_error"): continue
					check(generated.meta.reach_evaluated and generated.meta.clamped_leg_samples == 0 and generated.meta.evaluated_leg_samples == 2*plan.samples.size(), "every actual solve reported")
					check(generated.keys.has("__root_motion__") == (rooted and distance != 0.0), "single translation owner")
					var hip_end: Vector3 = generated.keys.hips.position[-1].delta
					var hip_start: Vector3 = generated.keys.hips.position[0].delta
					check((hip_end-hip_start).distance_to(Vector3.ZERO if rooted else (ctx.forward as Vector3)*distance) < 0.000001, "skeletal displacement only without extraction")
					for bone in generated.keys:
						check(not generated.keys[bone].loop_close, "one-shot endpoints preserved")
	for height in [0.0, -0.1, INF, NAN]:
		check(Plan.timing(height, 1.0, false, 60.0).has("error"), "invalid height refuses")
	check(Plan.timing(0.5, 0.3, true, 60.0).has("error"), "short explicit duration refuses")
	check(Plan.timing(0.5, 1.2, true, 60.0).length == 1.2, "explicit duration preserved")
	check(Plan.timing(0.5, 20.0, true, 120.0).has("error"), "event sampling budget refuses")
	var unreachable := context(Basis.IDENTITY, 60.0, false, 0.0)
	unreachable.config.jump_crouch = 2.0
	check(Specs.jump_keys(unreachable).meta.has("reach_error"), "unreachable crouch refuses before keys")
	check(Specs.jump_config("default").arm_swing == 40.0 and Specs.jump_config("grounded").arm_swing == 35.0, "reduced implicit arm amplitudes")
	check(Specs.jump_config("heavy", {"arm_swing":65.0}).arm_swing == 65.0, "explicit arm amplitude exact")
	print("TIER1_JUMP_PLAN=" + JSON.stringify({"checks":checks,"failures":failures}))
	print("TIER1 PASS" if failures.is_empty() else "TIER1 FAIL")
	quit(0 if failures.is_empty() else 1)

func context(frame: Basis, rate: float, rooted: bool, distance: float) -> Dictionary:
	var ctx := {"config":Specs.jump_config("responsive"), "up":frame*Vector3.UP, "forward":frame*Vector3.FORWARD,
		"lateral":frame*Vector3.RIGHT, "hips_origin":frame*Vector3(0,0.8,0), "hips":"hips", "roles":{"hips":"hips"},
		"legs":{}, "rest":{"hips":{"global":frame,"parent":""}}, "samples":rate, "root_motion":rooted, "world_scale":1.0}
	ctx.config.jump_distance = distance
	ctx.length = Plan.timing(0.5, 1.0, false, rate).length
	for side in ["l", "r"]:
		var x := -0.1 if side == "l" else 0.1
		ctx.legs[side] = {"upper":0.4,"lower":0.4,"hip":frame*Vector3(x,0.8,0), "knee":frame*Vector3(x,0.4,0), "ankle":frame*Vector3(x,0,0), "thigh":"thigh_"+side,"shin":"shin_"+side,"foot":"foot_"+side}
		for bone in ["thigh_"+side,"shin_"+side,"foot_"+side]:
			ctx.rest[bone] = {"global":frame,"parent":"hips"}
	return ctx
