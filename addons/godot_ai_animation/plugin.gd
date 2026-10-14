@tool
extends EditorPlugin

## Registers the animation toolkit's tools with Godot AI (>= 4.2.1):
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
const CORE_CFG := "res://addons/godot_ai/plugin.cfg"
const RETRY_WINDOW_SEC := 30.0
const POLL_INTERVAL_SEC := 0.5

var _retry_left := 0.0
var _registered := false
var _warned := false
var _poll := 0.0
var _registry: Object = null
var _dependency_message := ""


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
				"Godot AI Animation Toolkit: Godot AI (>= 4.2.1) not ready - "
				+ "no toolkit tools were registered."
			)
		return
	_try_register()


func _try_register() -> void:
	var dependency_error := _core_dependency_error()
	if not dependency_error.is_empty():
		if dependency_error != _dependency_message:
			push_warning("Godot AI Animation Toolkit: " + dependency_error)
			_dependency_message = dependency_error
		return
	_dependency_message = ""
	var live = _instance()
	if live == null:
		return
	if not live.has_signal("registry_ready") or not live.has_method("get_spec") or not live.has_method("unregister_source"):
		push_error("Godot AI Animation Toolkit: incompatible core registry API; registration refused.")
		return
	if _registry != live:
		_disconnect(_registry)
		_registry = live
		if not live.registry_ready.is_connected(_register):
			live.registry_ready.connect(_register)
	_register()


## Idempotent: also runs on `registry_ready` after a Godot AI reload.
func _register() -> void:
	if not _core_dependency_error().is_empty():
		return
	var live = _instance()
	if live == null:
		return
	var spec_script = load(SPEC_SCRIPT)
	if spec_script == null:
		return
	_registered = _register_specs(live, spec_script)
	if not _registered:
		push_error("Godot AI Animation Toolkit: registration rejected; see the core/fallback diagnostic above.")


## Returns success only after every family is registered. The fallback removes
## this source on first rejection and verifies rollback without touching others.
static func _register_specs(live: Object, spec_script: Script) -> bool:
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
		# call() does not coerce Array to Array[McpCustomToolSpec]. Construct the
		# typed array from the dynamically loaded script, so this addon still
		# parses when Godot AI is not installed.
		var typed_specs := Array(specs, TYPE_OBJECT, &"RefCounted", spec_script)
		return bool(live.call("batch_register", typed_specs))
	else:
		if not live.has_method("register") or not live.has_method("unregister_source"):
			push_error("Godot AI Animation Toolkit: incompatible core registration API; rollback unavailable.")
			return false
		for spec in specs:
			if not live.call("register", spec):
				live.call("unregister_source", SOURCE_CFG)
				for family_name in OpRegistry.family_names():
					var remaining = live.call("get_spec", family_name)
					if remaining != null and remaining.source_path == SOURCE_CFG:
						push_error("Godot AI Animation Toolkit: single-registration rollback failed.")
						return false
				return false
	return true


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
	if not _core_dependency_error().is_empty():
		return null
	if not ResourceLoader.exists(REGISTRY_SCRIPT):
		return null
	var registry_script = load(REGISTRY_SCRIPT)
	if registry_script == null:
		return null
	if not registry_script.has_method("get_instance"):
		return null
	var instance = registry_script.call("get_instance")
	if instance != null and (not instance.has_signal("registry_ready") or not instance.has_method("get_spec") or not instance.has_method("unregister_source")):
		return null
	return instance


## Check metadata before loading core scripts. Stable releases only; comparing
## numeric components avoids treating 4.10 as older than 4.2.
static func _core_dependency_error() -> String:
	if not FileAccess.file_exists(CORE_CFG):
		return "Godot AI >= 4.2.1 required; addon not installed (" + CORE_CFG + ")."
	var cfg := ConfigFile.new()
	if cfg.load(CORE_CFG) != OK:
		return "Godot AI metadata could not be read: " + CORE_CFG
	var version := str(cfg.get_value("plugin", "version", ""))
	var parts := version.split(".")
	if parts.size() != 3:
		return "Godot AI has an invalid or prerelease version: '" + version + "'; stable >= 4.2.1 required."
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or part.begins_with("+") or (part.length() > 1 and part.begins_with("0")):
			return "Godot AI has an invalid or prerelease version: '" + version + "'; stable >= 4.2.1 required."
	var minimum := [4, 2, 1]
	for i in range(3):
		if int(parts[i]) > minimum[i]:
			return _core_api_paths_error()
		if int(parts[i]) < minimum[i]:
			return "Godot AI " + version + " is too old; >= 4.2.1 required."
	return _core_api_paths_error()


static func _core_api_paths_error() -> String:
	if not ResourceLoader.exists(REGISTRY_SCRIPT) or not ResourceLoader.exists(SPEC_SCRIPT):
		return "Godot AI installation is incomplete or incompatible; custom-tool registry/spec scripts missing."
	var registry_script = load(REGISTRY_SCRIPT)
	if registry_script == null or not registry_script.has_method("get_instance"):
		return "Godot AI installation is incompatible; custom-tool registry singleton API missing."
	var instance = registry_script.call("get_instance")
	if instance != null and (not instance.has_signal("registry_ready") or not instance.has_method("get_spec") or not instance.has_method("unregister_source")):
		return "Godot AI installation is incompatible; custom-tool registry lifecycle API missing."
	return ""
