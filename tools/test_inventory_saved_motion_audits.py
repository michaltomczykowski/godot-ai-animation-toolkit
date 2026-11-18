import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from inventory_saved_motion_audits import inventory

class InventoryControls(unittest.TestCase):
    def bundle(self, root):
        (root / 'public-calls').mkdir()
        event = dict(id='audit:1', time_ns=4, context_sha256='ctx', driver='mcp_motion_audit_saved.py', operation='animation_inspect.motion_audit', request=dict(animation_name='walk_cycle', samples=31), response=dict(passed=True, body_travel=1, checks=[]))
        raw=root/'public-calls/a.jsonl'; raw.write_text(json.dumps(event)+'\n')
        report=dict(tested_source='old-source', context_sha256='ctx', dependencies={}, raw_artifacts=[dict(path='public-calls/a.jsonl',sha256=hashlib.sha256(raw.read_bytes()).hexdigest())])
        (root/'operation-case-results.json').write_text(json.dumps(report))
        return raw,report,event
    def test_contact_pass_does_not_qualify(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.bundle(root); row=inventory(root)['rows'][0]
            self.assertEqual(row['valid_effect'],'pending')
            self.assertIn('generation_save_open_join_missing',row['blockers'])
    def test_modified_raw_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); raw,_,_=self.bundle(root); raw.write_text('{}\n')
            with self.assertRaisesRegex(ValueError,'hash mismatch'): inventory(root)
    def test_wrong_context_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); raw,report,event=self.bundle(root); event['context_sha256']='other'; raw.write_text(json.dumps(event)+'\n'); report['raw_artifacts'][0]['sha256']=hashlib.sha256(raw.read_bytes()).hexdigest(); (root/'operation-case-results.json').write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError,'context mismatch'): inventory(root)
    def test_duplicate_id_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); raw,report,event=self.bundle(root); raw.write_text((json.dumps(event)+'\n')*2); report['raw_artifacts'][0]['sha256']=hashlib.sha256(raw.read_bytes()).hexdigest(); (root/'operation-case-results.json').write_text(json.dumps(report))
            with self.assertRaisesRegex(ValueError,'Duplicate'): inventory(root)

if __name__=='__main__': unittest.main()
