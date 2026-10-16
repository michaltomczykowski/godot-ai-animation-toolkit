"""Actual malformed-file read refusals only; no external invocation claims."""
import json
from operation_library_file_checks import same, file_bytes
TEST='test_safe_paths_and_malformed_documents_are_typed'

def derive(row):
    op=row.get('op'); request=row.get('request',{})
    if op not in {'template_list','spec_import'} or request.get('op')!=op: raise ValueError('read operation differs')
    path=request.get('library_path' if op=='template_list' else 'path')
    if path!='res://animation_toolkit/history_contracts/malformed.json': raise ValueError('unexpected fixture path')
    before=file_bytes(row.get('file_before'),path); after=file_bytes(row.get('file_after'),path)
    if before is None: raise ValueError('missing actual input bytes')
    text=before.decode('utf-8')
    try: doc=json.loads(text)
    except json.JSONDecodeError:
        if text!='{bad-json' or op!='template_list': raise ValueError('unexpected invalid JSON')
        doc=text
    # Exact authored malformed fixtures, independent of the production parser.
    recipes=['{bad-json',[],{'format':'other'},{'format':'godot-ai-animation-library','version':99,'templates':{}},{'templates':[]},{'templates':{'broken':[]}},{'templates':{'broken':{'tool':'animation_presets','op':'bounce','params':[]}}},{'templates':{'broken':{'tool':'animation_presets','op':'missing','params':{}}}}]
    clips=[{'format':'godot-ai-animation-clip','version':1,'tracks':{}},{'format':'godot-ai-animation-clip','version':1,'markers':[4],'tracks':[]},{'format':'godot-ai-animation-clip','version':1,'tracks':[{'type':0,'path':'Widget:position','keys':[4]}]}]
    if not any(same(doc,x) for x in (recipes if op=='template_list' else clips)): raise ValueError('not an exact malformed fixture')
    invariant=row.get('failed_before') is False and bool(row.get('before')) and same(row['before'],row.get('after')) and before==after and type(row.get('history_before')) is int and row.get('history_after')==row['history_before'] and type(row.get('global_before')) is int and row.get('global_after')==row['global_before']
    error=row.get('response',{}).get('error',{})
    # Library envelope validation uses INVALID_PARAMS; the three exact clip
    # fixtures violate schema field types and SpecJson returns WRONG_TYPE.
    expected_code='INVALID_PARAMS' if op=='template_list' else 'WRONG_TYPE'
    typed=isinstance(error,dict) and error.get('code')==expected_code and isinstance(error.get('message'),str) and bool(error['message'])
    clean=type(row.get('errors_before')) is int and row.get('errors_after')==row['errors_before'] and row.get('errors')==[]
    return {'typed_errors':'pass' if invariant and typed else 'fail','source_unchanged':'pass' if invariant else 'fail','reported_errors':'pass' if clean else 'fail'}

def verify_event(event,context,begins,support):
    dependencies=context.get('dependencies',{})
    for path in ('test_project/tests/test_library_contracts.gd','test_project/tests/operation_history_trace.gd',
                 'test_project/tests/test_preset_library_history.gd','test_project/tests/test_edit_route_history.gd',
                 'test_project/tests/test_fx_route_history.gd','test_project/tests/test_graph_route_history.gd',
                 'tools/mcp_presets_audit.py','tools/operation_library_file_checks.py','tools/operation_library_read_checks.py'):
        if path not in dependencies:raise ValueError('file contract source not bound: '+path)
    row=event.get('row',{})
    if event.get('driver')!='test_library_contracts.gd' or event.get('validator')!='library_read_refusal_v1' or event.get('route')!='public_test_run_inner_dispatch' or row.get('suite')!='library_contracts' or row.get('test')!=TEST or row.get('mode')!='malformed_read_refusal':
        raise ValueError('unknown library file contract source/case')
    if event.get('operation')!='animation_library.'+row.get('op','') or type(row.get('ordinal')) is not int or row['ordinal']<1 or type(row.get('assertion_count_before')) is not int or row['assertion_count_before']<0:
        raise ValueError('library file operation/case identity differs')
    token=event.get('test_run_begin_id')
    starts=[item for item in begins if item.get('id')==token]
    ends=[item for item in support if item.get('public_tool')=='test_run' and item.get('test_run_begin_id')==token]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('library case lacks unique actual public span')
    start,end=starts[0],ends[0]
    if start.get('request')!=end.get('request') or start.get('request',{}).get('suite')!='library_contracts' or start['request'].get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('library public request/order differs')
    checks=derive(row)
    actual=[item for item in end.get('response',{}).get('results',[]) if isinstance(item,dict) and item.get('suite')=='library_contracts' and item.get('test')==TEST]
    if len(actual)!=1 or actual[0].get('passed') is not True or actual[0].get('skipped',False) or type(actual[0].get('assertion_count')) is not int or actual[0]['assertion_count']<30 or actual[0]['assertion_count']<=row.get('assertion_count_before',-1):
        checks={key:'fail' for key in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],
            'limits':'Exact existing library file/read contract, embedded hashed file bytes and scene/global history invariance. No external operation invocation, scene Undo/Redo, playback or visual/audio qualification.'}
