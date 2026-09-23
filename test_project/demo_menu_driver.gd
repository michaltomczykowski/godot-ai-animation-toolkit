extends Node

## Menu demo driver.
##
## Plays the toolkit clips on a fixed 30 s timeline and feeds the menu
## synthetic mouse events (plus an on-screen cursor and a sliding selection
## highlight) so the recording shows real hover / press / click reactions.
## Every animation it triggers is an ordinary clip on one of the scene's
## AnimationPlayers.

var _root: Control
var _menu: Control
var _hint: Label
var _cursor: Control
var _highlight: Control
var _scrim: Control
var _readout: Label
var _options_panel: Control
var _credits_panel: Control
var _outro: Control
var _loading: Control
var _loading_bar: ProgressBar
var _loading_value: Label
var _tip: Label
var _buttons := {}

var _elapsed := 0.0
var _steps: Array = []
var _next := 0


func _ready() -> void:
	_root = get_parent()
	_menu = _root.get_node("Menu")
	_hint = _root.get_node("Menu/Hint") as Label
	_cursor = _root.get_node("Cursor")
	_highlight = _root.get_node("Highlight")
	_scrim = _root.get_node("Scrim")
	_readout = _root.get_node("Readout") as Label
	_options_panel = _root.get_node("OptionsPanel")
	_credits_panel = _root.get_node("CreditsPanel")
	_outro = _root.get_node("Outro")
	_loading = _root.get_node("Loading")
	_loading_bar = _root.get_node("Loading/LoadingBar") as ProgressBar
	_loading_value = _root.get_node("Loading/LoadingValue") as Label
	_tip = _root.get_node("Loading/Tip") as Label
	for name in ["PlayButton", "OptionsButton", "CreditsButton", "QuitButton"]:
		_buttons[name] = _root.get_node("Menu/Buttons/" + name)
	_build_steps()
	# Ambient loops and the entry stagger, started here so frame 0 is alive.
	_play("TitleAnim", "breathe")
	_play("GlowAnim", "glow")
	_play("WaveAnim", "float")
	_play("MenuAnim", "entry")
	_play("HintAnim", "type")
	_cursor.position = Vector2(576, 566)
	_cursor.modulate.a = 0.0
	_highlight.visible = false
	_scrim.visible = false


func _process(delta: float) -> void:
	_elapsed += delta
	while _next < _steps.size() and _elapsed >= float(_steps[_next].t):
		var step: Dictionary = _steps[_next]
		_next += 1
		(step.run as Callable).call()


# --- timeline --------------------------------------------------------------

func _build_steps() -> void:
	_add(1.1, _step.bind(func() -> void:
		_fade_cursor(1.0)
		_focus(_buttons.PlayButton, "PlayAnim")
		_say("entry stagger, aurora shader and drifting motes - all running")))
	_add(2.3, _step.bind(func() -> void:
		_press(_buttons.PlayButton, "PlayAnim", "PLAY")))
	_add(2.8, _step.bind(func() -> void:
		_highlight.visible = false
		_play("FlowAnim", "wipe_cover")))
	_add(3.2, _step.bind(func() -> void:
		_fade_cursor(0.0)
		_loading_bar.value = 0
		_loading_value.text = "0%"
		_tip.text = "loading the toolkit - 7 tools, 79 ops"
		_loading.visible = true
		_play("LoadTitleAnim", "pulse")
		_play("TipAnim", "type")
		_play("LoadBarAnim", "fill")
		_play("LoadValueAnim", "count")
		_say("transition wipe -> progress_fill + counter")))
	_add(7.1, _step.bind(func() -> void:
		_loading.visible = false
		_play("FlowAnim", "fade_in")))
	_add(7.6, _step.bind(func() -> void:
		_fade_cursor(1.0)
		_focus(_buttons.PlayButton, "PlayAnim")
		_say("back on the menu")))
	_add(8.2, _step.bind(func() -> void:
		_hint.text = "cursor over a button: the highlight slides, the button pops"
		_play("HintAnim", "type")))
	_add(9.4, _step.bind(func() -> void:
		_focus(_buttons.OptionsButton, "OptionsAnim")))
	_add(10.5, _step.bind(func() -> void:
		_press(_buttons.OptionsButton, "OptionsAnim", "OPTIONS")))
	_add(10.95, _step.bind(func() -> void:
		_highlight.visible = false
		_show_scrim(true)
		_options_panel.visible = true
		_play("PanelAnim", "in")
		_say("dialog_pop opens the options panel")))
	_add(12.2, _step.bind(func() -> void:
		_cursor_to(_root.get_node("OptionsPanel/OptionsBox/VolumeBar"))
		_play("VolBarAnim", "fill")
		_play("VolValueAnim", "count")
		_say("progress_fill + counter drive the volume")))
	_add(13.9, _step.bind(func() -> void:
		_highlight_to(_root.get_node("OptionsPanel/OptionsBox/BackButton"))
		_cursor_to(_root.get_node("OptionsPanel/OptionsBox/BackButton"))))
	_add(14.7, _step.bind(func() -> void:
		_click(_root.get_node("OptionsPanel/OptionsBox/BackButton"))
		_play("FxAnim", "flash_white")
		_play("CamAnim", "punch")
		_say("click: BACK")))
	_add(15.1, _step.bind(func() -> void: _play("PanelAnim", "out")))
	_add(15.25, _step.bind(func() -> void: _show_scrim(false)))
	_add(15.6, _step.bind(func() -> void:
		_options_panel.visible = false
		_focus(_buttons.OptionsButton, "OptionsAnim")))
	_add(16.2, _step.bind(func() -> void:
		_focus(_buttons.CreditsButton, "CreditsAnim")))
	_add(17.2, _step.bind(func() -> void:
		_press(_buttons.CreditsButton, "CreditsAnim", "CREDITS")
		_hint.text = "credits: what built what"
		_play("HintAnim", "type")))
	_add(17.65, _step.bind(func() -> void:
		_highlight.visible = false
		_show_scrim(true)
		_credits_panel.visible = true
		_play("CreditsAnim2", "in")
		_say("dialog_pop: the credits card")))
	_add(20.7, _step.bind(func() -> void: _play("CreditsAnim2", "out")))
	_add(20.85, _step.bind(func() -> void: _show_scrim(false)))
	_add(21.2, _step.bind(func() -> void:
		_credits_panel.visible = false
		_say("animation_edit reverse closes it")))
	_add(21.7, _step.bind(func() -> void:
		_focus(_buttons.QuitButton, "QuitAnim")))
	_add(22.7, _step.bind(func() -> void:
		_press(_buttons.QuitButton, "QuitAnim", "QUIT")
		_play("FxAnim", "flash_red")
		_play("FlowAnim", "quit_shake")
		_say("shake + hit_flash on quit")))
	_add(23.4, _step.bind(func() -> void:
		_highlight.visible = false
		_fade_cursor(0.0)
		_play("FlowAnim", "fade_out")))
	_add(24.0, _step.bind(func() -> void:
		_outro.visible = true
		_play("OutroAnim", "in")
		_say("fade to the outro card")))
	_add(27.3, _step.bind(func() -> void: _play("OutroAnim", "out")))
	_add(27.8, _step.bind(func() -> void:
		_outro.visible = false
		_play("FlowAnim", "fade_in")
		_play("MenuAnim", "entry")
		_hint.text = "thanks for watching"
		_play("HintAnim", "type")))
	_add(29.0, _step.bind(func() -> void:
		_fade_cursor(0.0)
		_highlight.visible = false
		_click_at(Vector2(1120, 630), false)
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


## Fade the modal scrim in or out with the toolkit's transition clips.
func _show_scrim(visible_now: bool) -> void:
	if visible_now:
		_scrim.visible = true
		_play("ScrimAnim", "show")
	else:
		if _scrim.visible:
			_play("ScrimAnim", "hide")
			var tween := create_tween()
			tween.tween_interval(0.3)
			tween.tween_callback(func() -> void: _scrim.visible = false)


## Move the cursor and the selection highlight onto a button and play its hover
## pop.
func _focus(button: Control, player_name: String) -> void:
	_cursor_to(button)
	_highlight_to(button)
	_play(player_name, "hover")


func _highlight_to(button: Control) -> void:
	_highlight.visible = true
	_play("HighlightAnim", "glow")
	var rect := button.get_global_rect().grow(12.0)
	_highlight.size = rect.size
	var tween := create_tween()
	tween.tween_property(_highlight, "position", rect.position, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	_play("CamAnim", "punch")
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
