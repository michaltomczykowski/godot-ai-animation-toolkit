"""Join only existing native FX history counter runs to exact public saved rows."""
import json
import re
from pathlib import PurePosixPath

MODES=('new','overwrite','missing_library','instanced')
CHECKER='test_project/tools/check_fx_runtime.gd'
DRIVER='tools/mcp_fx_history.py'
ADAPTER='tools/operation_fx_counter_native_checks.py'

def is_event(event):
    return (event.get('driver')=='mcp_fx_history.py' and event.get('operation')=='animation_fx.counter'
        and event.get('scene') in {f'user://fx_history_counter_{m}_redo.tscn' for m in MODES})

def verify_native(history,context,support,public_end):
    row=history['row'];mode=row.get('mode');scene=f'user://fx_history_counter_{mode}_redo.tscn'
    if mode not in MODES or row.get('persist_redo',{}).get('path')!=scene:raise ValueError('counter saved history path differs')
    matches=[e for e in support if is_event(e) and e.get('scene')==scene]
    if not matches:return {'checks':{'valid_effect':'pending','playback':'pending'},'reason':'Editor method tracks are suppressed by AnimationMixer editor_hint; matching native counter evidence absent.'}
    if len(matches)!=1:raise ValueError('counter native evidence must be unique per exact saved history row')
    event=matches[0]
    if any(p not in context.get('dependencies',{}) for p in (CHECKER,DRIVER,ADAPTER)):raise ValueError('counter native source dependencies absent')
    if not isinstance(history.get('context_sha256'),str) or not re.fullmatch('[0-9a-f]{64}',history['context_sha256']) or not history.get('run_id'):raise ValueError('counter history context identity absent')
    if event.get('kind')!='native_saved_output' or event.get('route')!='native_godot' or event.get('context_sha256')!=history.get('context_sha256') or event.get('run_id')!=history.get('run_id'):raise ValueError('counter native context/route differs')
    if not public_end.get('execution_ns',0)<event.get('execution_ns',0) or not public_end.get('time_ns',0)<event.get('time_ns',0):raise ValueError('counter native ran before public history completed')
    command=event.get('command',[])
    if (len(command)!=11 or command[0]!=context.get('engine_command') or command[1:3]!=['--headless','--path']
        or PurePosixPath(str(command[3]).replace('\\','/')).name!='test_project'
        or command[4:]!=['--script','res://tools/check_fx_runtime.gd','--',scene,'counter','generated','FxHistory']):raise ValueError('counter native command differs from existing source wrapper')
    if type(event.get('returncode')) is not int or event.get('returncode')!=0 or not isinstance(event.get('stdout'),str) or not isinstance(event.get('stderr'),str):return {'checks':{'valid_effect':'fail','playback':'fail'},'reason':'Actual counter native process failed.'}
    if any(s in event['stdout']+event['stderr'] for s in ('ERROR:','SCRIPT ERROR:')):return {'checks':{'valid_effect':'fail','playback':'fail'},'reason':'Actual counter native engine error.'}
    lines=[line[len('FX_RUNTIME='):] for line in event['stdout'].splitlines() if line.startswith('FX_RUNTIME=')]
    if len(lines)!=1:raise ValueError('counter native lacks unique actual FX_RUNTIME result')
    report=json.loads(lines[0])
    if not isinstance(report,dict):raise ValueError('counter native report is not an object')
    obs=report.get('counter_observation',{})
    expected={'schema':'fx_counter_native_v1','scene_sha256':row['persist_redo'].get('sha256'),'checker_sha256':context['dependencies'][CHECKER].get('sha256'),
        'clip':'generated','player_path':'AnimationPlayer','assigned_animation':'generated','method_callback_immediate':True,'manual_clock':True,'advance_seconds':.50001,'editor_hint':False,'inside_tree':True,
        'target_path':'ScoreLabel','target_class':'Label','text':'50','method_track_type':5,'method_track_enabled':True,'method_track_path':'ScoreLabel','method_track_key_count':31}
    valid=(report.get('op')=='counter' and report.get('scene')==scene and report.get('failures')==[]
        and report.get('checks')==[{'method_target':'ScoreLabel','text':'50'}]
        and isinstance(obs,dict) and obs.keys()==expected.keys()
        and all(type(obs.get(k)) is type(v) and obs[k]==v for k,v in expected.items())
        and isinstance(expected['scene_sha256'],str) and re.fullmatch('[0-9a-f]{64}',expected['scene_sha256'])
        and isinstance(expected['checker_sha256'],str) and re.fullmatch('[0-9a-f]{64}',expected['checker_sha256']))
    return {'checks':{'valid_effect':'pass' if valid else 'fail','playback':'pass' if valid else 'fail'},
        'reason':'Exact saved counter native method playback only; no visual/audible approval.', 'native_case_id':event['id']}
