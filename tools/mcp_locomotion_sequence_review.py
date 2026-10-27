"""Build and compose start/walk/stop on one X Bot through Godot AI."""

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


PLAYER = "/MotionXBot/WalkAnim"
SKELETON = "/MotionXBot/XBot/Skeleton3D"


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_locomotion_sequence" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    target = folder / "compose.tscn"
    copy_scene(args.project_root / "repair_xbot_fixture.tscn", target)
    scene = f"res://repair_locomotion_sequence/{run_id}/compose.tscn"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"run_id": run_id, "scene": scene}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        for op, duration in (("walk_start", 0.5), ("cycle", 1.0),
                             ("walk_stop", 0.5)):
            motion_params = {
                "op": op, "player_path": PLAYER, "skeleton_path": SKELETON,
                "animation_name": op, "duration": duration,
                "loop_mode": "linear" if op == "cycle" else "none",
                "root_motion": True, "samples": 30}
            if args.stride is not None:
                motion_params["stride"] = args.stride
            if args.knee_bend is not None:
                motion_params["knee_bend"] = args.knee_bend
            row[op] = await call(client, "custom_animation_motion", motion_params)
        sequence = {"op": "compose", "player_path": PLAYER,
                    "skeleton_path": SKELETON,
                    "animation_name": "start_walk_stop", "duration": 2.0,
                    "samples": 60, "segments": [
                        {"start": 0.0, "duration": 0.5,
                         "source_animation": "walk_start"},
                        {"start": 0.5, "duration": 1.0,
                         "source_animation": "cycle", "fade_in": 0.1},
                        {"start": 1.5, "duration": 0.5,
                         "source_animation": "walk_stop", "fade_in": 0.1},
                    ]}
        row["sequence_dry"] = await call(client, "custom_manage", {
            "op": "invoke", "params": {"tool_name": "animation_sequence",
            "params": {**sequence, "dry_run": True}}})
        row["sequence"] = await call(client, "custom_manage", {
            "op": "invoke", "params": {"tool_name": "animation_sequence",
            "params": sequence}})
        row["describe"] = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": PLAYER,
            "animation_name": "start_walk_stop", "max_tracks": 200})
        if not args.stop_before_save:
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["audit"] = await call(client, "custom_animation_inspect", {
                "op": "motion_audit", "player_path": PLAYER,
                "skeleton_path": SKELETON,
                "animation_name": "start_walk_stop", "samples": 241,
                "motion_kind": "transition", "max_slide": 0.016})
    print("MCP_LOCOMOTION_SEQUENCE=" + json.dumps(row, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--stride", type=float)
    parser.add_argument("--knee-bend", type=float)
    parser.add_argument("--stop-before-save", action="store_true",
                        help="Keep the composed clip as the editor's last undo action")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
