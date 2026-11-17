"""Collect exact synthetic graph and rig scenes from the released Linux public route."""
import argparse
import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from replay_linux_motion_effects import checked, load, save, sha, stop, use_authenticated_http


GRAPH = ('additive_lean', 'blend_space', 'blend_tree', 'locomotion',
         'one_shot_layer', 'state_machine', 'wire')
RIG = ('pose_to_clip', 'walk_cycle', 'idle_breathing', 'blink', 'jumping_jack', 'squat',
       'punch', 'bake_pose_sequence')
SCENES = {
    **{'animation_graph.' + name: f'graph_history_{name}_' + ('replace' if name == 'wire' else 'new')
       for name in GRAPH},
    **{'animation_rig.' + name: 'rig_clip_history_local_3d_' + name for name in RIG},
    'animation_rig.pose_apply': 'rig_pose_history_3d_local_apply',
}


async def public_suites(project, core, output):
    from ci_rendered_preview import wait_scene
    from mcp_graph_history import EXPECTED as GRAPH_TESTS
    from mcp_preset_library_history import valid_suite
    from mcp_presets_audit import call
    from mcp_rig_clip_history import EXPECTED as CLIP_TESTS
    from mcp_rig_modifier_ui_history import connected_editor
    from mcp_rig_pose_history import EXPECTED as POSE_TESTS

    selected = {'graph_route_history': {name: 1 for name in GRAPH_TESTS},
                'rig_clip_history': CLIP_TESTS, 'rig_pose_history': POSE_TESTS['rig_pose_history']}
    args = argparse.Namespace(project_root=project, core_root=core, port=8000, ws_port=9500)
    async with connected_editor(args) as (client, _):
        opened = await call(client, 'scene_open', {'path': 'res://main.tscn', 'force_reload': True})
        if opened.get('error'):
            raise ValueError('Main scene did not open')
        await wait_scene(lambda name, params: call(client, name, params), 'res://main.tscn')
        for suite, expected in selected.items():
            result = await call(client, 'test_run', {'suite': suite, 'verbose': True})
            save(output / (suite + '.json'), result)
            if not valid_suite(result, expected):
                raise ValueError('Public editor suite failed: ' + suite)
        response = await call(client, 'editor_manage', {'op': 'quit'})
        if response.get('error'):
            raise ValueError('Public editor quit failed')


def archive_scenes(output, user_data, operations):
    from audit_candidate_case_coverage import confined

    events = {}
    for artifact in operations['raw_artifacts']:
        if artifact['role'] != 'raw_public_calls':
            continue
        path = confined(output, artifact['path'])
        if sha(path) != artifact['sha256']:
            raise ValueError('Raw public call changed')
        for line in path.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            if event['id'] in events or event['context_sha256'] != operations['context_sha256']:
                raise ValueError('Raw public call identity differs')
            events[event['id']] = event
    scene_dir = output / 'scenes'
    scene_dir.mkdir()
    records = []
    for operation, stem in SCENES.items():
        undo_redo = [case for case in operations['cases'] if case['operation'] == operation
                     and case['route'] == 'public_test_run_inner_dispatch'
                     and all(case['checks'].get(k) == 'pass' for k in ('undo_redo', 'save_reopen', 'source_unchanged'))]
        evidence, = [case for case in undo_redo if events[case['raw_event_id']]['row']
                     .get('persist_redo', {}).get('path') == 'user://' + stem + '_redo.tscn']
        inner = events[evidence['raw_event_id']]
        outer = events[evidence['public_test_run_case_id']]
        if inner['operation'] != operation or outer['public_tool'] != 'test_run' or \
                events[inner['test_run_begin_id']]['request'] != outer['request']:
            raise ValueError('History row does not match its public test run: ' + operation)
        saved = {}
        for state in ('undo', 'redo'):
            name = f'{stem}_{state}.tscn'
            witness = inner['row']['persist_' + state]
            scene = confined(user_data, name)
            if witness['path'] != 'user://' + name or witness['sha256'] != sha(scene):
                raise ValueError('Saved scene bytes differ: ' + name)
            if '[ext_resource' in scene.read_text(encoding='utf-8'):
                raise ValueError('Only self-contained synthetic scenes may be archived: ' + name)
            target = scene_dir / name
            shutil.copyfile(scene, target)
            if sha(target) != witness['sha256']:
                raise ValueError('Archived scene copy differs: ' + name)
            saved[state] = {'path': 'scenes/' + name, 'sha256': witness['sha256']}
        records.append({'operation': operation, 'case_id': inner['id'], 'outer_id': outer['id'], 'saved': saved})
    save(output / 'saved-inputs.json', {'tested_source': operations['tested_source'],
         'platform': operations['platform'], 'engine': operations['engine'], 'core_version': operations['core_version'],
         'core_commit': operations['core_commit'], 'context_sha256': operations['context_sha256'],
         'operation_report_sha256': sha(output / 'operation-case-results.json'), 'cases': records})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('audit', 'core', 'output', 'godot'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    audit, core, output, godot = (path.resolve() for path in (args.audit, args.core, args.output, args.godot))
    sys.path.insert(0, str(audit / 'tools'))
    from ci_mcp_route import port_open
    from operation_case_collector import collect, prepare
    from operation_derived_gate import derived_failures

    use_authenticated_http()
    output.mkdir(exist_ok=False)
    project = audit / 'test_project'
    (project / 'addons/godot_ai').symlink_to(core / 'plugin/addons/godot_ai', target_is_directory=True)
    (project / 'addons/godot_ai_animation').symlink_to(audit / 'addons/godot_ai_animation', target_is_directory=True)
    storage = audit / 'visual-inputs-xdg'
    context, traces = output / 'operation-context.json', output / 'public-calls'
    os.environ.update(GODOT_AI_ALLOW_HEADLESS='1', GODOT_AI_DISABLE_TELEMETRY='true',
                      GODOT_AI_VENV_PYTHON=sys.executable, TOOLKIT_OPERATION_CONTEXT=str(context),
                      TOOLKIT_OPERATION_TRACE_DIR=str(traces), XDG_CONFIG_HOME=str(storage / 'config'),
                      XDG_DATA_HOME=str(storage / 'data'), XDG_CACHE_HOME=str(storage / 'cache'))
    checked([str(godot), '--headless', '--path', str(project), '--import'], output / 'import.log', 140)
    prepare(audit, core, godot, context)
    identity = load(context)
    if not identity['engine'].startswith('4.7.2.stable.official.') or identity['platform'] != 'linux' or \
            identity['core_version'] not in ('4.2.1', '4.3.0'):
        raise ValueError('Official Linux Godot 4.7.2 and a released core are required')
    if port_open(8000) or port_open(9500):
        raise ValueError('Backend ports already occupied')
    owned = []
    try:
        with (output / 'backend.log').open('xb') as backend_log, (output / 'editor.log').open('xb') as editor_log:
            backend = subprocess.Popen([sys.executable, '-m', 'godot_ai', '--transport', 'streamable-http'],
                                       cwd=core, stdout=backend_log, stderr=subprocess.STDOUT)
            owned.append(backend)
            deadline = time.monotonic() + 45
            while not (port_open(8000) and port_open(9500)):
                if backend.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Backend failed to open')
                time.sleep(.25)
            editor = subprocess.Popen([str(godot), '--headless', '--editor', '--path', str(project),
                                       'res://main.tscn'], stdout=editor_log, stderr=subprocess.STDOUT)
            owned.append(editor)
            asyncio.run(public_suites(project, core, output))
            if editor.wait(timeout=30):
                raise RuntimeError('Public editor did not exit cleanly')
    finally:
        for process in reversed(owned):
            stop(process)
    operations = collect(context, traces, audit)
    save(output / 'operation-case-results.json', operations)
    if derived_failures(operations):
        raise ValueError('Derived public operation check failed')
    archive_scenes(output, storage / 'data/godot/app_userdata/Godot AI Animation Toolkit Test', operations)
    print('LINUX_VISUAL_INPUTS=16 public operations, 32 exact saved scenes', flush=True)


if __name__ == '__main__':
    main()
