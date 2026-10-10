"""Run every rig clip writer's history and independent saved playback gate."""
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

EXPECTED = {'test_local_history': 441, 'test_overwrite_history': 450,
            'test_missing_library_history': 414, 'test_instanced_history': 495,
            'test_editable_history': 495, 'test_registry_writers_covered': 1}

async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        suite = await call(client, 'test_run', {'suite': 'rig_clip_history', 'verbose': True})
    passed = valid_suite(suite, EXPECTED)
    runtimes = []
    if passed:
        for layout in ('local', 'overwrite', 'missing_library', 'instanced', 'editable'):
            runtime = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
                '--script', 'res://tools/check_rig_clip_history.gd', '--', layout],
                capture_output=True, text=True, timeout=45, check=False)
            marker = 'RIG_CLIP_HISTORY_RUNTIME='
            payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
            report = json.loads(payload) if payload else {}
            ok = runtime.returncode == 0 and report.get('saved_states') == 18 and report.get('failures') == [] and report.get('engine_errors') == []
            runtimes.append({'layout': layout, 'passed': ok, 'report': report,
                'diagnostics': '' if ok else (runtime.stdout + runtime.stderr)[-6000:]})
            passed = passed and ok
    print('MCP_RIG_CLIP_HISTORY=' + json.dumps({'passed': passed, 'suite': suite,
        'saved_states': sum(row['report'].get('saved_states', 0) for row in runtimes), 'runtime': runtimes}, sort_keys=True))
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
