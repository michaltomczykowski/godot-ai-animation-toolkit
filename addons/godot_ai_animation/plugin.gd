@tool
extends EditorPlugin

## Registers the animation toolkit's tools with Godot AI (>= 4.1.0):
## `animation_presets`, `animation_fx`, `animation_graph`, `animation_edit`,
## `animation_inspect`, `animation_library`, `animation_rig` and
## `animation_motion`. All are promoted to first-class `custom_*` tools and are
## declared in `registry/op_registry.gd` — the single source of truth for
## descriptions, params schemas and the generated docs.
##
## Registration is defensive: when Godot AI is absent this plugin loads cleanly,
## retries for a while (the other plugin may be enabled later in the same
## session), then warns instead of failing.

const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const REGISTRY_SCRIPT := "res://addons/godot_ai/custom_tools/mcp_tool_registry.gd"
const SPEC_SCRIPT := "res://addons/godot_ai/custom_tools/mcp_custom_tool_spec.gd"
const SOURCE_CFG := "res://addons/godot_ai_animation/plugin.cfg"
const RETRY_INTERVAL_SEC := 0.5
const RETRY_WINDOW_SEC := 30.0

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
			+ "animation_presets and animation_edit were not registered."
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
	var registered_all := true
	for family_name in OpRegistry.family_names():
		var info: Dictionary = OpRegistry.family(family_name)
		var spec = spec_script.new()
		spec.name = family_name
		spec.description = str(info.get("description", ""))
		spec.params_schema = info.get("schema", {})
		spec.script_path = str(info.get("handler", ""))
		spec.method = &"run"
		spec.source_path = SOURCE_CFG
		spec.promoted = true
		spec.requires_writable = bool(info.get("requires_writable", true))
		spec.undoable = bool(info.get("undoable", true))
		spec.timeout_ms = int(info.get("timeout_ms", 5000))
		if not registry.call("register", spec):
			registered_all = false
	_registered = registered_all
	if registered_all:
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
