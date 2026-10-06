"""Prepare/check rig actions around native Godot Undo/Redo shortcuts."""
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

async def invoke(client: Client, params: dict) -> dict:
    return await call(client, 'custom_manage', {'op':'invoke', 'params':{'tool_name':'animation_rig', 'params':params}})

async def snapshot(client: Client, op: str) -> dict:
    path = '/RigUI/Generated' if op == 'chain' else '/RigUI/Skeleton'
    pose = await invoke(client, {'op':'pose_save', 'skeleton_path':path})
    rig = await invoke(client, {'op':'rig_get', 'skeleton_path':path})
    if pose.get('error'):
        error = pose['error']
        code = error.get('code') if isinstance(error, dict) else str(error).split(':', 1)[0]
        if op == 'chain' and code == 'NODE_NOT_FOUND': return {'absent':True}
        raise RuntimeError(pose)
    result = {'pose':pose['pose'], 'bones':rig['bones']}
    if op == 'bake':
        clips = await call(client, 'custom_animation_inspect', {'op':'describe', 'player_path':'/RigUI/AnimationPlayer'})
        if clips.get('error'): raise RuntimeError(clips)
        result['clips'] = clips['clips']
    return result

async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id':args.session_hint})
        if args.mode == 'setup':
            folder = args.project_root / 'repair_ui_undo'
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f'rig_{args.op}_{datetime.now(timezone.utc):%Y%m%d_%H%M%S}.tscn'
            text = '[gd_scene format=3]\n[node name="RigUI" type="Node"]\n'
            if args.op in ('pose3d', 'bake'):
                text += '''[node name="Skeleton" type="Skeleton3D" parent="."]
bones/0/name = "arm_L"
bones/0/parent = -1
bones/0/rest = Transform3D(0.9800666, 0.1986693, 0, -0.1986693, 0.9800666, 0, 0, 0, 1, 1, 2, 0)
bones/0/enabled = true
bones/0/position = Vector3(1.1, 2.2, 0)
bones/0/rotation = Quaternion(0, 0, 0.247404, 0.9689124)
bones/0/scale = Vector3(1.2, 0.8, 1.1)
'''
            elif args.op == 'pose2d':
                text += '''[node name="Skeleton" type="Skeleton2D" parent="."]
[node name="arm_L" type="Bone2D" parent="Skeleton"]
position = Vector2(1.1, 2.2)
rotation = 0.5
scale = Vector2(1.2, 0.8)
rest = Transform2D(0.9800666, 0.1986693, -0.1986693, 0.9800666, 1, 2)
auto_calculate_length_and_angle = false
length = 10.0
'''
            if args.op == 'bake':
                text += '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\ncallback_mode_process = 2\n'
            target.write_text(text, encoding='utf-8')
            scene = 'res://repair_ui_undo/' + target.name
            opened = await call(client, 'scene_open', {'path':scene})
            if args.op == 'bake':
                source = await invoke(client, {'op':'pose_to_clip', 'skeleton_path':'/RigUI/Skeleton',
                    'player_path':'/RigUI/AnimationPlayer', 'animation_name':'input', 'keys':[
                        {'time':0.0, 'pose':{'bones':{'arm_L':{}}}},
                        {'time':1.0, 'pose':{'bones':{'arm_L':{'rotation':{'kind':'quaternion','z':0.2955202,'w':0.9553365}}}}},
                    ]})
                if source.get('error'): raise RuntimeError(source)
            baseline = await snapshot(client, args.op)
            if args.op == 'chain':
                params = {'op':'rig_chain', 'skeleton_path':'/RigUI/Generated', 'bones':[{'name':'root'}, {'name':'tip', 'parent':'root', 'position':[0,1,0]}]}
            elif args.op == 'bake':
                params = {'op':'bake_pose_sequence', 'skeleton_path':'/RigUI/Skeleton', 'player_path':'/RigUI/AnimationPlayer',
                    'source_animation':'input', 'animation_name':'generated', 'duration':0.5, 'fps':4}
            else:
                params = {'op':'pose_apply', 'skeleton_path':'/RigUI/Skeleton', 'reset_first':True,
                    'blend':0.5, 'pose':{'bones':{'arm_L':{'rotation':{'kind':'quaternion','z':0.2955202,'w':0.9553365},
                    'position':{'kind':'vector3','x':0.4,'y':-0.3}, 'scale':{'kind':'vector3','x':1.6,'y':0.6,'z':1.3}}}}}
            made = await invoke(client, params)
            generated = await snapshot(client, args.op)
            args.record.write_text(json.dumps({'op':args.op, 'scene':scene, 'made':made, 'baseline':baseline, 'generated':generated}, indent=2), encoding='utf-8')
            result = {'passed':not opened.get('error') and not made.get('error') and not equivalent(baseline, generated), 'scene':scene, 'op':args.op}
        else:
            record = json.loads(args.record.read_text(encoding='utf-8'))
            actual = await snapshot(client, record['op'])
            result = {'passed':equivalent(actual, record[args.expect]), 'expected':args.expect, 'actual':actual, 'scene':record['scene']}
    print('MCP_RIG_UI_HISTORY=' + json.dumps(result, sort_keys=True))
    return 0 if result['passed'] else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--mode', choices=('setup','inspect'), required=True)
    parser.add_argument('--op', choices=('pose3d','pose2d','chain','bake'), default='pose3d')
    parser.add_argument('--expect', choices=('baseline','generated'), default='generated')
    parser.add_argument('--record', type=Path, required=True)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
