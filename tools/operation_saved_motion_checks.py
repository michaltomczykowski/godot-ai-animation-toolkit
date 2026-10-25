"""Bounded default locomotion proof from existing native world-space audits."""
import math
from pathlib import PurePosixPath

LIMITS = 'Default noninert locomotion and both-foot support/swing/grounding only; no exact default speed, all-parameter, visual or other-motion qualification.'
DEPS = ('tools/mcp_motion_remaining_cycles.py', 'tools/mcp_motion_audit_saved.py',
        'tools/motion_saved_observer.py', 'tools/operation_saved_motion_checks.py',
        'addons/godot_ai_animation/handlers/motion.gd',
        'addons/godot_ai_animation/handlers/inspect.gd',
        'addons/godot_ai_animation/spec/rig_analysis.gd')

def number(value):
    return type(value) in (int, float) and math.isfinite(value)

def require(condition, message):
    if not condition: raise ValueError(message)

def derive(row):
    saved = row['saved']; request = saved['request']; observed = row['audit_response']; params = row['audit_request']
    op = request['op']
    if op not in ('walk_cycle', 'run_cycle', 'cycle') or (op=='cycle' and request.get('preset')!='walk') or 'speed' in request:
        return {}
    require(request.get('root_motion') is True, 'default locomotion requires translating recipe')
    require(params.get('samples') in (31,61,121) and observed.get('sample_count')==params['samples'], 'sample clock mismatch')
    require(params.get('max_slide')==.016 and number(observed.get('length')) and observed['length']>0, 'audit configuration mismatch')
    require(params.get('motion_kind')==('run' if op=='run_cycle' else 'gait'), 'wrong audit branch')
    require(observed.get('motion_kind')==params['motion_kind'] and observed.get('loop_mode')=='linear', 'wrong observed branch/loop')
    require(number(observed.get('body_travel')) and observed['body_travel']>.1, 'inert default locomotion')
    require(observed.get('in_place') is False, 'unexpected in-place audit')
    hips=observed.get('hips',{}).get('trace',[])
    require(len(hips)==params['samples'] and all(isinstance(v,list) and len(v)==3 and all(number(x) for x in v) for v in hips), 'invalid hip samples')
    require(math.dist(hips[0],hips[-1])>.1, 'inert observed hip displacement')
    checks = observed.get('checks'); require(isinstance(checks,list), 'missing raw checks')
    names = ['hip_bob']+[stem+'.'+side for side in ('l','r') for stem in ('foot_slide','ground_penetration','knee_pole_flip')]
    if op=='run_cycle': names += ['run_flight','run_leg_extension']
    require(len(checks)==len(names) and {c.get('check') for c in checks}==set(names), 'missing/duplicate/foreign raw check')
    by = {c['check']:c for c in checks}
    for name in names:
        c=by[name]; require(number(c.get('value')) and number(c.get('budget')), 'nonfinite check')
        require(c.get('passed') is True, 'reported raw failure')
        if name=='run_flight': require(c['value']>=c['budget'], 'flight clearance failed')
        else: require(c['value']<=c['budget'], 'raw numeric limit failed')
    require(by['hip_bob']['budget']==.12, 'changed bob budget')
    feet=observed.get('feet',{}); require(set(feet)=={'l','r'}, 'missing feet')
    support=observed.get('support',{}).get('trace',[])
    require(len(support)==params['samples'], 'missing support samples')
    for side in ('l','r'):
        foot=feet[side]; trace=foot.get('trace',[])
        require(len(trace)==params['samples'] and all(isinstance(v,list) and len(v)==3 and all(number(x) for x in v) for v in trace), 'invalid foot samples')
        require(any(v!=trace[0] for v in trace[1:]), 'inert foot')
        require(number(foot.get('contact_time')) and foot['contact_time']>0, 'missing contact')
        states=[v.get('state') for v in support]
        require(all(v in ('l','r','both','flight') for v in states), 'invalid support state')
        require(any(v in (side,'both') for v in states) and any(v not in (side,'both') for v in states), 'missing foot support/swing')
        require(by['foot_slide.'+side]['budget']==.016, 'changed slide budget')
        require(by['knee_pole_flip.'+side]['budget']==0, 'changed knee budget')
        budget=foot.get('penetration_budget')
        require(number(budget) and budget>0 and by['ground_penetration.'+side]['budget']==budget, 'penetration policy mismatch')
        require(foot.get('max_penetration')==by['ground_penetration.'+side]['value'] and foot.get('worst_slide')==by['foot_slide.'+side]['value'], 'raw foot/check mismatch')
    if op=='run_cycle':
        flight=observed.get('flight',{})
        require(number(flight.get('airborne_fraction')) and flight['airborne_fraction']>=.05, 'missing run flight fraction')
        require(number(flight.get('clearance_budget')) and flight['clearance_budget']>0 and by['run_flight']['budget']==flight['clearance_budget'], 'run clearance policy mismatch')
        require(by['run_flight']['value']==flight.get('peak_both_feet_clearance'), 'flight raw mismatch')
        require(by['run_leg_extension']['budget']==.985 and by['run_leg_extension']['value']==flight.get('peak_leg_extension_ratio'), 'run reach policy mismatch')
    require(observed.get('passed') is True and observed.get('failed_checks')==0, 'audit failed')
    return {'valid_effect':'pass'}

def verify_event(event, context, public_events, support_events, snapshot_events):
    row=event['row']; saved=row['saved']; request=saved['request']; operation='animation_motion.'+request['op']
    require(event.get('operation')==operation and event.get('validator')=='motion_saved_audit_v1', 'wrong observer operation')
    for dep in DEPS: require(dep in context['dependencies'], 'missing dependency '+dep)
    require(saved.get('context_sha256')==event['context_sha256'], 'foreign saved context')
    digest=saved.get('scene_sha256'); require(isinstance(digest,str) and len(digest)==64 and all(c in '0123456789abcdef' for c in digest), 'invalid saved digest')
    require(digest==row.get('before_sha256')==row.get('after_sha256'), 'saved bytes changed')
    save_rows=[v for v in snapshot_events if v.get('id')==saved.get('save_witness_id')]
    require(len(save_rows)==1, 'missing saved witness')
    witness=save_rows[0]; expected=dict(saved); expected.pop('save_witness_id')
    require(witness.get('validator')=='motion_saved_file_v1' and witness.get('row')==expected and witness.get('driver')=='mcp_motion_remaining_cycles.py', 'wrong saved witness')
    require(event.get('driver')=='mcp_motion_audit_saved.py', 'wrong audit driver')
    scene=saved['scene']
    for command, driver in ((saved.get('save_command'),'mcp_motion_remaining_cycles.py'),(row.get('audit_command'),'mcp_motion_audit_saved.py')):
        require(isinstance(command,list) and len(command)>1 and all(isinstance(v,str) for v in command) and PurePosixPath(command[1].replace('\\','/')).name==driver, 'wrong observer command')
    command=row['audit_command']; require('--run-id' in command and command.index('--run-id')+1<len(command) and command[command.index('--run-id')+1]==scene.split('/')[-2], 'wrong audit command run ID')
    def exact(rows, predicate, message):
        found=[v for v in rows if predicate(v)]; require(len(found)==1,message); return found[0]
    generation=exact(public_events,lambda v: v.get('driver')=='mcp_motion_remaining_cycles.py' and v.get('operation')==operation and v.get('scene')==scene and v.get('request')==request and not v.get('response',{}).get('error'),'generation binding ambiguous')
    save=exact(support_events,lambda v: v.get('driver')=='mcp_motion_remaining_cycles.py' and v.get('public_tool')=='scene_save' and v.get('scene')==scene and v.get('response')==saved['save_response'],'save binding ambiguous')
    opened=exact(support_events,lambda v: v.get('driver')=='mcp_motion_audit_saved.py' and v.get('public_tool')=='scene_open' and v.get('request')=={'path':scene,'force_reload':True} and v.get('response')==row['opened'] and witness['time_ns']<v['time_ns']<event['time_ns'],'forced disk open binding ambiguous')
    require(row['opened'].get('reloaded_from_disk') is True and not row['opened'].get('error'), 'not disk reopened')
    audit=exact(public_events,lambda v: v.get('driver')=='mcp_motion_audit_saved.py' and v.get('operation')=='animation_inspect.motion_audit' and v.get('scene')==scene and v.get('request')==row['audit_request'] and v.get('response')==row['audit_response'] and opened['time_ns']<v['time_ns']<event['time_ns'],'audit binding ambiguous')
    require(generation['time_ns']<save['time_ns']<witness['time_ns']<opened['time_ns']<audit['time_ns'], 'invalid witness order')
    require(not any(v.get('scene')==scene and save['time_ns']<v['time_ns']<audit['time_ns'] and not v.get('operation','').startswith('animation_inspect.') and not v.get('request',{}).get('dry_run') and not v.get('response',{}).get('error') for v in public_events), 'intervening successful writer')
    for key in ('player_path','skeleton_path','animation_name'): require(request[key]==row['audit_request'][key]==row['audit_response'][key], 'target mismatch')
    return dict(checks=derive(row), public_case_ids=[generation['id'],audit['id']], dry_case_ids=[], failures=[], limits=LIMITS)
