"""Reopen actual rendered-preview artifacts and bind checks to one public call."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path, PureWindowsPath


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def artifact(root, value):
    raw=value.get('path','')
    if not isinstance(raw,str) or not raw or Path(raw).is_absolute() or PureWindowsPath(raw).drive:
        raise ValueError('preview artifact path must be portable')
    path=(root/raw).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file() or digest(path)!=value.get('sha256'):
        raise ValueError('preview artifact escaped root, missing, or hash changed')
    return path


def typed_error(value, code='INVALID_PARAMS'):
    error=value.get('error','') if isinstance(value,dict) else ''
    actual=error.get('code') if isinstance(error,dict) else str(error).split(':',1)[0]
    return actual==code


def validate_preview(report_path,context_path,context,public_events):
    from PIL import Image,ImageChops
    context_path=context_path.resolve()
    report_path=report_path.resolve()
    root=context_path.parent.resolve()
    if not report_path.resolve().is_relative_to(root):raise ValueError('preview report escaped receipt root')
    report=json.loads(report_path.read_text(encoding='utf-8'))
    if report.get('schema_version')!=1 or report.get('operation')!='animation_inspect.preview' or report.get('passed') is not True:
        raise ValueError('preview report is not an actual successful preview result')
    if report.get('context_sha256')!=digest(context_path) or report.get('context')!=context:
        raise ValueError('preview context identity differs')
    for source in ('tools/ci_rendered_preview.py','tools/operation_preview_adapter.py'):
        if source not in context['dependencies']:raise ValueError('preview producer/adapter not bound to tested source')
    by_id={event['id']:event for event in public_events}
    origin=by_id.get(report.get('public_case_id'))
    if not origin or origin.get('operation')!='animation_inspect.preview' or not isinstance(origin.get('response'),dict) or not origin['response'] or origin['response'].get('error') or origin.get('params',{}).get('dry_run'):
        raise ValueError('preview result lacks exact successful public invocation')
    if origin['response']!=report.get('raw_response'):raise ValueError('preview response differs from actual public call')
    params=origin['params'];response=origin['response']
    if params.get('width')!=320 or params.get('height')!=240 or len(params.get('times',[]))!=4 or response.get('times')!=params['times']:
        raise ValueError('preview dimensions/times differ from executed request')
    expected=[params.get('output_dir','').rstrip('/')+'/'+params.get('basename','')+'_%02d.png'%i for i in range(4)]
    if response.get('paths')!=expected:raise ValueError('preview returned paths differ from requested output')
    command=report.get('editor_command',[])
    if not command or command[0]!=context.get('engine_command') or '--headless' in command or '--editor' not in command:
        raise ValueError('preview requires the exact actual non-headless editor')
    try:method=command[command.index('--rendering-method')+1]
    except (ValueError,IndexError):method=None
    if method!='gl_compatibility':raise ValueError('preview editor rendering method differs from source contract')
    logs=report.get('logs',[])
    if len(logs)!=2 or {value.get('path') for value in logs}!={'editor.log','backend.log'}:raise ValueError('preview log identities incomplete or unexpected')
    editor=next((value for value in logs if value.get('path')=='editor.log'),None)
    backend=next((value for value in logs if value.get('path')=='backend.log'),None)
    if not editor or not backend:raise ValueError('preview lacks actual editor/backend logs')
    editor_path=artifact(root,editor);artifact(root,backend)
    text=editor_path.read_text(encoding='utf-8',errors='replace')
    clean_text=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',text)
    if any(marker in clean_text for marker in ('ERROR:','SCRIPT ERROR:','Parse Error')):
        raise ValueError('preview editor reported an engine/script error')
    identity=report.get('renderer_identity',[])
    if not identity or not all(isinstance(line,str) and line in text and 'OpenGL API' in line for line in identity):
        raise ValueError('preview renderer identity differs from actual startup log')
    if context['platform']=='linux' and not any('llvmpipe' in line.lower() for line in identity):
        raise ValueError('Linux preview contract requires actual llvmpipe renderer identity')
    rows=report.get('images',[])
    if len(rows)!=4 or [row.get('path') for row in rows]!=[Path(path).name for path in expected]:
        raise ValueError('preview must bind exactly four requested image identities')
    decoded=[]
    for row in rows:
        path=artifact(root,row)
        with Image.open(path) as source:
            if source.format!='PNG' or source.size!=(320,240):raise ValueError('invalid preview PNG format/dimensions')
            rgba=source.convert('RGBA')
            if rgba.getchannel('A').getextrema()!=(255,255):raise ValueError('preview output is transparent rather than visible pixels')
            image=rgba.convert('RGB')
        extrema=[list(pair) for pair in image.getextrema()]
        colors=len(image.getcolors(320*240) or [])
        if max(hi-lo for lo,hi in extrema)<12 or colors<2:raise ValueError('preview image is blank/uniform')
        if row.get('size')!=[320,240] or row.get('rgb_extrema')!=extrema or row.get('unique_colors')!=colors:
            raise ValueError('preview pixel metrics differ from decoded evidence')
        if any(ImageChops.difference(previous,image).getbbox() is None for previous in decoded):
            raise ValueError('preview times yielded duplicate decoded frames')
        decoded.append(image)
    restore=report.get('restoration',{})
    required=('before_scene','after_scene','before_timeline','after_timeline')
    if set(restore)!=set(required):raise ValueError('preview restoration artifacts incomplete')
    restored={key:artifact(root,restore[key]) for key in required}
    if restored['before_scene'].read_bytes()!=restored['after_scene'].read_bytes():
        raise ValueError('preview changed serialized source scene')
    before=json.loads(restored['before_timeline'].read_text(encoding='utf-8'))
    after=json.loads(restored['after_timeline'].read_text(encoding='utf-8'))
    if before!=after:raise ValueError('preview changed source timeline')
    if not isinstance(before,dict):raise ValueError('preview source timeline must be an object')
    if before.get('animation_name')!=params.get('animation_name') or before.get('player_path')!=params.get('player_path') or not isinstance(before.get('tracks'),list) or not before['tracks']:
        raise ValueError('preview source timeline is missing its actual generated clip')
    checkpoints=report.get('checkpoints',{})
    labels=('before_dry','after_dry','before_preview','after_preview','after_overwrite_refusal')
    if set(checkpoints)!=set(labels):raise ValueError('preview requires all five exact source checkpoints')
    points={}
    for label in labels:
        point=checkpoints.get(label,{})
        event=by_id.get(point.get('timeline_public_case_id'))
        if not event or event.get('operation')!='animation_inspect.timeline' or event.get('response',{}).get('error') or any(event.get('params',{}).get(key)!=params.get(key) for key in ('player_path','animation_name')):
            raise ValueError('preview checkpoint lacks exact actual source timeline call')
        scene=artifact(root,point.get('scene',{}))
        timeline=artifact(root,point.get('timeline',{}))
        actual_timeline=json.loads(timeline.read_text(encoding='utf-8'))
        if scene.read_bytes()!=restored['before_scene'].read_bytes() or actual_timeline!=before or event['response']!=actual_timeline:
            raise ValueError('individual preview checkpoint changed source or differs from actual timeline call')
        points[label]=event['execution_ns']
    if not points['before_preview']<origin['execution_ns']<points['after_preview']:
        raise ValueError('source checkpoints do not immediately bracket actual preview call')
    preview_calls=[event for event in public_events if event.get('operation')=='animation_inspect.preview']
    dry=[event for event in preview_calls if event['params']==dict(params,dry_run=True) and points['before_dry']<event['execution_ns']<points['after_dry']]
    invalid=[event for event in preview_calls if event['params'].get('animation_name')!=params.get('animation_name') and all(event['params'].get(key)==value for key,value in params.items() if key!='animation_name') and points['after_dry']<event['execution_ns']<points['before_preview']]
    overwrite=[event for event in preview_calls if event['params']==params and points['after_preview']<event['execution_ns']<points['after_overwrite_refusal']]
    if not all(any(typed_error(event.get('response')) for event in values) for values in (dry,invalid,overwrite)):
        raise ValueError('preview lacks actually bracketed typed dry/missing/overwrite refusals')
    artifacts=[{'path':report_path.relative_to(root).as_posix(),'sha256':digest(report_path),'role':'rendered_preview_result'}]
    artifacts += [dict(value,role='rendered_preview_image') for value in rows]
    artifacts += [dict(value,role='preview_source_restoration') for value in restore.values()]
    artifacts += [dict(value,role='preview_runtime_log') for value in logs]
    artifacts += [dict(point[key],role='preview_source_checkpoint') for point in checkpoints.values() for key in ('scene','timeline')]
    return {'public_case_id':origin['id'],'checks':{'valid_effect':'pass','file_effect':'pass',
             'source_unchanged':'pass','typed_errors':'pass','reported_errors':'pass'},
            'artifacts':artifacts,'limits':'Actual rendered PNG/output/restoration checks; independent visual assessment remains pending.'}


def verify_preview_bundle(directory):
    """Pure downloaded-artifact verification; caller enforces required matrix/source."""
    from operation_case_collector import operation_key
    directory=Path(directory).resolve()
    context_path=directory/'context.json'
    context=json.loads(context_path.read_text(encoding='utf-8'))
    if context.get('schema_version')!=1 or context.get('kind')!='operation_trace_context':
        raise ValueError('preview bundle has no actual trace context')
    context_sha=digest(context_path)
    events=[];seen=set()
    files=sorted((directory/'traces').glob('*.jsonl'))
    if not files:raise ValueError('preview bundle lacks raw public traces')
    for path in files:
        if not path.resolve().is_relative_to(directory):raise ValueError('preview trace escaped bundle')
        sequence=0
        for line in path.read_text(encoding='utf-8').splitlines():
            event=json.loads(line)
            if event.get('kind')!='public_operation_call' or event.get('route')!='public_godot_ai' or event.get('context_sha256')!=context_sha or event.get('run_id')!=context.get('run_id'):
                raise ValueError('preview trace is foreign or not an actual public call')
            if event.get('id') in seen or event.get('sequence')!=sequence+1:
                raise ValueError('preview trace duplicate/out-of-order identity')
            sequence+=1;seen.add(event['id'])
            operation,_=operation_key(event.get('public_tool',''),event.get('request',{}))
            if operation!=event.get('operation'):raise ValueError('preview trace operation differs from actual request')
            events.append(event)
    return {'context':context,'proof':validate_preview(directory/'rendered-preview.json',context_path,context,events)}
