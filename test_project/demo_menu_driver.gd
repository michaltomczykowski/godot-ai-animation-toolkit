extends Node

## Menu demo driver.
##
## Plays the authored clips on a fixed 30 s timeline and feeds the menu
## synthetic mouse events (plus an on-screen cursor) so the recording shows
## real hover/press/click reactions. Every animation it triggers is an ordinary
## toolkit clip living on the scene's AnimationPlayers.

var _root: Control
var _menu: Control
var _hint: Label
var _cursor: Control
var _readout: Label
var _options_panel: Control
var _loading: Control
var _loading_bar: ProgressBar
var _loading_value: Label
var _buttons := {}

var _elapsed := 0.0
var _steps: Array = []
var _next := 0


func _ready() -> void:
	_root = get_parent()
	_menu = _root.get_node("Menu")
	_hint = _root.get_node("Menu/Hint") as Label
	_cursor = _root.get_node("Cursor")
	_readout = _root.get_node("Readout") as Label
	_options_panel = _root.get_node("OptionsPanel")
	_loading = _root.get_node("Loading")
	_loading_bar = _root.get_node("Loading/LoadingBar") as ProgressBar
	_loading_value = _root.get_node("Loading/LoadingValue") as Label
	for name in ["PlayButton", "OptionsButton", "CreditsButton", "QuitButton"]:
		_buttons[name] = _root.get_node("Menu/Buttons/" + name)
	_build_steps()
	# Ambient loops: living background and a breathing title.
	_play("TitleAnim", "breathe")
	_play("GlowAnim", "glow")
	_play("WaveAnim", "float")
	_cursor.position = Vector2(560, 500)
	_cursor.modulate.a = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	while _next < _steps.size() and _elapsed >= float(_steps[_next].t):
		var step: Dictionary = _steps[_next]
		_next += 1
		(step.run as Callable).call()


# --- timeline --------------------------------------------------------------

func _build_steps() -> void:
	_add(0.0, _step.bind(func() -> void:
		_play("MenuAnim", "entry")
		_play("HintAnim", "type")
		_say("menu ready - entry stagger, title pulse and drifting blobs are looping")))
	_add(1.3, _step.bind(func() -> void:
		_fade_cursor(1.0)
		_cursor_to(_buttons.PlayButton)
		_play("PlayAnim", "hover")))
	_add(2.6, _step.bind(func() -> void:
		_press(_buttons.PlayButton, "PlayAnim", "PLAY")))
	_add(3.05, _step.bind(func() -> void: _play("FlowAnim", "wipe_cover")))
	_add(3.45, _step.bind(func() -> void:
		_fade_cursor(0.0)
		_loading_bar.value = 0
		_loading_value.text = "0%"
		_loading.visible = true
		_play("LoadBarAnim", "fill")
		_play("LoadValueAnim", "count")
		_say("transition wipe -> progress_fill + counter")))
	_add(7.3, _step.bind(func() -> void:
		_loading.visible = false
		_play("FlowAnim", "fade_in")))
	_add(7.8, _step.bind(func() -> void:
		_fade_cursor(1.0)
		_play("PlayAnim", "hover")
		_say("back on the menu")))
	_add(8.3, _step.bind(func() -> void:
		_hint.text = "press OPTIONS to open the panel"
		_play("HintAnim", "type")))
	_add(9.4, _step.bind(func() -> void:
		_cursor_to(_buttons.OptionsButton)
		_play("OptionsAnim", "hover")))
	_add(10.5, _step.bind(func() -> void:
		_press(_buttons.OptionsButton, "OptionsAnim", "OPTIONS")))
	_add(10.95, _step.bind(func() -> void:
		_options_panel.visible = true
		_play("PanelAnim", "in")
		_say("dialog_pop opens the panel")))
	_add(12.2, _step.bind(func() -> void:
		_cursor_to(_root.get_node("OptionsPanel/OptionsBox/VolumeBar"))
		_play("VolBarAnim", "fill")
		_play("VolValueAnim", "count")
		_say("progress_fill + counter drive the volume")))
	_add(13.9, _step.bind(func() -> void:
		_cursor_to(_root.get_node("OptionsPanel/OptionsBox/BackButton"))))
	_add(14.7, _step.bind(func() -> void:
		_click(_root.get_node("OptionsPanel/OptionsBox/BackButton"))
		_play("FxAnim", "flash_white")
		_say("click: BACK")))
	_add(15.1, _step.bind(func() -> void: _play("PanelAnim", "out")))
	_add(15.5, _step.bind(func() -> void: _options_panel.visible = false))
	_add(16.0, _step.bind(func() -> void:
		_cursor_to(_buttons.CreditsButton)
		_play("CreditsAnim", "hover")))
	_add(17.0, _step.bind(func() -> void:
		_press(_buttons.CreditsButton, "CreditsAnim", "CREDITS")
		_hint.text = "seven tools - one spec engine - 79 ops, no core patches"
		_play("HintAnim", "type")))
	_add(19.5, _step.bind(func() -> void:
		_cursor_to(_buttons.QuitButton)
		_play("QuitAnim", "hover")))
	_add(20.6, _step.bind(func() -> void:
		_press(_buttons.QuitButton, "QuitAnim", "QUIT")
		_play("FxAnim", "flash_red")
		_play("FlowAnim", "quit_shake")
		_say("shake + hit_flash on quit")))
	_add(21.5, _step.bind(func() -> void: _play("FlowAnim", "fade_out")))
	_add(22.2, _step.bind(func() -> void:
		_menu.visible = false
		_fade_cursor(0.0)
		_loading.visible = true
		_loading_bar.visible = false
		_loading_value.text = "seven tools - one spec engine"
		(_root.get_node("Loading/LoadingTitle") as Label).text = "THANKS FOR WATCHING"
		_say("fade to a closing card")))
	_add(24.6, _step.bind(func() -> void: _loading.visible = false))
	_add(25.0, _step.bind(func() -> void: _play("FlowAnim", "fade_in")))
	_add(25.6, _step.bind(func() -> void:
		(_root.get_node("Loading/LoadingTitle") as Label).text = "LOADING"
		_loading_bar.visible = true
		_menu.visible = true
		_play("MenuAnim", "entry")
		_hint.text = "thanks for watching"
		_play("HintAnim", "type")))
	_add(27.4, _step.bind(func() -> void:
		_fade_cursor(1.0)
		_say("animation_toolkit - seven tools, one spec engine")))


func _add(time: float, run: Callable) -> void:
	_steps.append({"t": time, "run": run})


func _step(run: Callable) -> void:
	run.call()


# --- helpers ---------------------------------------------------------------

func _play(player_name: String, clip: String) -> void:
	var player := _root.get_node(player_name) as AnimationPlayer
	if player != null and player.has_animation(clip):
		player.play(clip)


func _say(text: String) -> void:
	_readout.text = "> " + text


func _cursor_to(control: Control) -> void:
	var target := control.get_global_rect().get_center() - _cursor.size * 0.5
	var tween := create_tween()
	tween.tween_property(_cursor, "position", target, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_click_at(control.get_global_rect().get_center(), false)


func _fade_cursor(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_cursor, "modulate:a", alpha, 0.5)


func _press(button: Control, player_name: String, label: String) -> void:
	_play(player_name, "press")
	_play("FxAnim", "flash_white")
	_click(button)
	_say("click: " + label)


func _click(button: Control) -> void:
	_click_at(button.get_global_rect().get_center(), true)


func _click_at(centre: Vector2, with_click: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	Input.parse_input_event(motion)
	if not with_click:
		return
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	down.global_position = centre
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = centre
	up.global_position = centre
	Input.parse_input_event(up)
