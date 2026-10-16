"""Create an immutable saved-setup recording schedule; never invoke Godot."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(route, condition, seconds=3.0):
    if condition not in ('half_idle_walk', 'half_walk_run', 'jump'):
        raise ValueError('Unsupported scoped condition')
    if not math.isfinite(seconds) or seconds < 3 or seconds*60 != int(seconds*60):
        raise ValueError('Require at least three seconds and whole 60FPS frames')
    result=copy.deepcopy(route)
    if len(result.get('cases',[]))!=4 or len({r['id'] for r in result['cases']})!=4:
        raise ValueError('Require exactly four distinct saved public rigs')
    for row in result['cases']:
        meta=row.get('write',{})
        for _ in range(4):
            if 'clips' in meta: break
            meta=next((meta[k] for k in ('data','result','response') if isinstance(meta.get(k),dict)),{})
        if not isinstance(row.get('scene'),str) or not row['scene'].startswith('res://'):
            raise ValueError('Require saved scene resource path')
        if not isinstance(row.get('scene_sha256'),str) or len(row['scene_sha256'])!=64 or any(c not in '0123456789abcdef' for c in row['scene_sha256']):
            raise ValueError('Require exact saved scene SHA256')
        values=meta['speed_values']
        if any(type(values.get(k)) not in (int,float) or not math.isfinite(values[k]) or values[k]<=0 for k in ('walk','run')) or values['run']<=values['walk']:
            raise ValueError('Require finite ordered saved speeds')
        lengths=[meta['clips'][clip].get('length') for clip in ('idle','walk','run')]
        if any(type(v) not in (int,float) or not math.isfinite(v) or v<=0 for v in lengths):
            raise ValueError('Require actual finite positive saved clip lengths')
        speed=float(values['walk'])/2 if condition=='half_idle_walk' else (float(values['walk'])+float(values['run']))/2 if condition=='half_walk_run' else 0.0
        required=max(float(meta['clips'][clip].get('length',0)) for clip in ('idle','walk','run'))
        if seconds < required: raise ValueError('Take must cover each relevant saved cycle')
        if condition=='jump':
            jump=meta['clips']['jump']
            if float(jump.get('length',1.201))+.25+.2+.5>seconds: raise ValueError('Take truncates jump/fade/recovery')
        row['render_spec']={'condition':condition,'speed_mps':speed,'frames_per_take':int(seconds*60),'takes':2,
                            'controller_speed_mps':0.0 if meta['root_motion'] else speed,
                            'jump_fire_at_frame':15 if condition=='jump' else -1}
    result['recording']={'contract':'saved_setup_v1','fps':60,'size':[1920,1080], 'condition':condition,
                         'fresh_scene_per_take':True,'camera':'fixed_front_side','planner_sha256':sha(Path(__file__))}
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--route',type=Path,required=True)
    p.add_argument('--condition',choices=('half_idle_walk','half_walk_run','jump'),required=True)
    p.add_argument('--seconds',type=float,default=3.0)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    result=build(json.loads(a.route.read_text(encoding='utf-8-sig')),a.condition,a.seconds)
    result['recording']['route_sha256']=sha(a.route)
    with a.output.open('x',encoding='utf-8') as f: json.dump(result,f,indent=2)

if __name__=='__main__': main()
