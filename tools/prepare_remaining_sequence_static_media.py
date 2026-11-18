"""Fixed offline phase4 inventory/staging; no generation, engine or media tools.

Copies only three self-contained archived technical cases and two public static
chain pairs. Full sequence movies and private skinned rigs stay at their source.
This prepares inputs and records missing admissions; it never approves media.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

from operation_rig_scene_history_checks import verify_event as verify_chain

SYNTHETIC_SOURCE='751370894a2959ade6278ad972623e45813aa066'
SEQUENCE_SOURCE='10941ba81c367fe0c753ff9086fb826d3136bbec'
CHAIN_SOURCE='3d91adef459558f28a76b9537dfb4b6b5205d9bd'
IDS=('sequence_rooted_local_60','sequence_inline_pose_local_60','secondary_branches_local_60')
ARCHIVE_SHA='a4acf84f79bc21346ce387c8477b449fa0b227c17f75ba163dd45df0a71c6002'
SEQ_ARCHIVE_SHA='80c4330c884c42bc7e06bb5fab01fe8fd4a48717c559f9f65f4a145aaa53a6b2'
SEQ_RECEIPTS_SHA='a607db48c6a649b0e40fb903708828226368015220d74d26aada2f58fda91a66'
SEQ_ROUTE_SHA='1e96b7aceabde750c3df09f1d6128fec48c159184c3ac57b9bea7febdb423bfe'
CHAIN_CONTEXT_SHA='51cbda30de52942905ff13ddcc9a30ca128e82dc09a6e53231a01974617c0c63'


def need(ok,message):
    if not ok:raise ValueError(message)


def digest(raw):return hashlib.sha256(raw).hexdigest()
def sha(path):return digest(path.read_bytes())
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def pinned(path,expected):
    need(sha(path)==expected,'changed preserved bytes: '+str(path))
    return {'path':str(path.resolve()),'sha256':expected}


def git(repo,*args):return subprocess.check_output(['git',*args],cwd=repo,text=True).strip()


def source_comparison(repo,source,paths):
    candidate=git(repo,'rev-parse','HEAD');result=[]
    for path in paths:
        old=git(repo,'rev-parse',source+':'+path);current=git(repo,'rev-parse',candidate+':'+path)
        result.append(dict(path=path,historical_blob=old,candidate_blob=current,exact=old==current,
                           candidate_working_sha256=sha(repo/path)))
    return result


def function_comparison(repo,source,path,name):
    def body(ref):
        text=git(repo,'show',ref+':'+path)
        found=re.search(r'(?ms)^(?:static )?func '+name+r'\(.*?(?=^(?:static )?func |\Z)',text)
        need(found is not None,'required operative function missing: '+name)
        return found.group().strip()
    old,current=body(source),body('HEAD')
    return dict(path=path,function=name,historical_source=source,historical_lf_sha256=digest(old.encode()),candidate_lf_sha256=digest(current.encode()),exact=old==current,
                limits='Source comparison only; no fresh invocation or animation regeneration inferred.')


def select_rows(manifest):
    result=[]
    for identity in IDS:
        rows=[r for r in manifest.get('cases',[])if r.get('id')==identity]
        need(len(rows)==1,'missing/duplicate selected technical case: '+identity)
        result.append(rows[0])
    return result


def stage_member(archive,member,target):
    # Names come only from the pinned original row, and may never escape staging.
    need(Path(member).name==member and '/'not in member and '\\'not in member,'non-flat archived resource name')
    raw=archive.read(member);text=raw.decode('utf-8-sig')
    need('[ext_resource'not in text and 'type="MeshInstance3D"'not in text and 'type="Skin"'not in text,'technical capture requires self-contained unskinned inputs')
    target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('xb')as stream:stream.write(raw)
    return dict(path=str(target.resolve()),sha256=digest(raw),archive_member=member)


def technical_cases(snapshot,output):
    base=snapshot/'motion_sequence_history_20261008';path=base/'final-native-scenes.zip'
    proof=pinned(path,ARCHIVE_SHA);archive=read(base/'final-archive.json')
    need(archive['validated_source']==SYNTHETIC_SOURCE and archive['files']['final-native-scenes.zip']['sha256']==ARCHIVE_SHA,'original technical producer/archive identity differs')
    cases=[]
    with zipfile.ZipFile(path)as bundle:
        manifest=json.loads(bundle.read('motion_sequence_saved_matrix.json'))
        for row in select_rows(manifest):
            copied={}
            for label,virtual in [('source',row['source']),('reference',row['reference'])]+list(row['states'].items()):
                need(virtual.startswith('user://'),'unexpected archived virtual resource')
                member=virtual.removeprefix('user://');copied[label]=stage_member(bundle,member,output/'technical'/row['id']/member)
            need(copied['source']['sha256']==copied['undo']['sha256'],'source/undo archived inputs differ')
            replay=copy.deepcopy(row);replay.update(source=copied['source']['path'],reference=copied['reference']['path'],states={k:copied[k]['path']for k in ('do','undo','redo')})
            cases.append(dict(id=row['id'],operation='animation_motion.secondary_motion'if row['group']=='secondary'else'animation_sequence.compose',producer_source=SYNTHETIC_SOURCE,
                original_row=row,replay_row=replay,files=copied,
                new_capture_required=row['group']=='secondary',
                purpose='Required secondary branches representative'if row['group']=='secondary'else'Optional pose-channel variant'if row['variant']=='inline_pose'else'Optional technical/root native control; full sequence movie already exists',
                proposed_capture=dict(fps=60,takes=2,take_duration_s=6,frames=720,clock='one complete finite native clip then held endpoint; never stretched/repeated/generated'),
                admission='pending existing renderer adaptation: persisted reference only, full native channel/root parity, exact reset/clock/ownership and body/header framing'))
    return dict(archive=proof,source_route={'path':str(base/'final-source-route.json'),'sha256':sha(base/'final-source-route.json')},cases=cases,
                old_partial_movie=dict(path=str(base/'media/motion_sequence_history.mp4'),sha256=sha(base/'media/motion_sequence_history.mp4'),frames=316,fps=60,scope='Historical5.2667s technical composite; never full representative approval'))


def full_sequence(snapshot):
    closure=snapshot/'release_r2_start_stop_body_20261013/closure-r002';base=closure/'sequence-recording-r003';delivery=read(closure/'candidate-r002/review-delivery.json')
    archive=closure/'candidate-r002/native-scenes-and-local-rigs.zip';receipts=closure/'candidate-r002/phase-receipts.zip'
    bindings=[pinned(archive,SEQ_ARCHIVE_SHA),pinned(receipts,SEQ_RECEIPTS_SHA),pinned(base/'route.json',SEQ_ROUTE_SHA)]
    need(delivery['sequence_source']==SEQUENCE_SOURCE and delivery['archives'][str(archive)]==SEQ_ARCHIVE_SHA,'full sequence original source/archive differs')
    route=read(base/'route.json');native=read(base/'native-check.json');media=read(base/'media.json')
    need(route['source_head']==native['source_head']==SEQUENCE_SOURCE and route['passed']is True and native['passed']is True and native['engine_errors']==[],'full sequence route/native failure')
    keys={(r.get('id'),r.get('mixer'),r.get('fps'))for r in native['runs']}
    need(len(native['runs'])==24 and keys=={(identity,mode,fps)for identity in ('dummy','xbot','short','zup_tall')for mode in ('player','tree')for fps in (30,60,120)}and all(r.get('passed')is True and r.get('failures')==[]for r in native['runs']),'full sequence native clocks incomplete')
    scenes=[]
    with zipfile.ZipFile(archive)as bundle:
        for row in route['cases']:
            member='project/'+row['scene'].removeprefix('res://');need(digest(bundle.read(member))==row['scene_sha256'],'full sequence archived scene differs')
            scenes.append(dict(id=row['id'],scene=row['scene'],sha256=row['scene_sha256'],archive_member=member,private_local_only=row['id']=='xbot'))
    with zipfile.ZipFile(receipts)as bundle:
        for name in ('route.json','native-check.json','media.json','recording-progress.json'):
            need(bundle.read('sequence-recording-r003/'+name)==(base/name).read_bytes(),'archived full sequence receipt differs: '+name)
    movies=[]
    for mode in ('clean','diagnostic'):
        row=media['videos'][mode];path=Path(row['path']);pinned(path,row['sha256']);render=row['render']
        need(row['route_sha256']==SEQ_ROUTE_SHA and row['decoded_frames']==5280 and row['decoded_duration_s']==88 and render['source_head']==SEQUENCE_SOURCE and render['errors']==[] and render['fps']==60 and render['size']==[1920,1080]and render['root_consumers_per_view']==1,'full sequence movie/route/render identity differs')
        need([r['id']for r in render['cases']]==['dummy','xbot','short','zup_tall']and all(r['takes']==2 and r['reset_between_takes']is True and r['camera_views']==['FRONT','SIDE']and r['frames']==1320 for r in render['cases']),'full sequence take/view schedule differs')
        movies.append(dict(mode=mode,path=str(path),sha256=row['sha256'],recorded_full_decode=dict(frames=5280,duration_s=88,fps=60),
            frames_directory=str(base/(mode+'_frames')),actual_png_count=sum(1 for _ in (base/(mode+'_frames')).glob('[0-9]*.png')),
            case_frame_spans=[dict(id=r['id'],first=index*1320,last=(index+1)*1320-1,take_frames=660,private_local_only=r['id']=='xbot')for index,r in enumerate(render['cases'])],
            status='eligible preserved representative, pending fresh admission/full movie independent assessment; no new decode/view performed'))
    return dict(operation='animation_sequence.compose',producer_source=SEQUENCE_SOURCE,bindings=bindings,public_route=dict(path=str(base/'route.json'),sha256=SEQ_ROUTE_SHA),native_report=dict(path=str(base/'native-check.json'),sha256=sha(base/'native-check.json')),media_receipt=dict(path=str(base/'media.json'),sha256=sha(base/'media.json')),renderer_provenance=dict(path=str(closure/'renderer-source-provenance.json'),sha256=sha(closure/'renderer-source-provenance.json')),movies=movies,scenes=scenes,new_capture_required=False,
                remaining=['Current saved-scene/native admission with original input clips and model/import bindings retained.','Root full decode/current byte receipt plus ordered independent assessment, including both takes/endpoints; original recording remains historical.'],
                limits='Private XBot appears22..44s; retain movies locally. No full source/current generation or all sequence variant approval inferred.')


def chain_cases(evidence,output):
    base=evidence/'setup-public-history-witness-r002';context_path=base/'operation-context.json';pinned(context_path,CHAIN_CONTEXT_SHA);context=read(context_path)
    need(context['tested_source']==CHAIN_SOURCE,'chain public source differs')
    events=[];event_paths={}
    for path in (base/'public-calls').glob('*.jsonl'):
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            event=json.loads(line);events.append(event);event_paths[event['id']]=path
    begins=[e for e in events if e['kind']=='public_test_run_begin'];support=[e for e in events if e['kind']=='public_support_call'];cases=[]
    for variant in ('create','append'):
        selected=[e for e in events if e.get('row',{}).get('op')=='rig_chain'and e['row'].get('kind')=='3d'and e['row'].get('variant')==variant]
        need(len(selected)==1,'missing/duplicate actual static chain event');event=selected[0];proof=verify_chain(event,context,begins,support)
        need(proof['checks'].get('valid_effect')=='pass'and all(v=='pass'for v in proof['checks'].values()),'actual static chain intent/history/source gate failed')
        row=event['row'];copied={}
        for label,key in (('before','persist_undo'),('after','persist_redo')):
            saved=row[key];name=saved['path'].removeprefix('user://');source=base/'appdata/Godot/app_userdata/Toolkit R2 Turn Validation'/name;pinned(source,saved['sha256'])
            raw=source.read_bytes();need('[ext_resource'not in raw.decode('utf-8-sig'),'chain pair external dependency unresolved')
            target=output/'static'/variant/name;target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb')as stream:stream.write(raw)
            copied[label]=dict(path=str(target.resolve()),sha256=digest(raw),original_source=str(source),native_snapshot=saved['snapshot'])
        cases.append(dict(id='3d_local_'+variant,operation='animation_rig.rig_chain',producer_source=CHAIN_SOURCE,public_event_id=event['id'],public_test_run_case_id=proof['public_test_run_case_id'],raw_event=dict(path=str(event_paths[event['id']]),sha256=sha(event_paths[event['id']])),context=dict(path=str(context_path),sha256=CHAIN_CONTEXT_SHA),request=row['request'],native_checks=proof['checks'],files=copied,new_capture_required=True,
            proposed_capture=dict(fps=60,takes=2,take_duration_s=4,before_s=2,after_s=2,frames=480),
            admission='pending static-only renderer admission: zero animation writers, every original/new skeleton/bone/rest/parent/name/scale compared with bound snapshots, all geometry and labels framed; no hand-applied pose/key changes'))
    return cases


def prepare(args):
    need(not args.output.exists(),'preserve prior inventory/staging attempt')
    args.output.mkdir(parents=True,exist_ok=False)
    candidate=git(args.repo,'rev-parse','HEAD');technical=technical_cases(args.snapshot,args.output);sequence=full_sequence(args.snapshot);static=chain_cases(args.evidence,args.output)
    prefixes='addons/godot_ai_animation/'
    sequence_deps=[prefixes+p for p in ('handlers/sequence.gd','handlers/bone_animation.gd','handlers/animation_tool_base.gd','spec/sequence_specs.gd','spec/clip_spec.gd','spec/spec_modifiers.gd','spec/spec_builder.gd','spec/spec_io.gd','spec/pose_math.gd','utils/error_codes.gd','utils/tool_context.gd','utils/value_codec.gd')]
    secondary_deps=[prefixes+p for p in ('handlers/motion.gd','handlers/bone_animation.gd','handlers/animation_tool_base.gd','utils/secondary_clip_sampler.gd','utils/evaluation_sandbox.gd','spec/motion_drivers.gd','spec/spec_io.gd','utils/error_codes.gd','utils/tool_context.gd','utils/value_codec.gd')]
    result=dict(schema_version=1,kind='bounded_remaining_sequence_static_media_inputs',candidate_reference_source=candidate,qualification='pending; offline inventory/staging only',
        remaining_operation_rows=['animation_sequence.compose','animation_motion.secondary_motion','animation_rig.rig_chain'],
        full_sequence_reuse=sequence,technical_pairs=technical,static_pairs=static,
        minimum_new_capture_case_ids=['secondary_branches_local_60','3d_local_create','3d_local_append'],optional_extra_variant_case_ids=['sequence_inline_pose_local_60','sequence_rooted_local_60'],
        already_assessed_static=[dict(operation='animation_rig.pose_apply',assessment=str(args.evidence/'rig-visual-assessment-r004-r001/assessment.json'),sha256=sha(args.evidence/'rig-visual-assessment-r004-r001/assessment.json'),scope='Existing72s nine-rig-operation film includes before/after pose_apply; reuse bounded unskinned display assessment.'),dict(operation='animation_inspect.preview',checkpoint=str(args.repo/'docs/preview-static-assessment-checkpoint-20261026.md'),sha256=sha(args.repo/'docs/preview-static-assessment-checkpoint-20261026.md'),scope='Eight discrete Linux421/430 PNGs independently assessed; continuous media not applicable. Windows/current qualification stays separate.')],
        source_boundaries=dict(sequence_full_movie=source_comparison(args.repo,SEQUENCE_SOURCE,sequence_deps),secondary_technical=source_comparison(args.repo,SYNTHETIC_SOURCE,secondary_deps),
            secondary_operative_function=function_comparison(args.repo,SYNTHETIC_SOURCE,prefixes+'handlers/motion.gd','motion_secondary'),
            chain=source_comparison(args.repo,CHAIN_SOURCE,[prefixes+p for p in ('handlers/rig.gd','handlers/animation_tool_base.gd','spec/pose_math.gd','utils/error_codes.gd')]),
            limitation='Whole-file mismatches are disclosed; no current-source generation claim. Sequence full-movie handler differs by registry preflight, while transform composition helpers match; earlier751 sequence marker-grouping differs. Recheck actual selected dependency/function boundaries before promotion.'),
        exact_next_admissions=[
            'Reuse88s sequence: bind saved scene/model/native inputs and root clock, decode whole current movie bytes, independently inspect ordered actual video frames. Recapture only if a concrete admission/visible defect requires it.',
            'Secondary pair: existing legacy renderer must load persisted reference.tres and never Reference.build or replace libraries. Require two fresh6s takes, one complete finite action then hold, exact native phase/all-channel/root parity and complete body/header framing before GPU.',
            'Chain create/append: use bound current-public before/after snapshots, show every original/new skeleton plus parent/rest/name/scale, zero animation writers, two reset comparisons,2s before/2s after. Existing pose_apply renderer hardcodes nineops/constant bone counts and is not yet a chain renderer.',
            'After scoped native+framing admission: root alone records the three required cases, full-decodes and requests independent ordered assessment; optional inline-pose/root technical cases do not expand default capture queue.'],
        ownership='No engines/server/ffmpeg, generation, primary mutations, media uploads or XBot copies. Staged technical/static files are synthetic and self-contained. New renderer/native admission remains required; this manifest is not directly accepted by legacy four-case/nine-op renderers.')
    with (args.output/'manifest.json').open('x',encoding='utf-8')as stream:json.dump(result,stream,indent=2)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--snapshot',type=Path,default=Path('F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30'));p.add_argument('--evidence',type=Path,default=Path('E:/GodotAI-toolkit-release-2.0.0/20261014'))
    a=p.parse_args();r=prepare(a);print(json.dumps({'state':'prepared_inputs_admission_pending','candidate_reference_source':r['candidate_reference_source'],'new_capture_cases':r['minimum_new_capture_case_ids'],'sequence_movies_reused':len(r['full_sequence_reuse']['movies'])}))
    return 0


if __name__=='__main__':raise SystemExit(main())
