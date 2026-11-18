"""Create or inspect an unsaved graph action for visible editor Undo/Redo."""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from fixture_copy import copy_scene
from mcp_presets_audit import call


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    result = {"mode": args.mode}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            target = folder / f"graph_{stamp}.tscn"
            copy_scene(args.project_root / "repair_graph_fixture.tscn", target)
            result["open"] = await call(client, "scene_open", {"path": "res://repair_ui_undo/" + target.name})
            result["create"] = await call(client, "custom_animation_graph", {
                "op": "state_machine", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "states": [{"name": "idle", "animation": "idle"},
                           {"name": "walk", "animation": "walk"}],
                "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1}],
            })
        result["graph"] = await call(client, "custom_animation_graph", {
            "op": "graph_get", "tree_path": "/RepairGraphFixture/AnimationTree"})
    print("MCP_GRAPH_UI_HISTORY=" + json.dumps(result, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=("setup", "inspect"), required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
