"""Render saved motion clips through Godot AI's live preview tool."""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    root = "/MotionXBot" if args.rig == "xbot" else "/RepairRigFixture"
    player = root + ("/WalkAnim" if args.rig == "xbot" else "/AnimationPlayer")
    skeleton = root + ("/XBot/Skeleton3D" if args.rig == "xbot" else "/Dummy/Skeleton3D")
    rows = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op in args.ops:
            scene = f"res://repair_motion_audit/{args.run_id}/{op}.tscn"
            opened = await call(client, "scene_open", {"path": scene})
            times = ([0.0, 0.2, 0.3, 0.47, 0.62, 0.8, 1.0] if op == "jump"
                     else [0.0, 0.14, 0.3, 0.55, 0.8, 1.0] if op == "turn_cycle"
                     else [0.0, 0.1, 0.2, 0.3, 0.4, 0.5])
            preview = await call(client, "custom_animation_inspect", {
                "op": "preview", "player_path": player,
                "skeleton_path": skeleton, "animation_name": op,
                "times": times, "width": 600, "height": 600,
                "output_dir": f"res://animation_toolkit/previews/repair_{args.rig}_{args.run_id}",
                "basename": op, "overwrite": True})
            paths = preview.get("paths", [])
            files = [args.project_root / p.removeprefix("res://") for p in paths]
            rows.append({"op": op, "scene": scene, "open_error": opened.get("error"),
                         "preview_error": preview.get("error"), "paths": paths,
                         "times": times, "missing": [str(p) for p in files
                             if not p.is_file() or p.stat().st_size < 1000]})
    print("MCP_MOTION_PREVIEW=" + json.dumps(rows, sort_keys=True))
    return 0 if all(not row["open_error"] and not row["preview_error"]
                    and not row["missing"] and len(row["paths"]) == len(row["times"])
                    for row in rows) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--rig", choices=("dummy", "xbot"), required=True)
    parser.add_argument("--ops", nargs="+", choices=("jump", "turn_cycle", "walk_start", "walk_stop"),
                        required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
