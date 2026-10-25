"""Summarize actual spring startup/cache controls without granting approval."""
import argparse,json,hashlib
from pathlib import Path
from check_saved_bake_capture import require,pose_error,LIMITS
IDS=('modifier_spring_1_60','modifier_ordered_spring_look_1_60')
STRATEGIES=('direct-warm','direct-tight','sandbox-tight')
def summarize(report,manifest_sha):
 require(report.get('kind')=='saved_bake_spring_cache_causal_diagnostic'and report.get('manifest_sha256')==manifest_sha,'diagnostic identity mismatch');require(report.get('passed')is True and report.get('failures')==[]and report.get('engine_errors')==[],'diagnostic engine/observation failure')
 expected={(strategy,key,side,take)for strategy in STRATEGIES for key in IDS for side in ('source','redo')for take in (0,1)};index={}
 for row in report.get('runs',[]):
  identity=(row.get('strategy'),row.get('id'),row.get('side'),row.get('take'));require(identity in expected and identity not in index,'foreign/duplicate diagnostic cell');index[identity]=row
 require(set(index)==expected,'incomplete24cell diagnostic');pairs=[]
 for strategy in STRATEGIES:
  for key in IDS:
   for take in (0,1):
    source=index[strategy,key,'source',take];baked=index[strategy,key,'redo',take];a=source['trace'];b=baked['trace'];require(a and len(a)==len(b),'missing source/output trace');worst={c:0. for c in LIMITS};bad=[]
    for i,(u,v)in enumerate(zip(a,b)):
     require(u['time']==v['time'],'source/output time mismatch');require(len(u['selected_pose'])==len(v['selected_pose'])and u['selected_pose'],'missing final poses')
     errors=[pose_error(x,y)for x,y in zip(u['selected_pose'],v['selected_pose'])]+[pose_error(u['body'],v['body'])]
     for error in errors:
      for channel,value in error.items():worst[channel]=max(worst[channel],value)
     if any(e[c]>LIMITS[c]for e in errors for c in LIMITS):bad.append(i)
    pairs.append({'strategy':strategy,'id':key,'take':take,'worst':worst,'outside_original_limits_samples':bad,'parity_pass':not bad,'loaded_source_spring_cache':source['loaded_spring_cache'],'first_sample_source_spring_cache':a[0]['spring_cache'],'last_sample_source_spring_cache':a[-1]['spring_cache']})
 return {'kind':'spring_startup_causal_summary','diagnostic_only':True,'limits':LIMITS,'pairs':pairs,'scope':'Observed saved-source versus baked-output startup comparison. No schedule choice, product fix or media approval inferred.'}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 if a.output.exists():raise ValueError('preserve previous summary')
 r=summarize(json.loads(a.report.read_text()),hashlib.sha256(a.manifest.read_bytes()).hexdigest());a.output.write_text(json.dumps(r,indent=2));print(json.dumps({'pairs':len(r['pairs']),'parity_pass_pairs':sum(v['parity_pass']for v in r['pairs']),'diagnostic_only':True}))
