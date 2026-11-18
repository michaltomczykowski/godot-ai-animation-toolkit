"""Pure preserved rig manifest controls; no engine or live API."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from prepare_rig_media import build,CLIPS,sha

class RigManifestControls(unittest.TestCase):
    def fixture(self,base):
        rows=[]
        for op in CLIPS:
            scene=base/f'rig_clip_history_local_3d_{op}_redo.tscn'
            scene.write_text('[gd_scene format=3]\n# exact saved clip fixture')
            rows.append({'key':'animation_rig.'+op,'representative_saved_scenes':[{'name':scene.name,'path':str(scene),'sha256':sha(scene)}]})
        after=base/'rig_pose_history_3d_local_apply_redo.tscn';after.write_text('[gd_scene format=3]\n# exact after pose')
        after.with_name(after.name.replace('_redo','_undo')).write_text('[gd_scene format=3]\n# exact before pose')
        rows.append({'key':'animation_rig.pose_apply','representative_saved_scenes':[{'name':after.name,'path':str(after),'sha256':sha(after)}]})
        path=base/'coverage.json';path.write_text(json.dumps({'operations':rows}));return path
    def test_exact_immutable_subset_and_resource_applicability(self):
        with TemporaryDirectory()as tmp:
            base=Path(tmp);coverage=self.fixture(base);out=base/'out';manifest=build(coverage,out)
            self.assertEqual(len(manifest['cases']),9)
            self.assertEqual(manifest['pose_blend']['effect'],'pose JSON resource/file')
            self.assertNotIn('pose_blend',[r['operation']for r in manifest['cases']])
            for row in manifest['cases']:
                for receipt in [row['scene']]+([row['before']]if row.get('before')else[]):
                    self.assertEqual(Path(receipt['path']).read_bytes(),Path(receipt['source']).read_bytes())
            with self.assertRaises(FileExistsError):build(coverage,out)
    def test_changed_source_refuses(self):
        with TemporaryDirectory()as tmp:
            base=Path(tmp);coverage=self.fixture(base);(base/'rig_clip_history_local_3d_pose_to_clip_redo.tscn').write_text('changed')
            with self.assertRaisesRegex(ValueError,'hash mismatch'):build(coverage,base/'out')
    def test_missing_before_pair_refuses(self):
        with TemporaryDirectory()as tmp:
            base=Path(tmp);coverage=self.fixture(base);(base/'rig_pose_history_3d_local_apply_undo.tscn').unlink()
            with self.assertRaises(FileNotFoundError):build(coverage,base/'out')
if __name__=='__main__':unittest.main()
