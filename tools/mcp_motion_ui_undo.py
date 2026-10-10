"""Create a motion clip through Godot AI, then inspect after editor undo/redo."""

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


SCENE_ROOT = "/RepairRigFixture"
PLAYER = SCENE_ROOT + "/AnimationPlayer"
SKELETON = SCENE_ROOT + "/Dummy/Skeleton3D"
async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row = {"mode": args.mode}
        if args.mode == "setup":
            run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"motion_{run_id}.tscn"
            copy_scene(args.project_root / "repair_rig_fixture.tscn", target)
            row["scene"] = "res://repair_ui_undo/" + target.name
            row["open"] = await call(client, "scene_open", {"path": row["scene"]})
            row["write"] = await call(client, "custom_animation_motion", {
                "op": args.op, "player_path": PLAYER,
                "skeleton_path": SKELETON, "animation_name": args.clip,
                "samples": 30, "duration": 1.0 if args.op == "cycle" else 0.5,
                "loop_mode": "linear" if args.op == "cycle" else "none",
                "root_motion": True})
        row["inspect"] = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": PLAYER,
            "animation_name": args.clip, "max_tracks": 200})
    print("MCP_MOTION_UI_UNDO=" + json.dumps(row, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=("setup", "inspect"), required=True)
    parser.add_argument("--op", choices=("cycle", "walk_start", "walk_stop"),
                        default="walk_start")
    parser.add_argument("--clip", default="undo_walk_start")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
