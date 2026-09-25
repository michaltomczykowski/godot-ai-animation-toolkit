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
const RETRY_WINDOW_SEC := 30.0
const POLL_INTERVAL_SEC := 0.5

var _retry_left := 0.0
var _registered := false
var _warned := false
var _poll := 0.0
var _registry: Object = null


func _enter_tree() -> void:
	ToolContext.undo_redo = get_undo_redo()
	_retry_left = RETRY_WINDOW_SEC
	set_process(true)
	_try_register()


func _exit_tree() -> void:
	set_process(false)
	_disconnect(_registry)
	_registry = null
	var live = _instance()
	if live != null:
		live.call("unregister_source", SOURCE_CFG)
	_registered = false
	_warned = false
	ToolContext.undo_redo = null


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL_SEC
	var live = _instance()
	if live != _registry:
		# The core plugin reloaded and replaced its singleton. Our specs lived in
		# the old instance, so reconnect to the new one and register again - this
		# is what used to leave every toolkit tool missing until the editor was
		# restarted.
		_disconnect(_registry)
		_registry = live
		_registered = false
		_retry_left = RETRY_WINDOW_SEC
		_warned = false
		if live != null and not live.registry_ready.is_connected(_register):
			live.registry_ready.connect(_register)
	elif _registered and live != null and _spec_present(live):
		return
	elif _registered:
		_registered = false
	_retry_left -= POLL_INTERVAL_SEC
	if _retry_left <= 0.0:
		if not _warned:
			_warned = true
			push_warning(
				"Godot AI Animation Toolkit: Godot AI (>= 4.1.0) not found - "
				+ "no toolkit tools were registered."
			)
		return
	_try_register()


func _try_register() -> void:
	var live = _instance()
	if live == null:
		return
	if _registry != live:
		_disconnect(_registry)
		_registry = live
		if not live.registry_ready.is_connected(_register):
			live.registry_ready.connect(_register)
	_register()


## Idempotent: also runs on `registry_ready` after a Godot AI reload.
func _register() -> void:
	var live = _instance()
	if live == null:
		return
	var spec_script = load(SPEC_SCRIPT)
	if spec_script == null:
		return
	var specs: Array = []
	for family_name in OpRegistry.family_names():
		var info: Dictionary = OpRegistry.family(family_name)
		var spec = spec_script.new()
		spec.name = family_name
		spec.description = str(info.get("description", ""))
		spec.params_schema = info.get("schema", {})
		spec.script_path = str(info.get("handler", ""))
		spec.method = &"run"
		spec.source_path = SOURCE_CFG
		spec.promoted = bool(info.get("promoted", true))
		spec.requires_writable = bool(info.get("requires_writable", true))
		spec.undoable = bool(info.get("undoable", true))
		spec.deferred = bool(info.get("deferred", false))
		spec.timeout_ms = int(info.get("timeout_ms", 5000))
		specs.append(spec)
	# One atomic batch. A per-family loop that stopped on the first failure left
	# the families before it committed AND dispatchable while the server's tool
	# list never heard about them; `batch_register` validates everything first
	# and commits everything second, which matches how the server treats a
	# snapshot. `registry` is the fallback for an older core addon.
	if live.has_method("batch_register"):
		_registered = bool(live.call("batch_register", specs))
	else:
		_registered = true
		for spec in specs:
			if not live.call("register", spec):
				_registered = false
	if not _registered:
		push_error(
			"Godot AI Animation Toolkit: registration was rejected (the error above "
			+ "names the family), so NO toolkit tools were registered."
		)


## Every family present, so a partial registration is never treated as done.
func _spec_present(live: Object) -> bool:
	for family_name in OpRegistry.family_names():
		if live.call("get_spec", family_name) == null:
			return false
	return true


func _disconnect(registry: Object) -> void:
	if registry != null and registry.registry_ready.is_connected(_register):
		registry.registry_ready.disconnect(_register)


## The live Godot AI tool registry, or null when Godot AI isn't installed.
## Loaded by path so this addon parses and loads without the core addon.
static func _instance():
	if not ResourceLoader.exists(REGISTRY_SCRIPT):
		return null
	var registry_script = load(REGISTRY_SCRIPT)
	if registry_script == null:
		return null
	return registry_script.call("get_instance")
