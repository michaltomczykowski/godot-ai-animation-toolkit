extends Node2D
## Drives the saved clips from the chapter clock and supports the gallery transport.

const DURATION := 18.0
const DISPATCH_BEATS := Vector2(2.0, 10.5)
const BEACON_BEATS := Vector2(2.0, 10.2)
const FLIGHT_BEATS := Vector2(1.8, 10.2)
const RETIME_BEATS := Vector2(1.6, 9.3)
const PHASE_NAMES := ["DARK", "EMBER", "KINDLING", "LIT"]
const LAMP_FPS := 1.5

@export_enum("Dispatch", "Beacon", "Flight", "Retime") var stage_kind: int
@export var chapter_time := 0.0

var _running := false
var _interaction_playing := false
var _interaction_time := -1.0
var _last_beacon_time := -1.0
var _audio_started := false
var _last_beacon_frame := -1

@onready var _timeline: AnimationPlayer = $Timeline


func _ready() -> void:
	if stage_kind == 0:
		var button: Button = $Ledger/DispatchButton
		button.pressed.connect(_activate_dispatch)
	if stage_kind == 1:
		$Readout/BeaconButton.pressed.connect(_activate_beacon)
	_setup_routes()
	seek(0.0)
	if get_parent() == get_tree().root:
		play()


func play() -> void:
	if chapter_time >= DURATION:
		restart()
	_running = true
	_interaction_playing = _interaction_time >= 0.0
	_timeline.play(&"chapter")
	if stage_kind == 1:
		$Chime.stream_paused = false


func pause() -> void:
	_running = false
	_interaction_playing = false
	_timeline.pause()
	if stage_kind == 1:
		$Chime.stream_paused = true
		$AudioCue.pause()
		$AnimatedLamp.pause()
		_audio_started = false


func restart() -> void:
	var was_running := _running
	seek(0.0)
	if was_running:
		play()


func seek(seconds: float) -> void:
	_interaction_playing = false
	_interaction_time = -1.0
	if stage_kind == 1:
		$AudioCue.stop()
		$Chime.stop()
	_last_beacon_time = -1.0
	_audio_started = false
	chapter_time = clampf(seconds, 0.0, DURATION)
	if _timeline.assigned_animation != &"chapter":
		_timeline.play(&"chapter")
		_timeline.pause()
	_timeline.seek(chapter_time, true, true)
	_update_stage(0.0, false)


func timeline_position() -> float:
	return chapter_time


func _process(delta: float) -> void:
	if _running or _interaction_playing:
		_update_stage(delta, true)


func _update_stage(delta: float, permit_audio: bool) -> void:
	if _interaction_playing:
		_interaction_time += delta
	var local_time := -1.0
	match stage_kind:
		0:
			local_time = _stage_elapsed(DISPATCH_BEATS)
			_update_dispatch(local_time)
		1:
			local_time = _stage_elapsed(BEACON_BEATS)
			_update_beacon(local_time, permit_audio)
		2:
			local_time = _stage_elapsed(FLIGHT_BEATS)
			_update_flight(local_time)
		3:
			local_time = _stage_elapsed(RETIME_BEATS)
			_update_retime(local_time)


func _stage_elapsed(beats: Vector2) -> float:
	if _interaction_time >= 0.0:
		return _interaction_time
	return chapter_time - (beats.y if chapter_time >= beats.y else beats.x)


func _activate_dispatch() -> void:
	_interaction_playing = true
	_interaction_time = 0.0
	_update_dispatch(0.0)


func _activate_beacon() -> void:
	_interaction_playing = true
	_interaction_time = 0.0
	_last_beacon_time = -1.0
	_audio_started = false
	_update_beacon(0.0, true)


func _update_dispatch(elapsed: float) -> void:
	_sample($ButtonMotion, &"confirm", elapsed)
	_sample($Stamps, &"manifest_reveal", elapsed - 0.24)
	_sample($Progress, &"fill", elapsed - 0.48)
	_sample($Dialog, &"accepted", elapsed - 2.72)
	$Ledger/ProgressReadout.text = "%d%%" % roundi($Ledger/Charge.value)
	if elapsed < 0.0:
		$Ledger/ProgressState.text = "Ready to dispatch"
	elif elapsed < 2.72:
		$Ledger/ProgressState.text = "Dispatching manifest"
	else:
		$Ledger/ProgressState.text = "Dispatch complete"


func _update_beacon(elapsed: float, permit_audio: bool) -> void:
	_sample($Flipbook, &"ignition", elapsed)
	var lamp: AnimatedSprite2D = $AnimatedLamp
	var phase := clampi(int(floor(elapsed * LAMP_FPS)), 0, lamp.sprite_frames.get_frame_count(&"ignition") - 1)
	var animation_active := permit_audio and elapsed >= 0.0 and elapsed < PHASE_NAMES.size() / LAMP_FPS
	var next_cycle := elapsed < _last_beacon_time
	if not animation_active or next_cycle:
		lamp.pause()
	if not lamp.is_playing() or lamp.frame != phase:
		# Align the flipbook and SpriteFrames while scrubbing or starting a new beat.
		lamp.set_frame_and_progress(phase, clampf(elapsed * LAMP_FPS - phase, 0.0, 1.0))
	if animation_active and not lamp.is_playing():
		lamp.play(&"ignition")
	if phase != _last_beacon_frame:
		_last_beacon_frame = phase
		$Readout/LightState.text = PHASE_NAMES[phase]
		for index in PHASE_NAMES.size():
			$Readout.get_node("Pip%d" % index).modulate.a = 1.0 if index <= phase else 0.27
	if next_cycle:
		_audio_started = false
	if permit_audio and not _audio_started and elapsed >= 0.0 and elapsed < 2.0:
		_audio_started = true
		$AudioCue.stop()
		$Chime.stream_paused = false
		$AudioCue.play(&"bell")
		$AudioCue.seek(elapsed, true, true)
	_last_beacon_time = elapsed
	$Readout/ChimeState.text = "CHIME SENT" if elapsed >= 2.0 else "CHIME AT 2.00 S"
	var wave_time := elapsed - 2.0
	var ring: Line2D = $SignalRing
	ring.visible = wave_time >= 0.0 and wave_time < 1.15
	if ring.visible:
		var swell := wave_time / 1.15
		ring.scale = Vector2.ONE * lerpf(0.8, 2.1, swell)
		ring.modulate.a = 1.0 - swell


func _update_flight(elapsed: float) -> void:
	var travel := _sample($FlightPath, &"crossing", elapsed)
	var wing_elapsed := fposmod(maxf(elapsed, 0.0), $WingPose.get_animation(&"wingbeat").length)
	_sample($WingPose, &"wingbeat", wing_elapsed if travel < 1.0 else 0.0)
	_mark_route($Trail, travel)
	if elapsed < 0.0:
		$Readout/Status.text = "AWAITING LAUNCH"
	elif travel < 1.0:
		$Readout/Status.text = "IN FLIGHT  /  %d%%" % roundi(travel * 100.0)
	else:
		$Readout/Status.text = "EAST BREAKWATER REACHED"
	var courier: Node2D = $Courier
	courier.rotation = 0.2 * sin(travel * TAU) + 0.17


func _update_retime(elapsed: float) -> void:
	var before := _sample($Before/Move, &"crossing", elapsed)
	var after := _sample($After/Move, &"crossing", elapsed)
	_mark_route($Before/Trail, before)
	_mark_route($After/Trail, after)
	var before_length: float = $Before/Move.get_animation(&"crossing").length
	var after_length: float = $After/Move.get_animation(&"crossing").length
	$Before/Timer.text = "%.2f / %.2f S" % [before * before_length, before_length]
	$After/Timer.text = "%.2f / %.2f S" % [after * after_length, after_length]
	$Before/Arrived.visible = before >= 1.0
	$After/Arrived.visible = after >= 1.0
	$Before/Courier.rotation = before * TAU * 0.025 + 0.24
	$After/Courier.rotation = after * TAU * 0.025 + 0.24


func _setup_routes() -> void:
	match stage_kind:
		2:
			$Course.points = $Route.curve.get_baked_points()
		3:
			$Before/Course.points = $Before/Route.curve.get_baked_points()
			$After/Course.points = $After/Route.curve.get_baked_points()


func _sample(player: AnimationPlayer, clip_name: StringName, elapsed: float) -> float:
	if not player.has_animation(clip_name):
		return 0.0
	if player.assigned_animation != clip_name:
		player.play(clip_name)
		player.pause()
	var length := player.get_animation(clip_name).length
	var position := clampf(elapsed, 0.0, length)
	player.seek(position, true, true)
	return position / length


func _mark_route(line: Line2D, progress: float) -> void:
	var path: Path2D = line.get_parent().get_node("Route")
	var curve := path.curve
	var points := PackedVector2Array()
	var distance := curve.get_baked_length() * progress
	for index in range(49):
		points.append(curve.sample_baked(distance * index / 48.0))
	line.points = points
