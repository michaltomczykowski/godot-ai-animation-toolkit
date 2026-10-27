"""Isolated headless controls for dependency diagnostics and fallback rollback."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

SPEC = '''extends RefCounted
var name: String
var description: String
var params_schema: Dictionary
var script_path: String
var method: StringName
var source_path: String
var promoted: bool
var requires_writable: bool
var undoable: bool
var deferred: bool
var timeout_ms: int
'''
REGISTRY = '''extends RefCounted
signal registry_ready
static var instance: Object
var specs := {}
var calls := 0
var reject_at := -1
static func get_instance():
    return instance
func register(spec) -> bool:
    calls += 1
    if calls == reject_at:
        return false
    if specs.has(spec.name) and specs[spec.name].source_path != spec.source_path:
        return false
    specs[spec.name] = spec
    return true
func get_spec(name):
    return specs.get(name)
func unregister_source(source) -> int:
    var removed := 0
    for name in specs.keys():
        if specs[name].source_path == source:
            specs.erase(name)
            removed += 1
    return removed
'''
SUITE = '''extends SceneTree
class BatchRegistry extends RefCounted:
    var reject := false
    var calls := 0
    func batch_register(specs: Array) -> bool:
        calls += 1
        assert(specs.is_typed() and specs.get_typed_script() != null)
        assert(specs.size() == 10)
        return not reject
func _initialize() -> void:
    _run.call_deferred()
func _run() -> void:
    await create_timer(1.0).timeout
    var plugin_script = load("res://addons/godot_ai_animation/plugin.gd")
    var cfg_path := "res://addons/godot_ai/plugin.cfg"
    assert("not installed" in plugin_script._core_dependency_error())
    var versions := {"4.1.0": "too old", "4.2.0": "too old", "": "invalid", "4.2.1-rc1": "prerelease", "bad": "invalid", "4.2.1": "", "4.3.0": "", "4.10.0": ""}
    for version in versions:
        var cfg := ConfigFile.new()
        cfg.set_value("plugin", "version", version)
        assert(cfg.save(cfg_path) == OK)
        var message: String = plugin_script._core_dependency_error()
        if versions[version] == "":
            assert(message == "", message)
        else:
            assert(versions[version] in message, message)
    var file := FileAccess.open(cfg_path, FileAccess.WRITE)
    file.store_string("[plugin\nversion=broken")
    file.close()
    assert("could not be read" in plugin_script._core_dependency_error())
    for i in range(12):
        assert("could not be read" in plugin_script._core_dependency_error())
    var cfg := ConfigFile.new()
    cfg.set_value("plugin", "version", "4.2.1")
    cfg.save(cfg_path)
    var registry_script = load("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
    registry_script.instance = RefCounted.new()
    assert("lifecycle API missing" in plugin_script._core_dependency_error())
    registry_script.instance = null
    var spec_script = load("res://addons/godot_ai/custom_tools/mcp_custom_tool_spec.gd")
    var batch := BatchRegistry.new()
    assert(plugin_script._register_specs(batch, spec_script))
    batch.reject = true
    assert(not plugin_script._register_specs(batch, spec_script))
    for i in range(12):
        assert(not plugin_script._register_specs(batch, spec_script))
    assert(batch.calls == 2)
    cfg.set_value("plugin", "version", "4.3.0")
    cfg.save(cfg_path)
    assert(plugin_script._core_dependency_error() == "")
    assert(not plugin_script._register_specs(batch, spec_script))
    assert(batch.calls == 3)
    var registry = registry_script.new()
    registry_script.instance = registry
    assert(plugin_script._register_specs(registry, spec_script) and registry.specs.size() == 10)
    registry.specs.clear()
    registry.calls = 0
    registry.reject_at = 4
    assert(not plugin_script._register_specs(registry, spec_script) and registry.specs.is_empty())
    assert(registry.calls == 4)
    registry.reject_at = -1
    registry.calls = 0
    var foreign = load("res://addons/godot_ai/custom_tools/mcp_custom_tool_spec.gd").new()
    foreign.name = plugin_script.OpRegistry.family_names()[2]
    foreign.source_path = "res://addons/foreign/plugin.cfg"
    registry.specs[foreign.name] = foreign
    assert(not plugin_script._register_specs(registry, spec_script) and registry.specs.size() == 1)
    assert(registry.specs[foreign.name] == foreign)
    registry.specs.erase(foreign.name)
    assert(plugin_script._register_specs(registry, spec_script))
    assert(plugin_script._spec_present(registry))
    registry.specs[foreign.name] = foreign
    assert(not plugin_script._spec_present(registry))
    cfg.set_value("plugin", "version", "4.1.0")
    cfg.save(cfg_path)
    assert("too old" in plugin_script._core_dependency_error())
    assert(plugin_script._instance() == null)
    plugin_script._unregister_known(registry)
    assert(registry.specs.size() == 1 and registry.specs[foreign.name] == foreign)
    registry_script.instance = null
    await process_frame
    print("CORE_DEPENDENCY_PASS=metadata-cache,typed-batch,rejection-cache,fallback-rollback,foreign-presence,invalidated-cleanup")
    quit(0)
'''

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', required=True)
    a = p.parse_args()
    from ci_mcp_route import godot_executable
    a.godot = godot_executable(a.godot)
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='toolkit-core-controls-') as temp:
        project = Path(temp)
        shutil.copytree(repo / 'addons/godot_ai_animation', project / 'addons/godot_ai_animation')
        core = project / 'addons/godot_ai/custom_tools'
        core.mkdir(parents=True)
        (core / 'mcp_custom_tool_spec.gd').write_text(SPEC)
        (core / 'mcp_tool_registry.gd').write_text(REGISTRY)
        (project / 'project.godot').write_text('config_version=5\n')
        (project / 'suite.gd').write_text(SUITE)
        run = subprocess.run([a.godot, '--headless', '--path', str(project), '--script', 'res://suite.gd'], capture_output=True, text=True, timeout=90)
        print(run.stdout + run.stderr)
        unexpected_errors = [line for line in run.stderr.splitlines() if line.startswith('ERROR:') and not line.startswith('ERROR: ConfigFile parse error at res://addons/godot_ai/plugin.cfg:')]
        if run.returncode or 'CORE_DEPENDENCY_PASS=' not in run.stdout or 'Parse Error' in run.stderr or 'SCRIPT ERROR:' in run.stderr or unexpected_errors or run.stderr.count('ERROR: ConfigFile parse error') != 1:
            raise RuntimeError('Core dependency controls failed')

if __name__ == '__main__':
    main()
