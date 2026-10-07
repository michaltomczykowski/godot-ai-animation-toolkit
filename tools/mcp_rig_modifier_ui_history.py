"""Public modifier calls, core reloads, and native Windows history witnesses."""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call
from mcp_edit_audit import equivalent

OPS = ('ik_setup', 'look_at_setup', 'twist_setup', 'spring_setup', 'retarget_setup')
ROOT = '/ModifierUI'
PARAMS = {
    'ik_setup': {'kind': 'two_bone', 'chain': ['hips', 'spine', 'chest']},
    'look_at_setup': {'bone': 'head', 'use_secondary_rotation': False},
    'twist_setup': {'spine_chain': ['hips', 'spine', 'chest', 'head'], 'disperse': {'mode': 'even'}},
    'spring_setup': {'springs': [{'root_bone': 'spine', 'end_bone': 'head', 'center_from': 'world_origin', 'enable_all_child_collisions': False,
        'collisions': [ROOT + '/Caller/A/Collider', ROOT + '/Caller/B/Collider'], 'stiffness': 0.7, 'drag': 0.3}]},
    'retarget_setup': {'target_path': ROOT + '/Receiver', 'profile': 'auto'},
}

def valid_route(report: dict) -> bool:
    phases = report.get('phases', [])
    return (report.get('passed') is True and len(phases) == 2
        and [phase.get('phase') for phase in phases] == ['before_reload', 'after_reload']
        and isinstance(report.get('reload'), dict) and not report['reload'].get('error')
        and all(len(phase.get('rows', [])) == len(OPS)
            and [row.get('op') for row in phase['rows']] == list(OPS)
            and all(row.get('passed') is True and all(isinstance(row.get(key), dict)
                and not row[key].get('error') for key in ('made', 'dry', 'save', 'reopen'))
                for row in phase['rows']) for phase in phases))

def fixture_text() -> str:
    text = '[gd_scene format=3]\n[node name="ModifierUI" type="Node3D"]\n'
    for name in ('Source', 'Receiver'):
        text += f'[node name="{name}" type="Skeleton3D" parent="."]\n'
        text += 'position = Vector3(0.3, 0.1, -0.2)\nrotation = Vector3(0.05, 0.2, 0.1)\n'
        for i, bone in enumerate(('hips', 'spine', 'chest', 'head', 'untouched')):
            parent = i - 1 if i in (1, 2, 3) else -1
            text += f'bones/{i}/name = "{bone}"\nbones/{i}/parent = {parent}\n'
            text += f'bones/{i}/rest = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.45, 0)\n'
            text += f'bones/{i}/enabled = true\nbones/{i}/position = Vector3(0.02, 0.45, 0.01)\n'
            text += f'bones/{i}/rotation = Quaternion(0.0249974, 0, 0, 0.9996875)\nbones/{i}/scale = Vector3(1, 1, 1)\n'
    text += '[node name="Caller" type="Node3D" parent="."]\nposition = Vector3(-0.2, 0.4, 0.3)\nrotation = Vector3(0.1, 0.2, -0.3)\n'
    text += '[node name="Center" type="Marker3D" parent="Caller"]\n'
    for branch in ('A', 'B'):
        text += f'[node name="{branch}" type="Node3D" parent="Caller"]\nposition = Vector3(0.4, 0.2, 0.1)\nrotation = Vector3(0.1, 0.2, 0.3)\n'
        text += f'[node name="Collider" type="SpringBoneCollisionSphere3D" parent="Caller/{branch}"]\nposition = Vector3(0.3, 0.5, -0.2)\nradius = 0.08\n'
    text += '[node name="LastSibling" type="Node3D" parent="."]\n'
    return text

async def invoke(client: Client, params: dict) -> dict:
    return await call(client, 'custom_manage', {'op': 'invoke', 'params': {
        'tool_name': 'animation_rig_modifiers', 'params': params}})

async def snapshot(client: Client) -> dict:
    tree = await call(client, 'scene_get_hierarchy', {'depth': 8, 'limit': 100})
    result = {'tree': tree, 'nodes': {}, 'source_pose': await call(client, 'custom_animation_rig',
        {'op': 'pose_save', 'skeleton_path': ROOT + '/Source'})}
    for node in tree.get('nodes', []):
        path = node['path']
        if node.get('type', '').endswith(('Modifier3D', 'Simulator3D', 'Disperser3D', 'IK3D')):
            props = await call(client, 'node_get_properties', {'path': path})
            result['nodes'][path] = props
        elif node.get('type') == 'SpringBoneCollisionSphere3D':
            result['nodes'][path] = await call(client, 'node_get_properties',
                {'path': path, 'fields': ['transform', 'radius', 'name']})
        elif node.get('name') == 'Receiver':
            result['receiver_pose'] = await call(client, 'custom_animation_rig',
                {'op': 'pose_save', 'skeleton_path': path})
    return result

async def setup(client: Client, args: argparse.Namespace, op: str, existing: bool = False) -> dict:
    folder = args.project_root / 'repair_ui_undo'
    folder.mkdir(exist_ok=True)
    target = folder / f'modifier_{op}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S_%f}.tscn'
    target.write_text(fixture_text(), encoding='utf-8')
    scene = 'res://repair_ui_undo/' + target.name
    sentinel = 'Ready_' + target.stem
    with target.open('a', encoding='utf-8') as stream: stream.write(f'[node name="{sentinel}" type="Node3D" parent="."]\n')
    opened = await call(client, 'scene_open', {'path': scene})
    for _ in range(30):
        found = await call(client, 'node_find', {'name': sentinel})
        if any(node.get('name') == sentinel for node in found.get('nodes', [])): break
        await asyncio.sleep(0.2)
    else: raise RuntimeError('New scene root did not become active: ' + scene)
    params = {'op': op, 'skeleton_path': ROOT + '/Source', 'name': 'Configured', 'active': False, **PARAMS[op]}
    if existing:
        seed = await invoke(client, params)
        if seed.get('error'): raise RuntimeError(seed)
        params.update(target_path=seed['target_path'], position=True, scale=True, use_global_pose=True, move_target=False)
    baseline = await snapshot(client)
    unavailable = await invoke(client, {'op': 'ik_setup', 'skeleton_path': ROOT + '/Source',
        'kind': 'jacobian', 'chain': ['hips', 'spine', 'chest']})
    dry = await invoke(client, {**params, 'dry_run': True})
    after_dry = await snapshot(client)
    made = await invoke(client, params)
    generated = await snapshot(client)
    error = unavailable.get('error', {})
    code = error.get('code') if isinstance(error, dict) else str(error).split(':', 1)[0]
    passed = (not opened.get('error') and not dry.get('error') and not made.get('error')
        and equivalent(baseline, after_dry) and not equivalent(baseline, generated)
        and code == 'OPERATION_UNAVAILABLE')
    return {'passed': passed, 'op': op, 'scene': scene, 'baseline': baseline, 'generated': generated,
            'made': made, 'dry': dry, 'unavailable': unavailable}

async def run(args: argparse.Namespace) -> int:
    if args.mode == 'route': return await run_route(args)
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        if args.mode == 'setup':
            result = await setup(client, args, args.op, args.op == 'retarget_setup')
            args.record.write_text(json.dumps(result, indent=2), encoding='utf-8')
        elif args.mode == 'inspect':
            record = json.loads(args.record.read_text(encoding='utf-8'))
            actual = await snapshot(client)
            result = {'passed': equivalent(actual, record[args.expect]), 'expected': args.expect,
                      'actual': actual, 'scene': record['scene']}
    print('MCP_RIG_MODIFIER_UI_HISTORY=' + json.dumps(result, sort_keys=True))
    return 0 if result['passed'] else 1

async def run_route(args: argparse.Namespace) -> int:
    phases = []
    reload_result = {}
    for phase in ('before_reload', 'after_reload'):
        # Reconnect the attach client after a core reload. A prior attach
        # transport can retain the old session routing hint.
        transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
            '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
        async with Client(transport) as client:
            await client.call_tool('session_activate', {'session_id': args.session_hint})
            rows = []
            for op in OPS:
                row = await setup(client, args, op)
                row['save'] = await call(client, 'scene_save', {})
                row['saved'] = await snapshot(client)
                row['reopen'] = await call(client, 'scene_open', {'path': row['scene'], 'force_reload': True})
                row['persisted'] = await snapshot(client)
                row['passed'] &= (not row['save'].get('error') and not row['reopen'].get('error')
                    and equivalent(row['saved'], row['persisted'])
                    and equivalent(row['generated']['source_pose'], row['saved']['source_pose'])
                    and equivalent(row['generated']['receiver_pose'], row['saved']['receiver_pose']))
                rows.append(row)
            phases.append({'phase': phase, 'rows': rows})
            if phase == 'before_reload': reload_result = await call(client, 'editor_reload_plugin', {})
        if phase == 'before_reload': await asyncio.sleep(1.0)
    result = {'passed': all(row['passed'] for phase in phases for row in phase['rows']),
              'phases': phases, 'reload': reload_result}
    result['passed'] = valid_route(result)
    args.record.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('MCP_RIG_MODIFIER_UI_HISTORY=' + json.dumps(result, sort_keys=True))
    return 0 if result['passed'] else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--mode', choices=('setup', 'inspect', 'route'), required=True)
    parser.add_argument('--op', choices=OPS, default='look_at_setup')
    parser.add_argument('--expect', choices=('baseline', 'generated'), default='generated')
    parser.add_argument('--record', type=Path, required=True)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
