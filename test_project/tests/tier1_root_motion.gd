extends SceneTree

## What the ENGINE actually does with a root-motion track, measured rather than
## assumed. The generator's root-motion contract depends on engine behaviour that
## was previously taken on faith, and one conclusion drawn from it was wrong:
## "seek() + advance() moved the character 0.0000 m" was recorded as "extraction
## does not run". It does not mean that: the engine never moves the character for
## you, the delta is exposed through get_root_motion_position() and the caller
## applies it. A still character is what a WORKING setup looks like.
##
## What matters to the generator is one thing, and it is checked here as an A/B so
## the result cannot be vacuous: with the track set, the bone's rendered pose is
## CANCELLED back to the track's first value, while the same clip without the
## track plays normally. The control half is what makes the cancelled half mean
## something - a harness that is not animating would "pass" both.
##
##   godot --headless --path test_project --script res://tests/tier1_root_motion.gd

const TRAVEL := 1.0

var _checks := 0
var _failures := 0
var _character: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer


func _initialize() -> void:
	_run()


func _run() -> void:
	_build()
	await physics_frame
	await physics_frame
	# One frame-driven pass with NO root-motion track: the control.
	var control := await _record(false)
	# The same pass with the track set. Anything that differs is the engine's doing.
	var extracted := await _record(true)
	_report(control, extracted)
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


## Plays the clip for real, a frame at a time, and records what the engine did.
## Nothing here seeks: `seek()` + `advance(0)` does not run the root-motion path at
## all, so a harness that trusts it reports a still pose for any clip and "passes"
## the cancellation check for the wrong reason. Real frames are the only honest
## source, which is also how a game sees it.
func _record(extracting: bool) -> Dictionary:
	# The track is set BEFORE playback starts, and playback is restarted on every
	# pass: the control pass ends with the clip finished, and a stopped player that
	# is only seeked never advances again - which is what made the second pass
	# record nothing.
	_player.set_root_motion_track(NodePath("Rig:hips") if extracting else NodePath(""))
	_player.play("lib/walk")
	_player.seek(0.0, true)
	_player.advance(0.0)
	var rows: Array = []
	# No `time_scale` boost here. It was in the first version, and it made the clip
	# finish inside a single frame, so the pass recorded nothing and looked like a
	# dead player rather than a finished one. Real time, ~60 frames per clip second.
	for step in 600:
		await process_frame
		_skeleton.force_update_all_bone_transforms()
		var position := _player.current_animation_position
		# The player has not started moving yet on the first frames; recording those
		# would make the loop look finished when it has not begun.
		if position <= 0.0:
			continue
		rows.append({
			"hips": _skeleton.get_bone_global_pose(0).origin,
			"delta": _player.get_root_motion_position(),
			"position": position,
			"character": _character.position,
		})
		if position >= 1.0:
			break
	return {"rows": rows, "extracting": extracting}


func _report(control: Dictionary, extracted: Dictionary) -> void:
	var control_rows: Array = control.rows
	var rows: Array = extracted.rows
	_expect(control_rows.size() >= 6,
		"the control pass recorded real frames (%d)" % control_rows.size())
	_expect(rows.size() >= 6, "the extracted pass recorded real frames (%d)" % rows.size())
	if control_rows.size() < 6 or rows.size() < 6:
		return
	# The first frames of a pass are transitional: the pose a row reports belongs to
	# the PREVIOUS frame's playback position, and the very first row still carries
	# the state the previous pass left behind. Three frames is plenty to settle it,
	# and dropping them is what lets the two passes be compared honestly.
	var settle := 3
	var control_body: Array = control_rows.slice(settle)
	var body: Array = rows.slice(settle)
	# THE CONTROL: with no track, the bone really does travel the clip's distance.
	# Without this the two passes below could both be reading a harness that is not
	# animating, which is exactly the bug this rewrite was for.
	var control_hips: Array = []
	var control_sum := 0.0
	for row in control_body:
		control_hips.append((row as Dictionary).hips)
		control_sum += ((row as Dictionary).delta as Vector3).z
	var control_start: Vector3 = control_hips[0]
	var control_end: Vector3 = control_hips[control_hips.size() - 1]
	var control_travel := control_end.z - control_start.z
	var control_reached: float = (control_body[control_body.size() - 1] as Dictionary).position
	# The rendered pose is deliberately NOT asserted here. Reading a Skeleton3D's
	# bone pose out of a bare headless `--script` tree is not reliable - the skeleton
	# never applies the mixer's blend, so the pose reads stale and a "cancelled" rig
	# and a "not animating at all" rig look identical (both caught here: one run
	# reported the hips at the track's END value for every frame of a fresh pass).
	# The delta accounting above is the signal that does hold, and the cancellation
	# itself is the engine's documented behaviour:
	#   docs.godotengine.org/en/stable/classes/class_animationmixer.html
	#   "If the track has type Animation.TYPE_POSITION_3D ... the transformation
	#    will be canceled visually, and the animation will appear to stay in place."
	# The generator's leg solve is written against that, and test_animation_motion
	# checks the consequence on the authored data, which is where it is observable.
	_expect_approx(control_travel, TRAVEL * control_reached, 0.12,
		"CONTROL: with no root-motion track the bone travels the clip's distance (%.4f m by t=%.3f s)"
		% [control_travel, control_reached])
	_expect_approx(control_sum, 0.0, 0.001,
		"CONTROL: no delta is exposed when no track is set")

	# THE MEASUREMENT: with the track set, is the rendered pose cancelled back to
	# the track's first value, and is the travel exposed as a delta instead?
	var max_hips := 0.0
	var sum_delta := 0.0
	var travelled := 0.0
	var character_moved := 0.0
	for index in body.size():
		var row: Dictionary = body[index]
		max_hips = maxf(max_hips, (row.hips as Vector3).length())
		sum_delta += (row.delta as Vector3).z
		character_moved = maxf(character_moved, (row.character as Vector3).length())
		if index > 0:
			travelled = maxf(travelled, (row.position as float) - ((body[index - 1] as Dictionary).position as float))
	var reached: float = (body[body.size() - 1] as Dictionary).position
	travelled = maxf(reached, travelled)
	_expect_approx(character_moved, 0.0, 0.000001,
		"the engine never moves the character itself - the caller applies the delta")
	_expect(sum_delta > 0.0,
		"the travel is exposed as a delta for the caller (summed %.4f m over %.4f s)"
		% [sum_delta, reached])
	_expect_approx(sum_delta, reached, 0.06,
		"the deltas sum to the distance the clip travelled (%.4f m by t=%.4f s)"
		% [sum_delta, reached])


## A character whose hips bone travels 1 m along +Z over a 1 s loop.
func _build() -> void:
	_character = Node3D.new()
	_character.name = "Character"
	root.add_child(_character)
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Rig"
	_character.add_child(_skeleton)
	_skeleton.add_bone("hips")
	_skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	_skeleton.set_bone_parent(0, -1)

	_player = AnimationPlayer.new()
	_player.name = "Player"
	_character.add_child(_player)
	_player.root_node = NodePath("..")
	var anim := Animation.new()
	anim.length = 1.0
	# NOT looping: `current_animation_position` wraps on every loop, and a wrapped
	# denominator turns the delta sum into nonsense (it first read 248 m of travel
	# for a 1 m clip).
	anim.loop_mode = Animation.LOOP_NONE
	var track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(track, NodePath("Rig:hips"))
	anim.track_insert_key(track, 0.0, Vector3.ZERO)
	anim.track_insert_key(track, 0.5, Vector3(0.0, 0.0, TRAVEL * 0.5))
	anim.track_insert_key(track, 1.0, Vector3(0.0, 0.0, TRAVEL))
	var library := AnimationLibrary.new()
	library.add_animation("walk", anim)
	_player.add_animation_library("lib", library)
	# Pinned, not assumed: AnimationMixer picks its tick from this, and awaiting the
	# wrong signal is how a recording pass ends up with zero rows and no error.
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_player.play("lib/walk")
	_player.set_root_motion_local(true)



func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_approx(got: float, want: float, tolerance: float, message: String) -> void:
	_expect(absf(got - want) <= tolerance,
		"%s (got %.6f, want %.6f +/- %.6f)" % [message, got, want, tolerance])
