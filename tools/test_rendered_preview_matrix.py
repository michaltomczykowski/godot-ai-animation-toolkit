import copy
import unittest
from check_rendered_preview_matrix import verify_identity,CORES


class MatrixIdentityControls(unittest.TestCase):
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
