@tool
extends RefCounted

## Animation -> spec. Reads every track the toolkit understands, so an edit op
## can round-trip a clip it did not create (hand-authored clips included) and
## refuse the ones it cannot represent instead of silently dropping data.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")


static func from_animation(anim: Animation) -> Dictionary:
	var spec := ClipSpec.make(anim.length, anim.loop_mode)
	for marker_name in anim.get_marker_names():
		spec.markers.append({
			"name": String(marker_name),
			"time": anim.get_marker_time(marker_name),
			"color": anim.get_marker_color(marker_name),
		})
	for index in anim.get_track_count():
		spec.tracks.append(_read_track(anim, index))
	return spec


## Track indexes whose type the spec cannot represent. Edit ops refuse a clip
## when this is non-empty rather than losing the track on rewrite.
static func unsupported_tracks(anim: Animation) -> Array:
	var found: Array = []
	for index in anim.get_track_count():
		if not ClipSpec.is_supported_type(anim.track_get_type(index)):
			found.append({
				"track_index": index,
				"type": anim.track_get_type(index),
				"path": str(anim.track_get_path(index)),
			})
	return found


## Human-readable summary of what an edit op would refuse.
static func describe_unsupported(anim: Animation) -> String:
	var parts: Array = []
	for entry in unsupported_tracks(anim):
		parts.append("%s [%s]" % [entry.path, ClipSpec.type_name(int(entry.type))])
	return ", ".join(parts)


static func compressed_tracks(anim: Animation) -> Array:
	var found: Array = []
	for index in anim.get_track_count():
		if anim.track_is_compressed(index):
			found.append(str(anim.track_get_path(index)))
	return found


static func _read_track(anim: Animation, index: int) -> Dictionary:
	var type := anim.track_get_type(index)
	var track := {
		"type": type,
		"path": str(anim.track_get_path(index)),
		"enabled": anim.track_is_enabled(index),
		"compressed": anim.track_is_compressed(index),
		"keys": [],
	}
	var count := anim.track_get_key_count(index)
	match type:
		Animation.TYPE_VALUE:
			track["interp"] = anim.track_get_interpolation_type(index)
			track["update_mode"] = anim.value_track_get_update_mode(index)
			for key in count:
				track.keys.append({
					"time": anim.track_get_key_time(index, key),
					"value": anim.track_get_key_value(index, key),
					"transition": anim.track_get_key_transition(index, key),
				})
		Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
			track["interp"] = anim.track_get_interpolation_type(index)
			track["loop_wrap"] = anim.track_get_interpolation_loop_wrap(index)
			for key in count:
				track.keys.append({
					"time": anim.track_get_key_time(index, key),
					"value": anim.track_get_key_value(index, key),
					"transition": anim.track_get_key_transition(index, key),
				})
		Animation.TYPE_METHOD:
			for key in count:
				track.keys.append({
					"time": anim.track_get_key_time(index, key),
					"method": String(anim.method_track_get_name(index, key)),
					"args": anim.method_track_get_params(index, key),
				})
		Animation.TYPE_AUDIO:
			track["use_blend"] = anim.audio_track_is_use_blend(index)
			for key in count:
				track.keys.append({
					"time": anim.track_get_key_time(index, key),
					"stream": anim.audio_track_get_key_stream(index, key),
					"start_offset": anim.audio_track_get_key_start_offset(index, key),
					"end_offset": anim.audio_track_get_key_end_offset(index, key),
				})
	return track
