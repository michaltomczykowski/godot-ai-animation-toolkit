"""Corruption controls for admitting real CI case/check identities."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from audit_candidate_case_coverage import (
    MOTION_EFFECT_KEYS, admit_cell, attach_motion_effects, attach_preview_visual, attach_saved_visual, confined,
    setup_input_digests, sha,
)
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
                            platform='linux', core_version='4.4.2', core_commit=CORES['4.4.2'],
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


class MotionSupplementJoin(unittest.TestCase):
    def test_bound_checks_do_not_cross_platform_or_supply_setup(self):
        fields = dict(tested_source='same-source', core_version='4.4.2',
                      core_commit=CORES['4.4.2'], engine='4.7.2.stable.official')
        def effects(passing):
            return {k: {'checks': {'valid_effect': {'pass': [k + ':real'] if passing else []}},
                        'missing_passing_checks': ['valid_effect', 'visual_review']}
                    for k in MOTION_EFFECT_KEYS}
        windows = dict(**fields, platform='windows', operations=effects(False))
        linux = dict(**fields, platform='linux', operations=effects(False))
        sample = dict(**fields, platform='windows', operations=effects(True),
                      non_invocation_failures=[], report='report.json', report_sha256='report-hash',
                      context_sha256='context-hash', raw_artifacts=[])
        with patch('audit_candidate_case_coverage.admit_cell', return_value=sample):
            attach_motion_effects({}, 'same-source', {}, {}, [windows, linux], Path('archive'))
            self.assertEqual({tuple(row['missing_passing_checks']) for row in windows['operations'].values()},
                             {('visual_review',)})
            self.assertNotIn('motion_effect_supplement', linux)
            self.assertEqual({tuple(row['missing_passing_checks']) for row in linux['operations'].values()},
                             {('valid_effect', 'visual_review')})
            with self.assertRaisesRegex(ValueError, 'Duplicate motion supplement'):
                attach_motion_effects({}, 'same-source', {}, {}, [windows, linux], Path('duplicate'))
            sample['platform'] = 'linux'
            attach_motion_effects({}, 'same-source', {}, {}, [windows, linux], Path('another-cell'))
            self.assertEqual({tuple(row['missing_passing_checks']) for row in linux['operations'].values()},
                             {('visual_review',)})
            sample['tested_source'] = 'different-source'
            with self.assertRaisesRegex(ValueError, 'foreign source'):
                attach_motion_effects({}, 'same-source', {}, {}, [windows, linux], Path('archive'))


class PreviewVisualJoin(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.receipt = root / 'evidence.json'
        self.operation = 'animation_inspect.preview'
        self.source = 'a' * 40
        self.dependencies = {'addons/godot_ai_animation/handlers/inspect.gd': 'b' * 40}
        self.cells = []
        media = []
        ids = []
        for cell_index in range(2 * len(CORES)):
            case_id = f'public-preview-{cell_index}'
            ids.append(case_id)
            images = []
            for index in range(4):
                path = root / f'{cell_index}-{index}.png'
                path.write_bytes(path.name.encode())
                images.append({'path': path.name, 'sha256': sha(path), 'role': 'rendered_preview_image'})
            media.extend(dict(image, kind='image') for image in images)
            self.cells.append({'operations': {self.operation: {
                'rendered_preview': {'case_id': case_id, 'artifacts': images},
                'checks': {'visual_review': {'pass': []}},
                'missing_passing_checks': ['visual_review'],
            }}})
        assessment = root / 'review.json'
        assessment.write_text(json.dumps({'assessments': [{
            'operation': self.operation, 'case_ids': ids, 'reviewer_type': 'independent',
            'human_approved': False, 'status': 'pass', 'method': 'ordered static preview',
            'findings': 'fixture framing', 'media': media,
        }]}))
        self.record = {
            'operation_key': self.operation, 'tested_source': self.source, 'engine': '4.7.2',
            'scope': 'candidate', 'case_ids': ids, 'dependencies': self.dependencies,
            'artifacts': media + [{'path': assessment.name, 'sha256': sha(assessment),
                                   'role': 'independent_assessment'}],
        }

    def attach(self):
        self.receipt.write_text(json.dumps(self.record))
        attach_preview_visual(self.cells, self.source, self.dependencies, self.dependencies, self.receipt)

    def test_joins_only_the_actual_public_preview_cases(self):
        self.attach()
        for cell in self.cells:
            item = cell['operations'][self.operation]
            self.assertEqual(item['checks']['visual_review']['pass'], [item['rendered_preview']['case_id']])
            self.assertEqual(item['missing_passing_checks'], [])

    def test_rejects_wrong_public_case_or_different_image(self):
        actual = self.record['case_ids'][0]
        self.record['case_ids'][0] = 'foreign'
        with self.assertRaisesRegex(ValueError, 'cases, source or dependencies'):
            self.attach()
        self.record['case_ids'][0] = actual
        self.cells[-1]['operations'][self.operation]['rendered_preview']['artifacts'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'image hashes differ'):
            self.attach()
        self.assertTrue(all(not cell['operations'][self.operation]['checks']['visual_review']['pass']
                            for cell in self.cells))


class PortableSetupInputs(unittest.TestCase):
    def test_checks_copied_bytes_and_the_original_context(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            scene = 'res://mortared/dummy.tscn'
            names = ('mortared/dummy.tscn', 'models/human_dummy/HumanCharacterDummy_F.fbx',
                     'tools/check_setup_tree_quality.gd', 'addons/godot_ai_animation/runtime/setup_grounding.gd',
                     'addons/godot_ai_animation/spec/motion_space.gd')
            digests, dependencies = {}, {}
            for name in names:
                relative = 'inputs/' + name
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(name)
                key = name if name.startswith('addons/') else 'test_project/' + name
                digests[relative] = sha(path)
                dependencies[key] = {'sha256': sha(path)}
            inputs = {'path_base': 'replay', 'paths': digests}
            self.assertEqual(setup_input_digests(root, inputs, scene, dependencies),
                             [digests['inputs/mortared/dummy.tscn']])
            checker = root / 'inputs/tools/check_setup_tree_quality.gd'
            checker.write_text('wrong checker')
            with self.assertRaisesRegex(ValueError, 'physical inputs changed'):
                setup_input_digests(root, inputs, scene, dependencies)
            digests['inputs/tools/check_setup_tree_quality.gd'] = sha(checker)
            with self.assertRaisesRegex(ValueError, 'tested context'):
                setup_input_digests(root, inputs, scene, dependencies)


class SavedVisualJoin(unittest.TestCase):
    def test_rejects_a_foreign_saved_case_and_attaches_only_in_its_own_cell(self):
        operation = 'animation_graph.wire'
        inventory = {'operations': [{'key': operation, 'effect_kind': 'scene_structure'}]}
        with tempfile.TemporaryDirectory() as folder:
            receipt = Path(folder) / 'review.json'
            record = {'operation_key': operation, 'case_ids': ['foreign'], 'tested_source': 'same',
                      'scope': 'candidate', 'engine': '4.7.2', 'dependencies': {'graph.gd': 'blob'},
                      'artifacts': []}
            windows = {'platform': 'windows', 'core_version': '4.4.2',
                       'core_commit': CORES['4.4.2'], 'engine': 'official'}
            public_checks = {check: {'pass': ['actual-case']}
                             for check in ('undo_redo', 'save_reopen', 'source_unchanged')}
            source = dict(windows, tested_source='same', non_invocation_failures=[],
                          report_sha256='report', operations={operation: {'checks': public_checks}})
            cells = [dict(windows, platform=os, operations={operation: {
                'checks': {'visual_review': {'pass': []}}, 'missing_passing_checks': ['visual_review']
            }}) for os in ('windows', 'linux')]
            tree = record['dependencies']
            with patch('audit_candidate_case_coverage.admit_cell', return_value=source), \
                 patch('audit_candidate_case_coverage.operation_binding_errors', return_value=[]):
                receipt.write_text(json.dumps({'records': [record]}))
                with self.assertRaisesRegex(ValueError, 'case, source or dependencies'):
                    attach_saved_visual(inventory, 'same', tree, tree, {}, cells, Path(folder), receipt, 'graph')
                record['case_ids'] = ['actual-case']
                receipt.write_text(json.dumps({'records': [record]}))
                attach_saved_visual(inventory, 'same', tree, tree, {}, cells, Path(folder), receipt, 'graph')
            self.assertEqual(cells[0]['operations'][operation]['checks']['visual_review']['pass'], ['actual-case'])
            self.assertEqual(cells[1]['operations'][operation]['missing_passing_checks'], ['visual_review'])

    def test_rig_review_admits_only_recorded_operations(self):
        allowed, pending, outside = ('animation_rig.squat', 'animation_rig.blink', 'animation_rig.rig_chain')
        inventory = {'operations': [{'key': op, 'effect_kind': 'scene_structure'}
                                    for op in (allowed, pending, outside)]}
        cell_identity = dict(platform='windows', core_version='4.4.2',
                             core_commit=CORES['4.4.2'], engine='official')
        source = dict(cell_identity, tested_source='same', non_invocation_failures=[], report_sha256='report',
                      operations={op: {'checks': {name: {'pass': [op + '-case']}
                                                  for name in ('undo_redo', 'save_reopen', 'source_unchanged')}}
                                  for op in (allowed, pending, outside)})
        cell = dict(cell_identity, operations={op: {'checks': {'visual_review': {'pass': []}},
                                                   'missing_passing_checks': ['visual_review']}
                                              for op in (allowed, pending, outside)})
        deps = {'rig.gd': 'blob'}
        with tempfile.TemporaryDirectory() as folder, \
             patch('audit_candidate_case_coverage.admit_cell', return_value=source), \
             patch('audit_candidate_case_coverage.operation_binding_errors', return_value=[]):
            root = Path(folder)
            receipt = root / 'rig-review.json'
            for operation in (outside, allowed):
                record = dict(operation_key=operation, case_ids=[operation + '-case'], tested_source='same',
                              scope='candidate', engine='4.7.2', dependencies=deps, artifacts=[])
                receipt.write_text(json.dumps({'records': [record]}))
                if operation == outside:
                    with self.assertRaisesRegex(ValueError, 'unexpected operation coverage'):
                        attach_saved_visual(inventory, 'same', deps, deps, {}, [cell], root, receipt, 'rig')
                    continue
                attach_saved_visual(inventory, 'same', deps, deps, {}, [cell], root, receipt, 'rig')
                with self.assertRaisesRegex(ValueError, 'Duplicate rig visual review'):
                    attach_saved_visual(inventory, 'same', deps, deps, {}, [cell], root, receipt, 'rig')
            self.assertEqual(cell['operations'][allowed]['checks']['visual_review']['pass'], [allowed + '-case'])
            for operation in (pending, outside):
                self.assertEqual(cell['operations'][operation]['missing_passing_checks'], ['visual_review'])


if __name__ == '__main__': unittest.main()
