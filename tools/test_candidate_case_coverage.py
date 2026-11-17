"""Corruption controls for admitting real CI case/check identities."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from audit_candidate_case_coverage import admit_cell, confined
from check_release_audit import CORES


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = 'animation_motion.jump'
        self.inventory = {'operations': [{'key': self.key, 'effect_kind': 'scene_write'}]}
        self.blob = 'a' * 40
        self.content = b'committed production bytes'
        self.tree = {'addons/godot_ai_animation/example.gd': self.blob}
        self.context = dict(tested_source='b' * 40, engine='4.7.2.stable.official.ed1daf0bf',
                            platform='linux', core_version='4.2.1', core_commit=CORES['4.2.1'],
                            ci_source_identity={'checkout_sha': 'b' * 40},
                            dependencies={next(iter(self.tree)): {'git_blob': self.blob,
                                          'sha256': hashlib.sha256(self.content).hexdigest()}})
        (self.root / 'calls.jsonl').write_text('{}\n')
        self.report = copy.deepcopy(self.context)
        self.report['cases'] = [dict(id='positive', operation=self.key, checks={'mcp_invocation': 'pass', 'valid_effect': 'pending'}),
                                dict(id='refusal', operation=self.key, checks={'mcp_invocation': 'fail'}, outcome='refused_or_failed')]
        self.save()

    def save(self):
        context = self.root / 'operation-context.json'
        context.write_text(json.dumps(self.context))
        self.report['context_sha256'] = hashlib.sha256(context.read_bytes()).hexdigest()
        self.report['raw_artifacts'] = [{'path': 'operation-context.json', 'sha256': self.report['context_sha256'], 'role': 'trace_context'},
                                        {'path': 'calls.jsonl', 'sha256': hashlib.sha256((self.root / 'calls.jsonl').read_bytes()).hexdigest(), 'role': 'raw_public_calls'}]
        self.write_report()

    def write_report(self):
        (self.root / 'operation-case-results.json').write_text(json.dumps(self.report))

    def admit(self):
        return admit_cell(self.root, self.inventory, self.tree, {self.blob: self.content})

    def test_retains_case_identity_failures_and_gaps(self):
        result = self.admit()
        self.assertEqual(result['refused_or_failed'], ['refusal'])
        checks = result['operations'][self.key]['checks']
        self.assertEqual(checks['mcp_invocation']['pass'], ['positive'])
        self.assertEqual(checks['mcp_invocation']['fail'], ['refusal'])
        self.assertIn('valid_effect', result['operations'][self.key]['missing_passing_checks'])
        self.assertIn('visual_review', result['operations'][self.key]['missing_passing_checks'])

    def test_raw_corruption(self):
        (self.root / 'calls.jsonl').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Changed raw'): self.admit()

    def test_wrong_context(self):
        self.report['core_version'] = '4.3.0'; self.write_report()
        with self.assertRaisesRegex(ValueError, 'identity differs'): self.admit()

    def test_duplicate_case(self):
        self.report['cases'].append(self.report['cases'][0]); self.write_report()
        with self.assertRaisesRegex(ValueError, 'case identity'): self.admit()

    def test_dependency_corruption(self):
        self.context['dependencies'][next(iter(self.tree))]['sha256'] = '0' * 64
        self.report['dependencies'] = copy.deepcopy(self.context['dependencies']); self.save()
        with self.assertRaisesRegex(ValueError, 'Dependency identity'): self.admit()

    def test_missing_production_dependency(self):
        self.context['dependencies'] = {}; self.report['dependencies'] = {}; self.save()
        with self.assertRaisesRegex(ValueError, 'Incomplete production'): self.admit()

    def test_actual_checkout_required(self):
        self.context['ci_source_identity']['checkout_sha'] = 'c' * 40; self.save()
        with self.assertRaisesRegex(ValueError, 'Actual checkout'): self.admit()

    def test_path_escape(self):
        for name in ('../outside', 'C:/private.json', '/etc/passwd', 'folder\\file'):
            with self.subTest(name=name), self.assertRaises(ValueError): confined(self.root, name)


if __name__ == '__main__': unittest.main()
