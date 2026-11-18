"""Offline orchestration controls; never connects to Godot."""
import asyncio
from contextlib import asynccontextmanager, redirect_stdout
import importlib.util
import io
from pathlib import Path
import shutil
import sys
from tempfile import TemporaryDirectory
from types import ModuleType, SimpleNamespace
from unittest.mock import patch
import unittest


class SetupRouteControls(unittest.TestCase):
    def load(self, fail):
        state = {'written': False, 'reopened': False, 'requests': []}
        async def call(client, tool, params):
            if tool == 'scene_open':
                if state['written'] and params['path'] == state.get('scene'):
                    state['reopened'] = True
                else:
                    state.update(written=False, reopened=False, scene=params['path'])
                return {}
            if tool == 'custom_animation_inspect': return {'roles': {'hips': 'Hips'}}
            if tool == 'node_get_properties': return {'properties': [{'value': ''}]}
            if tool == 'custom_animation_rig': return {'pose': 'unchanged'}
            if tool == 'custom_manage':
                request = params['params']['params']
                state['requests'].append(request)
                if not request.get('dry_run'): state['written'] = True
                return {'clips': {'idle': {}, 'walk': {}, 'run': {}, 'jump': {}}, 'tree_path': '/Root/AnimationTree'}
            if tool == 'test_run': return {'passed': 0 if fail == 'history' else 1, 'failed': int(fail == 'history'), 'skipped': 0}
            return {}
        async def inspect(client, name, player):
            if not state['written']: return {'error': 'missing'}
            return {'clips': [{'name': name, 'length': 2 if fail == 'persist' and state['reopened'] else 1}]}
        @asynccontextmanager
        async def connected_editor(a): yield None, {'fake': True}
        rigs = tuple((f'rig{i}', 'fake', 'fixture.tscn', 'Root', 'Rig', 'Player', True) for i in range(4))
        dependencies = {
            'fixture_copy': {'copy_scene': shutil.copyfile},
            'mcp_character_quality_baseline': {'RIGS': rigs},
            'mcp_motion_remaining_cycles': {'inspect': inspect},
            'mcp_presets_audit': {'call': call},
            'mcp_rig_modifier_ui_history': {'connected_editor': connected_editor},
        }
        modules = {}
        for name, fields in dependencies.items():
            modules[name] = ModuleType(name)
            modules[name].__dict__.update(fields)
        path = Path(__file__).with_name('mcp_setup_quality_review.py')
        with patch.dict(sys.modules, modules):
            spec = importlib.util.spec_from_file_location('setup_client_controls', path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        return module, state

    def exercise(self, fail=None):
        module, state = self.load(fail)
        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / 'fixture.tscn').write_text('[gd_scene format=3]\n[node name="Root" type="Node3D"]\n[node name="Player" type="AnimationPlayer" parent="."]\n')
            args = SimpleNamespace(output=project/'output', project_root=project, repo=project,
                                   styles=['responsive'], variants=['extracted-stationary', 'in-place-stationary', 'extracted-forward'], turns=[False, True], godot=None, reuse_complete=None)
            with patch.object(module, 'dependency_hashes', return_value={'toolkit/test': 'digest', 'core/test': 'digest'}), patch.object(module.subprocess, 'check_output', return_value='fake-head'), redirect_stdout(io.StringIO()):
                if fail:
                    with self.assertRaises(RuntimeError): asyncio.run(module.run(args))
                else: self.assertEqual(asyncio.run(module.run(args)), 0)
            import json
            report = json.loads((args.output/'setup-matrix.json').read_text())
            self.assertEqual(report['passed'], not bool(fail))
            if not fail:
                self.assertEqual(len(report['groups']), 6)
                self.assertTrue(list((project/'output').glob('*/receipts/*.json')), 'immutable progress snapshots exist')
                self.assertEqual(len(state['requests']), 48)
                before_count = len(state['requests'])
                args.reuse_complete = args.output
                args.output = project / 'reused'
                with patch.object(module, 'dependency_hashes', return_value={'toolkit/test': 'digest', 'core/test': 'digest'}), patch.object(module.subprocess, 'check_output', return_value='fake-head'), redirect_stdout(io.StringIO()):
                    self.assertEqual(asyncio.run(module.run(args)), 0)
                self.assertEqual(len(state['requests']), before_count, 'completed public mutations must not repeat')
                args.output = project / 'rejected-reuse'
                with patch.object(module, 'dependency_hashes', return_value={'toolkit/test': 'changed'}), patch.object(module.subprocess, 'check_output', return_value='fake-head'):
                    with self.assertRaisesRegex(ValueError, 'dependency mismatch'): asyncio.run(module.run(args))
                self.assertEqual(len(state['requests']), before_count)
                for request in state['requests']:
                    self.assertFalse({'speed', 'run_speed', 'duration', 'run_duration', 'turn_duration'} & request.keys())
                    self.assertFalse(request['active'])
    def test_positive_defaults_and_matrix(self): self.exercise()
    def test_failed_external_history_cannot_pass(self): self.exercise('history')
    def test_reopen_clip_drift_cannot_pass(self): self.exercise('persist')

if __name__ == '__main__': unittest.main()
