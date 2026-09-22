@tool
extends RefCounted

## Pure spec builders for the `animation_fx` generators.
##
## Every function returns `{spec: <ClipSpec>}` plus op-specific fields, or an
## error dict (`ErrorCodes.make(...)`) when the parameters cannot produce a clip.
## No node or editor access happens here: the op wrappers resolve targets and
## baselines, then call these so the whole generator surface is tier-1 testable.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

const _WAVE_SEGMENTS_PER_CYCLE := 16
const _MAX_KEYS := 4096


## Stamp the resolved node path (and default property) onto every track the
## builders left with an empty path. Builders store "" for "the op's default
## property" and a property name like "modulate:a" for extra tracks; method and
## audio tracks take the node path alone.
static func assign_paths(spec: Dictionary, node_path: String, default_property: String) -> void:
	for track in spec.get("tracks", []):
		var type := int(track.get("type", -1))
		var stored := str(track.get("path", ""))
		if type == Animation.TYPE_METHOD or type == Animation.TYPE_AUDIO:
			track["path"] = node_path if stored.is_empty() else stored
			continue
		var property := stored if not stored.is_empty() else default_property
		track["path"] = "%s:%s" % [node_path, property]


# --- shake -----------------------------------------------------------------

## Decaying positional noise around `baseline`. `decay` is the falloff per full
## duration (1.0 = constant, 0.1 = mostly settled), `axes` any of "xyz".
static func shake_spec(
	baseline: Variant, intensity: float, duration: float,
	frequency: float, decay: float, seed_value: int, axes: String,
) -> Dictionary:
	if intensity <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'intensity' must be > 0")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if frequency <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'frequency' must be > 0")
	if decay <= 0.0 or decay > 1.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'decay' must be in (0, 1]")
	var is_3d := baseline is Vector3
	var clean_axes := _clean_axes(axes, is_3d)
	if clean_axes.is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'axis' must contain at least one of x/y%s" % ("/z" if is_3d else ""))
	var samples := clampi(int(ceil(duration * frequency * 2.0)), 8, _MAX_KEYS - 1)
	var step := duration / float(samples)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var keys: Array = []
	for index in samples + 1:
		var time := float(index) * step
		var falloff := pow(decay, time / duration)
		var offset: Variant = _random_offset(rng, clean_axes, is_3d) * intensity * falloff
		if index == samples:
			offset = Vector3.ZERO if is_3d else Vector2.ZERO
		keys.append({"time": time, "value": baseline + offset, "transition": 1.0})
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec, "keys": keys, "samples": samples, "axes": clean_axes}


static func _clean_axes(axes: String, is_3d: bool) -> String:
	var out := ""
	for axis in ["x", "y", "z"]:
		if axes.to_lower().contains(axis) and (is_3d or axis != "z"):
			out += axis
	return out


static func _random_offset(rng: RandomNumberGenerator, axes: String, is_3d: bool) -> Variant:
	if is_3d:
		return Vector3(
			rng.randf_range(-1.0, 1.0) if axes.contains("x") else 0.0,
			rng.randf_range(-1.0, 1.0) if axes.contains("y") else 0.0,
			rng.randf_range(-1.0, 1.0) if axes.contains("z") else 0.0,
		)
	return Vector2(
		rng.randf_range(-1.0, 1.0) if axes.contains("x") else 0.0,
		rng.randf_range(-1.0, 1.0) if axes.contains("y") else 0.0,
	)


# --- zoom_punch ------------------------------------------------------------

## Camera punch: overshoot then settle. `base` is a Camera2D `zoom` (Vector2)
## or a Camera3D `fov` (float).
static func zoom_punch_spec(base: Variant, amount: float, duration: float, peak_ratio: float) -> Dictionary:
	if amount == 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'amount' must not be 0")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if peak_ratio <= 0.0 or peak_ratio >= 1.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'peak_ratio' must be in (0, 1)")
	var peak: Variant
	if base is Vector2:
		peak = (base as Vector2) * (1.0 + amount)
	elif base is float or base is int:
		peak = float(base) * (1.0 + amount)
	else:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"zoom_punch targets a Camera2D (zoom) or Camera3D (fov), got %s" % ClipSpec.value_kind(base))
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", [
		{"time": 0.0, "value": base, "transition": 1.0},
		{"time": duration * peak_ratio, "value": peak, "transition": 0.5},
		{"time": duration, "value": base, "transition": 1.0},
	])
	return {"spec": spec}


# --- hit_flash -------------------------------------------------------------

## Flash `modulate` to `flash` and back `count` times.
static func hit_flash_spec(base: Color, flash: Color, duration: float, count: int) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if count < 1:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'count' must be >= 1")
	var step := duration / float(count * 2)
	var keys: Array = [{"time": 0.0, "value": base, "transition": 1.0}]
	for index in count:
		keys.append({"time": step * (2 * index + 1), "value": flash, "transition": 0.5})
		keys.append({"time": step * (2 * index + 2), "value": base, "transition": 0.5})
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec}


# --- typewriter ------------------------------------------------------------

## Reveal text: `visible_ratio` 0 -> 1, in `steps` discrete characters
## (nearest interpolation) or smoothly when `steps` is 0.
static func typewriter_spec(duration: float, steps: int, delay: float, from_ratio: float, to_ratio: float) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if delay < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'delay' must be >= 0")
	if from_ratio < 0.0 or to_ratio > 1.0 or to_ratio <= from_ratio:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'from_ratio'/'to_ratio' must satisfy 0 <= from < to <= 1")
	var keys: Array = []
	var interp := Animation.INTERPOLATION_LINEAR
	if steps > 0:
		interp = Animation.INTERPOLATION_NEAREST
		for index in steps + 1:
			keys.append({
				"time": delay + duration * float(index) / float(steps),
				"value": from_ratio + (to_ratio - from_ratio) * float(index) / float(steps),
				"transition": 1.0,
			})
	else:
		if delay > 0.0:
			keys.append({"time": 0.0, "value": from_ratio, "transition": 1.0})
		keys.append({"time": delay, "value": from_ratio, "transition": 1.0})
		keys.append({"time": delay + duration, "value": to_ratio, "transition": 1.0})
	var spec := ClipSpec.make(delay + duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys, interp)
	return {"spec": spec, "steps": steps}


# --- progress_fill ---------------------------------------------------------

## Animate a numeric property (ProgressBar `value`, `modulate:a`, a custom
## float) from `from` to `to`, optionally after a hold.
static func progress_fill_spec(from: float, to: float, duration: float, delay: float) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if delay < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'delay' must be >= 0")
	var keys: Array = [{"time": 0.0, "value": from, "transition": 1.0}]
	if delay > 0.0:
		keys.append({"time": delay, "value": from, "transition": 1.0})
	keys.append({"time": delay + duration, "value": to, "transition": 0.5})
	var spec := ClipSpec.make(delay + duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec}


# --- counter ---------------------------------------------------------------

## Rolling numbers: a method track that calls `method` with pre-formatted
## strings from `from` to `to` in `steps` increments.
static func counter_spec(
	from: float, to: float, steps: int, duration: float,
	format: String, prefix: String, suffix: String, method: String,
) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if steps < 1:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'steps' must be >= 1")
	if method.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "'method' must not be empty")
	var keys: Array = []
	for index in steps + 1:
		var ratio := float(index) / float(steps)
		var value := from + (to - from) * ratio
		var label := ""
		if format.contains("%d"):
			label = format % int(round(value))
		elif format.contains("%"):
			label = format % value
		else:
			label = format
		keys.append({
			"time": duration * ratio,
			"method": method,
			"args": [prefix + label + suffix],
		})
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_method_track(spec, "", keys)
	return {"spec": spec, "steps": steps}


# --- wave ------------------------------------------------------------------

## Cascading sine offsets: every target bobs along one axis, each shifted by
## `phase_step` seconds, looping seamlessly.
static func wave_spec(
	paths: Array, baselines: Array, axis: String, amplitude: float,
	period: float, phase_step: float, cycles: int,
) -> Dictionary:
	if amplitude <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'amplitude' must be > 0")
	if period <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'period' must be > 0")
	if cycles < 1:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'cycles' must be >= 1")
	if paths.size() != baselines.size():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "paths and baselines must match")
	var length := period * float(cycles)
	var samples := _WAVE_SEGMENTS_PER_CYCLE * cycles
	var spec := ClipSpec.make(length, Animation.LOOP_LINEAR)
	for index in paths.size():
		var baseline: Variant = baselines[index]
		var is_3d := baseline is Vector3
		var clean_axis := _clean_axes(axis, is_3d)
		if clean_axis.is_empty():
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"'axis' must contain at least one of x/y%s" % ("/z" if is_3d else ""))
		var offset_unit := _axis_unit(clean_axis, is_3d)
		var phase := (float(index) * phase_step) / period
		var keys: Array = []
		for sample in samples + 1:
			var time := length * float(sample) / float(samples)
			var wave := sin(TAU * (time / period + phase))
			keys.append({
				"time": time,
				"value": baseline + offset_unit * (amplitude * wave),
				"transition": 1.0,
			})
		ClipSpec.add_value_track(spec, str(paths[index]), keys)
	return {"spec": spec, "target_count": paths.size(), "length": length}


static func _axis_unit(axes: String, is_3d: bool) -> Variant:
	if is_3d:
		return Vector3(
			1.0 if axes.contains("x") else 0.0,
			1.0 if axes.contains("y") else 0.0,
			1.0 if axes.contains("z") else 0.0,
		)
	return Vector2(1.0 if axes.contains("x") else 0.0, 1.0 if axes.contains("y") else 0.0)


# --- spring ----------------------------------------------------------------

## Damped spring settle from the baseline to baseline + offset (step response).
static func spring_spec(
	baseline: Variant, offset: Variant, frequency: float,
	damping: float, duration: float, samples: int,
) -> Dictionary:
	if frequency <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'frequency' must be > 0")
	if damping <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'damping' must be > 0")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if typeof(baseline) != typeof(offset):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "'offset' must match the target's position type")
	samples = clampi(samples, 4, _MAX_KEYS - 1)
	var omega := TAU * frequency
	var keys: Array = []
	for index in samples + 1:
		var time := duration * float(index) / float(samples)
		var envelope := 1.0
		if damping < 1.0:
			var omega_d := omega * sqrt(1.0 - damping * damping)
			envelope = 1.0 - exp(-damping * omega * time) * cos(omega_d * time)
		else:
			envelope = 1.0 - (1.0 + omega * time) * exp(-omega * time)
		var value: Variant = baseline + offset * envelope
		if index == samples:
			value = baseline + offset
		keys.append({"time": time, "value": value, "transition": 1.0})
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec, "samples": samples}


# --- pendulum --------------------------------------------------------------

## Swinging rotation: a cosine swing with optional decay. 2D swings the
## `rotation` float, 3D swings the local Z euler component.
static func pendulum_spec(
	baseline: Variant, amplitude_deg: float, period: float,
	duration: float, decay: float,
) -> Dictionary:
	if amplitude_deg == 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'amplitude' must not be 0")
	if period <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'period' must be > 0")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if decay <= 0.0 or decay > 1.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'decay' must be in (0, 1]")
	var samples := clampi(int(ceil(duration / period * 16.0)), 8, _MAX_KEYS - 1)
	var amplitude := deg_to_rad(amplitude_deg)
	var keys: Array = []
	for index in samples + 1:
		var time := duration * float(index) / float(samples)
		var angle := amplitude * cos(TAU * time / period) * pow(decay, time / duration)
		var value: Variant
		if baseline is Vector3:
			var euler := baseline as Vector3
			value = Vector3(euler.x, euler.y, euler.z + angle)
		else:
			value = float(baseline) + angle
		keys.append({"time": time, "value": value, "transition": 1.0})
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec, "samples": samples}


# --- path_follow -----------------------------------------------------------

## Position keys sampled along pre-computed points (the op samples the curve).
static func path_follow_spec(points: Array, duration: float, loop_mode: int) -> Dictionary:
	if points.size() < 2:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "The path needs at least 2 sampled points")
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	var keys: Array = []
	for index in points.size():
		keys.append({
			"time": duration * float(index) / float(points.size() - 1),
			"value": points[index],
			"transition": 1.0,
		})
	var spec := ClipSpec.make(duration, loop_mode)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec, "samples": points.size()}


# --- flipbook --------------------------------------------------------------

## Step a Sprite2D's `frame` through a range with nearest interpolation.
static func flipbook_spec(from_frame: int, frames: int, fps: float, loop_mode: int) -> Dictionary:
	if frames < 1:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'frames' must be >= 1")
	if fps <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'fps' must be > 0")
	var duration := float(frames) / fps
	var keys: Array = []
	for index in frames:
		keys.append({
			"time": duration * float(index) / float(frames),
			"value": from_frame + index,
			"transition": 1.0,
		})
	var spec := ClipSpec.make(duration, loop_mode)
	ClipSpec.add_value_track(spec, "", keys, Animation.INTERPOLATION_NEAREST)
	return {"spec": spec, "frames": frames, "length": duration}


# --- sprite_frames ---------------------------------------------------------

## Slice `texture` into an `hframes` x `vframes` sheet and build a SpriteFrames
## resource with one animation. Returns `{frames, frame_count, cell_size}`.
static func sprite_frames_build(
	texture: Texture2D, hframes: int, vframes: int, fps: float,
	loop: bool, from_frame: int, to_frame: int, animation_name: String,
) -> Dictionary:
	if texture == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "A texture is required to slice")
	if hframes < 1 or vframes < 1:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'hframes' and 'vframes' must be >= 1")
	if fps <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'fps' must be > 0")
	var total := hframes * vframes
	if from_frame < 0 or to_frame >= total or to_frame < from_frame:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"'from_frame'/'to_frame' must be inside 0..%d (got %d..%d)" % [total - 1, from_frame, to_frame])
	var cell := Vector2(
		float(texture.get_width()) / float(hframes),
		float(texture.get_height()) / float(vframes),
	)
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, loop)
	for index in range(from_frame, to_frame + 1):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			Vector2(float(index % hframes), float(index / hframes)) * cell,
			cell,
		)
		frames.add_frame(animation_name, atlas)
	return {
		"frames": frames,
		"frame_count": to_frame - from_frame + 1,
		"cell_size": cell,
	}


# --- audio_cue -------------------------------------------------------------

## One audio key on a new clip, so a cue can be scheduled on the player.
static func audio_cue_spec(stream: AudioStream, time: float, start_offset: float, end_offset: float) -> Dictionary:
	if stream == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "An audio stream is required")
	if time < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'time' must be >= 0")
	var stream_length := 0.0
	if stream is AudioStream:
		stream_length = maxf(0.0, stream.get_length() - start_offset - end_offset)
	var length := maxf(time + stream_length, 0.1)
	var spec := ClipSpec.make(length, Animation.LOOP_NONE)
	ClipSpec.add_audio_track(spec, "", [{
		"time": time,
		"stream": stream,
		"start_offset": start_offset,
		"end_offset": end_offset,
	}])
	return {"spec": spec, "stream_length": stream_length}


# --- transition ------------------------------------------------------------

## Full-screen transition: `fade_in`/`fade_out` animate the overlay's alpha,
## `wipe_*` animate its scale (the op recenters the Control pivot first).
static func transition_spec(mode: String, duration: float) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	match mode:
		"fade_in":
			ClipSpec.add_value_track(spec, "", [
				{"time": 0.0, "value": 1.0, "transition": 1.0},
				{"time": duration, "value": 0.0, "transition": 1.0},
			])
		"fade_out":
			ClipSpec.add_value_track(spec, "", [
				{"time": 0.0, "value": 0.0, "transition": 1.0},
				{"time": duration, "value": 1.0, "transition": 1.0},
			])
		"wipe_right", "wipe_left", "wipe_up", "wipe_down":
			ClipSpec.add_value_track(spec, "", [
				{"time": 0.0, "value": Vector2.ZERO, "transition": 1.0},
				{"time": duration, "value": Vector2.ONE, "transition": 0.5},
			])
		_:
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"Invalid transition mode '%s'. Valid: fade_in, fade_out, wipe_right, wipe_left, wipe_up, wipe_down" % mode)
	return {"spec": spec}


# --- dialog_pop ------------------------------------------------------------

## Modal entrance: scale up from `from_scale` through `overshoot` to the
## baseline, optionally fading the alpha in.
static func dialog_pop_spec(
	baseline_scale: Variant, from_scale: float, overshoot: float,
	duration: float, fade: bool, base_alpha: float,
) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if from_scale <= 0.0 or overshoot <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'from_scale' and 'overshoot' must be > 0")
	if not (baseline_scale is Vector2 or baseline_scale is Vector3):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "dialog_pop targets a Control or Node2D/Node3D scale")
	var start: Variant
	if baseline_scale is Vector2:
		start = (baseline_scale as Vector2) * from_scale
	else:
		start = (baseline_scale as Vector3) * from_scale
	var peak: Variant = baseline_scale * overshoot
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", [
		{"time": 0.0, "value": start, "transition": 1.0},
		{"time": duration * 0.6, "value": peak, "transition": 0.5},
		{"time": duration, "value": baseline_scale, "transition": 1.0},
	])
	if fade:
		var alpha_track := ClipSpec.find_track_index(spec, "modulate:a")
		if alpha_track < 0:
			ClipSpec.add_value_track(spec, "modulate:a", [
				{"time": 0.0, "value": 0.0, "transition": 1.0},
				{"time": duration * 0.6, "value": base_alpha, "transition": 1.0},
			])
	return {"spec": spec}


# --- damage_bar ------------------------------------------------------------

## Delayed follow-up: hold at `from`, then ease to `to` after `delay`.
static func damage_bar_spec(from: float, to: float, delay: float, duration: float) -> Dictionary:
	if duration <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'duration' must be > 0")
	if delay < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'delay' must be >= 0")
	var keys: Array = [{"time": 0.0, "value": from, "transition": 1.0}]
	if delay > 0.0:
		keys.append({"time": delay, "value": from, "transition": 1.0})
	keys.append({"time": delay + duration, "value": to, "transition": 0.5})
	var spec := ClipSpec.make(delay + duration, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "", keys)
	return {"spec": spec}
