"""Small structural checks for the publication dependency and exact-run wiring."""
from pathlib import Path
import unittest
import yaml
from check_release_audit import CORES

ROOT=Path(__file__).resolve().parents[1]


class WorkflowGateControls(unittest.TestCase):
    def test_reusable_preview_is_required_and_same_run_artifacts_used(self):
        workflow=yaml.safe_load((ROOT/'.github/workflows/ci.yml').read_text())
        jobs=workflow['jobs']
        self.assertEqual(jobs['rendered-preview']['uses'],'./.github/workflows/rendered-preview.yml')
        gate=jobs['release-gate']
        self.assertIn('rendered-preview',gate['needs'])
        downloads=[s for s in gate['steps'] if s.get('uses')=='actions/download-artifact@v4']
        preview=next(s for s in downloads if s['with'].get('name')=='rendered-preview-linux-core-${{ env.CORE_VERSION }}')
        self.assertNotIn('run-id',preview['with'])
        self.assertNotIn('github-token',preview['with'])
        self.assertTrue(any('check_rendered_preview_matrix.py --source "$GITHUB_SHA"' in s.get('run','') for s in gate['steps']))

    def test_preview_reusable_without_duplicate_push_or_pr_runs(self):
        workflow=yaml.safe_load((ROOT/'.github/workflows/rendered-preview.yml').read_text())
        triggers=workflow.get('on',workflow.get(True))
        self.assertEqual(set(triggers),{'workflow_call','workflow_dispatch'})
        version, commit = next(iter(CORES.items()))
        ci = yaml.safe_load((ROOT/'.github/workflows/ci.yml').read_text())
        self.assertEqual((ci['env']['CORE_VERSION'], ci['env']['CORE_REF']), (version, commit))
        for name in ('editor-suite', 'mcp-route', 'clean-install'):
            job = ci['jobs'][name]
            self.assertEqual(job['strategy']['matrix'], {'os': ['ubuntu-latest', 'windows-latest']})
            core = next(step['with'] for step in job['steps']
                        if step.get('with', {}).get('repository') == 'hi-godot/godot-ai')
            self.assertEqual(core['ref'], '${{ env.CORE_REF }}')
        steps = workflow['jobs']['linux-rendered-preview']['steps']
        core = next(step['with'] for step in steps
                    if step.get('with', {}).get('repository') == 'hi-godot/godot-ai')
        self.assertEqual(core['ref'], commit)
        artifact = next(step['with']['name'] for step in steps
                        if step.get('uses') == 'actions/upload-artifact@v4')
        self.assertTrue(artifact.startswith(f'rendered-preview-linux-core-{version}${{{{'))

    def test_tag_uses_remote_main_and_only_three_explicit_assets(self):
        workflow=yaml.safe_load((ROOT/'.github/workflows/ci.yml').read_text())
        steps=workflow['jobs']['release']['steps']
        source=next(s['run'] for s in steps if s.get('name')=='Require tag to identify freshly fetched remote main')
        self.assertIn('git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main',source)
        self.assertIn('test "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/main)"',source)
        publish=next(s['run'] for s in steps if 'gh release create' in s.get('run',''))
        self.assertNotIn('dist/*',publish)
        self.assertIn('"$archive" "$archive.manifest.json" "$archive.sha256"',publish)


if __name__=='__main__': unittest.main()
