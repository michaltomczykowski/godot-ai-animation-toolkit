"""Require every clip edit's scene history through the actual Godot AI route."""
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

EXPECTED = {"test_registry_has_a_history_case_for_every_edit_operation": 1,
            "test_local_scene_history": 900, "test_instanced_scene_history": 1000,
            "test_editable_instance_scene_history": 1000}
CONTRACTS = {"test_3d_and_value_metadata_survive_retime_history": 10,
             "test_compressed_sources_are_rejected_consistently": 40,
             "test_unsupported_sources_are_rejected_consistently": 40}


def valid_suite(result: dict, expected: dict[str, int]) -> bool:
    rows = result.get("results", [])
    return (result.get("failed") == 0 and result.get("skipped", 0) == 0
            and result.get("passed") == len(expected) and result.get("total") == len(expected)
            and len(rows) == len(expected) and {r.get("test") for r in rows} == set(expected)
            and all(r.get("passed") and r.get("assertion_count", 0) >= expected[r["test"]]
                    for r in rows))


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port)], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        await call(client, "scene_open", {"path": "res://main.tscn"})
        result = await call(client, "test_run", {"suite": "edit_route_history", "verbose": True})
        contracts = await call(client, "test_run", {"suite": "edit_contracts", "verbose": True})
    passed = valid_suite(result, EXPECTED) and valid_suite(contracts, CONTRACTS)
    runtimes = []
    if passed:
        for layout in ("local", "instanced", "editable"):
            try:
                runtime = subprocess.run([args.godot, "--headless", "--path", str(args.project_root),
                    "--script", "res://tools/check_edit_history_runtime.gd", "--", layout],
                    capture_output=True, text=True, timeout=30, check=False)
                marker = "EDIT_HISTORY_RUNTIME="
                payload = next((line[len(marker):] for line in runtime.stdout.splitlines()
                                if line.startswith(marker)), "")
                report = json.loads(payload) if payload else {}
                ok = (runtime.returncode == 0 and report.get("saved_states") == 48
                      and report.get("failures") == [] and report.get("engine_errors") == [])
                runtimes.append({"layout": layout, "passed": ok, "report": report,
                                 "diagnostics": "" if ok else (runtime.stdout + runtime.stderr)[-5000:]})
                passed = passed and ok
            except subprocess.TimeoutExpired:
                passed = False
                runtimes.append({"layout": layout, "passed": False, "error": "playback timeout"})
        runtime = subprocess.run([args.godot, "--headless", "--path", str(args.project_root),
            "--script", "res://tools/check_edit_contracts_runtime.gd"], capture_output=True,
            text=True, timeout=20, check=False)
        marker = "EDIT_CONTRACTS_RUNTIME="
        payload = next((line[len(marker):] for line in runtime.stdout.splitlines() if line.startswith(marker)), "")
        report = json.loads(payload) if payload else {}
        ok = runtime.returncode == 0 and report.get("saved_states") == 2 and report.get("failures") == [] and report.get("engine_errors") == []
        runtimes.append({"layout": "3d", "passed": ok, "report": report,
                         "diagnostics": "" if ok else (runtime.stdout + runtime.stderr)[-5000:]})
        passed = passed and ok
    print("MCP_EDIT_HISTORY=" + json.dumps({"passed": passed, "result": result, "contracts": contracts,
          "saved_states": sum(r.get("report", {}).get("saved_states", 0) for r in runtimes),
          "runtime": runtimes}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
