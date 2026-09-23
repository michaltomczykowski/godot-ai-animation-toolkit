extends SceneTree

## Tier-1 headless checks for the clip-spec JSON codec: value kind encoding,
## exact round-trips, remapping, summaries and validation. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_spec_json.gd

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecJson := preload("res://addons/godot_ai_animation/spec/spec_json.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_values()
	_check_roundtrip()
	_check_track_kinds()
	_check_remap()
	_check_summary()
	_check_validation()
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
	_expect(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_error(result: Dictionary, message: String) -> void:
	_expect(result.has("error"), message)


func _fixture() -> Dictionary:
	var spec := ClipSpec.make(1.2, Animation.LOOP_PINGPONG)
	ClipSpec.add_value_track(spec, "Sprite:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.6, "value": Vector2(12, 4), "transition": 2.0},
		{"time": 1.2, "value": Vector2(0, 0), "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, "Sprite:modulate:a", [
		{"time": 0.0, "value": 0.0},
		{"time": 1.2, "value": 1.0},
	])
	ClipSpec.add_value_track(spec, "Body:scale", [
		{"time": 0.0, "value": Vector3(1, 1, 1)},
		{"time": 1.2, "value": Vector3(1.2, 1.2, 1.2)},
	], Animation.INTERPOLATION_CUBIC, Animation.TYPE_SCALE_3D)
	ClipSpec.add_value_track(spec, "Body:rotation", [
		{"time": 0.0, "value": Quaternion(Vector3(0, 0, 1), PI / 4.0)},
		{"time": 1.2, "value": Quaternion.IDENTITY},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	ClipSpec.add_method_track(spec, "Sprite", [
		{"time": 0.3, "method": "on_beat", "args": [2, "x"]},
	])
	ClipSpec.add_audio_track(spec, "Sprite", [
		{"time": 0.1, "stream": load("res://tests/fixtures/cue.wav"), "start_offset": 0.0, "end_offset": 0.2},
	])
	ClipSpec.add_marker(spec, "peak", 0.6, Color(1, 0.5, 0.25, 1))
	return spec


func _check_values() -> void:
	var encoded := SpecJson.encode_value(Vector2(3, 4))
	_expect(not encoded.has("error"), "Vector2 encodes")
	_expect(str(encoded.ok.kind) == "vector2", "Vector2 carries its kind")
	_expect_approx(float(encoded.ok.x), 3.0, "Vector2 x is stored")
	var decoded := SpecJson.decode_value(encoded.ok)
	_expect(not decoded.has("error"), "Vector2 decodes")
	_expect((decoded.ok as Vector2).is_equal_approx(Vector2(3, 4)), "Vector2 round-trips")
	var quat := Quaternion(Vector3(0, 1, 0), PI / 3.0)
	var encoded_quat := SpecJson.encode_value(quat)
	_expect(str(encoded_quat.ok.kind) == "quaternion", "quaternions carry their kind")
	var decoded_quat := SpecJson.decode_value(encoded_quat.ok)
	_expect((decoded_quat.ok as Quaternion).is_equal_approx(quat), "quaternions round-trip")
	var color := Color(0.1, 0.2, 0.3, 0.4)
	var decoded_color := SpecJson.decode_value(SpecJson.encode_value(color).ok)
	_expect((decoded_color.ok as Color).is_equal_approx(color), "colors round-trip")
	var encoded_float := SpecJson.encode_value(1.5)
	_expect(encoded_float.ok is float, "floats stay bare numbers")
	_expect_approx(float(SpecJson.decode_value(2).ok), 2.0, "numbers decode as floats")
	_expect_error(SpecJson.encode_value("text"), "strings cannot be encoded")
	_expect_error(SpecJson.decode_value("text"), "strings cannot be decoded")
	_expect_error(SpecJson.decode_value({"x": 1}), "value dicts need a kind")
	_expect_error(SpecJson.decode_value({"kind": "blob"}), "unknown kinds are rejected")


func _check_roundtrip() -> void:
	var spec := _fixture()
	var json := SpecJson.to_json(spec)
	_expect(str(json.format) == SpecJson.FORMAT, "the envelope names the format")
	_expect(int(json.version) == SpecJson.VERSION, "the envelope carries a version")
	_expect_approx(float(json.length), 1.2, "length is exported")
	_expect(int(json.loop_mode) == Animation.LOOP_PINGPONG, "loop mode is exported")
	_expect((json.tracks as Array).size() == 6, "every track is exported")
	_expect((json.markers as Array).size() == 1, "markers are exported")
	_expect(str(json.markers[0].name) == "peak", "marker names are exported")
	var back := SpecJson.from_json(json)
	_expect(not back.has("error"), "the exported spec decodes")
	var restored: Dictionary = back.spec
	_expect_approx(float(restored.length), 1.2, "length round-trips")
	_expect(int(restored.loop_mode) == Animation.LOOP_PINGPONG, "loop mode round-trips")
	_expect((restored.tracks as Array).size() == 6, "track count round-trips")
	_expect_eq_keys(spec, restored)
	# The same JSON through a real Animation and back must still match.
	var anim := SpecBuilder.to_animation(restored)
	var reread := SpecIO.from_animation(anim)
	_expect_eq_keys(restored, reread)
	_expect(SpecJson.from_json(SpecJson.to_json(reread)).has("error") == false,
		"a second JSON generation still decodes")


func _expect_eq_keys(a: Dictionary, b: Dictionary) -> void:
	for index in (a.tracks as Array).size():
		var track_a: Dictionary = a.tracks[index]
		var track_b: Dictionary = b.tracks[index]
		_expect(str(track_a.path) == str(track_b.path), "track %d path round-trips" % index)
		_expect((track_a.keys as Array).size() == (track_b.keys as Array).size(),
			"track %d key count round-trips" % index)
		for key_index in (track_a.keys as Array).size():
			var key_a: Dictionary = track_a.keys[key_index]
			var key_b: Dictionary = track_b.keys[key_index]
			_expect_approx(float(key_a.time), float(key_b.time), "track %d key %d time" % [index, key_index])
			if key_a.has("value"):
				_expect(ClipSpec.values_equal(key_a.value, key_b.value, 0.0001),
					"track %d key %d value round-trips (%s vs %s)"
					% [index, key_index, str(key_a.value), str(key_b.value)])
			if key_a.has("method"):
				_expect(str(key_a.method) == str(key_b.method), "method names round-trip")
				_expect((key_a.args as Array).size() == (key_b.args as Array).size(), "method args round-trip")


func _check_track_kinds() -> void:
	var spec := _fixture()
	var json := SpecJson.to_json(spec)
	_expect(int(json.tracks[0].type) == Animation.TYPE_VALUE, "value tracks keep their type")
	_expect(int(json.tracks[0].interp) == Animation.INTERPOLATION_LINEAR, "interpolation is exported")
	_expect(json.tracks[0].has("update_mode"), "value tracks export their update mode")
	_expect(int(json.tracks[2].type) == Animation.TYPE_SCALE_3D, "scale tracks keep their type")
	_expect(int(json.tracks[2].interp) == Animation.INTERPOLATION_CUBIC, "cubic interpolation is exported")
	_expect(json.tracks[2].has("loop_wrap"), "3D transform tracks export loop_wrap")
	_expect(int(json.tracks[4].type) == Animation.TYPE_METHOD, "method tracks keep their type")
	_expect(str(json.tracks[4].keys[0].method) == "on_beat", "method keys export the method name")
	_expect((json.tracks[4].keys[0].args as Array).size() == 2, "method args are exported")
	_expect(int(json.tracks[5].type) == Animation.TYPE_AUDIO, "audio tracks keep their type")
	_expect(str(json.tracks[5].keys[0].stream) == "res://tests/fixtures/cue.wav",
		"audio streams export their resource path (%s)" % str(json.tracks[5].keys[0].stream))
	_expect_approx(float(json.tracks[5].keys[0].end_offset), 0.2, "audio offsets are exported")
	_expect_approx(float(json.tracks[1].keys[1].value), 1.0, "float values export as numbers")


func _check_remap() -> void:
	var spec := _fixture()
	var remapped := SpecJson.remap_node(spec, "Other/Node")
	_expect(str(remapped.tracks[0].path) == "Other/Node:position", "value track paths are remapped")
	_expect(str(remapped.tracks[1].path) == "Other/Node:modulate:a", "subpath properties survive remapping")
	_expect(str(remapped.tracks[4].path) == "Other/Node", "method track paths become the node path")
	_expect(str(remapped.tracks[5].path) == "Other/Node", "audio track paths become the node path")
	_expect(str(spec.tracks[0].path) == "Sprite:position", "remapping never mutates the input")
	_expect(ClipSpec.total_key_count(remapped) == ClipSpec.total_key_count(spec), "remapping keeps the keys")


func _check_summary() -> void:
	var summary := SpecJson.summarize(_fixture())
	_expect_approx(float(summary.length), 1.2, "summaries report the length")
	_expect(int(summary.track_count) == 6, "summaries count tracks")
	_expect(int(summary.key_count) == 11, "summaries count keys (%d)" % int(summary.key_count))
	_expect(int(summary.track_types.value) == 2, "summaries count value tracks")
	_expect(int(summary.track_types.method) == 1, "summaries count method tracks")
	_expect((summary.paths as Array).size() == 6, "summaries list track paths")


func _check_validation() -> void:
	_expect_error(SpecJson.from_json("text"), "specs must be objects")
	_expect_error(SpecJson.from_json({"format": "other", "tracks": []}), "the format is checked")
	var future := SpecJson.to_json(_fixture())
	future["version"] = SpecJson.VERSION + 1
	_expect_error(SpecJson.from_json(future), "newer versions are refused")
	var empty := SpecJson.to_json(_fixture())
	empty["tracks"] = []
	_expect_error(SpecJson.from_json(empty), "empty specs are refused")
	var no_path := SpecJson.to_json(_fixture())
	no_path.tracks[0]["path"] = ""
	_expect_error(SpecJson.from_json(no_path), "tracks need a path")
	var bad_type := SpecJson.to_json(_fixture())
	bad_type.tracks[0]["type"] = Animation.TYPE_BEZIER
	_expect_error(SpecJson.from_json(bad_type), "unsupported track types are refused")
	var no_keys := SpecJson.to_json(_fixture())
	no_keys.tracks[0]["keys"] = []
	_expect_error(SpecJson.from_json(no_keys), "tracks need keys")
	var bad_value := SpecJson.to_json(_fixture())
	bad_value.tracks[0]["keys"][0]["value"] = {"kind": "blob"}
	_expect_error(SpecJson.from_json(bad_value), "bad values are refused")
	var no_method := SpecJson.to_json(_fixture())
	no_method.tracks[4]["keys"][0]["method"] = ""
	_expect_error(SpecJson.from_json(no_method), "method keys need a method")
	var no_stream := SpecJson.to_json(_fixture())
	no_stream.tracks[5]["keys"][0]["stream"] = ""
	_expect_error(SpecJson.from_json(no_stream), "audio keys need a stream path")
	var missing_stream := SpecJson.to_json(_fixture())
	missing_stream.tracks[5]["keys"][0]["stream"] = "res://nope.wav"
	_expect_error(SpecJson.from_json(missing_stream), "missing audio streams are refused")
	var good := SpecJson.to_json(_fixture())
	good.tracks[5]["keys"][0]["stream"] = "res://tests/fixtures/cue.wav"
	_expect(not SpecJson.from_json(good).has("error"), "existing audio streams load")
