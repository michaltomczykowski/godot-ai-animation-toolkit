"""Verify rig pose/chain history through the external Godot AI MCP route."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import subprocess
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call
from mcp_preset_library_history import valid_suite

EXPECTED = {
    'rig_pose_history': {'test_local_pose_history': 260, 'test_locked_pose_history': 300,
                         'test_editable_pose_history': 300, 'test_pose_file_and_shape_contracts': 26,
                         'test_registry_contract_categories': 2},
    'rig_chain_history': {'test_local_chain_history': 147, 'test_locked_chain_history': 171,
                          'test_editable_chain_history': 171, 'test_chain_rejections_have_no_effect': 24},
}

async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    reports = {}
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        for suite, expected in EXPECTED.items():
            reports[suite] = await call(client, 'test_run', {'suite': suite, 'verbose': True})
    passed = all(valid_suite(reports[name], expected) for name, expected in EXPECTED.items())
    runtimes = []
    if passed and not args.suite_only:
        for layout in ('local', 'locked', 'editable'):
            runtime = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
                '--script', 'res://tools/check_rig_pose_history.gd', '--', layout],
                capture_output=True, text=True, timeout=45, check=False)
            marker = 'RIG_POSE_HISTORY_RUNTIME='
            payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
            report = json.loads(payload) if payload else {}
            ok = runtime.returncode == 0 and report.get('saved_states') == 32 and report.get('failures') == [] and report.get('engine_errors') == []
            runtimes.append({'layout':layout, 'passed':ok, 'report':report, 'diagnostics':'' if ok else (runtime.stdout + runtime.stderr)[-5000:]})
            passed = passed and ok
    print('MCP_RIG_POSE_HISTORY=' + json.dumps({'passed':passed, 'results':reports,
        'saved_states':sum(r.get('report', {}).get('saved_states', 0) for r in runtimes), 'runtime':runtimes}, sort_keys=True))
    return 0 if passed else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--suite-only', action='store_true', help='Diagnostic suite check; not the CI gate')
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
