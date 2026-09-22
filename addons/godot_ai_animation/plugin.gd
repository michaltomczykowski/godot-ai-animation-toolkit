@tool
extends EditorPlugin

## Registers the animation presets as a Godot AI custom tool
## (`animation_presets`, promoted to the first-class `custom_animation_presets`).
##
## Requires the Godot AI addon (>= 4.1.0) in the same project. Registration is
## defensive: when Godot AI is absent this plugin loads cleanly, retries for a
## while (the other plugin may be enabled later in the same session), then
## warns instead of failing.

const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")

const REGISTRY_SCRIPT := "res://addons/godot_ai/custom_tools/mcp_tool_registry.gd"
const SPEC_SCRIPT := "res://addons/godot_ai/custom_tools/mcp_custom_tool_spec.gd"
const HANDLER_SCRIPT := "res://addons/godot_ai_animation/handlers/presets.gd"
const SOURCE_CFG := "res://addons/godot_ai_animation/plugin.cfg"

const TOOL_NAME := "animation_presets"
const RETRY_INTERVAL_SEC := 0.5
const RETRY_WINDOW_SEC := 30.0

const DESCRIPTION := (
	"One-call animation presets for an AnimationPlayer: pulse (breathing / "
	+ "ping-pong on any property), bounce (press feedback), orbit (circular "
	+ "position), sweep (full-turn rotation), drift (one-axis offset). Each "
	+ "preset builds one Animation clip with typed keys and commits a single "
	+ "undoable action; Controls get their pivot recentered for bounce/sweep. "
	+ "Requires the Godot AI addon."
)

const PARAMS_SCHEMA := {
	"type": "object",
	"properties": {
		"op": {
			"type": "string",
			"enum": ["pulse", "bounce", "orbit", "sweep", "drift"],
			"description": "Which preset to build.",
		},
		"player_path": {
			"type": "string",
			"description": "Scene path to the AnimationPlayer (it must already exist).",
		},
		"target_path": {
			"type": "string",
			"description": (
				"Node to animate: relative to the player's root_node "
				+ "(e.g. \"Button\") or scene-absolute (e.g. \"/Main/Button\")."
			),
		},
		"animation_name": {
			"type": "string",
			"description": "Clip name; defaults to the preset name.",
		},
		"overwrite": {
			"type": "boolean",
			"default": false,
			"description": "Replace an existing clip with the same name.",
		},
		"property": {
			"type": "string",
			"description": "pulse: property to breathe (default \"scale\").",
		},
		"from_scale": {"type": "number", "default": 1.0},
		"to_scale": {"type": "number", "default": 1.1},
		"from_value": {
			"description": "pulse: start value for a non-scale property (typed to the property).",
		},
		"to_value": {"description": "pulse: end value."},
		"intensity": {
			"type": "number",
			"description": "bounce: peak overshoot fraction (default 0.15).",
		},
		"radius": {
			"type": "number",
			"description": "orbit: circle radius (default 1.0 for 3D, 100.0 for 2D).",
		},
		"clockwise": {"type": "boolean", "default": true},
		"turns": {
			"type": "number",
			"description": "sweep: full turns (default 1.0).",
		},
		"axis": {
			"type": "string",
			"enum": ["x", "y", "z"],
			"description": "drift: axis to offset along (z only for 3D targets).",
		},
		"distance": {
			"type": "number",
			"description": "orbit/sweep/drift distance (defaults by dimension).",
		},
		"duration": {"type": "number", "description": "Clip length in seconds."},
		"loop_mode": {
			"type": "string",
			"enum": ["none", "linear", "pingpong"],
			"description": "Drift refuses \"linear\" (the clip ends at a net offset).",
		},
	},
	"required": ["op", "player_path", "target_path"],
}

var _retry_left := 0.0
var _registered := false


func _enter_tree() -> void:
	ToolContext.undo_redo = get_undo_redo()
	_retry_left = RETRY_WINDOW_SEC
	set_process(true)
	_try_register()


func _exit_tree() -> void:
	set_process(false)
	var registry = _registry()
	if registry != null:
		if registry.registry_ready.is_connected(_register):
			registry.registry_ready.disconnect(_register)
		if _registered:
			registry.call("unregister_source", SOURCE_CFG)
	_registered = false
	ToolContext.undo_redo = null


func _process(delta: float) -> void:
	if _registered:
		set_process(false)
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		set_process(false)
		push_warning(
			"Godot AI Animation Toolkit: Godot AI (>= 4.1.0) not found - "
			+ "animation_presets was not registered."
		)
		return
	_try_register()


func _try_register() -> void:
	var registry = _registry()
	if registry == null:
		return
	if not registry.registry_ready.is_connected(_register):
		registry.registry_ready.connect(_register)
	_register()


## Idempotent: also runs on `registry_ready` after a Godot AI reload.
func _register() -> void:
	var registry = _registry()
	if registry == null:
		return
	var spec_script = load(SPEC_SCRIPT)
	if spec_script == null:
		return
	var spec = spec_script.new()
	spec.name = TOOL_NAME
	spec.description = DESCRIPTION
	spec.params_schema = PARAMS_SCHEMA
	spec.script_path = HANDLER_SCRIPT
	spec.method = &"run"
	spec.source_path = SOURCE_CFG
	spec.promoted = true
	spec.requires_writable = true
	spec.undoable = true
	spec.timeout_ms = 5000
	if registry.call("register", spec):
		_registered = true
		set_process(false)


## The live Godot AI tool registry, or null when Godot AI isn't installed.
## Loaded by path so this addon parses and loads without the core addon.
static func _registry():
	if not ResourceLoader.exists(REGISTRY_SCRIPT):
		return null
	var registry_script = load(REGISTRY_SCRIPT)
	if registry_script == null:
		return null
	return registry_script.call("get_instance")
