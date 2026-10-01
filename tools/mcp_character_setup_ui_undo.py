"""Create a character setup through Godot AI and inspect its editor undo state."""

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


ROOT = "/RepairRigFixture"
PLAYER = ROOT + "/AnimationPlayer"
SKELETON = ROOT + "/Dummy/Skeleton3D"
TREE = ROOT + "/AnimationTree"


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row: dict = {"mode": args.mode}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"character_setup_{run_id}.tscn"
            copy_scene(args.project_root / "repair_rig_fixture.tscn", target)
            row["scene"] = "res://repair_ui_undo/" + target.name
            row["open"] = await call(client, "scene_open", {"path": row["scene"]})
            row["write"] = await call(client, "custom_animation_motion", {
                "op": "character_setup", "player_path": PLAYER,
                "skeleton_path": SKELETON, "duration": 1.0,
                "run_duration": 0.7, "include_jump": True,
                "root_motion": True, "samples": 30})
        row["clips"] = {name: await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": PLAYER,
            "animation_name": name, "max_tracks": 200})
            for name in ("idle", "walk", "run", "jump")}
        row["tree"] = await call(client, "node_get_properties", {
            "path": TREE, "fields": ["active", "anim_player",
                                     "root_motion_track"]})
        row["player"] = await call(client, "node_get_properties", {
            "path": PLAYER, "fields": ["root_motion_track"]})
    print("MCP_CHARACTER_SETUP_UI_UNDO=" + json.dumps(row, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=("setup", "inspect"), required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
