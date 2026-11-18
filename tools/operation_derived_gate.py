"""Fail explicit derived contract failures; intentional invocation refusals are separate."""
def derived_failures(report):
    if not isinstance(report,dict) or not isinstance(report.get('cases'),list):raise ValueError('operation report cases must be a list')
    failures=[]
    for case in report['cases']:
        if not isinstance(case,dict) or not isinstance(case.get('checks'),dict):raise ValueError('operation case checks must be a dictionary')
        for check,status in case['checks'].items():
            if not isinstance(check,str) or not isinstance(status,str):raise ValueError('operation check/status must be strings')
            if check!='mcp_invocation' and status=='fail':
                failures.append({'id':case.get('id'),'operation':case.get('operation'),'check':check})
    return failures
