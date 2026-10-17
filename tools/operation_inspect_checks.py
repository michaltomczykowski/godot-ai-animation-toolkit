"""Strict fixed-fixture read assertions; no live pose or engine-log inference."""
import math
from operation_snapshot_checks import equivalent, successful, error_code

ERROR_CODES = dict(describe='NODE_NOT_FOUND', timeline='INVALID_PARAMS', audit='NODE_NOT_FOUND',
                   compare='INVALID_PARAMS', stats='NODE_NOT_FOUND', motion_report='INVALID_PARAMS',
                   dry_run='INVALID_PARAMS', help='VALUE_OUT_OF_RANGE')
EDIT_OPS = 'retime retarget reverse mirror offset ease_range set_interp trim split_at merge amplitude loop key_edit cleanup smooth resample reduce add_noise overlap layer'.split()
SCENE = 'res://repair_edit_fixture.tscn'
PLAYER = '/RepairGraphFixture/AnimationPlayer'
DEPENDENCIES = ('tools/mcp_inspect_audit.py', 'tools/operation_inspect_checks.py',
    'tools/operation_snapshot_checks.py', 'test_project/repair_edit_fixture.tscn',
    'addons/godot_ai_animation/handlers/inspect.gd',
    'addons/godot_ai_animation/handlers/edit.gd',
    'addons/godot_ai_animation/spec/quality_modifiers.gd',
    'addons/godot_ai_animation/spec/clip_spec.gd',
    'addons/godot_ai_animation/handlers/animation_tool_base.gd',
    'addons/godot_ai_animation/utils/error_codes.gd',
    'addons/godot_ai_animation/registry/op_registry.gd')


def walk(value):
    if not successful(value) or value.get('key_count') != 2:return False
    tracks=value.get('tracks', [])
    if len(tracks)!=1:return False
    keys=tracks[0].get('keys', [])
    return (tracks[0].get('path')=='Character:position' and len(keys)==2
            and keys[0].get('value',{}).get('x')==0
            and keys[1].get('value',{}).get('x')==100)


def effect(op,r):
    if not successful(r):return False
    if op=='describe':
        clips=r.get('clips',[])
        if r.get('clip_count')!=1 or len(clips)!=1:return False
        clip=clips[0];tracks=clip.get('tracks',[])
        return (clip.get('name')=='walk' and clip.get('length')==1.0
                and clip.get('track_count')==1 and clip.get('key_count')==2
                and len(tracks)==1 and tracks[0].get('path')=='Character:position'
                and tracks[0].get('type')=='value' and tracks[0].get('keys')==2)
    if op=='timeline':return walk(r)
    if op=='audit':return r.get('players_scanned')==1 and r.get('clips_scanned')==5
    if op=='compare':
        changed=r.get('changed_tracks',[])
        return (r.get('identical') is False and len(changed)==1
                and changed[0].get('path')=='Character:position'
                and changed[0].get('key_count_a')==2 and changed[0].get('key_count_b')==2
                and changed[0].get('changed_keys')==1 and changed[0].get('max_delta')==100)
    if op=='stats':return r.get('totals',{}).get('key_count')==12
    if op=='motion_report':
        gap=r.get('worst_seam_gap')
        return type(gap) in (float,int) and math.isfinite(gap) and math.isclose(gap,100.0,rel_tol=0.0,abs_tol=1e-5)
    if op=='dry_run':return r.get('dry_run') is True and r.get('length_before')==1 and r.get('length_after')==0.5
    if op=='help':return r.get('tool_count')==1 and len(r.get('tools',[]))==1 and len(r['tools'][0].get('ops',[]))==20 and sorted(x.get('name','') for x in r['tools'][0]['ops'])==sorted(EDIT_OPS)
    return False


def derive(row):
    op=row.get('op');ok=op in ERROR_CODES
    return {'valid_effect':'pass' if ok and effect(op,row.get('result',{})) else 'fail',
            'source_unchanged':'pending' if walk(row.get('before',{})) and equivalent(row.get('before'),row.get('after')) else 'fail',
            'typed_errors':'pass' if ok and error_code(row.get('typed_error'))==ERROR_CODES[op] else 'fail'}


def verify_event(event,context,public_events,scene_events):
    row=event.get('row',{});op=row.get('op');key='animation_inspect.'+str(op)
    if event.get('validator')!='inspect_read_v1' or event.get('driver')!='mcp_inspect_audit.py' or any(p not in context.get('dependencies',{}) for p in DEPENDENCIES):raise ValueError('inspect evidence lacks source-bound dependencies')
    if op not in ERROR_CODES or event.get('operation')!=key or row.get('scene')!=SCENE:raise ValueError('inspect operation/scene mismatch')
    # Exact requests are independently imported from the committed producer, not supplied by a row.
    from mcp_inspect_audit import CASES, ERROR_CASES
    request={'op':op,**CASES[op]};bad={'op':op,**ERROR_CASES[op]}
    if row.get('request')!=request or row.get('error_request')!=bad:raise ValueError('inspect request mismatch')
    def find(operation,params,response):
        matches=[e for e in public_events if e.get('operation')==operation and e.get('public_tool')=='custom_animation_inspect' and e.get('route')=='public_godot_ai' and e.get('scene')==SCENE and equivalent(e.get('params'),params) and equivalent(e.get('response'),response) and e['execution_ns']<event['execution_ns']]
        if not matches:raise ValueError('inspect missing exact public call')
        return max(matches,key=lambda e:e['execution_ns'])
    read=find(key,request,row.get('result'));refusal=find(key,bad,row.get('typed_error'))
    probe={'op':'timeline','player_path':PLAYER,'animation_name':'walk'}
    after=find('animation_inspect.timeline',probe,row.get('after'))
    if op=='timeline':
        earlier=[e for e in public_events if e.get('operation')==key and e.get('scene')==SCENE and e.get('params')==request and equivalent(e.get('response'),row.get('result')) and e['execution_ns']<after['execution_ns']]
        if not earlier:raise ValueError('inspect missing timeline read before after probe')
        read=max(earlier,key=lambda e:e['execution_ns'])
    before_candidates=[e for e in public_events if e.get('operation')=='animation_inspect.timeline' and e.get('scene')==SCENE and e.get('params')==probe and equivalent(e.get('response'),row.get('before')) and e['execution_ns']<read['execution_ns']]
    if not before_candidates:raise ValueError('inspect missing baseline public call')
    before=min(before_candidates,key=lambda e:e['execution_ns'])
    opens=[e for e in scene_events if e.get('public_tool')=='scene_open' and e.get('request')=={'path':SCENE,'force_reload':True} and equivalent(e.get('response'),row.get('open')) and successful(e.get('response')) and e['execution_ns']<before['execution_ns']]
    if not opens or not read['execution_ns']<after['execution_ns']<refusal['execution_ns']:raise ValueError('inspect source call order mismatch')
    checks=derive(row)
    if event.get('checks')!=checks:raise ValueError('inspect declared checks mismatch')
    return {'checks':checks,'public_case_ids':[read['id'],refusal['id'],before['id'],after['id'],max(opens,key=lambda e:e['execution_ns'])['id']], 'dry_case_ids':[], 'failures':[],
            'observations':{'walk_timeline_equal':walk(row.get('before',{})) and equivalent(row.get('before'),row.get('after'))},
            'limits':'source_unchanged remains pending because all-clip/live pose/Player/invalid-call invariance is unobserved. Fixed authored 2D fixture response predicates and walk timeline equality only. Live pose/history/file invariance and complete engine reported_errors remain pending; no visual/playback claim.'}
