"""Require every modifier's allocation contract through the Godot AI route."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import sys
import subprocess
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call
from mcp_preset_library_history import valid_suite
from gate_diagnostics import bounded_run, progress

EXPECTED = {
    'test_ik_allocation': 234,
    'test_look_at_allocation_and_refusal': 264,
    'test_twist_allocation_and_refusal': 183,
    'test_spring_allocation_and_refusal': 212,
    'test_retarget_allocation_and_refusal': 162,
    'test_look_at_external_origin_contract': 59,
    'test_registry_allocation_coverage': 1,
    'test_spring_center_and_collision_contracts': 319,
}

async def run(args: argparse.Namespace) -> int:
    def stage(name, **details):
        progress(args, name, marker='RIG_MODIFIER_ALLOCATION_PROGRESS', **details)

    stage('attach_start')
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        stage('session_activate_start')
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        stage('scene_open_start')
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        stage('test_run_start')
        suite = await call(client, 'test_run', {'suite': 'rig_modifier_allocation', 'verbose': True})
        stage('test_run_returned_client_close_start')
    stage('client_closed')
    passed = valid_suite(suite, EXPECTED)
    report = {}
    diagnostics = ''
    if passed:
        stage('native_start')
        command = [args.godot, '--headless', '--path', str(args.project_root),
                   '--script', 'res://tools/check_rig_modifier_origin.gd']
        record = getattr(args, 'record', None)
        runtime = (bounded_run(command, 45, record, 'modifier_origin') if record else
                   subprocess.run(command, capture_output=True, text=True, timeout=45, check=False))
        stage('native_returned', native_returncode=runtime.returncode)
        marker = 'RIG_MODIFIER_ORIGIN_RUNTIME='
        payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
        report = json.loads(payload) if payload else {}
        passed = runtime.returncode == 0 and report.get('played_states') == 4 and report.get('failures') == [] and report.get('engine_errors') == []
        diagnostics = '' if passed else (runtime.stdout + runtime.stderr)[-6000:]
    print('MCP_RIG_MODIFIER_ALLOCATION=' + json.dumps({'passed': passed, 'suite': suite,
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
    parser.add_argument('--record', type=Path)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
