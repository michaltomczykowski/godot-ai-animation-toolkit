extends SceneTree

## Tier-1 headless checks for the animation_fx spec builders: deterministic
## shapes, decay/settle behaviour, formatting and validation. No editor, no
## undo manager. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_fx_specs.gd

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const FxSpecs := preload("res://addons/godot_ai_animation/spec/fx_specs.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_shake()
	_check_zoom_punch()
	_check_hit_flash()
	_check_typewriter()
	_check_progress_and_damage()
	_check_counter()
	_check_wave()
	_check_spring()
	_check_pendulum()
	_check_path_follow()
	_check_flipbook()
	_check_sprite_frames()
	_check_audio_cue()
	_check_transition()
	_check_dialog_pop()
	_check_assign_paths()
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


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_error(result: Dictionary, message: String) -> void:
	_expect(result.has("error"), message)


func _track(spec: Dictionary, index: int = 0) -> Dictionary:
	return spec.tracks[index]


func _keys(spec: Dictionary, index: int = 0) -> Array:
	return spec.tracks[index].keys


func _check_shake() -> void:
	var baseline := Vector2(100, 50)
	var built := FxSpecs.shake_spec(baseline, 10.0, 0.4, 20.0, 0.15, 7, "xy")
	_expect(not built.has("error"), "shake builds a spec")
	var spec: Dictionary = built.spec
	var keys := _keys(spec)
	_expect(keys.size() > 8, "shake emits a dense key list (%d)" % keys.size())
	_expect_approx(float(spec.length), 0.4, "shake length")
	_expect((keys[keys.size() - 1].value as Vector2).is_equal_approx(baseline), "shake settles on the baseline")
	var peak := 0.0
	for key in keys:
		peak = maxf(peak, (key.value as Vector2).distance_to(baseline))
	_expect(peak <= 10.001, "shake stays within the intensity (peak %s)" % peak)
	_expect(peak > 4.0, "shake actually moves (peak %s)" % peak)
	var late := 0.0
	for index in range(keys.size() - 1, keys.size() - 4, -1):
		late = maxf(late, (keys[index].value as Vector2).distance_to(baseline))
	var early := 0.0
	for index in 4:
		early = maxf(early, (keys[index].value as Vector2).distance_to(baseline))
	_expect(late < early, "shake decays over time (early %s > late %s)" % [early, late])
	var again := FxSpecs.shake_spec(baseline, 10.0, 0.4, 20.0, 0.15, 7, "xy")
	_expect(str(again.spec) == str(spec), "the same seed reproduces the same shake")
	var other := FxSpecs.shake_spec(baseline, 10.0, 0.4, 20.0, 0.15, 8, "xy")
	_expect(str(other.spec) != str(spec), "a different seed changes the shake")
	var x_only := FxSpecs.shake_spec(baseline, 10.0, 0.3, 20.0, 1.0, 1, "x")
	for key in _keys(x_only.spec):
		_expect_approx((key.value as Vector2).y, baseline.y, "axis=x keeps y fixed")
	var v3 := FxSpecs.shake_spec(Vector3(0, 0, 0), 5.0, 0.3, 20.0, 1.0, 1, "xyz")
	_expect((_keys(v3.spec)[2].value as Vector3).z != 0.0, "3D shake moves on z too")
	_expect_error(FxSpecs.shake_spec(baseline, 0.0, 0.4, 20.0, 1.0, 1, "xy"), "shake rejects intensity 0")
	_expect_error(FxSpecs.shake_spec(baseline, 5.0, 0.4, 20.0, 1.5, 1, "xy"), "shake rejects decay > 1")
	_expect_error(FxSpecs.shake_spec(baseline, 5.0, 0.4, 20.0, 1.0, 1, "q"), "shake rejects unknown axes")


func _check_zoom_punch() -> void:
	var built := FxSpecs.zoom_punch_spec(Vector2(2, 2), 0.1, 0.25, 0.3)
	_expect(not built.has("error"), "zoom_punch builds a spec")
	var keys := _keys(built.spec)
	_expect(keys.size() == 3, "zoom_punch is a three-key punch")
	_expect((keys[1].value as Vector2).is_equal_approx(Vector2(2.2, 2.2)), "zoom_punch overshoots by amount")
	_expect((keys[2].value as Vector2).is_equal_approx(Vector2(2, 2)), "zoom_punch returns to base")
	var fov := FxSpecs.zoom_punch_spec(70.0, -0.1, 0.3, 0.5)
	_expect_approx(float(_keys(fov.spec)[1].value), 63.0, "zoom_punch works on a float fov")
	_expect_error(FxSpecs.zoom_punch_spec(Vector2(2, 2), 0.0, 0.25, 0.3), "zoom_punch rejects amount 0")
	_expect_error(FxSpecs.zoom_punch_spec(Color(1, 1, 1), 0.1, 0.25, 0.3), "zoom_punch rejects unsupported types")


func _check_hit_flash() -> void:
	var base := Color(1, 1, 1, 1)
	var flash := Color(1, 0, 0, 1)
	var built := FxSpecs.hit_flash_spec(base, flash, 0.18, 2)
	_expect(not built.has("error"), "hit_flash builds a spec")
	var keys := _keys(built.spec)
	_expect(keys.size() == 5, "two flashes produce five keys (%d)" % keys.size())
	_expect((keys[1].value as Color).is_equal_approx(flash), "hit_flash peaks on the flash color")
	_expect((keys[2].value as Color).is_equal_approx(base), "hit_flash returns to the base color")
	_expect_approx(float(built.spec.length), 0.18, "hit_flash length")
	_expect_error(FxSpecs.hit_flash_spec(base, flash, 0.0, 1), "hit_flash rejects zero duration")
	_expect_error(FxSpecs.hit_flash_spec(base, flash, 0.2, 0), "hit_flash rejects count 0")


func _check_typewriter() -> void:
	var stepped := FxSpecs.typewriter_spec(1.0, 10, 0.2, 0.0, 1.0)
	_expect(not stepped.has("error"), "typewriter builds a spec")
	var keys := _keys(stepped.spec)
	_expect(keys.size() == 11, "10 steps produce 11 keys (%d)" % keys.size())
	_expect_approx(float(stepped.spec.length), 1.2, "typewriter adds the delay to the length")
	_expect_approx(float(keys[0].time), 0.2, "typewriter starts after the delay")
	_expect_approx(float(keys[0].value), 0.0, "typewriter starts at from_ratio")
	_expect_approx(float(keys[10].value), 1.0, "typewriter ends at to_ratio")
	_expect(int(stepped.spec.tracks[0].interp) == Animation.INTERPOLATION_NEAREST,
		"stepped typewriter uses nearest interpolation")
	var smooth := FxSpecs.typewriter_spec(1.0, 0, 0.0, 0.25, 0.75)
	_expect(int(smooth.spec.tracks[0].interp) == Animation.INTERPOLATION_LINEAR,
		"smooth typewriter uses linear interpolation")
	_expect_approx(float(_keys(smooth.spec)[0].value), 0.25, "smooth typewriter honours from_ratio")
	_expect_error(FxSpecs.typewriter_spec(1.0, 0, 0.0, 0.9, 0.5), "typewriter rejects from > to")


func _check_progress_and_damage() -> void:
	var fill := FxSpecs.progress_fill_spec(0.0, 100.0, 0.6, 0.2)
	_expect(not fill.has("error"), "progress_fill builds a spec")
	_expect(_keys(fill.spec).size() == 3, "progress_fill holds then fills")
	_expect_approx(float(_keys(fill.spec)[1].time), 0.2, "progress_fill holds until the delay")
	_expect_approx(float(_keys(fill.spec)[2].value), 100.0, "progress_fill reaches 'to'")
	_expect_approx(float(fill.spec.length), 0.8, "progress_fill length includes the delay")
	var damage := FxSpecs.damage_bar_spec(100.0, 40.0, 0.3, 0.4)
	_expect(not damage.has("error"), "damage_bar builds a spec")
	_expect_approx(float(_keys(damage.spec)[0].value), 100.0, "damage_bar starts at 'from'")
	_expect_approx(float(_keys(damage.spec)[1].value), 100.0, "damage_bar holds during the delay")
	_expect_approx(float(_keys(damage.spec)[2].value), 40.0, "damage_bar eases to 'to'")
	_expect_error(FxSpecs.damage_bar_spec(0.0, 1.0, 0.0, 0.0), "damage_bar rejects zero duration")


func _check_counter() -> void:
	var built := FxSpecs.counter_spec(0.0, 1000.0, 4, 1.0, "%d", "$", "", "set_text")
	_expect(not built.has("error"), "counter builds a spec")
	var track := _track(built.spec)
	_expect(int(track.type) == Animation.TYPE_METHOD, "counter uses a method track")
	_expect((track.keys as Array).size() == 5, "counter emits steps + 1 calls")
	_expect(str(track.keys[0].method) == "set_text", "counter calls the requested method")
	_expect(str(track.keys[0].args[0]) == "$0", "counter formats the first value (%s)" % str(track.keys[0].args[0]))
	_expect(str(track.keys[4].args[0]) == "$1000", "counter formats the last value (%s)" % str(track.keys[4].args[0]))
	_expect(str(track.keys[2].args[0]) == "$500", "counter interpolates the middle value (%s)" % str(track.keys[2].args[0]))
	var floats := FxSpecs.counter_spec(0.0, 1.0, 2, 1.0, "%.2f", "", "%", "set_text")
	_expect(str(floats.spec.tracks[0].keys[2].args[0]) == "1.00%", "counter supports float formats")
	_expect_error(FxSpecs.counter_spec(0.0, 1.0, 0, 1.0, "%d", "", "", "set_text"), "counter rejects steps 0")
	_expect_error(FxSpecs.counter_spec(0.0, 1.0, 4, 1.0, "%d", "", "", ""), "counter rejects an empty method")


func _check_wave() -> void:
	var built := FxSpecs.wave_spec(["A:position", "B:position"], [Vector2(0, 0), Vector2(10, 0)],
		"y", 10.0, 1.0, 0.25, 1)
	_expect(not built.has("error"), "wave builds a spec")
	var spec: Dictionary = built.spec
	_expect((spec.tracks as Array).size() == 2, "wave emits one track per target")
	_expect_approx(float(spec.length), 1.0, "wave length is one period")
	_expect(int(spec.loop_mode) == Animation.LOOP_LINEAR, "wave loops linearly")
	var first_track: Dictionary = spec.tracks[0]
	var second_track: Dictionary = spec.tracks[1]
	var peak := 0.0
	for key in first_track.keys:
		peak = maxf(peak, absf((key.value as Vector2).y))
	_expect_approx(peak, 10.0, "wave peaks at the amplitude")
	_expect_approx(float(first_track.keys[0].value.y), 0.0, "the first target starts at phase 0")
	_expect(float(second_track.keys[0].value.y) > 9.0,
		"the second target starts a quarter-cycle ahead, at the peak (%s)" % str(second_track.keys[0].value.y))
	var first_value: Variant = first_track.keys[0].value
	var last_value: Variant = first_track.keys[first_track.keys.size() - 1].value
	_expect((first_value as Vector2).is_equal_approx(last_value as Vector2), "wave is seamless over a full cycle")
	_expect_error(FxSpecs.wave_spec(["A:position"], [Vector2.ZERO], "y", 0.0, 1.0, 0.1, 1), "wave rejects amplitude 0")
	_expect_error(FxSpecs.wave_spec(["A:position"], [Vector2.ZERO], "y", 5.0, 0.0, 0.1, 1), "wave rejects period 0")


func _check_spring() -> void:
	var baseline := Vector2(0, 0)
	var offset := Vector2(0, -60)
	var built := FxSpecs.spring_spec(baseline, offset, 2.5, 0.3, 1.0, 30)
	_expect(not built.has("error"), "spring builds a spec")
	var keys := _keys(built.spec)
	_expect(keys.size() == 31, "spring emits samples + 1 keys")
	_expect((keys[0].value as Vector2).is_equal_approx(baseline), "spring starts at the baseline")
	var final: Vector2 = keys[keys.size() - 1].value
	_expect(final.distance_to(offset) < 1.0, "spring settles on baseline + offset (%s)" % str(final))
	var overshoot := 0.0
	for key in keys:
		overshoot = minf(overshoot, (key.value as Vector2).y)
	_expect(overshoot < -60.0, "an underdamped spring overshoots (%s)" % overshoot)
	var critical := FxSpecs.spring_spec(baseline, offset, 2.5, 1.0, 1.0, 30)
	var critical_overshoot := 0.0
	for key in _keys(critical.spec):
		critical_overshoot = minf(critical_overshoot, (key.value as Vector2).y)
	_expect(critical_overshoot >= -60.5, "a critically damped spring does not overshoot (%s)" % critical_overshoot)
	_expect_error(FxSpecs.spring_spec(baseline, offset, 0.0, 0.3, 1.0, 30), "spring rejects frequency 0")
	_expect_error(FxSpecs.spring_spec(baseline, Vector3(0, 1, 0), 2.0, 0.3, 1.0, 30), "spring rejects mismatched types")


func _check_pendulum() -> void:
	var built := FxSpecs.pendulum_spec(0.0, 20.0, 1.0, 2.0, 1.0)
	_expect(not built.has("error"), "pendulum builds a spec")
	var keys := _keys(built.spec)
	_expect_approx(float(keys[0].value), deg_to_rad(20.0), "pendulum starts at +amplitude")
	_expect_approx(float(keys[keys.size() - 1].value), deg_to_rad(20.0), "a full period returns to the start")
	var quarter: float = keys[keys.size() / 4].value
	_expect(quarter < 0.0, "pendulum swings the other way a quarter-period in (%s)" % quarter)
	var damped := FxSpecs.pendulum_spec(0.0, 20.0, 1.0, 2.0, 0.3)
	var last_damped: float = _keys(damped.spec)[_keys(damped.spec).size() - 1].value
	_expect(absf(last_damped) < deg_to_rad(20.0), "a damped pendulum winds down (%s)" % last_damped)
	var euler := FxSpecs.pendulum_spec(Vector3(0, 0, 0), 15.0, 1.0, 1.0, 1.0)
	_expect(_keys(euler.spec)[0].value is Vector3, "3D pendulum stores euler vectors")
	_expect_error(FxSpecs.pendulum_spec(0.0, 0.0, 1.0, 1.0, 1.0), "pendulum rejects amplitude 0")


func _check_path_follow() -> void:
	var points: Array = [Vector2(0, 0), Vector2(50, 0), Vector2(50, 50)]
	var built := FxSpecs.path_follow_spec(points, 2.0, Animation.LOOP_NONE)
	_expect(not built.has("error"), "path_follow builds a spec")
	var keys := _keys(built.spec)
	_expect(keys.size() == 3, "one key per sampled point")
	_expect_approx(float(keys[0].time), 0.0, "the first point is at 0")
	_expect_approx(float(keys[2].time), 2.0, "the last point is at the duration")
	_expect((keys[1].value as Vector2).is_equal_approx(Vector2(50, 0)), "points land in order")
	_expect_error(FxSpecs.path_follow_spec([Vector2.ZERO], 2.0, Animation.LOOP_NONE), "path_follow needs 2+ points")


func _check_flipbook() -> void:
	var built := FxSpecs.flipbook_spec(2, 4, 8.0, Animation.LOOP_LINEAR)
	_expect(not built.has("error"), "flipbook builds a spec")
	var keys := _keys(built.spec)
	_expect(keys.size() == 4, "flipbook emits one key per frame (%d)" % keys.size())
	_expect_approx(float(built.spec.length), 0.5, "flipbook length is frames / fps")
	_expect(int(keys[0].value) == 2, "flipbook starts at from_frame")
	_expect(int(keys[3].value) == 5, "flipbook steps through the range")
	_expect(int(built.spec.tracks[0].interp) == Animation.INTERPOLATION_NEAREST, "flipbook uses nearest interpolation")
	_expect_error(FxSpecs.flipbook_spec(0, 0, 8.0, Animation.LOOP_LINEAR), "flipbook rejects 0 frames")
	_expect_error(FxSpecs.flipbook_spec(0, 4, 0.0, Animation.LOOP_LINEAR), "flipbook rejects fps 0")


func _check_sprite_frames() -> void:
	var image := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 1))
	var texture := ImageTexture.create_from_image(image)
	var built := FxSpecs.sprite_frames_build(texture, 4, 1, 12.0, true, 1, 3, "run")
	_expect(not built.has("error"), "sprite_frames builds a resource")
	var frames: SpriteFrames = built.frames
	_expect(frames.has_animation("run"), "the animation is named")
	_expect(frames.get_frame_count("run") == 3, "the frame range is sliced (%d)" % frames.get_frame_count("run"))
	_expect_approx(float(frames.get_animation_speed("run")), 12.0, "the speed is set")
	_expect(frames.get_animation_loop("run"), "the loop flag is set")
	_expect((built.cell_size as Vector2).is_equal_approx(Vector2(16, 16)), "the cell size is computed")
	var first: AtlasTexture = frames.get_frame_texture("run", 0)
	_expect(first.region.position.is_equal_approx(Vector2(16, 0)), "frames are offset by the cell (%s)" % str(first.region))
	_expect(first.atlas == texture, "frames reference the source atlas")
	_expect_error(FxSpecs.sprite_frames_build(null, 4, 1, 12.0, true, 0, 3, "run"), "a texture is required")
	_expect_error(FxSpecs.sprite_frames_build(texture, 4, 1, 12.0, true, 0, 9, "run"), "the frame range is validated")
	_expect_error(FxSpecs.sprite_frames_build(texture, 0, 1, 12.0, true, 0, 0, "run"), "hframes must be >= 1")


func _check_audio_cue() -> void:
	var stream := AudioStreamWAV.new()
	var built := FxSpecs.audio_cue_spec(stream, 0.2, 0.0, 0.0)
	_expect(not built.has("error"), "audio_cue builds a spec")
	var track := _track(built.spec)
	_expect(int(track.type) == Animation.TYPE_AUDIO, "audio_cue uses an audio track")
	_expect_approx(float(track.keys[0].time), 0.2, "the cue fires at 'time'")
	_expect(track.keys[0].stream == stream, "the stream is stored on the key")
	_expect(float(built.spec.length) >= 0.2, "the clip covers the cue")
	_expect_error(FxSpecs.audio_cue_spec(null, 0.0, 0.0, 0.0), "a stream is required")


func _check_transition() -> void:
	var fade_out := FxSpecs.transition_spec("fade_out", 0.5)
	_expect(not fade_out.has("error"), "transition builds a spec")
	var keys := _keys(fade_out.spec)
	_expect_approx(float(keys[0].value), 0.0, "fade_out starts transparent")
	_expect_approx(float(keys[1].value), 1.0, "fade_out ends opaque")
	var fade_in := FxSpecs.transition_spec("fade_in", 0.5)
	_expect_approx(float(_keys(fade_in.spec)[0].value), 1.0, "fade_in starts opaque")
	var wipe := FxSpecs.transition_spec("wipe_right", 0.4)
	_expect((_keys(wipe.spec)[0].value as Vector2).is_equal_approx(Vector2.ZERO), "wipes start at zero scale")
	_expect((_keys(wipe.spec)[1].value as Vector2).is_equal_approx(Vector2.ONE), "wipes end at full scale")
	_expect_error(FxSpecs.transition_spec("dissolve", 0.5), "unknown transition modes are rejected")


func _check_dialog_pop() -> void:
	var built := FxSpecs.dialog_pop_spec(Vector2(1, 1), 0.85, 1.06, 0.35, true, 1.0)
	_expect(not built.has("error"), "dialog_pop builds a spec")
	var spec: Dictionary = built.spec
	_expect((spec.tracks as Array).size() == 2, "dialog_pop adds a fade track")
	var scale_keys := _keys(spec, 0)
	_expect((scale_keys[0].value as Vector2).is_equal_approx(Vector2(0.85, 0.85)), "dialog_pop starts small")
	_expect((scale_keys[1].value as Vector2).is_equal_approx(Vector2(1.06, 1.06)), "dialog_pop overshoots")
	_expect((scale_keys[2].value as Vector2).is_equal_approx(Vector2(1, 1)), "dialog_pop settles at the baseline")
	var alpha_keys := _keys(spec, 1)
	_expect_approx(float(alpha_keys[0].value), 0.0, "the fade track starts transparent")
	_expect_approx(float(alpha_keys[1].value), 1.0, "the fade track reaches the base alpha")
	var plain := FxSpecs.dialog_pop_spec(Vector3(1, 1, 1), 0.9, 1.04, 0.3, false, 1.0)
	_expect((plain.spec.tracks as Array).size() == 1, "fade=false skips the alpha track")
	_expect_error(FxSpecs.dialog_pop_spec(Vector2(1, 1), 0.0, 1.06, 0.35, true, 1.0), "from_scale must be > 0")


func _check_assign_paths() -> void:
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", [{"time": 0.0, "value": 0.0}])
	ClipSpec.add_value_track(spec, "modulate:a", [{"time": 0.0, "value": 0.0}])
	ClipSpec.add_method_track(spec, "", [{"time": 0.0, "method": "set_text", "args": []}])
	ClipSpec.add_audio_track(spec, "", [{"time": 0.0, "stream": null}])
	FxSpecs.assign_paths(spec, "Panel", "scale")
	_expect(str(spec.tracks[0].path) == "Panel:scale", "empty paths take the default property")
	_expect(str(spec.tracks[1].path) == "Panel:modulate:a", "stored properties are kept")
	_expect(str(spec.tracks[2].path) == "Panel", "method tracks take the node path alone")
	_expect(str(spec.tracks[3].path) == "Panel", "audio tracks take the node path alone")
