"""Require preset and library history through the actual Godot AI route."""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import subprocess
import sys
import os
import time
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call

EXPECTED = {"test_registry_operations_covered": 1,
            "test_local_history": 300, "test_overwrite_history": 320,
            "test_missing_library_history": 250, "test_instanced_history": 350,
            "test_editable_history": 350, "test_showcase_subtree_history": 60}
CONTRACTS = {"test_file_operations_preserve_history_and_dry_bytes": 30,
             "test_invalid_destinations_and_unexportable_values_leave_no_effect": 25,
             "test_safe_paths_and_malformed_documents_are_typed": 55,
             "test_typed_export_apply_preserves_metadata_and_history": 35}


def progress(args, stage, **values):
    """Persist the last phase/payload before another potentially blocking await."""
    if not hasattr(args,'_started'):
        args._started=time.perf_counter()
        args._progress={'events':[]}
    event={'stage':stage,'elapsed_seconds':round(time.perf_counter()-args._started,6)}
    event.update({key:value for key,value in values.items() if key in ('suite','layout')})
    args._progress.update(values)
    args._progress['stage']=stage
    args._progress['events'].append(event)
    print(getattr(args,'progress_marker','PRESET_LIBRARY_PROGRESS')+'='+json.dumps(event,sort_keys=True),flush=True)
    if args.record:
        target=args.record.with_suffix('.progress.json')
        pending=args.record.with_suffix('.progress.pending')
        target.parent.mkdir(parents=True,exist_ok=True)
        with pending.open('w',encoding='utf-8') as stream:
            json.dump(args._progress,stream,indent=2);stream.flush();os.fsync(stream.fileno())
        pending.replace(target)


def valid_suite(result: dict, expected: dict[str, int]) -> bool:
    rows = result.get("results", [])
    return (result.get("failed") == 0 and result.get("skipped", 0) == 0
            and result.get("passed") == len(expected) and result.get("total") == len(expected)
            and len(rows) == len(expected) and {r.get("test") for r in rows} == set(expected)
            and all(r.get("passed") and r.get("assertion_count", 0) >= expected[r["test"]]
                    for r in rows))


async def run(args: argparse.Namespace) -> int:
    progress(args,'connecting')
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        progress(args,'session_activate_start')
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        progress(args,'scene_open_start')
        await call(client, "scene_open", {"path": "res://main.tscn"})
        progress(args,'suite_start',suite='preset_library_history')
        result = await call(client, "test_run", {"suite": "preset_library_history", "verbose": True})
        progress(args,'suite_returned',suite='preset_library_history',result=result)
        progress(args,'suite_start',suite='library_contracts')
        contracts = await call(client, "test_run", {"suite": "library_contracts", "verbose": True})
        progress(args,'suite_returned',suite='library_contracts',contracts=contracts)
        progress(args,'transport_exit_start')
    progress(args,'transport_exit_completed')
    passed = valid_suite(result, EXPECTED) and valid_suite(contracts, CONTRACTS)
    runtimes = []
    if passed and not args.suite_only:
        for layout, count in (("local", 22), ("overwrite", 22), ("missing_library", 22),
                              ("instanced", 22), ("editable", 22), ("showcase", 8), ("typed", 8)):
            progress(args,'native_start',layout=layout)
            runtime = subprocess.run([args.godot, "--headless", "--path", str(args.project_root),
                "--script", "res://tools/check_preset_library_history.gd", "--", layout],
                capture_output=True, text=True, timeout=45, check=False)
            marker = "PRESET_LIBRARY_HISTORY_RUNTIME="
            payload = next((line[len(marker):] for line in runtime.stdout.splitlines()
                            if line.startswith(marker)), "")
            report = json.loads(payload) if payload else {}
            ok = (runtime.returncode == 0 and report.get("saved_states") == count
                  and report.get("failures") == [] and report.get("engine_errors") == [])
            runtimes.append({"layout": layout, "passed": ok, "report": report,
                             "diagnostics": "" if ok else (runtime.stdout + runtime.stderr)[-5000:]})
            passed = passed and ok
            progress(args,'native_returned',layout=layout,runtime=runtimes)
    print("MCP_PRESET_LIBRARY_HISTORY=" + json.dumps({"passed": passed, "result": result, "contracts": contracts,
          "saved_states": sum(r.get("report", {}).get("saved_states", 0) for r in runtimes),
          "runtime": runtimes}, sort_keys=True))
    progress(args,'completed',passed=passed)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--suite-only", action="store_true", help="Diagnostic baseline; not the CI gate")
    parser.add_argument("--record",type=Path,help="Durable phase diagnostics, not qualification")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
