"""Verify bake playback state and saved clips via the external Godot AI route."""
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

STATES = ('unassigned', 'paused', 'stopped', 'playing', 'reverse', 'zero_scale', 'other_source', 'section')

async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        suite = await call(client, 'test_run', {'suite': 'rig_bake_state', 'verbose': True})
    expected = {('test_other_source_state' if state == 'other_source' else f'test_{state}_source_state'): 40 if state == 'zero_scale' else 35 for state in STATES}
    passed = valid_suite(suite, expected)
    report = {}
    diagnostics = ''
    if passed:
        runtime = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
            '--script', 'res://tools/check_rig_bake_state.gd'], capture_output=True, text=True, timeout=45, check=False)
        marker = 'RIG_BAKE_STATE_RUNTIME='
        payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
        report = json.loads(payload) if payload else {}
        passed = runtime.returncode == 0 and report.get('saved_states') == 16 and report.get('failures') == [] and report.get('engine_errors') == []
        if not passed: diagnostics = (runtime.stdout + runtime.stderr)[-5000:]
    print('MCP_RIG_BAKE_STATE=' + json.dumps({'passed': passed, 'suite': suite, 'runtime': report, 'diagnostics': diagnostics}, sort_keys=True))
    return 0 if passed else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--godot', required=True)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
