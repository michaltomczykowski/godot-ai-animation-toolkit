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
from operation_case_collector import record_native_result
from mcp_preset_library_history import valid_suite, progress

EXPECTED = {'test_local_history': 441, 'test_overwrite_history': 450,
            'test_missing_library_history': 414, 'test_instanced_history': 495,
            'test_editable_history': 495, 'test_registry_writers_covered': 1}

async def run(args: argparse.Namespace) -> int:
    args.progress_marker='RIG_CLIP_PROGRESS'
    progress(args,'connecting')
    transport = StdioTransport(sys.executable, ['-m', 'godot_ai', 'attach', '--port', str(args.port),
        '--ws-port', str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        progress(args,'session_activate_start')
        await client.call_tool('session_activate', {'session_id': args.session_hint})
        progress(args,'scene_open_start')
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        progress(args,'suite_start',suite='rig_clip_history')
        suite = await call(client, 'test_run', {'suite': 'rig_clip_history', 'verbose': True})
        progress(args,'suite_returned',suite='rig_clip_history',suite_result=suite)
        progress(args,'transport_exit_start')
    progress(args,'transport_exit_completed')
    passed = valid_suite(suite, EXPECTED)
    runtimes = []
    if passed:
        for layout in ('local', 'overwrite', 'missing_library', 'instanced', 'editable'):
            progress(args,'native_start',layout=layout)
            command = [args.godot, '--headless', '--path', str(args.project_root),
                '--script', 'res://tools/check_rig_clip_history.gd', '--', layout]
            runtime = subprocess.run(command,
                capture_output=True, text=True, timeout=45, check=False)
            for op in ('pose_to_clip', 'walk_cycle', 'idle_breathing', 'blink', 'jumping_jack', 'squat', 'punch', 'bake_pose_sequence'):
                record_native_result('animation_rig.' + op,
                    f'user://rig_clip_history_{layout}_3d_{op}_redo.tscn', command, runtime)
            marker = 'RIG_CLIP_HISTORY_RUNTIME='
            payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), '')
            report = json.loads(payload) if payload else {}
            ok = runtime.returncode == 0 and report.get('saved_states') == 18 and report.get('failures') == [] and report.get('engine_errors') == []
            runtimes.append({'layout': layout, 'passed': ok, 'report': report,
                'diagnostics': '' if ok else (runtime.stdout + runtime.stderr)[-6000:]})
            passed = passed and ok
            progress(args,'native_returned',layout=layout,runtime=runtimes)
    print('MCP_RIG_CLIP_HISTORY=' + json.dumps({'passed': passed, 'suite': suite,
        'saved_states': sum(row['report'].get('saved_states', 0) for row in runtimes), 'runtime': runtimes}, sort_keys=True))
    progress(args,'completed',passed=passed)
    return 0 if passed else 1

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--record',type=Path,help='Durable phase diagnostics, not qualification')
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
