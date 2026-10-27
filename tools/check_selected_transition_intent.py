"""Root-owned native replay of one fixed transition and accepted saved references."""
import argparse,hashlib,json,os,subprocess,time
from pathlib import Path
from operation_transition_intent_checks import request,REFERENCES,SCRIPT,need
from operation_case_collector import record_native_result,record_snapshot_result

def run(a):
 context=json.loads(Path(os.environ['TOOLKIT_OPERATION_CONTEXT']).read_text())
 raw=a.route.read_bytes();route=json.loads(raw.decode('utf-8-sig'));op=route.get('operation');expected=request(op)
 need(route.get('passed')is True and route.get('case_selection')=='dummy'and len(route.get('cases',[]))==1,'requires completed selected public transition')
 case=route['cases'][0];need(case.get('params')==expected and route.get('source_head')==context.get('tested_source')and str(a.godot)==context.get('engine_command'),'transition source/request/engine differs')
 references={}
 for kind,path in [('walk',a.walk_reference),('idle',a.idle_reference)]:
  data=path.read_bytes();manifest=json.loads(data.decode('utf-8-sig'));rows=[v for v in manifest.get('cases',[])if v.get('id')=='dummy']
  need(manifest.get('source_head')=='9188ffa22e756213ae48e88d359b5918c0b2c384'and manifest.get('passed')is True and len(rows)==1 and (rows[0].get('scene'),rows[0].get('scene_sha256'))==REFERENCES[kind],'accepted reference admission failed')
  scene=a.project_root/REFERENCES[kind][0].removeprefix('res://');need(scene.is_file()and hashlib.sha256(scene.read_bytes()).hexdigest()==REFERENCES[kind][1],'accepted reference scene bytes differ')
  references[kind]={'bytes_hex':data.hex(),'sha256':hashlib.sha256(data).hexdigest()}
 a.output.mkdir(exist_ok=False);report=a.output/'native.json'
 command=[str(a.godot),'--headless','--path',str(a.project_root),'--script','res://tools/'+SCRIPT,'--',str(a.route),str(a.route),str(a.walk_reference),str(a.idle_reference),str(report),'case_id=dummy']
 receipt=a.output/'execution.json';state={'stage':'launching','command':command,'source':context['tested_source']}
 def save():
  temp=receipt.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2));os.replace(temp,receipt)
 save();started=time.monotonic();log=a.output/'native.log'
 with log.open('xb')as stream:
  child=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT);state.update(stage='running',pid=child.pid);save()
  try:state['returncode']=child.wait(timeout=120)
  except subprocess.TimeoutExpired:child.kill();child.wait(timeout=10);state.update(returncode=child.returncode,timed_out=True)
 state.update(stage='complete',seconds=time.monotonic()-started,log_sha256=hashlib.sha256(log.read_bytes()).hexdigest());save()
 result=subprocess.CompletedProcess(command,state['returncode'],log.read_text(encoding='utf-8'),"")
 native=record_native_result('animation_motion.'+op,case['scene'],command,result)
 if report.exists():
  data=report.read_bytes();record_snapshot_result('transition_physical_v1',dict(operation='animation_motion.'+op,scene=case['scene'],native_case_id=native,command=command,project_root=str(a.project_root),route_path=str(a.route),walk_route_path=str(a.walk_reference),idle_route_path=str(a.idle_reference),report_path=str(report),route_bytes_hex=raw.hex(),route_sha256=hashlib.sha256(raw).hexdigest(),report_bytes_hex=data.hex(),report_sha256=hashlib.sha256(data).hexdigest(),reference_routes=references))
 need(result.returncode==0 and report.exists(),'transition native failed; original receipts preserved')
 return 0

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('godot','project-root','route','walk-reference','idle-reference','output'):p.add_argument('--'+name,required=True,type=Path)
 raise SystemExit(run(p.parse_args()))
