import copy
import unittest
import tempfile
from pathlib import Path
from prepare_saved_modifier_capture import admit_native,script_uid
class Admission(unittest.TestCase):
    def test_exact_uid_sidecar_when_present(self):
        with tempfile.TemporaryDirectory() as folder:
            script=Path(folder)/'dependency.gd';script.write_text('extends Node')
            self.assertIsNone(script_uid(script))
            uid=Path(str(script)+'.uid');uid.write_text('uid://4srxgpb4kwpg')
            self.assertEqual(script_uid(script),uid)
            self.assertIsNone(script_uid(uid))
    def fixture(self):
        row={'id':'local_spring_setup_dummy','op':'spring_setup','params':{'active':False},'states':{'redo':'user://case.tscn'}}
        report={'rows':[dict(id=row['id'],op=row['op'],params=row['params'],state='redo',scene=row['states']['redo'],native=False,fps=fps,case_failures=[],case_engine_errors=[]) for fps in (30,60,120)]}
        return row,report
    def test_exact_three_actual_cells(self):
        r,n=self.fixture();self.assertEqual(len(admit_native(r,n)),3)
    def test_wrong_missing_error_and_native_reference_refused(self):
        for mutate in (lambda n:n['rows'].pop(),lambda n:n['rows'][0].update(native=True),lambda n:n['rows'][0].update(scene='wrong'),lambda n:n['rows'][0].update(params={'active':True}),lambda n:n['rows'][0].update(case_engine_errors=['error']),lambda n:n['rows'][0].update(fps=120),lambda n:n['rows'][0].update(case_failures=['effect'])):
            r,n=self.fixture();mutate(n)
            with self.assertRaises(ValueError):admit_native(r,n)
if __name__=='__main__':unittest.main()
