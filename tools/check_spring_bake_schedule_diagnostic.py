"""Compare raw native Spring schedules. Measurements, never parity approval."""
import argparse,json,hashlib,itertools,math
from pathlib import Path
from check_saved_bake_capture import require,pose_error,LIMITS
STRATEGIES=('sampler-private-tight','unprimed-private-tight','tight-inherited','tight-disabled','paced-after-inherited','original-before-inherited','original-before-disabled')
def identity(r):return r['axis'],r['individual'],r['animated'],r['fps']
def pose(v):return {'p':v['position'],'q':v['rotation'],'s':v['scale']}
def solve_changes(before,after):return {k:after.get(k,0)-before.get(k,0)for k in ('raw','final','skin')}
def summarize(report):
 require(report.get('kind')=='spring_bake_raw_schedule_diagnostic'and report.get('passed_observations')is True and report.get('failures')==[]and report.get('engine_errors')==[],'raw observation failure')
 selection=report.get('case_selection','full');require(selection in ('full','individual60'),'unknown diagnostic selection')
 cases=((4,True,False,60),)if selection=='individual60'else tuple((axis,individual,animated,fps)for axis,individual,animated in ((3,False,False),(4,True,False),(3,False,True))for fps in (30,60,120))
 expected={(*case,strategy)for case in cases for strategy in STRATEGIES};index={}
 for r in report['runs']:
  key=(*identity(r),r['strategy']);require(key in expected and key not in index,'foreign/duplicate run');index[key]=r
 require(set(index)==expected,'incomplete selected diagnostic');comparisons=[];notifications=[]
 for key,r in index.items():
  trace=r['trace'];require(len(trace)==math.ceil(.2*r['fps'])+1,'missing tick');require(all(abs(x['time']-min(i/r['fps'],.2))<1e-12 for i,x in enumerate(trace)),'changed manual clock')
  changes=[]
  for x in trace:
   if 'after_wait'in x:
    delta=solve_changes(x.get('after_player',{}),x['after_wait'])
    if any(delta.values()):changes.append({'tick':x['tick'],'during_pre_sample_wait':delta})
  notifications.append({'identity':list(key),'reset_wait_changes':solve_changes(r.get('reset_state',{}),r.get('post_reset_wait',{})),'pre_sample_wait_changes':changes,'loaded_cache':r.get('loaded_cache')})
 for case in sorted({identity(r)for r in report['runs']}):
  a=index[*case,'sampler-private-tight']['trace']
  for strategy in STRATEGIES[1:]:
   b=index[*case,strategy]['trace'];worst={c:0. for c in LIMITS};first=None;bad=[]
   for i,(u,v)in enumerate(zip(a,b)):
    require(len(u['final_pose'])==len(v['final_pose'])and u['final_pose'],'missing final bone observations')
    for x,y in zip(u['final_pose'],v['final_pose']):
     errors=pose_error(pose(x),pose(y))
     for c,value in errors.items():worst[c]=max(worst[c],value)
     if any(errors[c]>LIMITS[c]for c in LIMITS):
      bad.append(i)
      if first is None:first={'tick':i,'private':u,'other':v}
   comparisons.append({'case':list(case),'other_strategy':strategy,'worst':worst,'outside_original_limits_ticks':sorted(set(bad)),'first_outside':first})
 return {'kind':'spring_raw_schedule_summary','diagnostic_only':True,'limits':LIMITS,'comparisons':comparisons,'notifications':notifications,'scope':'No product/regression approval. Exact raw observations are retained; compare reset/process notifications before changing the oracle.'}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise ValueError('preserve previous summary')
 r=summarize(json.loads(a.report.read_text()));r['raw_sha256']=hashlib.sha256(a.report.read_bytes()).hexdigest();a.output.write_text(json.dumps(r,indent=2));print(json.dumps({'comparisons':len(r['comparisons']),'diagnostic_only':True}))
