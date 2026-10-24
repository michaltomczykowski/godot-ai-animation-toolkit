"""Deliver complete transition videos with strict evidence and no visual approval."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from archive_run_review import digest, read, require, write, RIGS, STYLES


def require_sequence_render(render, route, mode):
    require(render['operation']=='animation_sequence' and render['source_head']==route['source_head']
        and render['mode']==mode and render['fps']==60 and render['size']==[1920,1080]
        and render['root_consumers_per_view']==1 and not render['errors'], 'Sequence recording source or ownership differs')
    require(tuple(r['id'] for r in render['cases'])==RIGS and len(route['cases'])==4,
        'Incomplete sequence recording rigs')
    for index,(recorded,saved) in enumerate(zip(render['cases'],route['cases'])):
        require(recorded['scene']==saved['scene'] and recorded['camera_views']==['FRONT','SIDE']
            and recorded['frames']==1320 and recorded['start_s']==index*22 and recorded['duration_s']==22
            and recorded['takes']==2 and recorded['reset_between_takes'], 'Sequence recording chapter differs')


def review_movie_name(video):
    operation, style, mode = video['operation'], video['style'], video['render']['mode']
    require(operation in ('walk_start','walk_stop','animation_sequence') and style in STYLES
        and mode in ('clean','diagnostic'), 'Invalid review movie identity')
    return f'{operation}-{style}-{mode}.mp4'


def require_transition_render(video, route, baseline, mode):
    render=video['render']
    require(digest(Path(video['path']))==video['sha256'] and not render['errors']
        and render['source_head']==route['source_head'] and render['operation']==route['operation']
        and render['profile']==route['profile'] and render['mode']==mode and render['fps']==60
        and render['size']==[1920,1080] and render['root_consumers_per_view']==1,
        'Incorrect transition recording identity/source')
    if render.get('layout')=='simultaneous_front_side':
        require(video['decoded_frames']==1440 and abs(video['decoded_duration_s']-24)<.017
            and tuple(r['id'] for r in render['cases'])==RIGS and len(render['cases'])==4,
            'Incomplete simultaneous camera movie')
        for index,(recorded,saved) in enumerate(zip(render['cases'],route['cases'])):
            require(recorded['scene']==saved['scene'] and recorded['camera_views']==['FRONT','SIDE']
                and recorded['takes']==2 and recorded['reset_between_takes'] and recorded['frames']==360
                and recorded['start_s']==index*6 and recorded['duration_s']==6, 'Incorrect saved scene/camera/take chapter')
    else:
        expected=[(rig,angle) for rig in RIGS for angle in ('FRONT','SIDE')]
        require(video['decoded_frames']==2880 and abs(video['decoded_duration_s']-48)<.017
            and render['baseline_source_head']==baseline['source_head']
            and [(r['id'],r['angle']) for r in render['cases']]==expected
            and all(r['takes']==2 and r['reset_between_takes'] and r['frames']==360 for r in render['cases']),
            'Incomplete continuous native comparison')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('repo','project-root','core-root','recovery','matrix','timing','sequence','reload','gates','ci-receipt','walk-reference','idle-reference'):
        p.add_argument('--'+name,type=Path,required=True)
    for name in ('candidate','baseline','actor-controls','preview-parity','renderer-provenance'):
        p.add_argument('--'+name,type=Path)
    a=p.parse_args(); candidate=a.candidate or a.recovery/'candidate-r001'; delivery=candidate/'review-delivery.json'
    require(not delivery.exists(),'Preserve delivered feedback; do not recreate the archive')
    state_path=a.repo/'docs/character-quality-review.json'; state=read(state_path)
    previous=state['start_stop_review']
    require(previous.get('visual_approval') is None and not previous.get('candidate_quality_approved'),'Feedback already exists')
    matrix=read(a.matrix)
    require(matrix['passed'] and matrix['native_runs']==480 and len(matrix['rows'])==20,'Incomplete ordinary playback matrix')
    source=matrix['source_head']; videos=[]; records=[]
    actor=read(a.actor_controls or candidate/'actor-controls-9dc1a5c5ad2d417ab203ea7aca8bb9a6/summary.json')
    require(actor['passed'] and actor['detected']==48 and actor['engine_errors']==0,'Missing actor drift controls')
    for name in ('continuation-self-check.json','continuation-self-check-in-place.json'):
        control=read(a.recovery/name)
        require(control['passed'] and len(control['rows'])==144 and not control['engine_errors'],'Missing independent reference audit controls')
    parity=None
    if a.preview_parity:
        parity=read(a.preview_parity)
        require(parity['passed'] and parity['native_runs']==96 and len(parity['rows'])==4,
            'Approved Responsive preview parity failed')
        for row in parity['rows']:
            report=read(Path(row['report']))
            require(report['passed'] and not report['engine_errors'] and len(report['runs'])==24
                and all(r['passed'] and r['authored_channels_exact'] for r in report['runs']), 'Preview output changed')
            require(digest(Path(row['report']))==row['sha256'], 'Preview parity report changed')
    for item in matrix['rows']:
        require(item['passed'] and item['complete'] and not item['engine_errors'],'Native failure')
        native=read(Path(item['report']))
        require(native['passed'] and len(native['runs'])==24 and all(r['active_mixers']==1 and r['thresholds_pass'] and r['generation_reach_clamped']==0 for r in native['runs']),'Incomplete native quality gate')
        for path,sha in item['input_sha256'].items(): require(digest(Path(path))==sha,'Changed native input')
    for op in ('walk_start','walk_stop'):
        for style in STYLES:
            baseline=read((a.baseline or a.recovery/'baseline')/op/style/'route.json')
            for label in (style,style+'-in-place'):
                route=read(candidate/op/label/'route.json')
                require(route['passed'] and route['source_head']==source and route['invocation_kind']=='ordinary call'
                    and tuple(r['id'] for r in route['cases'])==RIGS,'Missing ordinary public route')
                for r in route['cases']:
                    require(r['history']['passed']==r['history']['total']==1 and r['history']['failed']==r['history']['skipped']==0
                        and r['before']==r['after_dry'] and r['pose_before']==r['pose_after_dry']==r['pose_after']
                        and r['after']==r['after_history']==r['persisted'],'Public history/dry/reopen failed')
                    require(not any(k in r['params'] for k in ('overrides','phase','duration','samples','speed','loop_mode','gait_duration','gait_samples')),'Review overrides ordinary defaults')
                records.append(route)
            media=read(candidate/op/style/'media.json')
            require(set(media['videos'])=={'clean','diagnostic'},'Both continuous review modes required')
            for mode,v in media['videos'].items():
                require_transition_render(v,read(candidate/op/style/'route.json'),baseline,mode)
                videos.append({'operation':op,'style':style,**v})
    timing=read(a.timing/'timing-matrix.json')
    require(timing['passed'] and timing['public_requests']==96 and timing['public_clips']+timing['typed_nonmutating_refusals']==96
        and timing['native_runs']==6*timing['public_clips'] and len(timing['groups'])==24,'Incomplete independent timing/refusal matrix')
    sequence_route=read(a.sequence/'route.json'); sequence_native=read(a.sequence/'native-check.json')
    require(sequence_route['passed'] and sequence_native['passed'] and len(sequence_native['runs'])==24 and not sequence_native['engine_errors'],'Missing saved public composition')
    records.append(sequence_route)
    for mode,v in read(a.sequence/'media.json')['videos'].items():
        require_sequence_render(v['render'],sequence_route,mode)
        require(mode in ('clean','diagnostic') and digest(Path(v['path']))==v['sha256'] and v['decoded_frames']==5280
            and v['route_sha256']==digest(a.sequence/'route.json')
            and abs(v['decoded_duration_s']-88)<.017 and not v['render']['errors']
            and all(r['takes']==2 and r['reset_between_takes'] for r in v['render']['cases']),'Invalid sequence movie')
        videos.append({'operation':'animation_sequence','style':'responsive',**v})
    require(len(videos)==22,'Complete transition and composition media required')
    reload=read(a.reload/'core-reload.json')
    require(reload['passed'] and len(reload['phases'])==2 and all(len(s['rows'])==80 and all(r['passed'] for r in s['rows']) for s in reload['phases']),'Missing core reload dry/pose/full-file proof')
    gates=read(a.gates); ci=read(a.ci_receipt)
    require(gates['passed'] and gates['full_editor']['total']==gates['full_editor']['passed']==397
        and gates['full_editor']['skipped']==0 and gates['headless_suites']==14 and gates['public_motion']['passed']==71
        and gates['public_sequence']['passed']==3 and gates['engine_errors']==0,'Unexpected local regression')
    require(ci['all_required_source_jobs_pass'] and ci['all_advisory_jobs_pass'] and ci['protected_gaits_checked']
        and ci['expected_editor_total']==397 and ci['tracked_tree_matches_source'],'Incomplete Windows/Linux source CI')
    # The only addon follow-up after the recorded motion source is the separate
    # sequence marker repair. All transition generation dependencies are exact.
    require(subprocess.run(['git','diff','--quiet',source,ci['source_head'],'--','addons/godot_ai_animation',
        ':(exclude)addons/godot_ai_animation/spec/sequence_specs.gd'],cwd=a.repo).returncode==0,'CI transition source differs')
    for relative in ('test_project/tools/render_start_stop_comparison.gd',
            'test_project/tools/render_transition_sequence_review.gd',
            'test_project/tools/check_start_stop_quality.gd',
            'test_project/tools/check_transition_sequence_review.gd'):
        require((a.repo/relative).is_file(), 'Playback evidence source is missing')
        require(subprocess.run(['git','diff','--quiet',gates['source_head'],ci['source_head'],'--',relative],
            cwd=a.repo).returncode==0, 'CI playback evidence source differs')
    for protected in read(a.recovery/'protected-fixtures-before.json'):
        require(digest(Path(protected['path']))==protected['sha256'],'Accepted or historical fixture changed')
    destination=candidate/'review-videos'; destination.mkdir(exist_ok=True)
    require(len({review_movie_name(v) for v in videos})==len(videos), 'Duplicate review movie names')
    for v in videos:
        target=destination/review_movie_name(v)
        if not target.exists(): shutil.copy2(v['path'],target)
        require(digest(target)==v['sha256'],'Review copy differs');v['path']=str(target)
    scenes={}
    for base in (a.recovery,a.walk_reference,a.idle_reference):
        for path in base.rglob('route.json'):
            record=read(path)
            if record.get('passed'): records.append(record)
    scene_zip=candidate/'native-scenes-and-local-rigs.zip'
    with zipfile.ZipFile(scene_zip,'w',zipfile.ZIP_DEFLATED) as archive:
        for record in records:
            for row in record.get('cases',[]):
                if row.get('refused'): continue
                relative=row['scene'].removeprefix('res://'); path=a.project_root/relative
                require(digest(path)==row['scene_sha256'],'Saved scene differs')
                if relative not in scenes:
                    scenes[relative]=row['scene_sha256']; archive.write(path,'project/'+relative)
        for phase in reload['phases']:
            for row in phase['rows']:
                relative=row['scene'].removeprefix('res://'); path=a.project_root/relative
                require(digest(path)==row['after_sha256'],'Reload scene differs')
                if relative not in scenes:
                    scenes[relative]=row['after_sha256']; archive.write(path,'project/'+relative)
        for fixture in ('repair_rig_fixture.tscn','repair_xbot_fixture.tscn','repair_synthetic_short.tscn','repair_synthetic_zup_tall.tscn'):
            archive.write(a.project_root/fixture,'project/'+fixture)
        for directory in ('models/human_dummy','models/x_bot'):
            for path in (a.project_root/directory).rglob('*'):
                if path.is_file(): archive.write(path,'project/'+path.relative_to(a.project_root).as_posix())
    source_zip=candidate/'animation-source.zip'
    subprocess.run(['git','-c','core.autocrlf=false','archive','--format=zip','--output',str(source_zip),source],cwd=a.repo,check=True)
    sequence_zip=candidate/'sequence-and-tooling-source.zip'
    subprocess.run(['git','-c','core.autocrlf=false','archive','--format=zip','--output',str(sequence_zip),ci['source_head']],cwd=a.repo,check=True)
    receipts_zip=candidate/'phase-receipts.zip'
    with zipfile.ZipFile(receipts_zip,'w',zipfile.ZIP_DEFLATED) as archive:
        for path in a.recovery.rglob('*'):
            if path.is_file() and path.suffix in ('.json','.log','.exit'): archive.write(path,path.relative_to(a.recovery).as_posix())
    archives={str(path):digest(path) for path in (scene_zip,source_zip,sequence_zip,receipts_zip)}
    for path in archives:
        with zipfile.ZipFile(path) as archive: require(archive.testzip() is None,'Archive CRC failed')
    # Windows working provenance files may have CRLF; source ZIPs must contain
    # their exact canonical Git blobs, without rewriting accepted fixtures.
    for path,revision in ((source_zip,source),(sequence_zip,ci['source_head'])):
        with zipfile.ZipFile(path) as archive:
            for protected in read(a.recovery/'protected-fixtures-before.json'):
                relative=Path(protected['path']).relative_to(a.repo).as_posix()
                blob=subprocess.check_output(['git','show',revision+':'+relative],cwd=a.repo)
                require(archive.read(relative)==blob,'Archived protected fixture differs from exact source')
    simultaneous=all(v['render'].get('layout')=='simultaneous_front_side' for v in videos if v['operation']!='animation_sequence')
    if simultaneous:
        require(a.renderer_provenance is not None, 'Candidate camera layout needs its captured renderer source')
        renderer=read(a.renderer_provenance)
        require(renderer['unchanged_during_capture'] and len(renderer['files'])==6,'Incomplete renderer dependency proof')
        for row in renderer['files']:
            require((a.repo/row['path']).is_file() and digest(a.repo/row['path'])==row['working_sha256'], 'Renderer dependency changed during recording')
            require(subprocess.run(['git','diff','--quiet',renderer['source'],ci['source_head'],'--',row['path']],cwd=a.repo).returncode==0,
                'CI renderer source differs from captured tooling')
    transition_instructions=('Style videos show FRONT (left) and SIDE (right) simultaneously. Cameras follow translation; the ground grid stays fixed.\n'
        'Style videos: 24s, 1080p60; 00-06 dummy, 06-12 X Bot, 12-18 short, 18-24 tall Z-up. Two reset-separated complete takes per rig.\n'
        if simultaneous else 'Compare BEFORE (left) and CANDIDATE (right). Front/side cameras follow translation; the ground grid stays fixed.\n'
        'Transition videos: 48s, 1080p60; 00-12 dummy, 12-24 X Bot, 24-36 short, 36-48 tall Z-up. Two reset-separated complete takes per angle.\n')
    (destination/'START-HERE.txt').write_text(
        'Start with walk_start-responsive-clean.mp4, then walk_stop-responsive-clean.mp4 and animation_sequence-responsive-clean.mp4.\n'+
        transition_instructions+
        'Sequence videos: 88s, 1080p60; simultaneous front/side, two complete 11s takes per rig. Idle/start/two walks/stop/idle is one saved clip.\n'
        'Clean videos are for motion judgement; diagnostic videos show intended stance within the ankle band, hip projection and root travel.\n'
        'Review anticipation, stepping, weight transfer, arms/head and the joins into walking/standing. Approve or request changes for start/stop styles and sequence.\n'
        'Numerical checks have passed. Human animation approval, remaining roadmap work and release are pending.\n',encoding='utf-8')
    receipt={'state':'awaiting_start_stop_feedback','animation_source':source,'sequence_source':sequence_route['source_head'],
        'ci_source':ci['source_head'],'core_source':subprocess.check_output(['git','rev-parse','HEAD'],cwd=a.core_root,text=True).strip(),
        'created_utc':datetime.now(timezone.utc).isoformat(),'public_clips':80,'native_runs':480,'timing':timing,
        'sequence_native_runs':24,'reload_dry_calls':160,'videos':videos,'scene_files':scenes,'archives':archives,
        'ci_receipt':str(a.ci_receipt),'gates':str(a.gates),'preview_parity':parity,
        'renderer_provenance':str(a.renderer_provenance) if a.renderer_provenance else None,'visual_approval':None,'release_ready':False}
    write(delivery,receipt)
    previous.update(state=receipt['state'],animation_source=source,review_delivery=str(delivery),videos=videos,
        profile_approvals=previous.get('profile_approvals',{op:{style:None for style in STYLES} for op in ('walk_start','walk_stop')}),sequence_approval=previous.get('sequence_approval'),
        candidate_quality_approved=False,visual_approval=None,release_ready=False)
    state.update(state=receipt['state'],active_review_field='start_stop_review',operation='walk_start/walk_stop',
        next_action='Open PC Explorer on the complete start/stop videos; pause for explicit motion and sequence feedback.')
    write(state_path,state)
    print('START_STOP_REVIEW_READY=22 continuous movies; public/history/native/timing/reload/local/CI gates complete; human feedback pending')

if __name__=='__main__': main()
