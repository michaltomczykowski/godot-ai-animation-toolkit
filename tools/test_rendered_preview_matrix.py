import copy
from pathlib import Path
import unittest
from check_rendered_preview_matrix import source_blobs,verify_identity,CORES


class MatrixIdentityControls(unittest.TestCase):
    def test_trace_fixture_dependencies_are_mandatory(self):
        root=Path(__file__).resolve().parents[1]
        source='HEAD'
        blobs=source_blobs(root,source)
        fixtures=('test_project/repair_rig_fixture.tscn',
                  'test_project/models/human_dummy/HumanCharacterDummy_F.fbx',
                  'test_project/tests/fixtures/sheet.png',
                  'test_project/tests/fixtures/cue.wav')
        context={'tested_source':source,'platform':'linux','core_version':'4.3.0',
                 'core_commit':CORES['4.3.0'],'core_qualification':'released',
                 'engine':'4.7.2.stable.official',
                 'dependencies':{p:{'git_blob':b} for p,b in blobs.items()}}
        verify_identity(context,source,'4.3.0',blobs)
        for rel in fixtures:
            with self.subTest(rel=rel):
                self.assertIn(rel,blobs)
                bad=copy.deepcopy(context)
                bad['dependencies'].pop(rel)
                with self.assertRaisesRegex(ValueError,'dependency set/blobs'):
                    verify_identity(bad,source,'4.3.0',blobs)

    def test_exact_source_and_canonical_blobs_required(self):
        source='a'*40
        blobs={'tools/ci_rendered_preview.py':'b'*40}
        context={'tested_source':source,'platform':'linux','core_version':'4.2.1',
            'core_commit':CORES['4.2.1'],'core_qualification':'released','engine':'4.7.2.stable.official',
            'dependencies':{'tools/ci_rendered_preview.py':{'git_blob':'b'*40,'sha256':'raw-windows-or-linux'}}}
        verify_identity(context,source,'4.2.1',blobs)
        for key,value in [('tested_source','c'*40),('platform','windows'),('core_version','4.3.0'),
                          ('core_commit','d'*40),('core_qualification','advisory'),('engine','4.6.stable')]:
            bad=copy.deepcopy(context);bad[key]=value
            with self.assertRaises(ValueError,msg=key): verify_identity(bad,source,'4.2.1',blobs)
        for dependencies in ({},{'tools/ci_rendered_preview.py':{'git_blob':'e'*40}}):
            bad=copy.deepcopy(context);bad['dependencies']=dependencies
            with self.assertRaises(ValueError): verify_identity(bad,source,'4.2.1',blobs)


if __name__=='__main__': unittest.main()
