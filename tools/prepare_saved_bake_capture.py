"""Copy eight exact historical bake pairs. Input staging only; no qualification."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path
IDS=('graph_state_60','graph_oneshot_60','modifier_spring_1_60','modifier_ordered_spring_look_1_60','modifier_retarget_1_60','root_preserve_true_true_true_60','root_pose_only_true_true_true_60','root_apply_true_true_true_60')
SOURCE='e3a9e9338aa542b09fc3e2142ed91ea07e89da73'
MANIFEST_SHA='2b73dd4ca99c745574c47d864a04fac2503b5c4816fd050a720dad21f08fb632'
ARCHIVE_SHA='895a6c27cc4488fac2864e41c9d6c45230f44caea05a6f5f86adfa374124084c'
HELPER='addons/godot_ai_animation/utils/retarget_pose_restore.gd'
NAME='Toolkit Saved Bake Eight Capture'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def user_relative(path):
    if not isinstance(path,str) or not path.startswith('user://'):raise ValueError('expected confined user resource')
    if path[7:].startswith(('/',chr(92))):raise ValueError('rooted user resource')
    rel=Path(path[7:])
    if rel.is_absolute() or '..' in rel.parts or ':' in str(rel) or not rel.parts:raise ValueError('unsafe user resource')
    return rel

def admit(anchor):
    manifest=anchor/'final-native-manifest.json';checkpoint=read(anchor/'closing-checkpoint.json')
    if sha(manifest)!=MANIFEST_SHA or checkpoint.get('source')!=SOURCE or checkpoint.get('archive_sha256')!=ARCHIVE_SHA:raise ValueError('historical source/manifest pin mismatch')
    if sha(anchor/'completed-phase-source.zip')!=ARCHIVE_SHA:raise ValueError('historical source archive changed')
    log=(anchor/'final-native-runtime.log').read_text(encoding='utf-8-sig');rows=[x.split('RIG_BAKE_RESTORATION_RUNTIME=',1)[1] for x in log.splitlines() if x.startswith('RIG_BAKE_RESTORATION_RUNTIME=')]
    if len(rows)!=1:raise ValueError('missing exact historical native report')
    report=json.loads(rows[0])
    if report.get('failures')!=[] or report.get('engine_errors')!=[] or report.get('cases')!=201:raise ValueError('historical native report failed')
    allrows=read(manifest).get('cases',[]);selected=[]
    for case_id in IDS:
        found=[r for r in allrows if r.get('id')==case_id]
        if len(found)!=1:raise ValueError('missing/duplicate exact case '+case_id)
        row=found[0]
        if row.get('params',{}).get('op')!='bake_pose_sequence' or row['params'].get('fps')!=60:raise ValueError('wrong saved request')
        if set(row.get('states',{}))!={'do','undo','redo'}:raise ValueError('missing historical state')
        for path in [row['source'],*row['states'].values()]:
            rel=user_relative(path);file=(anchor/'native_saved_scenes'/rel).resolve()
            if not file.is_relative_to((anchor/'native_saved_scenes').resolve()) or not file.is_file():raise ValueError('missing/escaped archived scene')
            refs=re.findall(r'\[ext_resource[^\n]*path="([^"]+)"',file.read_text())
            if set(refs)-{'res://'+HELPER}:raise ValueError('unexpected scene dependency')
        selected.append(row)
    return selected,report

def prepare(repo,anchor,out):
    if out.exists():raise ValueError('preserve earlier output')
    rows,report=admit(anchor)
    # The only imported production helper is unchanged, checked against exact historical Git bytes.
    historical=subprocess.check_output(['git','-C',str(repo),'show',SOURCE+':'+HELPER])
    current=(repo/HELPER).read_bytes()
    if historical.replace(b'\r\n',b'\n')!=current.replace(b'\r\n',b'\n'):raise ValueError('retarget restore helper changed')
    project=out/'project';app=out/'appdata/Godot/app_userdata'/NAME
    project.mkdir(parents=True);app.mkdir(parents=True);files={}
    for row in rows:
        for virtual in [row['source'],*row['states'].values()]:
            rel=user_relative(virtual);src=anchor/'native_saved_scenes'/rel;dst=app/rel
            dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
            files[virtual]={'original':str(src),'sha256':sha(src),'copied_sha256':sha(dst)}
    dst=project/HELPER;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(historical)
    files['res://'+HELPER]={'source':SOURCE,'sha256':sha(dst),'git_blob':subprocess.check_output(['git','-C',str(repo),'rev-parse',SOURCE+':'+HELPER],text=True).strip()}
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="'+NAME+'"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/stretch/mode="viewport"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    receipt={'kind':'saved_bake_eight_input_staging','state':'historical_inputs_staged_native_capture_pending','source_public':SOURCE,'capture_source':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),'source_manifest_sha256':MANIFEST_SHA,'source_archive_sha256':ARCHIVE_SHA,'source_native_report':report,'source_native_log_sha256':sha(anchor/'final-native-runtime.log'),'cases':rows,'files':files,'scope':'Exact historical input bytes only; no current producer equivalence, per-case native acceptance, engine execution, media or visual qualification.','pending':['explicit producer-to-current bridge','shared actual saved-source/redo evaluator','retarget per-rig final freshness','root consumer ownership admission','native full trace','render framing/PNG/full decode','independent temporal review']}
    (project/'bake-manifest.json').write_text(json.dumps(receipt,indent=2));(out/'preparation.json').write_text(json.dumps({'manifest_sha256':sha(project/'bake-manifest.json'),'project':str(project),'APPDATA':str(out/'appdata'),'state':receipt['state']},indent=2));return receipt
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True);p.add_argument('--anchor',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=prepare(a.repo.resolve(),a.anchor.resolve(),a.output.resolve());print(json.dumps({'state':r['state'],'cases':len(r['cases'])}))
