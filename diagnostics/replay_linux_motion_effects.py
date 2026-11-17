"""Run the scoped physical audit on one released Linux Godot AI core."""
import argparse
import asyncio
from functools import partial
import hashlib
import json
import os
from pathlib import Path
import shutil
import runpy
import subprocess
import sys
import time


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def use_authenticated_http():
    import mcp_rig_modifier_ui_history as route
    from fastmcp.client.transports import StreamableHttpTransport
    from godot_ai.attach.ensure import BackendEnsurer
    from godot_ai.attach.proxy import _http_client_factory

    def transport(*args, **kwargs):
        endpoint = BackendEnsurer(8000, 9500)
        return StreamableHttpTransport(endpoint.mcp_url,
            httpx_client_factory=partial(_http_client_factory, endpoint.http_capability))

    route.StdioTransport = transport


def checked(command, logfile, timeout):
    print(logfile.stem, flush=True)
    with logfile.open('xb') as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=timeout)


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=8)


async def ready(project, core):
    from ci_rendered_preview import wait_scene
    from mcp_presets_audit import call
    from mcp_rig_modifier_ui_history import connected_editor

    connection = argparse.Namespace(project_root=project, core_root=core, port=8000, ws_port=9500)
    async with connected_editor(connection) as (client, _):
        response = await call(client, 'scene_open', {'path': 'res://main.tscn', 'force_reload': True})
        if response.get('error'):
            raise ValueError('Main fixture failed to open')
        await wait_scene(lambda name, params: call(client, name, params), 'res://main.tscn')


def only_dummy_setup(arguments):
    import mcp_setup_quality_review as driver

    driver.RIGS = tuple(rig for rig in driver.RIGS if rig[0] == 'dummy')
    args = argparse.Namespace(**arguments, styles=['responsive'], variants=['extracted-stationary'],
                              turns=[False], reuse_complete=None, godot=None, port=8000, ws_port=9500)
    return asyncio.run(driver.run(args))


def stage_setup(root, project, godot, context):
    from audit_setup_intent_bridge import REQUEST, SPEC, verify_numeric

    source = context['tested_source']
    route = root / 'setup-public/responsive-extracted-stationary-no-turn/route.json'
    original = load(route)
    case, = original['cases']
    if original['source_head'] != source or not case['passed'] or case['id'] != 'dummy' or case['request'] != REQUEST:
        raise ValueError('Expected a completed dummy setup')
    scene = case['scene']
    relative = scene.removeprefix('res://')
    if sha(project / relative) != case['scene_sha256']:
        raise ValueError('Saved setup scene changed')
    events = [json.loads(line) for path in (root / 'public-calls').glob('*.jsonl')
              for line in path.read_text(encoding='utf-8').splitlines()]
    events = [event for event in events if event.get('scene') == scene]
    dry, = [e for e in events if e.get('params') == dict(REQUEST, dry_run=True)]
    write, = [e for e in events if e.get('params') == REQUEST]
    saved, = [e for e in events if e.get('public_tool') == 'scene_save']
    reopened, = [e for e in events if e.get('public_tool') == 'scene_open'
                 and e.get('response', {}).get('reloaded_from_disk') is True
                 and e.get('request') == {'path': scene, 'force_reload': True}]
    ordered = (dry, write, saved, reopened)
    replay = root / 'fixed-speed'
    replay.mkdir()
    manifest = replay / 'fixed-spec.json'
    save(manifest, {'source_head': source, 'cases': [dict(case, quality_specs=[SPEC])]})
    checker = 'tools/check_setup_tree_quality.gd'
    if sha(project / checker) != context['dependencies']['test_project/' + checker]['sha256']:
        raise ValueError('Setup native checker bytes changed')
    files = (relative, 'models/human_dummy/HumanCharacterDummy_F.fbx', checker,
             'addons/godot_ai_animation/runtime/setup_grounding.gd',
             'addons/godot_ai_animation/spec/motion_space.gd')
    inputs = {}
    for path in files:
        name = 'inputs/' + path
        target = replay / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / path, target)
        inputs[name] = sha(target)
    native_path = replay / 'native.json'
    checked([str(godot), '--headless', '--path', str(project), '--script', 'res://' + checker,
             '--', str(manifest), str(native_path)], replay / 'native.log', 90)
    native = load(native_path)
    if not native['passed'] or native['engine_errors'] or native['failures'] or len(native['runs']) != 3:
        raise ValueError('Three-clock setup replay failed')
    input_path = replay / 'input.json'
    save(input_path, {'source': source, 'path_base': 'replay', 'paths': inputs,
                      'manifest_sha256': sha(manifest), 'route_sha256': sha(route),
                      'context_sha256': sha(root / 'operation-context.json'),
                      'case_report_sha256': sha(root / 'operation-case-results.json'),
                      'raw_case_ids': [event['id'] for event in ordered]})
    save(replay / 'setup-valid-effect.json',
         dict(operation='animation_motion.character_setup', status='pass', tested_source=source,
              engine=context['engine'], platform=context['platform'], core_version=context['core_version'],
              public_case_id=write['id'], input_sha256=sha(input_path), native_sha256=sha(native_path),
              observations=verify_numeric(native['runs'], [-1.35006184791564e-5, 0., 1.])))


def replay(audit, core, godot, root, references, setup=False):
    from ci_mcp_route import port_open
    from operation_case_collector import collect, prepare
    from operation_derived_gate import derived_failures
    from operation_transition_intent_checks import REFERENCES

    root.mkdir()
    project = audit / 'test_project'
    context_path = root / 'operation-context.json'
    traces = root / 'public-calls'
    prepare(audit, core, godot, context_path)
    context = load(context_path)
    if not context['engine'].startswith('4.7.2.stable.official.') or not context.get('core_version'):
        raise ValueError('Official Godot 4.7.2 and a released core are required')
    preferences = project.parent / ('setup-config' if setup else 'motion-config')
    os.environ.update(TOOLKIT_OPERATION_CONTEXT=str(context_path), TOOLKIT_OPERATION_TRACE_DIR=str(traces),
                      XDG_CONFIG_HOME=str(preferences / 'config'), XDG_DATA_HOME=str(preferences / 'data'),
                      XDG_CACHE_HOME=str(preferences / 'cache'))
    if port_open(8000) or port_open(9500):
        raise ValueError('Isolated backend ports are unavailable')
    if not setup:
        for kind, (scene, digest) in REFERENCES.items():
            target = project / scene.removeprefix('res://')
            target.parent.mkdir(parents=True)
            shutil.copyfile(references / (kind + '.tscn'), target)
            if sha(target) != digest:
                raise ValueError('Pinned transition input differs')
    owned = []
    operation_args = {'repo': audit, 'core_root': core, 'project_root': project, 'output': root / 'setup-public'}
    try:
        with (root / 'backend.log').open('wb') as backend_log, (root / 'editor.log').open('wb') as editor_log:
            backend = subprocess.Popen([sys.executable, '-m', 'godot_ai', '--transport', 'streamable-http'],
                                       cwd=core, stdout=backend_log, stderr=subprocess.STDOUT)
            owned.append(backend)
            deadline = time.monotonic() + 45
            while not (port_open(8000) and port_open(9500)):
                if backend.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Backend failed to open')
                time.sleep(.25)
            editor = subprocess.Popen([str(godot), '--headless', '--editor', '--path', str(project), 'res://main.tscn'],
                                      stdout=editor_log, stderr=subprocess.STDOUT)
            owned.append(editor)
            asyncio.run(ready(project, core))
            if setup:
                checked([sys.executable, __file__, '--setup', str(audit), str(core), str(project),
                         str(operation_args['output'])], root / 'setup-driver.log', 180)
            else:
                operations = {
                    'idle_cycle': [], 'turn_cycle': ['--direction', 'left', '--angle', '180', '--steps', '2'],
                    'jump': ['--height', '0.2'], 'strafe_cycle': ['--direction', 'left', '--speed', '0.1'],
                    'walk_start': [], 'walk_stop': [],
                }
                for op, extra in operations.items():
                    checked([sys.executable, __file__, '--motion', str(audit / 'tools/mcp_run_quality_review.py'), '--repo', str(audit),
                             '--core-root', str(core), '--project-root', str(project), '--phase', 'candidate',
                             '--operation', op, '--styles', 'responsive', '--root-modes', 'extracted',
                             '--rig-id', 'dummy', '--revision', 'linux-intent-' + op, '--output', str(root / op),
                             *extra], root / (op + '-route.log'), 90)
    finally:
        for process in reversed(owned):
            stop(process)
    if not setup:
        for op in operations:
            transition = op in ('walk_start', 'walk_stop')
            driver = 'check_selected_transition_intent.py' if transition else 'check_selected_motion_intent.py'
            refs = ['--walk-reference', str(references / 'walk-route.json'),
                    '--idle-reference', str(references / 'idle-route.json')] if transition else []
            checked([sys.executable, str(audit / 'tools' / driver), '--godot', str(godot), '--project-root', str(project),
                     '--route', str(root / op / 'responsive/route.json'), '--output', str(root / (op + '-native')),
                     *refs], root / (op + '-native.log'), 140)
    report = collect(context_path, traces, audit)
    save(root / 'operation-case-results.json', report)
    if derived_failures(report):
        raise ValueError('Derived effect failed')
    if setup:
        stage_setup(root, project, godot, context)
    else:
        observed = {case['operation'] for case in report['cases'] if case['checks'].get('valid_effect') == 'pass'}
        if observed != {'animation_motion.' + op for op in operations}:
            raise ValueError('Expected six distinct valid effects')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--motion':
        driver = Path(sys.argv[2])
        sys.path.insert(0, str(driver.parent))
        use_authenticated_http()
        sys.argv = [str(driver), *sys.argv[3:]]
        runpy.run_path(str(driver), run_name='__main__')
    if len(sys.argv) > 1 and sys.argv[1] == '--setup':
        names = ('repo', 'core_root', 'project_root', 'output')
        arguments = dict(zip(names, map(Path, sys.argv[2:]), strict=True))
        sys.path.insert(0, str(arguments['repo'] / 'tools'))
        use_authenticated_http()
        raise SystemExit(only_dummy_setup(arguments))
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('audit', 'core', 'output', 'godot'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--setup-only', action='store_true')
    args = parser.parse_args()
    audit, core, output, godot = (path.resolve() for path in (args.audit, args.core, args.output, args.godot))
    sys.path.insert(0, str(audit / 'tools'))
    use_authenticated_http()
    output.mkdir(exist_ok=False)
    project = audit / 'test_project'
    (project / 'addons/godot_ai').symlink_to(core / 'plugin/addons/godot_ai', target_is_directory=True)
    (project / 'addons/godot_ai_animation').symlink_to(audit / 'addons/godot_ai_animation', target_is_directory=True)
    os.environ.update(GODOT_AI_ALLOW_HEADLESS='1', GODOT_AI_DISABLE_TELEMETRY='true',
                      GODOT_AI_VENV_PYTHON=sys.executable)
    checked([str(godot), '--headless', '--path', str(project), '--import'], output / 'import.log', 140)
    references = Path(__file__).resolve().parent / 'transition-references'
    failures = {}
    for phase in (('setup',) if args.setup_only else ('motion', 'setup')):
        try:
            replay(audit, core, godot, output / phase, references, setup=phase == 'setup')
        except Exception as error:
            failures[phase] = repr(error)
    save(output / 'outcome.json', {'passed': not failures, 'failures': failures})
    if failures:
        raise SystemExit(str(failures))
