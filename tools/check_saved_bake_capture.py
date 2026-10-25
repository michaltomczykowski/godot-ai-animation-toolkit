"""Independent saved-source/output scheduling comparison; original parity limits."""
import argparse,hashlib,json,math
from pathlib import Path
from prepare_saved_bake_capture import IDS
LIMITS={'position':.0001,'rotation':.001,'scale':.0001}
def require(ok,msg):
 if not ok:raise ValueError(msg)
def finite(v):return isinstance(v,(float,int))and not isinstance(v,bool)and math.isfinite(v)
def vector(v,n):require(isinstance(v,list)and len(v)==n and all(finite(x)for x in v),'nonfinite/missing native vector');return v
def distance(a,b):return math.sqrt(sum((x-y)**2 for x,y in zip(vector(a,3),vector(b,3))))
def pose_error(a,b):
 q=vector(a['q'],4);r=vector(b['q'],4);dot=abs(sum(x*y for x,y in zip(q,r)));den=math.sqrt(sum(x*x for x in q)*sum(x*x for x in r));require(den>0,'zero quaternion')
 return {'position':distance(a['p'],b['p']),'rotation':2*math.acos(min(1.,dot/den)),'scale':distance(a['s'],b['s'])}
def times(params):
 duration=params['duration'];fps=params['fps'];values=[min(i/fps,duration)for i in range(math.ceil(duration*fps)+1)]
 for event in params.get('tree_events',[]):
  if event['time']not in values:values.append(event['time'])
 values.sort();seen=set()
 for event in params.get('tree_events',[]):
  t=event['time']
  if t<=0 or t in seen:continue
  seen.add(t);previous=max(v for v in values if v<t);values.append(t-min(.00004*max(1.,abs(t)),(t-previous)*.5))
 return sorted(values)
def compare(report,manifest,manifest_sha):
 require(report.get('kind')in ('saved_bake_eight_scheduling_diagnostic','saved_bake_eight_native'),'unknown report kind');require(report.get('manifest_sha256')==manifest_sha,'manifest identity mismatch');
 for field,path in [('evaluator_sha256','res://tools/check_saved_bake_capture.gd'),('reference_helper_sha256','res://tools/check_rig_bake_restoration.gd')]:require(report.get(field)==manifest.get('files',{}).get(path,{}).get('sha256')and isinstance(report.get(field),str),'helper identity mismatch')
 require(report.get('failures')==[]and report.get('engine_errors')==[]and report.get('passed')is True,'native engine/observation failure')
 diagnostic=report.get('kind')=='saved_bake_eight_scheduling_diagnostic';ids=IDS[2:4]if diagnostic else IDS;expected={(key,side,take,pace,flush)for key in ids for side in ('source','redo')for take in (0,1)for pace in ((False,True)if diagnostic else (False,))for flush in ((False,True)if diagnostic else (False,))}
 runs=report.get('runs',[]);index={}
 for r in runs:
  key=(r.get('id'),r.get('side'),r.get('take'),r.get('paced'),r.get('flush'));require(key in expected and key not in index,'missing/foreign/duplicate run');require(r.get('failures')==[],'case-local native failure');index[key]=r
 require(set(index)==expected,'incomplete source/output/take/schedule matrix');results=[]
 for key,side,take,pace,flush in sorted(expected):
  if side!='source':continue
  source=index[key,side,take,pace,flush];baked=index[key,'redo',take,pace,flush];a=source.get('trace',[]);b=baked.get('trace',[])
  row=next(v for v in manifest['cases']if v['id']==key);duration=row['params']['duration'];expected_times=times(row['params']);require(a and len(a)==len(b)==len(expected_times),'missing native time samples');require(all(abs(v['time']-t)<1e-12 for v,t in zip(a,expected_times)),'wrong native sample schedule');require(a[0]['time']==0 and abs(a[-1]['time']-duration)<1e-12,'authored span missing')
  worst={k:0. for k in LIMITS};bad=[]
  for i,(u,v)in enumerate(zip(a,b)):
   require(finite(u['time'])and u['time']==v['time']and(i==0 or u['time']>a[i-1]['time']),'native schedule changed')
   require(len(u.get('selected_pose',[]))==len(v.get('selected_pose',[]))and u['selected_pose'],'missing selected final skeleton')
   for sample in (u,v):
    require(isinstance(sample.get('required'),dict)and sample['required'],'required rig witnesses missing')
    require(row['skeleton']in sample['required'],'selected rig final witness missing')
    if key=='modifier_retarget_1_60':require(row['modifiers'][0]['path'].rsplit('/',1)[0]in sample['required'],'retarget source rig witness missing')
    for witness in sample['required'].values():require(isinstance(witness.get('final'),int)and witness['final']==witness.get('final_before',-2)+1 and isinstance(witness.get('skin'),int)and witness['skin']>=witness.get('skin_before',10**9)+1 and witness.get('pose',{}).get('local'),'final/skin freshness missing')
   errors=[pose_error(x,y)for x,y in zip(u['selected_pose'],v['selected_pose'])]+[pose_error(u['body'],v['body'])]
   for error in errors:
    for channel,value in error.items():worst[channel]=max(worst[channel],value)
   if any(e[c]>LIMITS[c]for e in errors for c in LIMITS):bad.append(i)
  results.append({'id':key,'take':take,'paced':pace,'flush':flush,'samples':len(a),'worst':worst,'outside_original_limits_samples':sorted(set(bad)),'parity_pass':not bad})
 freshness=[]
 for key,side,take,pace,flush in sorted(expected):
  if take:continue
  a=index[key,side,0,pace,flush]['trace'];b=index[key,side,1,pace,flush]['trace']
  # Absolute node paths may differ across fresh instances: compare selected final poses/body/time only.
  equal=all({f:u[f]for f in ('time','selected_pose','body')}=={f:v[f]for f in ('time','selected_pose','body')}for u,v in zip(a,b))and len(a)==len(b)
  freshness.append({'id':key,'side':side,'paced':pace,'flush':flush,'fresh_take_exact':equal})
 return {'kind':'saved_bake_schedule_comparison','diagnostic_only':diagnostic,'limits':LIMITS,'pairs':results,'fresh_takes':freshness,'parity_pass':all(x['parity_pass']for x in results),'fresh_take_pass':all(x['fresh_take_exact']for x in freshness),'scope':'Actual selected final skeleton/body key schedule only. No visual/current-operation qualification. Diagnostic variants may honestly fail parity.'}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 if a.output.exists():raise ValueError('preserve prior comparison')
 r=compare(json.loads(a.report.read_text()),json.loads(a.manifest.read_text()),hashlib.sha256(a.manifest.read_bytes()).hexdigest());a.output.write_text(json.dumps(r,indent=2));print(json.dumps({'parity_pass':r['parity_pass'],'fresh_take_pass':r['fresh_take_pass'],'diagnostic_only':r['diagnostic_only']}))
 raise SystemExit(0 if r['diagnostic_only']or(r['parity_pass']and r['fresh_take_pass'])else 1)
