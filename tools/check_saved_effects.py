"""Check narrow native FX observations; does not certify visual or audio quality."""
from __future__ import annotations
import argparse
import json
import math
import re
from pathlib import Path
import struct
from saved_effect_contracts import is_nearest_hold

CAPTURE_SIZE = [1400, 800]

def capture_failures(report, frames_dir=None, expected_frames=None):
    failures = []
    geometry = report.get('capture_geometry', {})
    if report.get('startup_capture') != {'viewport_width':1400,'viewport_height':800,'stretch_mode':'viewport','stretch_aspect':'keep'}:
        failures.append('missing or wrong pre-startup Movie Maker viewport settings')
    if (geometry.get('logical_size') != CAPTURE_SIZE or geometry.get('render_size') != CAPTURE_SIZE
            or geometry.get('content_scale_mode') != 2 or geometry.get('content_scale_aspect') != 1):
        failures.append('missing or cropped fixed logical/render viewport contract')
    window = geometry.get('window_size', [])
    if len(window) != 2 or any(not isinstance(v,int) or v <= 0 for v in window):
        failures.append('actual physical window dimensions missing')
    if frames_dir is not None:
        paths = sorted(Path(frames_dir).glob('*.png'))
        if len(paths) != expected_frames:
            failures.append(f'capture PNG count {len(paths)} != {expected_frames}')
        invalid=[]
        for path in paths:
            with path.open('rb') as stream: header = stream.read(24)
            if (len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR'
                    or list(struct.unpack('>II',header[16:24])) != CAPTURE_SIZE):
                invalid.append(path.name)
        if invalid:
            failures.append(f'cropped/invalid PNG dimensions: {len(invalid)} frame(s); first: '+', '.join(invalid[:5]))
    return failures

# Independent history-case inputs, not values extracted from output animation keys.
ENDPOINTS = {'damage_bar': ('DamageBar', 'value', 30),
             'progress_fill': ('FillBar', 'value', 100),
             'counter': ('ScoreLabel', 'text', 100)}
TARGETS = {'shake':'Camera2D','zoom_punch':'Camera2D','hit_flash':'Flash',
           'damage_bar':'DamageBar','typewriter':'TypeLabel','progress_fill':'FillBar',
           'counter':'ScoreLabel','dialog_pop':'DialogPanel','transition':'FadeOverlay',
           'wave':'Card1','spring':'SpringTarget','pendulum':'PendulumTarget',
           'path_follow':'Drone','flipbook':'Sprite2D','sprite_frames':'SheetSprite',
           'audio_cue':'CuePlayer'}

def player_clock_failures(case, samples):
    if case['operation']=='animation_fx.sprite_frames': return []
    selected=case.get('playbacks',[{'player':case.get('player','AnimationPlayer'),'redo_clip':case.get('clip','generated')}])
    failures=[]
    for take in (1,2):
        rows=[row for row in samples if row.get('take')==take]
        for playback in selected:
            path=playback['player']
            clocks=[row.get('players',[{},{}])[1].get(path,{}) for row in rows if len(row.get('players',[]))==2]
            valid=(bool(rows) and len(clocks)==len(rows) and all(clock.get('active') is True
                and clock.get('callback_mode_process')==1 and clock.get('assigned_animation')==playback['redo_clip']
                for clock in clocks) and max((clock.get('position',0) for clock in clocks),default=0)>0)
            if not valid: failures.append(f'take {take}: selected redo player {path} lacks active idle native clock/progression')
    return failures

def check(case, report):
    failures = capture_failures(report)
    if case.get('operation')=='animation_edit.set_interp' and case.get('variant')=='set_interp' and not case.get('require_progression',True) and not is_nearest_hold(case):
        failures.append('held nearest representative lacks its exact contract')
    if report.get('operation') != case['operation'] or report.get('case_id') != case['id']:
        failures.append('operation/case mismatch')
    if report.get('scenes') != case['scenes'] or report.get('dependencies_verified') != case['dependencies']:
        failures.append('scene/dependency identity mismatch')
    op = case['operation'].split('.')[-1]
    target = TARGETS.get(op) if case['operation'].startswith('animation_fx.') else None
    failures.extend(report.get('runtime_failures', []))
    errors = report.get('engine_errors')
    if not isinstance(errors, list) or errors:
        failures.append('engine errors present or engine-error capture missing')
    if case['operation'] in ('animation_fx.shake', 'animation_fx.zoom_punch'):
        if report.get('camera_presentation') != 'native_camera_static_calibration_grid':
            failures.append('camera effect was not presented through its native camera and calibration grid')
        cameras = report.get('native_camera_states', [])
        if len(cameras) != 2 or not all(c.get('enabled') is True and c.get('current') is True for c in cameras):
            failures.append('both independent native cameras must be enabled and current')

    samples = report.get('samples', [])
    failures.extend(player_clock_failures(case,samples))
    if report.get('header_rect') != [12,8,1376,170]:
        failures.append('fixed header/body separation missing')
    expected_transform=[.55,0,0,.55,0,100] if case.get('display_mode')=='showcase' else [1,0,0,1,250,260]
    presentation_failures=0
    for sample in samples:
        panes=sample.get('presentation',[])
        if len(panes)!=2:
            presentation_failures+=1
            continue
        for index,pane in enumerate(panes):
            actual=pane.get('canvas_transform',[])
            if case.get('audio_output_required') and (pane.get('audio_listener_2d') is not True or pane.get('audio_listener_3d') is not True):
                presentation_failures+=1
            if pane.get('body_rect') != [index*700,190,700,610]:
                presentation_failures+=1
            if case['operation'] not in ('animation_fx.shake','animation_fx.zoom_punch'):
                if len(actual)!=6 or any(not isinstance(a,(int,float)) or not math.isfinite(a) or abs(a-b)>.00001 for a,b in zip(actual,expected_transform)):
                    presentation_failures+=1
    if presentation_failures:
        failures.append(f'invalid/missing fixed pane presentation in {presentation_failures} observations')
    expected_frames = case['fps'] * case['seconds']
    if len(samples) < expected_frames - 2 or report.get('frames', 0) < expected_frames - 2:
        failures.append('incomplete fixed-FPS temporal samples')
    if report.get('max_delta_error', 1) > 0.00001:
        failures.append('native clock was not fixed at requested FPS')
    if any(s.get('frame') != i + 1 for i, s in enumerate(samples)):
        failures.append('missing/duplicate/out-of-order frame sample')
    if any(abs(s.get('time', 0) - (i + 1) / case['fps']) > 0.002 for i, s in enumerate(samples)):
        failures.append('sample clock does not match native fixed FPS')
    checks = {}
    for take in (1, 2):
        rows = [s for s in samples if s.get('take') == take]
        if len(rows) < case['fps'] * case['take_seconds'] - 2:
            failures.append(f'take {take}: incomplete')
            continue
        if any(len(r.get('states', [])) != 2 for r in rows):
            failures.append(f'take {take}: missing independently played clone')
            continue
        redo = [r['states'][1].get(target, {}) if target else r['states'][1] for r in rows]
        undo = [r['states'][0].get(target, {}) if target else r['states'][0] for r in rows]
        if not all(redo) or not all(undo):
            failures.append(f'take {take}: missing target state')
            continue
        changed = len({json.dumps(s, sort_keys=True) for s in redo}) > 1
        different = any(a != b for a, b in zip(redo, undo))
        if not changed and case.get('require_progression', True):
            failures.append(f'take {take}: intended target never progressed')
        if not different and case.get('require_visible_difference', True):
            failures.append(f'take {take}: no changed effect relative to undo')
        checks[f'take_{take}_target_progression'] = 'pass' if changed else 'not_applicable' if not case.get('require_progression', True) else 'fail'
        checks[f'take_{take}_changed_effect'] = 'pass' if different else 'not_applicable' if not case.get('require_visible_difference', True) else 'fail'
        if is_nearest_hold(case):
            contracts=report.get('playback_contracts',[])
            valid=True
            for state,interpolation in [('undo',1),('redo',0)]:
                clips=[clip for clip in contracts if clip.get('state')==state and clip.get('player')=='AnimationPlayer']
                track=next((track for clip in clips for track in clip.get('tracks',[]) if track.get('path')=='Character:position'),{})
                keys=track.get('keys',[])
                valid=valid and len(clips)==1 and clips[0].get('length')==1.0 and clips[0].get('loop_mode')==1 and track.get('type')==0 and track.get('enabled') is True and track.get('interpolation')==interpolation and len(keys)==2
                valid=valid and len(keys)==2 and keys[0].get('time')==0.0 and keys[1].get('time')==1.0 and matches(keys[0].get('value'),'position:x',0) and matches(keys[1].get('value'),'position:x',100)
            held=all(matches(state.get('Character',{}).get('position'),'position:x',0) for state in redo)
            reference_moved=len({json.dumps(state,sort_keys=True) for state in undo})>1
            undo_clock=all(len(row.get('players',[]))==2 and row['players'][0].get('AnimationPlayer',{}).get('active') is True and row['players'][0].get('AnimationPlayer',{}).get('callback_mode_process')==1 for row in rows)
            okay=valid and held and reference_moved and undo_clock and different
            checks[f'take_{take}_held_nearest_output']='pass' if okay else 'fail'
            if not okay: failures.append(f'take {take}: nearest held output/reference/actual track metadata mismatch')
        if op in ENDPOINTS:
            node, prop, expected = ENDPOINTS[op]
            try:
                actual = float(rows[-1]['states'][1][node][prop])
                okay = abs(actual - expected) < 0.05
            except (ValueError, KeyError, TypeError):
                okay = False
            checks[f'take_{take}_independent_endpoint'] = 'pass' if okay else 'fail'
            if not okay:
                failures.append(f'take {take}: independent endpoint expected {expected}')
        if op in ('flipbook', 'sprite_frames'):
            frames = {s.get('frame') for s in redo}
            okay = {'0', '1', '2', '3'} <= frames
            checks[f'take_{take}_four_native_cells'] = 'pass' if okay else 'fail'
            if not okay:
                failures.append(f'take {take}: did not observe all four native cells')
        if not target:
            for n, expected in enumerate(expected_samples(case)):
                at, node, prop, value = expected
                candidates = [r for r in rows if 'AnimationPlayer' in r.get('players', [{},{}])[1]]
                best = min(candidates, key=lambda r: abs(r['players'][1]['AnimationPlayer']['position'] - at)) if candidates else None
                actual_time = best['players'][1]['AnimationPlayer']['position'] if best else -1
                actual = best['states'][1].get(node, {}).get(prop.split(':')[0]) if best else None
                okay = abs(actual_time - at) < 0.002 and matches(actual, prop, value)
                checks[f'take_{take}_independent_sample_{n}'] = 'pass' if okay else 'fail'
                if not okay:
                    failures.append(f'take {take}: {node}:{prop} at native {at}: expected {value}, got {actual} at {actual_time}')
    return {'schema_version': 1, 'operation': case['operation'], 'case_id': case['id'],
            'checks': checks, 'failures': failures, 'native_observation_pass': not failures,
            'semantic_endpoints': 'checked' if op in ENDPOINTS else 'not_comprehensive',
            'visual_assessment': 'pending', 'audio_output': 'pending' if op == 'audio_cue' else 'not_applicable',
            'qualification': 'pending', 'human_review': 'waived_not_approved'}

# Independent historical saved-playback expectations. These are not read from
# output animation keys and are checked against native mixer position, not an
# assumed frame-to-player ordering. Original reference scripts remain preserved.
EDIT_EXPECTED = {
 'retime':[(.25,'Character','position:x',50)],
 'reverse':[(.25,'Character','position:x',75)],
 'mirror':[(.5,'Character','position:x',-50)],
 'trim':[(.3,'Character','position:x',50)],
 'amplitude':[(.5,'Character','position:x',25)],
 'resample':[(.25,'Character','position:x',25),(.75,'Character','position:x',75)],
 'reduce':[(.25,'Character','position:x',25),(.75,'Character','position:x',75)],
 'loop':[(.25,'Character','position:x',25),(.75,'Character','position:x',75)],
 'layer':[(.5,'Character','position:x',90)],
 'offset':[(.5,'Character','position:x',30)],
 'key_edit':[(.5,'Character','position:x',15)],
 'overlap':[(.5,'Character','position:x',40)],
 'retarget':[(.5,'OtherCharacter','position:x',50),(.5,'Character','position:x',0)],
 'ease_range':[(.25,'Character','position:x',6.25),(.5,'Character','position:x',25)],
 'set_interp':[(.75,'Character','position:x',0)],
 'split_at':[(.25,'Character','position:x',75)],
 'split_head':[(.25,'Character','position:x',25)],
 'merge':[(.5,'Character','position:x',50),(1.5,'Character','position:x',100)],
 'cleanup':[(.5,'Character','position:x',0)],
 'smooth':[(.5,'Character','position:y',-40)],
 # Exact t0 noise keys need a separate pre-advance native sample, intentionally
 # not inferred from a later frame. General trajectory review stays applicable.
 'add_noise':[],
}
PRESET_EXPECTED = {
 'pulse':[(.5,'Target3D','scale',[1.4,1.4,1.4])],
 'bounce':[(.35,'Widget','scale',[2.4,2.4])],
 'template_preset':[(.35,'Widget','scale',[2.4,2.4])],
 'orbit':[(.25,'Target3D','position',[2,3,6])],
 'sweep':[(.25,'Widget','rotation',math.pi/2)],
 'drift':[(.5,'Target3D','position',[4,3,4])],
 'spin':[(.25,'Target3D','quaternion',[0,math.sqrt(.5),0,math.sqrt(.5)])],
 'float':[(.5,'Target3D','position',[2,4,4]),(.5,'Target3D','scale',[1.25,1.25,1.25])],
 'stagger':[(.5,'Widget','modulate:a',.75),(.5,'OtherWidget','modulate:a',.51)],
 'template_fx':[(.5,'Widget','modulate',[1,0,0,1])],
 'spec_apply':[(.5,'Widget','position:x',20)],
 'showcase':[],
}

def expected_samples(case):
    table = EDIT_EXPECTED if case['operation'].startswith('animation_edit.') else PRESET_EXPECTED
    return table[case['variant']]

def matches(actual, prop, expected):
    if actual is None:
        return False
    try:
        values = [float(v) for v in re.findall(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', str(actual))]
        if ':' in prop:
            axis = prop.split(':')[1]
            index = {'x':0,'y':1,'z':2,'a':3}[axis]
            values = [values[index]]
        expected = expected if isinstance(expected,list) else [expected]
        if prop == 'quaternion':
            return len(values) == 4 and abs(abs(sum(a*b for a,b in zip(values,expected)))-1) < .002
        return len(values) == len(expected) and all(abs(a-b)<.02 for a,b in zip(values,expected))
    except (ValueError, IndexError):
        return False

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan', type=Path, required=True)
    p.add_argument('--case', type=int, required=True)
    p.add_argument('--observations', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--frames-dir', type=Path, required=True, help='Actual Movie Maker PNG directory; every frame must be 1400x800')
    a = p.parse_args()
    case = json.loads(a.plan.read_text(encoding='utf-8'))['cases'][a.case]
    report = check(case, json.loads(a.observations.read_text(encoding='utf-8')))
    report['failures'].extend(capture_failures(json.loads(a.observations.read_text(encoding='utf-8')),a.frames_dir,case['fps']*case['seconds']))
    report['native_observation_pass'] = not report['failures']
    with a.output.open('x', encoding='utf-8') as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))
    return 0 if report['native_observation_pass'] else 1
if __name__ == '__main__':
    raise SystemExit(main())
