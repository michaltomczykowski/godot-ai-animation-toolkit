"""Offline strict saved-setup schedule/trace validation, without image approval."""
import math


def validate(schedule, report, expected_schedule_sha256):
    recording=schedule['recording']
    if recording['contract']!='saved_setup_v1' or recording['fps']!=60 or recording['size']!=[1920,1080]: return False
    if not isinstance(report.get('engine_errors'),list) or report['engine_errors'] or report.get('passed') is not True: return False
    if report.get('schedule_sha256')!=expected_schedule_sha256: return False
    for key in ('renderer_sha256','checker_loader_sha256','runtime_sha256'):
        if not isinstance(report.get(key),str) or len(report[key])!=64: return False
    expected=[(row,take) for row in schedule['cases'] for take in (1,2)]
    if len(expected)!=8 or len({row['id'] for row in schedule['cases']})!=4 or len(report.get('cases',[]))!=8: return False
    total=0
    for (row,take),actual in zip(expected,report['cases']):
        frames=row['render_spec']['frames_per_take']
        if type(frames) is not int or frames<180: return False
        if (actual.get('id'),actual.get('take'),actual.get('scene_sha256'))!=(row['id'],take,row['scene_sha256']): return False
        if actual.get('frames')!=frames or len(actual.get('trace',[]))!=frames or actual.get('prime_signals')!=[1,1]: return False
        for frame,samples in enumerate(actual['trace']):
            if len(samples)!=2: return False
            for view,sample in zip(('front','side'),samples):
                if (sample.get('id'),sample.get('take'),sample.get('view'),sample.get('frame'))!=(row['id'],take,view,frame): return False
                if not math.isclose(sample.get('time_s',-1),(frame+1)/60,abs_tol=1e-12): return False
                if sample.get('signals')!=frame+2: return False
                before=sample.get('skin_updates_before');after=sample.get('skin_updates_after_draw')
                if type(before) is not int or type(after) is not int or after<=before: return False
                proof=sample.get('framing',{})
                if proof.get('passed') is not True or proof.get('behind')!=0 or proof.get('bone_count',0)<=0: return False
                low=proof.get('minimum_px',[]);high=proof.get('maximum_px',[])
                if len(low)!=2 or len(high)!=2 or any(not math.isfinite(v) for v in low+high): return False
                if min(low)<20 or high[0]>932 or high[1]>880: return False
        total+=frames
    return report.get('frames')==total and report.get('fps')==60 and report.get('size')==[1920,1080]
