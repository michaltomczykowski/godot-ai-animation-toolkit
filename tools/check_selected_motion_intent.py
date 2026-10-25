"""Replay one existing selected idle/turn route; root owns engine scheduling."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
from operation_idle_turn_intent_checks import SCRIPTS,fixed_request,need
from operation_case_collector import record_native_result,record_snapshot_result


def command_for(godot,project,route,report,operation):
 return [str(godot),'--headless','--path',str(project),'--script','res://tools/'+SCRIPTS[operation],'--',str(route),str(report)]+(['candidate']if operation=='idle_cycle'else[])+['case_id=dummy']


def run(args):
 need(bool(os.environ.get('TOOLKIT_OPERATION_CONTEXT'))and bool(os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')),'exact source trace context required before native launch')
 route_bytes=args.route.read_bytes();route=json.loads(route_bytes.decode('utf-8-sig'));op=route.get('operation');need(op in SCRIPTS,'only idle/turn supported')
 need(route.get('case_selection')=='dummy'and len(route.get('cases',[]))==1 and route.get('passed')is True,'requires completed explicit dummy public route')
 context=json.loads(Path(os.environ['TOOLKIT_OPERATION_CONTEXT']).read_text(encoding='utf-8'))
 need(route.get('source_head')==context.get('tested_source')and str(args.godot)==context.get('engine_command'),'public route/context/engine identity differs before replay')
 case=route['cases'][0];need(case.get('params')==fixed_request(op)and case.get('id')=='dummy','requires exact ordinary public request')
 if args.output.exists():raise FileExistsError('preserve prior native attempt output')
 args.output.mkdir(parents=True);report=args.output/'native.json';command=command_for(args.godot,args.project_root,args.route,report,op)
 try:result=subprocess.run(command,capture_output=True,text=True,timeout=90,check=False)
 except subprocess.TimeoutExpired as exc:
  for name,value in [('stdout',exc.stdout),('stderr',exc.stderr)]:
   (args.output/('native.partial.'+name)).write_bytes(value if isinstance(value,bytes)else(value or '').encode('utf-8'))
  (args.output/'timeout.json').write_text(json.dumps({'command':command,'timeout_s':90,'state':'timed_out_unknown_no_retry'}),encoding='utf-8')
  raise
 (args.output/'native.stdout.log').write_text(result.stdout,encoding='utf-8');(args.output/'native.stderr.log').write_text(result.stderr,encoding='utf-8')
 native_id=record_native_result('animation_motion.'+op,case['scene'],command,result)
 if report.is_file():
  raw=report.read_bytes();record_snapshot_result('idle_turn_physical_v1',{'operation':'animation_motion.'+op,'scene':case['scene'],'native_case_id':native_id,'command':command,'project_root':str(args.project_root),'route_path':str(args.route),'report_path':str(report),'route_bytes_hex':route_bytes.hex(),'route_sha256':hashlib.sha256(route_bytes).hexdigest(),'report_bytes_hex':raw.hex(),'report_sha256':hashlib.sha256(raw).hexdigest()})
 need(result.returncode==0,'native checker failed; original outputs preserved')
 need(report.is_file(),'native report missing')
 return 0

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('godot','project-root','route','output'):p.add_argument('--'+name,type=Path,required=True)
 raise SystemExit(run(p.parse_args()))
