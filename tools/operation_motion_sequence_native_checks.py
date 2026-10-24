"""Join one completed native batch to exact public history case hashes.
Motion duplicate references prove playback/path types only, not intended motion.
"""
import json
import math
import re
import struct
from functools import lru_cache
from bisect import bisect_left
from operation_motion_sequence_history_checks import (verify_event as history_verify, digest, exact, finite_tree, MOTIONS, SEQUENCES)
DEPENDENCIES=('test_project/tools/check_motion_sequence_history.gd','test_project/tools/motion_sequence_native_reference.gd','test_project/tools/motion_sequence_native_evidence.gd','tools/operation_motion_sequence_native_checks.py','tools/mcp_motion_sequence_history.py')
THRESHOLDS=dict(position=.0001,rotation=.001,scale=.0001,root_delta=.0001)

def real32(value):
    """Godot's standard build stores each Vector3/Quaternion operation as real_t."""
    return struct.unpack('f',struct.pack('f',value))[0]

def error(a,b):
    if not isinstance(a,list) or not isinstance(b,list) or len(a)!=len(b) or len(a) not in (3,4) or not finite_tree([a,b]) or any(type(x) not in (int,float) for x in a+b):raise ValueError('invalid raw native metric values')
    if len(a)==4 and any(abs(sum(x*x for x in q)-1)>1e-5 for q in (a,b)):raise ValueError('unnormalized native quaternion')
    # Match the observed standard Godot build's real_t intermediates, including
    # expression order. Python doubles give a different witness error; the
    # unchanged native bounds and strict reported-error comparison still apply.
    add=lambda x,y:real32(x+y)
    sub=lambda x,y:real32(x-y)
    mul=lambda x,y:real32(x*y)
    a,b=([real32(x) for x in values] for values in (a,b))
    def length(v):return real32(math.sqrt(add(add(mul(v[0],v[0]),mul(v[1],v[1])),mul(v[2],v[2]))))
    if len(a)==3:return length([sub(x,y) for x,y in zip(a,b)])
    x,y,z,w=(-a[0],-a[1],-a[2],a[3]);u,v,t,s=b
    q=(sub(add(add(mul(w,u),mul(x,s)),mul(y,t)),mul(z,v)),
       sub(add(add(mul(w,v),mul(y,s)),mul(z,u)),mul(x,t)),
       sub(add(add(mul(w,t),mul(z,s)),mul(x,v)),mul(y,u)),
       sub(sub(sub(mul(w,s),mul(x,u)),mul(y,v)),mul(z,t)))
    return 2*math.atan2(length(q),abs(q[3]))

def metric(m,limit,rotation=False):
    if not isinstance(m,dict) or type(m.get('error')) not in (int,float) or not finite_tree(m):return False
    if not isinstance(m.get('actual'),list) or len(m['actual'])!=(4 if rotation else 3):return False
    actual=error(m['actual'],m.get('reference'))
    return abs(actual-m['error'])<=1e-12 and actual<=limit and type(m.get('time')) in (int,float) and m['time']>=0

def tracks(rows,length):
    if not isinstance(rows,list) or not rows:return False
    for t in rows:
        if t.get('type') not in (1,2,3) or type(t.get('type')) is not int or t.get('enabled') is not True or t.get('target_class') not in ('Node3D','Skeleton3D') or not isinstance(t.get('path'),str) or not t['path'] or t.get('finite_values') is not True or t.get('normalized') is not True:return False
        if t['target_class']=='Skeleton3D' and (t.get('subnames')!=1 or not isinstance(t.get('bone'),str) or not t['bone'] or type(t.get('bone_index')) is not int or t['bone_index']<0):return False
        times=t.get('times')
        if not isinstance(times,list) or len(times)<2 or not finite_tree(times) or any(type(x) not in (int,float) for x in times) or any(not 0<=x<=length+.000001 for x in times) or any(b<=a for a,b in zip(times,times[1:])):return False
    return True

def derive(public,native):
    if native.get('id')!=public['case_id'] or any(native.get(k)!=public[k] for k in ('group','variant','mode','fps')) or not exact(native.get('params'),public['request']):raise ValueError('native/public case mismatch')
    if native.get('thresholds')!=THRESHOLDS:raise ValueError('native thresholds changed')
    for key in ('source','reference'):
        prefix='source_scene' if key=='source' else 'reference'
        f=native.get(key,{})
        if f.get('path')!=public.get(prefix+'_path') or not digest(f.get('sha256')) or f['sha256']!=public.get(prefix+'_sha256') or type(f.get('bytes')) is not int or f['bytes']<=0:raise ValueError('missing/wrong native '+key+' binding')
    if native['source']['bytes']!=public.get('source_scene_bytes'):raise ValueError('source scene byte length differs')
    for state in ('do','undo','redo'):
        f=native.get('states',{}).get(state,{});p=public['persist_'+state]
        if f.get('path')!=p['path'] or not digest(f.get('sha256')) or f['sha256']!=p['sha256'] or f.get('bytes')!=p['bytes']:raise ValueError('wrong saved native state binding')
    clean=finite_tree(native) and type(native.get('failure_count')) is int and native['failure_count']==0 and type(native.get('engine_errors')) is list and native['engine_errors']==[]
    plays=native.get('plays',[])
    if len(plays)!=9 or {(p.get('state'),p.get('fps')) for p in plays}!={(s,f) for s in ('do','undo','redo') for f in (30,60,120)}:raise ValueError('missing/duplicate native state/FPS cell')
    paths=clean;played=clean;noninert=False;required_travel=set()
    for p in plays:
        length=p.get('length');times=p.get('times',[])
        if type(length) not in (int,float) or length<=0:raise ValueError('invalid native length')
        a=p.get('actual_tracks');b=p.get('reference_tracks')
        good=tracks(a,length) and tracks(b,length) and len(a)==len(b) and all(x['path']==y['path'] and x['type']==y['type'] for x,y in zip(a,b))
        paths=paths and good
        schedule=isinstance(times,list) and len(times)>2 and finite_tree(times) and times[0]==0 and times[-1]==length and all(y>x for x,y in zip(times,times[1:]))
        # Existing schedule contains exact FPS ticks plus every output key/midpoint.
        if schedule:
            expected=[k/p['fps'] for k in range(1,math.ceil(length*p['fps']))]+[0.,length]
            if good:
                for t in a:
                    expected+=t['times']+[(x+y)/2 for x,y in zip(t['times'],t['times'][1:])]
            def present(x):
                i=bisect_left(times,x)
                return any(abs(x-times[j])<=1e-14*max(1.,abs(x)) for j in (i-1,i) if 0<=j<len(times))
            schedule=all(present(x) for x in expected)
        if p['state']!='undo' and p.get('loop_mode')==0 and good and any(t['type']==1 and t['path']==p.get('root_motion_track') for t in a):required_travel.add((p['state'],p['fps']))
        metrics=p.get('errors',{})
        fields={('position' if t['type']==1 else 'rotation' if t['type']==2 else 'scale') for t in a} if good else set()
        count=len(times)*len(a) if good else -1
        played=played and good and schedule and p.get('clock')=='native_manual_advance' and p.get('pose_samples')==count and type(p.get('key_samples')) is int and p['key_samples']>0 and type(p.get('intermediate_samples')) is int and p['intermediate_samples']>0 and p['key_samples']+p['intermediate_samples']==count and set(metrics)==fields|{'root_delta'} and all(metric(metrics[f],THRESHOLDS[f],f=='rotation') for f in fields|{'root_delta'})
        for field,m in metrics.items():
            allowed={t['path'] for t in a if ('position' if t['type']==1 else 'rotation' if t['type']==2 else 'scale')==field} if good else set()
            played=played and m.get('time') in times and (m.get('path')=='' if field=='root_delta' else m.get('path') in allowed)
        if p['state']!='undo':
            for field,m in p.get('reference_span',{}).items():
                if field in fields and metric(m,float('inf'),field=='rotation') and m['error']>2*THRESHOLDS[field]:noninert=True
    travel=native.get('travel',[])
    played=played and isinstance(travel,list) and len(travel)==len(required_travel) and {(t.get('state'),t.get('fps')) for t in travel}==required_travel
    for t in travel:
        played=played and t.get('state') in ('do','redo') and t.get('fps') in (30,60,120) and error(t.get('actual'),t.get('reference'))<=.0001 and error(t.get('origin_before'),t.get('origin_after'))<=1e-5
    checks={'track_paths_types':'pass' if paths else 'fail','playback':'pass' if played else 'fail'}
    if public['group'] in ('sequence','secondary'):checks['valid_effect']='pass' if played and noninert else 'fail'
    return checks

@lru_cache(maxsize=1)
def parsed_report(stdout):
    prefix='MOTION_SEQUENCE_HISTORY_RUNTIME='
    lines=[x[len(prefix):] for x in stdout.splitlines() if x.startswith(prefix)]
    if len(lines)!=1:raise ValueError('missing unique completed native report')
    return json.loads(lines[0])

def native_proof(event,context,public):
    for path in DEPENDENCIES:
        d=context.get('dependencies',{}).get(path,{})
        if not digest(d.get('sha256')) or not isinstance(d.get('git_blob'),str) or re.fullmatch('[0-9a-f]{40}',d['git_blob']) is None:raise ValueError('unbound native dependency')
    if event.get('run_id')!=context.get('run_id') or not digest(event.get('context_sha256')) or event.get('driver')!='mcp_motion_sequence_history.py' or event.get('route')!='native_godot' or event.get('kind')!='native_saved_output' or event.get('scene')!='user://motion_sequence_saved_matrix.json' or event.get('operation')!='animation_sequence.compose':raise ValueError('wrong native batch source')
    command=event.get('command',[])
    if len(command)!=6 or command[0]!=context.get('engine_command') or command[1:3]!=['--headless','--path'] or not isinstance(command[3],str) or not command[3] or command[4:]!=['--script','res://tools/check_motion_sequence_history.gd']:raise ValueError('wrong native batch command')
    report=parsed_report(event.get('stdout',''))
    if report.get('evidence_schema')!='motion_sequence_native_v1' or not digest(report.get('manifest_sha256')):raise ValueError('missing native manifest identity')
    for path in DEPENDENCIES[:3]:
        if report.get('native_dependencies',{}).get(path)!=context['dependencies'][path]['sha256']:raise ValueError('actual native script bytes differ from context')
    rows=report.get('native_cases',[])
    required={f'{g}_{v}_{m}_{fps}' for g,variants,modes in (('motion',MOTIONS,('local','instanced','editable','missing_library','overwrite')),('secondary',('single','branches'),('local','instanced','editable')),('sequence',SEQUENCES,('local','instanced','editable','missing_library','overwrite'))) for v in variants for m in modes for fps in (30,60,120)}
    if len(rows)!=273 or {r.get('id') for r in rows}!=required:raise ValueError('native case manifest incomplete/duplicate')
    matches=[r for r in rows if r.get('id')==public['case_id']]
    if len(matches)!=1:raise ValueError('native case not uniquely present')
    checks=derive(public,matches[0])
    if type(event.get('returncode')) is not int or event['returncode']!=0 or 'ERROR:' in event.get('stdout','')+event.get('stderr','') or type(report.get('engine_errors')) is not list or report['engine_errors']!=[] or type(report.get('failures')) is not list or report['failures']!=[]:checks={k:'fail' for k in checks}
    return checks

def verify_event(event,context,begins,support):
    proof=history_verify(event,context,begins,support)
    ends=[x for x in support if x.get('id')==proof['public_test_run_case_id']]
    batches=[x for x in support if x.get('kind')=='native_saved_output' and (x.get('scene')=='user://motion_sequence_saved_matrix.json' or 'res://tools/check_motion_sequence_history.gd' in x.get('command',[])) and x.get('execution_ns',0)>ends[0]['execution_ns']]
    if len(batches)>1:raise ValueError('ambiguous native history batch')
    if batches:
        if batches[0].get('context_sha256')!=event.get('context_sha256'):raise ValueError('native/public context differs')
        checks=native_proof(batches[0],context,event['row'])
        if any(x=='fail' for x in proof['checks'].values()):checks={k:'fail' for k in checks}
        proof['checks'].update(checks)
    proof['limits']+=' Optional exact saved-state native linkage: motion playback/path/type only (duplicate output oracle); sequence/secondary sampled source/rest-reference effect. No continuous physical/artistic claim.'
    return proof
