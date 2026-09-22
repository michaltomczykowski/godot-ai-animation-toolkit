@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## One-call generators for game feel, UI, sprites and audio — the
## `animation_fx` tool.
##
## Same contract as the presets: resolve the target, build a ClipSpec with the
## pure builders in `spec/fx_specs.gd`, then commit ONE scene-pinned undo action.
## `sprite_frames` is the exception: it builds a SpriteFrames resource and
## assigns it to the node instead of a clip.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const FxSpecs := preload("res://addons/godot_ai_animation/spec/fx_specs.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const _LOOP_MODES := {
	"none": Animation.LOOP_NONE,
	"linear": Animation.LOOP_LINEAR,
	"pingpong": Animation.LOOP_PINGPONG,
}

const _MAX_WAVE_TARGETS := 64


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	var result := _dispatch(params)
	if _dry_run and result.has("data"):
		result.data["dry_run"] = true
		result.data["undoable"] = false
	return result


func _dispatch(params: Dictionary) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"shake":
			return fx_shake(params)
		"zoom_punch":
			return fx_zoom_punch(params)
		"hit_flash":
			return fx_hit_flash(params)
		"typewriter":
			return fx_typewriter(params)
		"progress_fill":
			return fx_progress_fill(params)
		"counter":
			return fx_counter(params)
		"wave":
			return fx_wave(params)
		"spring":
			return fx_spring(params)
		"pendulum":
			return fx_pendulum(params)
		"path_follow":
			return fx_path_follow(params)
		"flipbook":
			return fx_flipbook(params)
		"sprite_frames":
			return fx_sprite_frames(params)
		"audio_cue":
			return fx_audio_cue(params)
		"transition":
			return fx_transition(params)
		"dialog_pop":
			return fx_dialog_pop(params)
		"damage_bar":
			return fx_damage_bar(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_FX))])


# ============================================================================
# Camera / game feel
# ============================================================================

## Decaying screen shake on a Camera2D/Camera3D/Control position.
func fx_shake(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var target: Node = context.target
	var property := str(params.get("property", "position"))
	var baseline: Variant = target.get(property)
	if not (baseline is Vector2 or baseline is Vector3):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"shake needs a Vector2/Vector3 property (got '%s' of type %s)" % [property, ClipSpec.value_kind(baseline)])
	var intensity := float(params.get("intensity", 8.0))
	var duration := float(params.get("duration", 0.4))
	var frequency := float(params.get("frequency", 20.0))
	var decay := float(params.get("decay", 0.15))
	var seed_value := int(params.get("seed", 0))
	var axes := str(params.get("axis", "xyz" if baseline is Vector3 else "xy"))
	var built := FxSpecs.shake_spec(baseline, intensity, duration, frequency, decay, seed_value, axes)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Shake %s" % context.track_path_root, {
		"intensity": intensity,
		"frequency": frequency,
		"decay": decay,
		"seed": seed_value,
		"samples": built.samples,
		"property": property,
	})


## Camera punch: overshoot then settle on Camera2D `zoom` or Camera3D `fov`.
func fx_zoom_punch(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var target: Node = context.target
	if not (target is Camera2D or target is Camera3D):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"zoom_punch targets a Camera2D or Camera3D (got %s)" % target.get_class())
	var property := "zoom" if target is Camera2D else "fov"
	var baseline: Variant = target.get(property)
	var amount := float(params.get("amount", 0.08))
	var duration := float(params.get("duration", 0.25))
	var peak_ratio := float(params.get("peak_ratio", 0.3))
	var built := FxSpecs.zoom_punch_spec(baseline, amount, duration, peak_ratio)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Zoom punch %s" % context.track_path_root, {
		"amount": amount,
		"property": property,
		"base_value": ValueCodec.serialize(baseline),
	})


## Flash a CanvasItem's modulate (damage / hit feedback).
func fx_hit_flash(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var target: Node = context.target
	if not target is CanvasItem:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"hit_flash targets a CanvasItem (Control/Node2D), got %s" % target.get_class())
	var base_color: Color = (target as CanvasItem).modulate
	var flash := _coerce_color(params.get("color", Color(1, 1, 1, 1)))
	if flash == null:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "'color' must be a hex string or {r,g,b[,a]} dict")
	var duration := float(params.get("duration", 0.18))
	var count := int(params.get("count", 1))
	var built := FxSpecs.hit_flash_spec(base_color, flash, duration, count)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "modulate")
	return _commit_spec(context, built.spec, "MCP: Hit flash %s" % context.track_path_root, {
		"color": ValueCodec.serialize(flash),
		"count": count,
	})


## Delayed follow-up bar: hold, then ease to the new value.
func fx_damage_bar(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var property := str(params.get("property", "value"))
	var baseline: Variant = context.target.get(property)
	if not (baseline is float or baseline is int):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"damage_bar needs a numeric property (got '%s' of type %s)" % [property, ClipSpec.value_kind(baseline)])
	var from := float(params.get("from", baseline))
	var to := float(params.get("to", 0.0))
	var delay := float(params.get("delay", 0.25))
	var duration := float(params.get("duration", 0.4))
	var built := FxSpecs.damage_bar_spec(from, to, delay, duration)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Damage bar %s" % context.track_path_root, {
		"from": from,
		"to": to,
		"delay": delay,
		"property": property,
	})


# ============================================================================
# UI / text
# ============================================================================

## Reveal a Label/RichTextLabel's text with `visible_ratio`.
func fx_typewriter(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var property := str(params.get("property", "visible_ratio"))
	var duration := float(params.get("duration", 1.5))
	var steps := int(params.get("steps", 0))
	var delay := float(params.get("delay", 0.0))
	var from_ratio := float(params.get("from_ratio", 0.0))
	var to_ratio := float(params.get("to_ratio", 1.0))
	var built := FxSpecs.typewriter_spec(duration, steps, delay, from_ratio, to_ratio)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Typewriter %s" % context.track_path_root, {
		"steps": steps,
		"delay": delay,
		"property": property,
	})


## Fill a numeric property (ProgressBar value, modulate:a, custom float).
func fx_progress_fill(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var property := str(params.get("property", "value"))
	var baseline: Variant = context.target.get(property)
	if not (baseline is float or baseline is int):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"progress_fill needs a numeric property (got '%s' of type %s)" % [property, ClipSpec.value_kind(baseline)])
	var from := float(params.get("from", baseline))
	var to := float(params.get("to", 1.0))
	var duration := float(params.get("duration", 0.8))
	var delay := float(params.get("delay", 0.0))
	var built := FxSpecs.progress_fill_spec(from, to, duration, delay)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Progress fill %s" % context.track_path_root, {
		"from": from,
		"to": to,
		"delay": delay,
		"property": property,
	})


## Rolling numbers: a method-track clip that calls a setter with formatted text.
func fx_counter(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var from := float(params.get("from", 0.0))
	var to := float(params.get("to", 100.0))
	var steps := int(params.get("steps", 30))
	var duration := float(params.get("duration", 1.0))
	var format := str(params.get("format", "%d"))
	var prefix := str(params.get("prefix", ""))
	var suffix := str(params.get("suffix", ""))
	var method := str(params.get("method", "set_text"))
	var built := FxSpecs.counter_spec(from, to, steps, duration, format, prefix, suffix, method)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "")
	return _commit_spec(context, built.spec, "MCP: Counter %s" % context.track_path_root, {
		"from": from,
		"to": to,
		"steps": steps,
		"method": method,
	})


## Modal entrance: scale through an overshoot, optionally fading in.
func fx_dialog_pop(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var baseline: Variant = context.target.get("scale")
	if not (baseline is Vector2 or baseline is Vector3):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"dialog_pop needs a Control/Node2D/Node3D scale (got %s)" % ClipSpec.value_kind(baseline))
	var from_scale := float(params.get("from_scale", 0.85))
	var overshoot := float(params.get("overshoot", 1.06))
	var duration := float(params.get("duration", 0.35))
	var fade := bool(params.get("fade", true))
	var base_alpha := 1.0
	if context.target is CanvasItem:
		base_alpha = (context.target as CanvasItem).modulate.a
	var built := FxSpecs.dialog_pop_spec(baseline, from_scale, overshoot, duration, fade, base_alpha)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "scale")
	return _commit_spec(context, built.spec, "MCP: Dialog pop %s" % context.track_path_root, {
		"from_scale": from_scale,
		"overshoot": overshoot,
		"fade": fade,
	})


## Full-screen fade/wipe transition on an overlay Control.
func fx_transition(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var target: Node = context.target
	if not target is Control:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"transition targets a full-screen Control overlay (got %s)" % target.get_class())
	var mode := str(params.get("mode", "fade_out"))
	var duration := float(params.get("duration", 0.5))
	var built := FxSpecs.transition_spec(mode, duration)
	if built.has("error"):
		return built
	var extra_props: Array = []
	var property := "modulate:a"
	if mode.begins_with("wipe_"):
		property = "scale"
		var pivot := _wipe_pivot(mode, (target as Control).size)
		if not (target as Control).pivot_offset.is_equal_approx(pivot):
			extra_props.append({
				"object": target,
				"property": "pivot_offset",
				"value": pivot,
				"old": (target as Control).pivot_offset,
			})
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Transition %s" % mode, {
		"mode": mode,
		"property": property,
		"pivot_recentered": not extra_props.is_empty(),
	}, extra_props)


static func _wipe_pivot(mode: String, size: Vector2) -> Vector2:
	match mode:
		"wipe_right":
			return Vector2(0.0, size.y * 0.5)
		"wipe_left":
			return Vector2(size.x, size.y * 0.5)
		"wipe_down":
			return Vector2(size.x * 0.5, 0.0)
		"wipe_up":
			return Vector2(size.x * 0.5, size.y)
	return size * 0.5


# ============================================================================
# Motion
# ============================================================================

## Cascading sine bob for a list of targets (or the editor selection).
func fx_wave(params: Dictionary) -> Dictionary:
	var player_result := _fx_player(params)
	if player_result.has("error"):
		return player_result
	var player: AnimationPlayer = player_result.player
	var paths_result := _fx_target_paths(player, params)
	if paths_result.has("error"):
		return paths_result
	var paths: Array = paths_result.paths
	if paths.size() > _MAX_WAVE_TARGETS:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"wave supports up to %d targets (got %d)" % [_MAX_WAVE_TARGETS, paths.size()])
	var baselines: Array = []
	var track_paths: Array = []
	for entry in paths:
		var resolved := _fx_target(player, str(entry))
		if resolved.has("error"):
			return resolved
		var baseline: Variant = resolved.target.get("position")
		if not (baseline is Vector2 or baseline is Vector3):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"wave needs a Vector2/Vector3 position on %s" % str(entry))
		baselines.append(baseline)
		track_paths.append(resolved.track_path_root)
	var built := FxSpecs.wave_spec(track_paths, baselines, str(params.get("axis", "y")),
		float(params.get("amplitude", 12.0)), float(params.get("period", 1.2)),
		float(params.get("phase_step", 0.12)), int(params.get("cycles", 1)))
	if built.has("error"):
		return built
	var loop_result := _loop_mode(params, "linear")
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	built.spec.loop_mode = loop_result.ok
	return _commit_spec(player_result, built.spec, "MCP: Wave", {
		"target_count": built.target_count,
		"amplitude": float(params.get("amplitude", 12.0)),
		"period": float(params.get("period", 1.2)),
		"phase_step": float(params.get("phase_step", 0.12)),
	})


## Damped spring settle from the current position to position + offset.
func fx_spring(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var baseline: Variant = context.target.get("position")
	if not (baseline is Vector2 or baseline is Vector3):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"spring needs a Vector2/Vector3 position (got %s)" % ClipSpec.value_kind(baseline))
	var offset := _coerce_vector(params.get("offset"), baseline)
	if offset == null:
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"spring needs 'offset' as {x,y[,z]} matching the target's position type")
	var built := FxSpecs.spring_spec(baseline, offset, float(params.get("frequency", 2.0)),
		float(params.get("damping", 0.35)), float(params.get("duration", 1.0)), int(params.get("samples", 30)))
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "position")
	return _commit_spec(context, built.spec, "MCP: Spring %s" % context.track_path_root, {
		"offset": ValueCodec.serialize(offset),
		"frequency": float(params.get("frequency", 2.0)),
		"damping": float(params.get("damping", 0.35)),
	})


## Swinging rotation (2D `rotation` float, 3D local-Z euler).
func fx_pendulum(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var property := "rotation"
	var baseline: Variant = context.target.get(property)
	if not (baseline is float or baseline is int or baseline is Vector3):
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"pendulum needs a 2D rotation float or a 3D rotation Vector3 (got %s)" % ClipSpec.value_kind(baseline))
	var built := FxSpecs.pendulum_spec(baseline, float(params.get("amplitude", 18.0)),
		float(params.get("period", 1.0)), float(params.get("duration", 2.0)),
		float(params.get("decay", 1.0)))
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, property)
	return _commit_spec(context, built.spec, "MCP: Pendulum %s" % context.track_path_root, {
		"amplitude": float(params.get("amplitude", 18.0)),
		"period": float(params.get("period", 1.0)),
		"decay": float(params.get("decay", 1.0)),
	})


## Follow a Path2D/Path3D curve.
func fx_path_follow(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var path_node_path := str(params.get("path_node", ""))
	if path_node_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "path_follow needs 'path_node'")
	var scene_root := EditorInterface.get_edited_scene_root()
	var path_node := ValueCodec.resolve_scene_path(path_node_path, scene_root)
	if path_node == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(path_node_path, scene_root))
	var points_result := _sample_path(path_node, context.target, int(params.get("samples", 24)))
	if points_result.has("error"):
		return points_result
	var duration := float(params.get("duration", 2.0))
	var loop_result := _loop_mode(params, "none")
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var built := FxSpecs.path_follow_spec(points_result.points, duration, loop_result.ok)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "position")
	return _commit_spec(context, built.spec, "MCP: Path follow %s" % context.track_path_root, {
		"path_node": path_node_path,
		"samples": built.samples,
	})


func _sample_path(path_node: Node, target: Node, samples: int) -> Dictionary:
	samples = clampi(samples, 2, 512)
	var points: Array = []
	var target_parent := target.get_parent()
	if path_node is Path2D and target is Node2D:
		var curve: Curve2D = (path_node as Path2D).curve
		if curve == null or curve.point_count < 2:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The Path2D curve needs at least 2 points")
		for index in samples:
			var local := curve.sample_baked(curve.get_baked_length() * float(index) / float(samples - 1))
			var global := (path_node as Node2D).to_global(local)
			points.append((target_parent as Node2D).to_local(global) if target_parent is Node2D else global)
		return {"points": points}
	if path_node is Path3D and target is Node3D:
		var curve3: Curve3D = (path_node as Path3D).curve
		if curve3 == null or curve3.point_count < 2:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The Path3D curve needs at least 2 points")
		for index in samples:
			var local3 := curve3.sample_baked(curve3.get_baked_length() * float(index) / float(samples - 1))
			var global3 := (path_node as Path3D).to_global(local3)
			points.append((target_parent as Node3D).to_local(global3) if target_parent is Node3D else global3)
		return {"points": points}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"path_follow needs a Path2D with a Node2D target or a Path3D with a Node3D target (path is %s, target is %s)"
		% [path_node.get_class(), target.get_class()])


# ============================================================================
# Sprites / audio
# ============================================================================

## Step a Sprite2D's `frame` through a range.
func fx_flipbook(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var frames := int(params.get("frames", 4))
	var fps := float(params.get("fps", 12.0))
	var from_frame := int(params.get("from_frame", 0))
	var loop_result := _loop_mode(params, "linear")
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var built := FxSpecs.flipbook_spec(from_frame, frames, fps, loop_result.ok)
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, str(params.get("property", "frame")))
	return _commit_spec(context, built.spec, "MCP: Flipbook %s" % context.track_path_root, {
		"frames": frames,
		"fps": fps,
		"length": built.length,
	})


## Build a SpriteFrames resource from a spritesheet and assign it to the node.
func fx_sprite_frames(params: Dictionary) -> Dictionary:
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var sprite_path := str(params.get("sprite_path", ""))
	if sprite_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "sprite_frames needs 'sprite_path'")
	var texture_path := str(params.get("texture", ""))
	if texture_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "sprite_frames needs 'texture'")
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var node := ValueCodec.resolve_scene_path(sprite_path, scene_root)
	if node == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(sprite_path, scene_root))
	if not node is AnimatedSprite2D:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			("sprite_frames targets an AnimatedSprite2D (got %s). For a Sprite2D sheet use "
			+ "flipbook plus hframes/vframes on the node.") % node.get_class())
	if not ResourceLoader.exists(texture_path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Texture not found: %s" % texture_path)
	var texture: Texture2D = load(texture_path)
	if texture == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Could not load texture: %s" % texture_path)
	var hframes := int(params.get("hframes", 4))
	var vframes := int(params.get("vframes", 1))
	var fps := float(params.get("fps", 12.0))
	var loop := bool(params.get("loop", true))
	var from_frame := int(params.get("from_frame", 0))
	var to_frame := int(params.get("to_frame", hframes * vframes - 1))
	var animation_name := str(params.get("animation_name", "default"))
	var built := FxSpecs.sprite_frames_build(
		texture, hframes, vframes, fps, loop, from_frame, to_frame, animation_name)
	if built.has("error"):
		return built
	var sprite := node as AnimatedSprite2D
	var old_frames: Variant = sprite.sprite_frames
	var old_playing := sprite.is_playing()
	sprite.stop()
	var play := bool(params.get("play", true))
	_create_scene_pinned_action("MCP: Sprite frames %s" % sprite_path)
	var undo := ToolContext.undo_redo
	undo.add_do_property(node, "sprite_frames", built.frames)
	undo.add_undo_property(node, "sprite_frames", old_frames)
	undo.add_do_reference(built.frames)
	undo.add_do_method(sprite, "play", animation_name)
	if old_playing:
		undo.add_undo_method(sprite, "play")
	else:
		undo.add_undo_method(sprite, "stop")
	undo.commit_action()
	return {"data": {
		"sprite_path": sprite_path,
		"texture": texture_path,
		"animation_name": animation_name,
		"frame_count": built.frame_count,
		"cell_size": ValueCodec.serialize(built.cell_size),
		"fps": fps,
		"loop": loop,
		"playing": play,
		"undoable": true,
	}}


## Schedule an audio cue on the player as a one-key audio clip.
func fx_audio_cue(params: Dictionary) -> Dictionary:
	var context := _fx_context(params)
	if context.has("error"):
		return context
	var stream_path := str(params.get("stream", ""))
	if stream_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "audio_cue needs 'stream'")
	if not ResourceLoader.exists(stream_path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Audio stream not found: %s" % stream_path)
	var stream: AudioStream = load(stream_path)
	if stream == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Could not load audio stream: %s" % stream_path)
	var built := FxSpecs.audio_cue_spec(stream, float(params.get("time", 0.0)),
		float(params.get("start_offset", 0.0)), float(params.get("end_offset", 0.0)))
	if built.has("error"):
		return built
	FxSpecs.assign_paths(built.spec, context.track_path_root, "")
	return _commit_spec(context, built.spec, "MCP: Audio cue %s" % stream_path, {
		"stream": stream_path,
		"stream_length": built.stream_length,
	})


# ============================================================================
# Helpers
# ============================================================================

## Resolve player + target for a single-target FX op.
func _fx_context(params: Dictionary) -> Dictionary:
	var player_result := _fx_player(params)
	if player_result.has("error"):
		return player_result
	var target_path := str(params.get("target_path", ""))
	if target_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: target_path")
	var resolved := _fx_target(player_result.player, target_path)
	if resolved.has("error"):
		return resolved
	return {
		"player": player_result.player,
		"player_path": player_result.player_path,
		"library": player_result.library,
		"library_created": player_result.library_created,
		"animation_name": player_result.animation_name,
		"overwrite": player_result.overwrite,
		"op_name": player_result.op_name,
		"target": resolved.target,
		"track_path_root": resolved.track_path_root,
	}


func _fx_player(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "Missing required param: player_path")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	if library == null:
		library = AnimationLibrary.new()
	return {
		"player": player,
		"player_path": player_path,
		"library": library,
		"library_created": resolved.library == null,
		"animation_name": str(params.get("animation_name", "")),
		"overwrite": bool(params.get("overwrite", false)),
		"op_name": str(params.get("op", "")),
	}


## Resolve one target against the player's root node (scene-absolute or
## relative), mirroring the presets' target vocabulary.
func _fx_target(player: AnimationPlayer, target_path: String) -> Dictionary:
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no resolvable root_node (is the scene open?)" % str(player.get_path()))
	var target: Node = null
	var track_path_root := target_path
	if target_path.begins_with("/"):
		var scene_root := EditorInterface.get_edited_scene_root()
		if scene_root == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Cannot resolve scene-absolute target_path '%s': no scene open" % target_path)
		target = ValueCodec.resolve_scene_path(target_path, scene_root)
		if target == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, ValueCodec.format_node_error(target_path, scene_root))
		track_path_root = str(root_node.get_path_to(target))
	else:
		target = root_node.get_node_or_null(target_path)
		if target == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Target node not found at '%s' (relative to the player's root_node '%s')" % [target_path, str(root_node.name)])
	return {"target": target, "track_path_root": track_path_root}


func _fx_target_paths(player: AnimationPlayer, params: Dictionary) -> Dictionary:
	if params.has("target_paths"):
		var raw = params.get("target_paths")
		if not raw is Array or (raw as Array).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'target_paths' must be a non-empty array")
		return {"paths": raw}
	if bool(params.get("use_selection", false)):
		var selection := EditorInterface.get_selection()
		if selection == null:
			return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No editor selection available")
		var root_node := ValueCodec.player_root_node(player)
		var paths: Array = []
		for node in selection.get_selected_nodes():
			if root_node == null or not root_node.is_ancestor_of(node):
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"Selected node '%s' is outside the player's root_node subtree" % str(node.name))
			paths.append(str(root_node.get_path_to(node)))
		if paths.is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The editor selection is empty")
		return {"paths": paths}
	return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
		"Pass 'target_paths' or use_selection=true")


## Build the spec into an Animation and commit it as one undo action.
func _commit_spec(
	context: Dictionary, spec: Dictionary, action_label: String, extra: Dictionary,
	extra_props: Array = [],
) -> Dictionary:
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var anim_name := str(context.get("animation_name", ""))
	if anim_name.is_empty():
		anim_name = str(context.get("op_name", "fx"))
	var overwrite := bool(context.get("overwrite", false))
	var existing := _existing_animation(context.library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var anim := SpecBuilder.to_animation(spec)
	_commit_animation_add(action_label, context.player, context.library,
		bool(context.get("library_created", false)), anim_name, anim, existing.old_anim, extra_props)
	var data := {
		"player_path": str(context.get("player_path", "")),
		"animation_name": anim_name,
		"length": float(spec.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(spec.loop_mode)),
		"track_count": (spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"overwritten": existing.old_anim != null,
		"undoable": true,
	}
	data.merge(extra, true)
	return {"data": data}


static func _loop_mode(params: Dictionary, default_mode: String) -> Dictionary:
	var mode := str(params.get("loop_mode", default_mode))
	if not _LOOP_MODES.has(mode):
		return {"error": "Invalid loop_mode '%s'. Valid: %s" % [mode, ", ".join(_LOOP_MODES.keys())]}
	return {"ok": _LOOP_MODES[mode]}


func _coerce_vector(raw: Variant, like: Variant) -> Variant:
	if raw == null:
		return null
	if like is Vector3:
		if raw is Vector3:
			return raw
		if raw is Dictionary and raw.has("x") and raw.has("y"):
			return Vector3(float(raw.x), float(raw.y), float(raw.get("z", 0.0)))
		if raw is Array and (raw as Array).size() == 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		return null
	if raw is Vector2:
		return raw
	if raw is Dictionary and raw.has("x") and raw.has("y"):
		return Vector2(float(raw.x), float(raw.y))
	if raw is Array and (raw as Array).size() == 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return null


static func _coerce_color(raw: Variant) -> Variant:
	if raw is Color:
		return raw
	if raw is String:
		var parsed := Color.from_string(raw as String, Color(-1, -1, -1, -1))
		if parsed != Color(-1, -1, -1, -1):
			return parsed
		return null
	if raw is Dictionary and raw.has("r") and raw.has("g") and raw.has("b"):
		return Color(float(raw.r), float(raw.g), float(raw.b), float(raw.get("a", 1.0)))
	return null
