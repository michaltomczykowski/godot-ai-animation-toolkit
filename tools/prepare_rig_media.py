"""Prepare exact historical rig scenes; do not regenerate rig clips or poses."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
CLIPS=('pose_to_clip','walk_cycle','idle_breathing','blink','jumping_jack','squat','punch','bake_pose_sequence')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def build(coverage,output):
    output.mkdir(parents=True,exist_ok=False);(output/'scenes').mkdir()
    data=json.loads(coverage.read_text(encoding='utf-8-sig'));rows=[]
    def copy(source,name,expected=None):
        if expected and sha(source)!=expected:raise ValueError('Preserved source hash mismatch')
        if '[ext_resource' in source.read_text(encoding='utf-8-sig'):raise ValueError('Self-contained scenes required')
        target=output/'scenes'/name;shutil.copyfile(source,target)
        return {'path':str(target.resolve()),'sha256':sha(target),'source':str(source)}
    for op in CLIPS:
        rec=next(r for r in data['operations']if r['key']=='animation_rig.'+op)
        entry=next(r for r in rec['representative_saved_scenes']if 'local_3d_' in r['name'])
        scene=copy(Path(entry['path']),op+'.tscn',entry['sha256'])
        rows.append(dict(operation=op,kind='clip',scene=scene,skeleton='RigClipHistory/Character/Skeleton',player='RigClipHistory/Playback/AnimationPlayer',animation='generated'))
    rec=next(r for r in data['operations']if r['key']=='animation_rig.pose_apply')
    entry=next(r for r in rec['representative_saved_scenes']if '_apply_redo' in r['name']);source=Path(entry['path'])
    rows.append(dict(operation='pose_apply',kind='saved_static_pair',scene=copy(source,'pose_apply-after.tscn',entry['sha256']),before=copy(source.with_name(source.name.replace('_redo','_undo')),'pose_apply-before.tscn'),skeleton='RigPoseHistory/Skeleton'))
    result=dict(schema_version=1,cases=rows,takes=2,take_duration_s=4,fps=60,coverage_sha256=sha(coverage),
        geometry='Display-only unskinned joint spheres, parent lines and local-axis rods; no animated bones or skinned meshes replaced.',
        pose_blend={'effect':'pose JSON resource/file','scene_applicability':'Not directly applicable; no preserved downstream public pose_apply linkage asserted'},visual_approval=False)
    with (output/'manifest.json').open('x',encoding='utf-8')as f:json.dump(result,f,indent=2)
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--coverage',type=Path,default=Path(__file__).resolve().parents[1]/'docs/operation-media-coverage.json');p.add_argument('--output',type=Path,required=True);a=p.parse_args();build(a.coverage,a.output)
