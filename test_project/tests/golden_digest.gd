extends RefCounted

## A quantized digest of a generated clip, so a change to the generator shows up
## as a NUMBER rather than "it looks a bit different".
##
## Quantizing is what gives the comparison an explicit tolerance. One unit is
## 1/2048 of the component, so float noise cannot fail the comparison and a real
## change cannot hide inside it - and the tolerance is a stated number rather
## than a feeling. The measured facts behind the choice:
##
##   - Godot's Vector3/Quaternion are float32 while GDScript floats are float64,
##     and the sample times are narrowed to float32 in a PackedFloat32Array
##     before they reach the clip, so there is a rounding step in the pipeline;
##   - the walk's critical path is sin -> deg_to_rad -> asin -> sin, plus cos,
##     sqrt and slerp, none of which Godot promises are bit-identical between
##     platforms or versions;
##   - same-process, same-platform drift between two generations measures about
##     1e-4 rad, so 2 units (1e-3) is ten times the observed floor;
##   - and across platforms it measured ZERO units of drift, on ubuntu-latest and
##     windows-latest alike, which is why these fixtures are safe to gate from
##     tier-1 as well as the editor suites.
##
## Two sources, one digest. `from_animation` reads a committed clip, which is what
## the editor suite has after a real op call; `from_keys` reads a spec's key
## dict, which is what a headless tier-1 suite can reach. They are not
## comparable to each other - a spec holds rest-relative rotation deltas while a
## clip holds absolute local rotations - so they get separate fixtures and this
## class only guarantees that each source is self-consistent.
##
## A missing file means "record it", so regenerating a golden is a deliberate act
## (delete the file, run) rather than something a test quietly does to itself.

const SCALE := 2048
const TOLERANCE := 2
const FORMAT := "godot-ai-animation-golden"
const VERSION := 1


## Digest of a committed `Animation`: the 3D rotation and position tracks, keyed
## by bone name and sorted by it, every value an integer.
static func from_animation(anim: Animation) -> Dictionary:
	var tracks: Array = []
	for track in anim.get_track_count():
		var kind := anim.track_get_type(track)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var bone := str(anim.track_get_path(track)).get_slice(":", 1)
		if bone.is_empty():
			continue
		var keys: Array = []
		for index in anim.track_get_key_count(track):
			keys.append(_quantize(anim.track_get_key_value(track, index)))
		tracks.append({"bone": bone, "type": kind, "keys": keys})
	return _assemble(anim.length, tracks)


## Digest of a spec's `keys` dict, for a headless suite with no clip. The rotation
## values are the spec's rest-relative deltas and the position values are plain
## offsets - self-consistent across runs, which is the point.
static func from_keys(keys: Dictionary, length: float) -> Dictionary:
	var tracks: Array = []
	for bone in keys:
		var entry: Dictionary = keys[bone]
		var name := str(bone)
		if name.is_empty():
			continue
		if entry.has("rotation"):
			var keys_out: Array = []
			for key in entry.rotation:
				keys_out.append(_quantize((key as Dictionary).delta))
			tracks.append({"bone": name, "type": Animation.TYPE_ROTATION_3D, "keys": keys_out})
		if entry.has("position"):
			var keys_out: Array = []
			for key in entry.position:
				# The spec names a position key's payload "delta", the same as a
				# rotation's, and the clip names it "value". Read both so the digest
				# does not care which side of the commit it is looking at.
				var payload: Dictionary = key
				keys_out.append(_quantize(payload.get("value", payload.get("delta", Vector3.ZERO))))
			tracks.append({"bone": name, "type": Animation.TYPE_POSITION_3D, "keys": keys_out})
	return _assemble(length, tracks)


## Every key as integers at 1/2048. Quaternion sign is normalised first, because
## q and -q are the same rotation and the engine is free to store either.
static func _quantize(value) -> Array:
	if value is Quaternion:
		var q: Quaternion = value
		if q.w < 0.0:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		return [q.x, q.y, q.z, q.w].map(func(v: float) -> int: return roundi(v * SCALE))
	var v3: Vector3 = value
	return [v3.x, v3.y, v3.z].map(func(v: float) -> int: return roundi(v * SCALE))


static func _assemble(length: float, tracks: Array) -> Dictionary:
	tracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.bone) < str(b.bone))
	return {
		"format": FORMAT,
		"version": VERSION,
		# The engine that produced it, purely diagnostic: a 4.7.3 bump that moves
		# the numbers should be explicable from the log rather than mysterious.
		"godot": "%s.%s.%s" % [
			Engine.get_version_info().get("major", 0),
			Engine.get_version_info().get("minor", 0),
			Engine.get_version_info().get("patch", 0),
		],
		"scale": SCALE,
		"tolerance": TOLERANCE,
		"length": snappedf(length, 0.0001),
		"tracks": tracks,
	}


## The largest per-component integer difference between two digests, and where it
## was. Returns {"worst": int, "where": String, "shape": String} - `shape` names a
## structural difference (a track or key count that no longer matches), which is
## a different kind of change from a drift and reads better than a raw count.
static func compare(fresh: Dictionary, golden: Dictionary) -> Dictionary:
	var out := {"worst": 0, "where": "", "shape": ""}
	if absf(float(fresh.length) - float(golden.length)) > 0.0001:
		out.shape = "clip length %.4f vs the golden's %.4f" % [float(fresh.length), float(golden.length)]
		return out
	var fresh_tracks: Array = fresh.tracks
	var golden_tracks: Array = golden.tracks
	if fresh_tracks.size() != golden_tracks.size():
		out.shape = "%d tracks vs the golden's %d" % [fresh_tracks.size(), golden_tracks.size()]
		return out
	for index in fresh_tracks.size():
		var a: Dictionary = fresh_tracks[index]
		var b: Dictionary = golden_tracks[index]
		if str(a.bone) != str(b.bone):
			out.shape = "track %d is %s, the golden says %s" % [index, str(a.bone), str(b.bone)]
			return out
		var a_keys: Array = a.keys
		var b_keys: Array = b.keys
		if a_keys.size() != b_keys.size():
			out.shape = "%s has %d keys, the golden has %d" % [str(a.bone), a_keys.size(), b_keys.size()]
			return out
		for key_index in a_keys.size():
			var gap := 0
			var row_a: Array = a_keys[key_index]
			var row_b: Array = b_keys[key_index]
			for component in row_a.size():
				gap = maxi(gap, absi(int(row_a[component]) - int(row_b[component])))
			if gap > int(out.worst):
				out.worst = gap
				out.where = "%s key %d" % [str(a.bone), key_index]
	return out


## Reads the fixture, or records `digest` there and returns {"recorded": true}.
static func load_or_record(path: String, digest: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).has("tracks"):
			return {"recorded": false, "golden": parsed}
		return {"error": "%s does not parse as a golden" % path}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "could not write %s (%s)" % [path, str(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(digest, "  "))
	file.close()
	return {"recorded": true, "path": path}
