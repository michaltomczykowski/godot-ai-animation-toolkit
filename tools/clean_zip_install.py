"""Qualify an extracted committed toolkit ZIP in a fresh, unlinked project.

Runs the existing full public-route/history/native-effect/reload harness against
installed bytes, in both plugin enable orders. A companion editor plugin checks
registry selection and persisted disable state before the public route starts.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
from validate_release_package import validate, git, read_blobs

PROBE = '''@tool
extends EditorPlugin
var done := false
func _process(_delta: float) -> void:
    if done:
        var request_path := "res://clean-selection-request.json"
        if FileAccess.file_exists(request_path):
            var request = JSON.parse_string(FileAccess.get_file_as_string(request_path))
            if request is Dictionary and request.has("enabled"):
                var registry = load("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd").call("get_instance")
                if registry != null:
                    registry.set_tool_enabled("animation_inspect", bool(request.enabled))
        return
    var registry_script = load("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
    var registry = registry_script.call("get_instance")
    if registry == null:
        return
    var names = load("res://addons/godot_ai_animation/registry/op_registry.gd").family_names()
    for family in names:
        if registry.get_spec(family) == null:
            return
    done = true
    assert(names.size() == 10)
    var promoted := 0
    for family in names:
        if registry.get_spec(family).promoted:
            promoted += 1
        registry.set_tool_enabled(family, false)
        assert(not registry.is_tool_enabled(family))
        assert(registry.get_spec(family) != null)
    assert(promoted == 8)
    var disabled = EditorInterface.get_editor_settings().get_project_metadata("godot_ai", "disabled_custom_tools", [])
    for family in names:
        assert(family in disabled)
        registry.set_tool_enabled(family, true)
        assert(registry.is_tool_enabled(family))
    print("CLEAN_INSTALL_SELECTION_PASS=10/8")
'''

def unpack_safe(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            path = Path(item.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in item.filename or ':' in item.filename or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe core ZIP entry: ' + item.filename)
        z.extractall(destination)

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True)
    p.add_argument('--zip', type=Path, required=True)
    p.add_argument('--core-root', type=Path, required=True)
    p.add_argument('--core-zip', type=Path, help='Released core plugin asset; otherwise exact core checkout files')
    p.add_argument('--core-ref', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--godot', default='godot')
    p.add_argument('--port', type=int, default=8000)
    p.add_argument('--ws-port', type=int, default=9500)
    a = p.parse_args()
    repo = Path(__file__).resolve().parents[1]
    manifest = validate(repo, a.source, a.zip)
    a.output = a.output.resolve()
    if a.output.exists():
        raise ValueError('Use a fresh output directory; previous evidence is preserved')
    a.output.mkdir(parents=True)
    core_sha = git(a.core_root, 'rev-parse', 'HEAD').decode().strip()
    expected = {'4.2.1': 'bfc264200584ea5823f18356acb164781f57796d', '4.3.0': 'b82b5c519b1b17228f70d8effce1626f391bd1dd'}
    if a.core_ref not in expected or core_sha != expected[a.core_ref]:
        raise ValueError('Clean install requires an exact supported released core')
    results = []
    for order in ('core-first', 'toolkit-first'):
        project = a.output / order
        project.mkdir()
        # External validation fixtures are source controlled; the addon itself
        # is installed exclusively from its ZIP. git archive excludes local rigs.
        fixtures = a.output / ('fixtures-' + order + '.zip')
        subprocess.run(['git', '-c', 'core.autocrlf=false', '-C', str(repo), 'archive', '--format=zip', '--output', str(fixtures), manifest['source'], 'test_project'], check=True)
        staging = a.output / ('fixture-source-' + order)
        unpack_safe(fixtures, staging)
        shutil.copytree(staging / 'test_project', project, dirs_exist_ok=True)
        installed = project / 'addons' / 'godot_ai_animation'
        if installed.exists():
            raise ValueError('Validation fixture unexpectedly includes toolkit addon')
        unpack_safe(a.zip, project)
        if a.core_zip:
            core_stage = a.output / ('core-source-' + order)
            unpack_safe(a.core_zip, core_stage)
            candidates = list(core_stage.rglob('godot_ai/plugin.cfg'))
            if len(candidates) != 1:
                raise ValueError('Core release ZIP must contain one godot_ai addon')
            shutil.copytree(candidates[0].parent, project / 'addons' / 'godot_ai')
        else:
            core_archive = a.output / ('core-' + order + '.zip')
            subprocess.run(['git', '-c', 'core.autocrlf=false', '-C', str(a.core_root), 'archive', '--format=zip', '--output', str(core_archive), core_sha, 'plugin/addons/godot_ai'], check=True)
            core_stage = a.output / ('core-source-' + order)
            unpack_safe(core_archive, core_stage)
            shutil.copytree(core_stage / 'plugin/addons/godot_ai', project / 'addons/godot_ai')
        core_files = {}
        for row in git(a.core_root, 'ls-tree', '-rz', core_sha, '--', 'plugin/addons/godot_ai').split(b'\0'):
            if not row:
                continue
            metadata, filename = row.split(b'\t', 1)
            mode, kind, blob = metadata.decode().split()
            if kind != 'blob' or mode == '120000':
                raise ValueError('Released core tree contains a nonregular addon file')
            relative = Path(filename.decode()).relative_to('plugin')
            core_files[relative] = blob
        core_blobs = read_blobs(a.core_root, list(core_files.values()))
        for relative, blob in core_files.items():
            if (project / relative).read_bytes() != core_blobs[blob]:
                raise ValueError('Released core asset differs from exact core source: ' + str(relative))
        for path in (project / 'addons').rglob('*'):
            if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
                raise ValueError('Installed addon contains a link: ' + str(path))
        probe = project / 'addons/clean_install_probe'
        probe.mkdir()
        (probe / 'plugin.gd').write_text(PROBE)
        (probe / 'plugin.cfg').write_text('[plugin]\nname="Clean install qualification"\nscript="plugin.gd"\n')
        cfg = project / 'project.godot'
        text = cfg.read_text()
        start = text.index('enabled=PackedStringArray(')
        end = text.index(')', start) + 1
        plugins = ['godot_ai', 'godot_ai_animation']
        if order == 'toolkit-first':
            plugins.reverse()
        text = text[:start] + 'enabled=PackedStringArray(' + ', '.join('"res://addons/' + x + '/plugin.cfg"' for x in plugins + ['clean_install_probe']) + ')' + text[end:]
        cfg.write_text(text)
        from ci_mcp_route import godot_executable
        env = os.environ.copy()
        env['GODOT_AI_ALLOW_HEADLESS'] = '1'
        subprocess.run([godot_executable(a.godot), '--headless', '--path', str(project), '--import'], check=True, env=env)
        log = a.output / (order + '-editor.log')
        command = [sys.executable, str(repo / 'tools/ci_mcp_route.py'), '--project', str(project), '--core-root', str(a.core_root.resolve()), '--godot', a.godot, '--log', str(log), '--install-selection', '--port', str(a.port), '--ws-port', str(a.ws_port)]
        run = subprocess.run(command, capture_output=True, text=True, env=env)
        (a.output / (order + '-route.log')).write_text(run.stdout + run.stderr)
        if run.returncode or 'CLEAN_INSTALL_SELECTION_PASS=10/8' not in log.read_text(errors='replace'):
            raise RuntimeError('Clean install failed: ' + order + '\n' + run.stdout[-3000:] + run.stderr[-1000:])
        results.append({'order': order, 'status': 'pass', 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest()})
    receipt = {'schema_version': 1, 'source': manifest['source'], 'zip_sha256': manifest['zip_sha256'], 'engine': '4.7.2', 'core': a.core_ref, 'core_source': core_sha, 'platform': sys.platform, 'cases': results}
    (a.output / 'clean-install-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('CLEAN_ZIP_INSTALL_PASS=' + json.dumps(receipt))

if __name__ == '__main__':
    main()
