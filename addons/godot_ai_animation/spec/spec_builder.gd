@tool
extends RefCounted

## Spec -> Animation. The only place the toolkit creates an Animation resource,
## so every generator and edit op produces identical track plumbing (typed
## tracks, interpolation, loop wrap, markers).

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")


## Structural check: {} when the spec can be built, else an error dict.
static func validate(spec: Dictionary) -> Dictionary:
	if not spec.has("tracks"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Clip spec is missing 'tracks'")
	if not spec.has("length"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Clip spec is missing 'length'")
	if float(spec.length) < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Clip spec 'length' must be >= 0")
	var tracks: Array = spec.tracks
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var type := int(track.get("type", -1))
		if not ClipSpec.is_supported_type(type):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"Track %d has unsupported type %d (supported: value, position_3d, rotation_3d, scale_3d, method, audio)" % [i, type])
		if str(track.get("path", "")).is_empty():
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Track %d has an empty path" % i)
		for key in track.get("keys", []):
			if not key.has("time"):
				return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
					"Track %d has a key without 'time'" % i)
	return {}


static func to_animation(spec: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = float(spec.get("length", 0.0))
	anim.loop_mode = int(spec.get("loop_mode", Animation.LOOP_NONE))
	for marker in spec.get("markers", []):
		var marker_name := StringName(str(marker.get("name", "")))
		if marker_name == StringName():
			continue
		anim.add_marker(marker_name, float(marker.get("time", 0.0)))
		if marker.has("color"):
			anim.set_marker_color(marker_name, marker.get("color"))
	for track in spec.get("tracks", []):
		_build_track(anim, track)
	return anim


static func _build_track(anim: Animation, track: Dictionary) -> void:
	var type := int(track.get("type", Animation.TYPE_VALUE))
	var index := anim.add_track(type)
	anim.track_set_path(index, NodePath(str(track.get("path", ""))))
	anim.track_set_enabled(index, bool(track.get("enabled", true)))
	match type:
		Animation.TYPE_VALUE:
			anim.track_set_interpolation_type(index, int(track.get("interp", Animation.INTERPOLATION_LINEAR)))
			anim.value_track_set_update_mode(index, int(track.get("update_mode", Animation.UPDATE_CONTINUOUS)))
			for key in track.get("keys", []):
				anim.track_insert_key(
					index, float(key.get("time", 0.0)), key.get("value"),
					float(key.get("transition", 1.0)),
				)
		Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
			anim.track_set_interpolation_type(index, int(track.get("interp", Animation.INTERPOLATION_LINEAR)))
			anim.track_set_interpolation_loop_wrap(index, bool(track.get("loop_wrap", true)))
			for key in track.get("keys", []):
				anim.track_insert_key(index, float(key.get("time", 0.0)), key.get("value"))
		Animation.TYPE_METHOD:
			for key in track.get("keys", []):
				anim.track_insert_key(index, float(key.get("time", 0.0)), {
					"method": str(key.get("method", "")),
					"args": key.get("args", []),
				})
		Animation.TYPE_AUDIO:
			anim.audio_track_set_use_blend(index, bool(track.get("use_blend", false)))
			for key in track.get("keys", []):
				anim.audio_track_insert_key(
					index, float(key.get("time", 0.0)), key.get("stream"),
					float(key.get("start_offset", 0.0)), float(key.get("end_offset", 0.0)),
				)
