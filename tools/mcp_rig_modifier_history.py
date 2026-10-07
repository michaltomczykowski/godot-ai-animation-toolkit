"""Require modifier history, native references and ordered saved playback."""
from __future__ import annotations
import argparse
import asyncio
from collections import Counter
import json
from pathlib import Path
import subprocess
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call
from mcp_preset_library_history import valid_suite

OPS = ('ik_setup', 'look_at_setup', 'twist_setup', 'spring_setup', 'retarget_setup')
EXPECTED = {
    'test_dummy_history': 166, 'test_editable_history': 171,
    'test_ik_variants': 376, 'test_local_history': 166,
    'test_locked_history': 154, 'test_look_at_variants': 495,
    'test_nested_history': 292, 'test_ordered_stack_history': 444,
    'test_predictable_refusals': 157, 'test_registry_coverage': 1,
    'test_retarget_variants': 309, 'test_spring_live_redo_restart': 168,
    'test_spring_variants': 198, 'test_twist_variants': 320,
}

def required_ids() -> set[str]:
    ids = {f'{layout}_{op}_base' for layout in ('local', 'editable', 'locked')
           for op in OPS if (layout, op) != ('locked', 'retarget_setup')}
    ids |= {f'{layout}_{op}_base' for layout in ('nested_00', 'nested_01', 'nested_10', 'nested_11')
            for op in ('ik_setup', 'spring_setup')}
    variants = {
        'ik_setup': [f'{k}_{mode}' for k in ('two_bone', 'ccdik', 'fabrik', 'spline')
                     for mode in ('generated', 'supplied')] + ['mixed_false', 'mixed_true', 'virtual'],
        'look_at_setup': [f'origin_{k}' for k in ('self', 'bone', 'external_node', 'skeleton')]
            + [f'axis_{k}' for k in ('px', 'nx', 'py', 'ny', 'pz', 'nz')]
            + ['secondary_false', 'secondary_true', 'generated', 'limited', 'relative_timed'],
        'twist_setup': ['even', 'weighted_0.0', 'weighted_0.5', 'weighted_1.0',
            'extended_false', 'extended_true', 'reference', 'influence_0.0', 'influence_0.5', 'influence_1.0'],
        'spring_setup': [f'world_origin_{selection}' for selection in ('automatic', 'listed', 'excluded')]
            + ['node_no_collision', 'bone_no_collision', 'multiple'],
        'retarget_setup': ['position', 'rotation', 'scale', 'all', 'global', 'existing', 'different_rests', 'target_instance'],
    }
    ids |= {f'local_{op}_{variant}' for op, variants_for_op in variants.items() for variant in variants_for_op}
    ids |= {'editable_retarget_setup_existing'}
    ids |= {f'local_{op}_dummy' for op in OPS}
    ids |= {f'stack_{i}_{weight}' for i in range(6) for weight in ('0.5', '1.0')}
    return ids

def valid_runtime(report: dict) -> bool:
    ids = required_ids()
    expected = Counter((case, state, fps, native) for case in ids for fps in (30, 60, 120)
                       for state, native in (('do', False), ('undo', False), ('redo', False), ('do', True)))
    rows = report.get('rows', [])
    actual = Counter((r.get('id'), r.get('state'), r.get('fps'), r.get('native')) for r in rows)
    return (report.get('failures') == [] and report.get('engine_errors') == []
            and len(ids) == 90 and report.get('saved_states') == 810
            and report.get('native_states') == 270 and report.get('stack_states') == 108
            and actual == expected and all(r.get('samples', 0) >= 1 for r in rows)
            and all(r.get('samples') == r['fps'] and len(r.get('order', [])) in (2, 3)
                    for r in rows if str(r.get('id', '')).startswith('stack_') and r.get('state') != 'undo'))

async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        suite = await call(client, 'test_run', {'suite': 'rig_modifier_history', 'verbose': True})
    passed = valid_suite(suite, EXPECTED)
    report = {}
    diagnostics = ''
    if passed:
        runtime = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
            '--script', 'res://tools/check_rig_modifier_history.gd'], capture_output=True, text=True, timeout=90, check=False)
        marker = 'RIG_MODIFIER_HISTORY_RUNTIME='
        payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
        report = json.loads(payload) if payload else {}
        passed = runtime.returncode == 0 and valid_runtime(report)
        diagnostics = '' if passed else (runtime.stdout + runtime.stderr)[-9000:]
    print('MCP_RIG_MODIFIER_HISTORY=' + json.dumps({'passed': passed, 'suite': suite,
        'runtime': report, 'diagnostics': diagnostics}, sort_keys=True))
    return 0 if passed else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
