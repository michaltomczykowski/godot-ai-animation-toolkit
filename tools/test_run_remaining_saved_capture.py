"""Offline controls. Synthetic reports are validator fixtures, never engine proof."""
from copy import deepcopy
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_remaining_saved_capture as s

INPUTS = Path('E:/GodotAI-toolkit-release-2.0.0/20261014/sequence-secondary-static-inputs-r001/manifest.json')
PRIMARY = Path('G:/godot-ai-dev/godot-ai-animation-toolkit')
WORKER = Path(__file__).resolve().parents[1]


def channel(track, t):
    # A numeric unit fixture, not a replacement for native cubic interpolation.
    keys = track['keys']
    for key in keys:
        if abs(key['time']-t) < 1e-8: return key['value']
    u, v = next((u, v) for u, v in zip(keys, keys[1:]) if u['time'] <= t <= v['time'])
    weight = (t-u['time'])/(v['time']-u['time'])
    value = [a+(b-a)*weight for a, b in zip(u['value'], v['value'])]
    if len(value) == 4:
        length = math.sqrt(sum(x*x for x in value)); value = [x/length for x in value]
    return value


def fixture(inventory, rendered=False):
    secondary = next(r for r in inventory['technical_pairs']['cases'] if r['id'] == s.IDS[0])
    tracks = s.persisted_tracks(secondary['files']['reference']['path'])
    names = s.saved_bone_names(secondary['files']['redo']['path'])
    rows = [dict(id=s.IDS[0], files=secondary['files'], params=secondary['original_row']['params'], persisted_reference_tracks=tracks, expected_bone_names={side:names for side in ('source','redo')})]
    rows += [{**deepcopy(r), 'expected_bone_names':{side:s.saved_bone_names(r['files'][side]['path']) for side in ('before','after')}} for r in inventory['static_pairs']]
    runs = []
    def state(bones_by_path, values=None):
        rigs = {}; tree = {'type':'Node', 'children':{}}
        for path, bone_names in bones_by_path.items():
            bones = [dict(name=n, parent=-1, rest={}, pose={}, enabled=True, meta={}) for n in bone_names]
            components = [dict(position=[0,0,0], rotation=[0,0,0,1], scale=[1,1,1]) for n in bone_names]
            if values:
                for track, value in zip(tracks, values):
                    components[bone_names.index(track['path'].split(':')[1])][{1:'position',2:'rotation',3:'scale'}[track['type']]] = value
            world = [dict(origin=[i*.1,0,0], basis=[[1,0,0],[0,1,0],[0,0,1]]) for i in range(len(bones))]
            rigs[path] = dict(snapshot={'bones':bones}, components=components, pose={'world':world})
            tree['children'][path] = {'bones':bones, 'children':{}}
        clocks = {'player':dict(active=bool(values), manual=True, position=0., playing=bool(values), assigned='unrelated' if values else '', speed=1.)}
        return dict(rigs=rigs, clocks=clocks, tree=tree)
    for row in rows:
        for take in (0, 1):
            if row['id'] == s.IDS[0]:
                for fps in ((60,) if rendered else (30,60,120)):
                    for side in ('reference','redo'):
                        trace = []; previous = 0.
                        for t in s.schedule(tracks, fps):
                            values = [channel(track, t) for track in tracks]
                            actual_state = state(names, values)
                            actual_state['clocks']['player']['position']=t
                            trace.append(dict(time=t, delta=t-previous, actual=values, reference=values, owners=1, root_delta=[0,0,0], state=actual_state, required={k:{'pose':v['pose']} for k,v in actual_state['rigs'].items()})); previous=t
                        runs.append(dict(id=row['id'], side=side, take=take, fps=fps, scene_sha256=row['files']['source' if side=='reference' else 'redo']['sha256'], reference_sha256=row['files']['reference']['sha256'], length=1., loop_mode=0, saved_speed_scale=.8, evaluation_speed_scale=1., tracks=tracks, reference_tracks=tracks, markers={'cue':{'time':.3,'color':'(0.8, 0.3, 0.2, 1.0)'}}, trace=trace, held_endpoint=trace[-1]['state'], hold_simulation_advances=0, failures=[]))
            else:
                for side in ('before','after'):
                    actual_state = state(row['expected_bone_names'][side]); sample=dict(time=0.,delta=0.,state=actual_state,required={k:{'pose':v['pose']} for k,v in actual_state['rigs'].items()})
                    runs.append(dict(id=row['id'],side=side,take=take,fps=0,scene_sha256=row['files'][side]['sha256'],snapshot=row['files'][side]['native_snapshot'],simulation_advances=0,trace=[sample],after_draw=actual_state,failures=[]))
    return dict(cases=rows), dict(kind='remaining_saved_native',manifest_sha256='manifest',binding_sha256='binding',rendered=rendered,passed=True,failures=[],engine_errors=[],runs=runs)


@unittest.skipUnless(INPUTS.is_file(), 'private original inputs unavailable')
class ActualShapeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory=s.read(INPUTS); cls.manifest,cls.report=fixture(cls.inventory)

    def validate(self, report):
        return s.validate(report,self.manifest,'manifest','binding')

    def test_actual_archives_public_traces_and_reference_shape(self):
        s.verify_originals(self.inventory)
        self.assertTrue(s.current_boundaries(PRIMARY,self.inventory)['secondary_operative_function']['exact'])
        row=self.manifest['cases'][0]
        self.assertEqual([t['path'] for t in row['persisted_reference_tracks']],['Skeleton:hips']*3+['Skeleton:hand_L','Skeleton:hand_R'])
        self.assertEqual(sum(len(t['keys']) for t in row['persisted_reference_tracks']),131)
        self.assertEqual(len(row['expected_bone_names']['redo']['MotionSequenceHistory/Character/Skeleton']),17)
        self.assertTrue(self.validate(self.report)['passed'])

    def test_false_pass_cannot_hide_missing_clocks_keys_or_failed_rows(self):
        for fault in ('missing','duplicate','failed','wrong_binding','time','clock','speed','hold','owner','root','key','type','nonfinite','played','bone_join','missing_bone'):
            report=deepcopy(self.report); run=report['runs'][0]
            if fault=='missing':report['runs'].pop()
            elif fault=='duplicate':report['runs'][1]=deepcopy(run)
            elif fault=='failed':run['failures']=['real native failure']
            elif fault=='wrong_binding':report['binding_sha256']='other'
            elif fault=='time':run['trace'][3]['time']+=.01
            elif fault=='clock':run['trace'][3]['state']['clocks']['player']['position']=0.
            elif fault=='speed':run['evaluation_speed_scale']=.8
            elif fault=='hold':run['hold_simulation_advances']=1
            elif fault=='owner':run['trace'][0]['owners']=2
            elif fault=='root':run['trace'][0]['root_delta'][0]=.1
            elif fault=='key':run['tracks'][3]['keys'][0]['value'][0]+=.1
            elif fault=='type':run['tracks'][0]['path']='Skeleton:wrong'
            elif fault=='nonfinite':run['trace'][0]['actual'][0][0]=float('nan')
            elif fault=='played':run['trace'][5]['actual'][0][0]+=.1
            elif fault=='bone_join':run['trace'][3]['state']['rigs']['MotionSequenceHistory/Character/Skeleton']['components'][0]['scale'][0]+=1
            elif fault=='missing_bone':run['trace'][0]['state']['rigs']['MotionSequenceHistory/Character/Skeleton']['snapshot']['bones'].pop()
            with self.subTest(fault=fault),self.assertRaises((ValueError,KeyError)):self.validate(report)

    def test_static_snapshot_and_zero_clock_are_independent_of_pass_flag(self):
        for fault in ('name','parent','rest','pose','enabled','meta','owner','time','advances','writer','draw','scene'):
            report=deepcopy(self.report);run=next(r for r in report['runs'] if r['id']==s.IDS[2] and r['side']=='after'); bone=run['snapshot']['children']['Skeleton']['bones'][-1]
            if fault=='name':bone['name']='wrong'
            elif fault=='parent':bone['parent']=-1
            elif fault=='rest':bone['rest']['origin']['x']+=1
            elif fault=='pose':bone['pose']['basis']['x']['x']+=1
            elif fault=='enabled':bone['enabled']=False
            elif fault=='meta':bone['meta']['unexpected']='bad'
            elif fault=='owner':run['snapshot']['children']['Skeleton']['owner']='wrong'
            elif fault=='time':run['trace'][0]['time']=1/60
            elif fault=='advances':run['simulation_advances']=1
            elif fault=='writer':run['trace'][0]['state']['clocks']['player']['active']=True
            elif fault=='draw':run['after_draw']=deepcopy(run['after_draw']);run['after_draw']['tree']['type']='changed'
            elif fault=='scene':run['scene_sha256']='wrong'
            with self.subTest(fault=fault),self.assertRaises(ValueError):self.validate(report)

    def test_wrong_original_request_group_snapshot_or_bytes_refuses(self):
        for fault in ('request','group','snapshot','bytes','context'):
            value=deepcopy(self.inventory)
            if fault=='request':value['static_pairs'][0]['request']['bones'][0]['scale'][0]=2
            elif fault=='group':value['technical_pairs']['cases'][-1]['original_row']['group']='motion'
            elif fault=='snapshot':value['static_pairs'][1]['files']['after']['native_snapshot']['children']['Skeleton']['bones'][0]['enabled']=False
            elif fault=='bytes':value['static_pairs'][0]['files']['after']['sha256']='0'*64
            elif fault=='context':value['static_pairs'][0]['context']['sha256']='0'*64
            with self.subTest(fault=fault),self.assertRaises(ValueError):s.verify_originals(value)

    def test_rendered_matrix_and_conservative_cameras(self):
        manifest,report=fixture(self.inventory,True)
        self.assertEqual(s.validate(report,manifest,'manifest','binding',True)['secondary_plays'],4)
        cameras=s.cameras(report)
        self.assertEqual(set(cameras),set(s.IDS));self.assertTrue(all(len(v)==2 and all(c['size']>0 for c in v) for v in cameras.values()))

    def test_image_bytes_clock_framing_and_zero_step_guards(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);(folder/'samples').mkdir();s.write(folder/'capture-binding.json',{})
            run=dict(id=s.IDS[1],side='before',take=0,trace=[dict(time=0.,delta=0.)])
            name=s.IDS[1]+'-before-0-000.png';Image.new('RGB',(960,1080)).save(folder/'samples'/name)
            row=dict(id=s.IDS[1],side='before',take=0,sample=0,time=0.,delta=0.,name=name,sha256=s.sha(folder/'samples'/name),bounds=[[20,20,940,520]]*2,camera_states=[{'size':5}]*2,no_simulation_advance=True)
            report=dict(kind='remaining_saved_images',passed=True,failures=[],engine_errors=[],size=[960,1080],binding_sha256=s.sha(folder/'capture-binding.json'),images=[row])
            s.write(folder/'samples/render.json',report);self.assertEqual(s.validate_images(folder,{},dict(runs=[run])),1)
            for fault in ('bytes','clock','bounds','inert','flag'):
                changed=deepcopy(report)
                if fault=='bytes':changed['images'][0]['sha256']='0'*64
                elif fault=='clock':changed['images'][0]['time']=1/60
                elif fault=='bounds':changed['images'][0]['bounds'][0][0]=-10
                elif fault=='inert':changed['images'][0]['no_simulation_advance']=False
                elif fault=='flag':changed['failures']=['real draw failure']
                (folder/'samples/render.json').write_text(json.dumps(changed))
                with self.subTest(fault=fault),self.assertRaises(ValueError):s.validate_images(folder,{},dict(runs=[run]))

    def test_copied_project_has_original_bytes_and_exclusive_outputs(self):
        # Temp Git repo exercises committed helper identities without changing
        # primary or this worktree. No engine is started.
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory);repo=base/'repo';repo.mkdir(); pending=[s.SCRIPT,s.BASE];seen=set()
            while pending:
                name=pending.pop()
                if name in seen:continue
                seen.add(name);src=(WORKER if name==s.SCRIPT else PRIMARY)/'test_project'/name
                text=src.read_text(encoding='utf-8-sig');target=repo/'test_project'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,target)
                pending += s.re.findall(r'(?:extends\s+|(?:preload|load)\(\s*)"res://([^"\n]+\.gd)"',text)
            for relative in s.PYTHON_HELPERS:
                target=repo/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(WORKER/relative,target)
            for command in (['git','init','-q',str(repo)],['git','-C',str(repo),'add','.'],['git','-C',str(repo),'-c','user.name=Offline test','-c','user.email=offline@example.invalid','commit','-qm','fixture']):subprocess.run(command,check=True,capture_output=True)
            output=base/'stage'
            with patch.object(s,'current_boundaries',return_value={'unit_fixture_only':True}):binding=s.prepare(repo,INPUTS,output)
            s.verify_frozen(binding)
            manifest=s.read(output/'project/remaining-manifest.json');self.assertEqual([r['id'] for r in manifest['cases']],list(s.IDS))
            self.assertEqual(len(list((output/'project/saved').rglob('*.tscn'))),8)
            self.assertEqual(len(list((output/'project/saved').rglob('*.tres'))),1)
            self.assertEqual(list(output.rglob('*.fbx')),[])
            with self.assertRaisesRegex(ValueError,'preserve previous'):s.prepare(repo,INPUTS,output)
            target=Path(binding['files'][0]['path']);target.write_bytes(target.read_bytes()+b'\n')
            with self.assertRaisesRegex(ValueError,'changed bound'):s.verify_frozen(binding)


if __name__=='__main__':unittest.main()
