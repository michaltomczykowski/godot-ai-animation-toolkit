"""Require graph history and error-free saved playback through Godot AI."""
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

EXPECTED = {"test_new_graph_scene_history", "test_replaced_graph_scene_history",
            "test_instanced_graph_scene_history", "test_graph_get_is_read_only",
            "test_instanced_new_graph_scene_history",
            "test_wire_parameter_validation_and_history",
            "test_wire_vector_bool_and_enum_parameters",
            "test_registry_has_a_graph_history_case_for_every_operation"}
OPS = ("state_machine", "blend_space", "blend_tree", "wire", "locomotion",
       "one_shot_layer", "additive_lean")


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        await call(client, "scene_open", {"path": "res://main.tscn"})
        result = await call(client, "test_run", {"suite": "graph_route_history", "verbose": True})
    rows = result.get("results", [])
    passed = (result.get("failed") == 0 and result.get("passed") == len(EXPECTED)
              and result.get("total") == len(EXPECTED) and len(rows) == len(EXPECTED)
              and {row.get("test") for row in rows} == EXPECTED
              and all(row.get("passed") and row.get("assertion_count", 0) > 0 for row in rows))
    failures = []
    count = 0
    if passed and args.godot:
        for mode in ("new", "replace", "instanced", "instanced_new"):
            for op in OPS:
                try:
                    runtime = subprocess.run([
                        args.godot, "--headless", "--path", str(args.project_root),
                        "--script", "res://tools/check_graph_history_runtime.gd", "--",
                        f"user://graph_history_{op}_{mode}_redo.tscn", op,
                    ], capture_output=True, text=True, timeout=20, check=False)
                except subprocess.TimeoutExpired as exc:
                    failures.append({"op": op, "mode": mode,
                                     "error": "saved playback exceeded 20 seconds",
                                     "output": str(exc.stdout or "")[-2200:]})
                    continue
                marker = "GRAPH_HISTORY_RUNTIME="
                report = next((line[len(marker):] for line in runtime.stdout.splitlines()
                               if line.startswith(marker)), "")
                if runtime.returncode or not report or json.loads(report).get("failures"):
                    failures.append({"op": op, "mode": mode,
                                     "output": (runtime.stdout + runtime.stderr)[-2200:]})
                else:
                    count += 1
    passed = passed and not failures
    print("MCP_GRAPH_HISTORY=" + json.dumps({"passed": passed, "result": result,
          "saved_cases": count, "runtime_failures": failures}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--godot")
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
