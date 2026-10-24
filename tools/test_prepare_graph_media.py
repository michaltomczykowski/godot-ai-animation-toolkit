"""Pure immutable graph manifest construction controls."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from prepare_graph_media import build, OPS, sha

class GraphManifestControls(unittest.TestCase):
    def fixture(self, base):
        rows=[]
        for op in OPS:
            scene=base/f'graph_history_{op}_new_redo.tscn'
            scene.write_text('[gd_scene format=3]\ntree_root = SubResource("Original")\n')
            rows.append({'key':'animation_graph.'+op,'representative_saved_scenes':[{'name':scene.name,'path':str(scene),'sha256':sha(scene)}]})
        (base/'graph_history_wire_replace_redo.tscn').write_text('[gd_scene format=3]\ntree_root = SubResource("SavedIdle")\n')
        coverage=base/'coverage.json';coverage.write_text(json.dumps({'operations':rows}))
        return coverage
    def test_exact_copy_controls_and_immutable_output(self):
        with TemporaryDirectory() as tmp:
            base=Path(tmp);coverage=self.fixture(base);out=base/'out'
            manifest=build(coverage,out)
            self.assertEqual(len(manifest['cases']),7)
            for row in manifest['cases']:
                self.assertEqual(Path(row['scene']).read_bytes(),Path(row['preserved_source']).read_bytes())
                self.assertEqual(row['scene_sha256'],sha(Path(row['scene'])))
                self.assertTrue(row['control_contract'])
            self.assertIn('replace_redo',next(r for r in manifest['cases']if r['operation']=='wire')['preserved_source'])
            with self.assertRaises(FileExistsError):build(coverage,out)
    def test_changed_preserved_source_refuses(self):
        with TemporaryDirectory() as tmp:
            base=Path(tmp);coverage=self.fixture(base)
            (base/'graph_history_state_machine_new_redo.tscn').write_text('changed')
            with self.assertRaisesRegex(ValueError,'hash mismatch'):build(coverage,base/'out')
    def test_external_dependency_refuses(self):
        with TemporaryDirectory() as tmp:
            base=Path(tmp);coverage=self.fixture(base);data=json.loads(coverage.read_text())
            source=base/'graph_history_blend_space_new_redo.tscn';source.write_text(source.read_text()+'[ext_resource path="user://unknown"]')
            data['operations'][1]['representative_saved_scenes'][0]['sha256']=sha(source);coverage.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,'Self-contained'):build(coverage,base/'out')

if __name__=='__main__':unittest.main()
