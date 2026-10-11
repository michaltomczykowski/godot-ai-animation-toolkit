"""Prove all saved transition dry calls survive a released core plugin reload."""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import shutil
from uuid import uuid4
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_probe import EXPECTED_CATALOG, EXPECTED_PROMOTED
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    receipt = a.output / 'core-reload.json'; folder = a.project_root / 'repair_transition_reload' / uuid4().hex
    folder.mkdir(parents=True)
    report = {'passed': False, 'phases': [], 'candidate_root': str(a.candidate)}
    def save(): write_json(receipt, report)
    old_session = ''
    for phase in ('before_reload', 'after_reload'):
        async with connected_editor(a, old_session) as (client, connection):
            catalog = await call(client,'custom_manage',{'op':'list'})
            names = {t['name'] for t in catalog.get('tools',[])}
            tools = {t.name for t in await client.list_tools()}
            section = {'phase':phase,'connection':connection,'catalog':catalog,
                'promoted':sorted(tools & EXPECTED_PROMOTED),'rows':[]}
            report['phases'].append(section); save()
            if EXPECTED_CATALOG - names or EXPECTED_PROMOTED - tools: raise RuntimeError('Toolkit family missing after core reload')
            for op in ('walk_start','walk_stop'):
                for style in ('responsive','grounded','relaxed','heavy','sneaky'):
                    for mode in ('extracted','in_place'):
                        label = style if mode == 'extracted' else style+'-in-place'
                        route_path = a.candidate/op/label/'route.json'; route = json.loads(route_path.read_text())
                        assert route['passed'] and route['invocation_kind'] == 'ordinary call'
                        for source_row in route['cases']:
                            original = a.project_root/source_row['scene'].removeprefix('res://')
                            assert digest(original) == source_row['scene_sha256']
                            target = folder/f'{phase}-{op}-{label}-{source_row["id"]}.tscn'
                            shutil.copyfile(original,target)
                            scene = 'res://'+target.relative_to(a.project_root).as_posix()
                            params = {**source_row['params'],'overwrite':True,'dry_run':True}
                            opened = await call(client,'scene_open',{'path':scene,'force_reload':True})
                            normalized = await call(client,'scene_save',{})
                            before_hash = digest(target)
                            before = await inspect(client,params['animation_name'],params['player_path'])
                            pose_params = {'op':'pose_save','skeleton_path':params['skeleton_path']}
                            pose_before = await call(client,'custom_animation_rig',pose_params)
                            dry = await call(client,'custom_manage',{'op':'invoke','params':{'tool_name':'animation_motion','params':params}})
                            pose_after = await call(client,'custom_animation_rig',pose_params)
                            after = await inspect(client,params['animation_name'],params['player_path'])
                            saved = await call(client,'scene_save',{})
                            after_hash = digest(target)
                            passed = (before == after == source_row['persisted'] and pose_before == pose_after
                                and before_hash == after_hash and dry.get('dry_run') is True
                                and not any(v.get('error') for v in (opened,normalized,pose_before,pose_after,saved,dry)))
                            section['rows'].append({'operation':op,'style':style,'root_mode':mode,'id':source_row['id'],
                                'scene':scene,'source_scene_sha256':source_row['scene_sha256'], 'before_sha256':before_hash,
                                'after_sha256':after_hash,'pose_unchanged':pose_before==pose_after,'dry':dry,'passed':passed})
                            save()
            print(f'{phase}: {sum(r["passed"] for r in section["rows"])}/80 complete saved transition dry calls',flush=True)
            if phase == 'before_reload':
                old_session = connection['session_id']; report['reload'] = await call(client,'editor_reload_plugin',{});save()
    report['passed'] = (not report['reload'].get('error') and len(report['phases']) == 2
        and report['phases'][0]['connection']['session_id'] != report['phases'][1]['connection']['session_id']
        and all(len(p['rows'])==80 and all(r['passed'] for r in p['rows']) for p in report['phases']))
    save(); return int(not report['passed'])

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('core-root','project-root','candidate','output'): p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--port',type=int,default=8000);p.add_argument('--ws-port',type=int,default=9500)
    raise SystemExit(asyncio.run(run(p.parse_args())))
