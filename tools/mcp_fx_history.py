"""Require the complete FX scene-history matrix through Godot AI's MCP runner."""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
import subprocess

from mcp_fx_audit import CASES

from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from mcp_presets_audit import call

EXPECTED = {
    "test_new_clip_scene_history", "test_overwritten_clip_scene_history",
    "test_missing_library_scene_history", "test_instanced_player_scene_history",
    "test_registry_has_a_history_case_for_every_fx_operation",
}


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        await call(client, "scene_open", {"path": "res://main.tscn"})
        result = await call(client, "test_run", {"suite": "fx_route_history", "verbose": True})
    rows = result.get("results", [])
    tests = {row.get("test") for row in rows}
    passed = (not result.get("error") and result.get("failed") == 0
              and result.get("passed") == len(EXPECTED)
              and result.get("total") == len(EXPECTED)
              and len(rows) == len(EXPECTED) and tests == EXPECTED
              and all(row.get("passed") and row.get("assertion_count", 0) > 0
                      for row in rows))
    playback_failures = []
    if passed and args.godot:
        for mode in ("new", "overwrite", "missing_library", "instanced"):
            for op in CASES:
                if op == "sprite_frames_stopped":
                    continue
                scene = f"user://fx_history_{op}_{mode}_redo.tscn"
                runtime = subprocess.run([
                    args.godot, "--headless", "--path", str(args.project_root),
                    "--script", "res://tools/check_fx_runtime.gd", "--",
                    scene, op, "generated", "FxHistory",
                ], capture_output=True, text=True, timeout=20, check=False)
                marker = "FX_RUNTIME="
                report = next((line[len(marker):] for line in runtime.stdout.splitlines()
                               if line.startswith(marker)), "")
                if runtime.returncode or not report or json.loads(report).get("failures"):
                    playback_failures.append({"op": op, "mode": mode,
                                              "output": (runtime.stdout + runtime.stderr)[-1800:]})
        passed = not playback_failures
    print("MCP_FX_HISTORY=" + json.dumps({"passed": passed, "result": result,
          "playback_failures": playback_failures,
          "saved_playback_cases": 64 if args.godot and not playback_failures and passed else 0}, sort_keys=True))
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--godot", help="Also play all 64 saved redone scenes in fresh processes")
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
