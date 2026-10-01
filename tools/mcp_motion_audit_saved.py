"""Run played world-space motion audits on saved clips via Godot AI."""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


OPS = ("idle_cycle", "cycle", "jump", "turn_cycle",
       "strafe_cycle", "walk_start", "walk_stop")
ROOT = "/RepairRigFixture"


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = []
    root = "/MotionXBot" if args.rig == "xbot" else ROOT
    player = root + ("/WalkAnim" if args.rig == "xbot" else "/AnimationPlayer")
    skeleton = root + ("/XBot/Skeleton3D" if args.rig == "xbot" else "/Dummy/Skeleton3D")
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op in args.ops or OPS:
            scene = f"res://repair_motion_audit/{args.run_id}/{op}.tscn"
            opened = await call(client, "scene_open", {"path": scene})
            for fps in (30, 60, 120):
                params = {
                    "op": "motion_audit", "player_path": player,
                    "skeleton_path": skeleton,
                    "animation_name": op, "samples": fps + 1,
                    "motion_kind": ("jump" if op == "jump" else
                                    "turn" if op == "turn_cycle" else
                                    "strafe" if op == "strafe_cycle" else
                                    "transition" if op in ("walk_start", "walk_stop") else "gait"),
                    "max_slide": args.max_slide}
                if args.contact_threshold is not None:
                    params["contact_threshold"] = args.contact_threshold
                result = await call(client, "custom_animation_inspect", params)
                feet = result.get("feet", {})
                rows.append({"op": op, "fps": fps, "scene": scene,
                    "open_error": opened.get("error"), "error": result.get("error"),
                    "passed": result.get("passed"),
                    "failed_checks": result.get("failed_checks", []),
                    "body_travel": result.get("body_travel"),
                    "min_lateral_foot_gap": result.get("min_lateral_foot_gap"),
                    "failed_details": [c for c in result.get("checks", [])
                                       if not c.get("passed", True)],
                    "feet": {side: {key: foot.get(key) for key in
                        ("contact_time", "worst_slide", "max_penetration",
                         "penetration_budget", "penetration_time", "knee_pole",
                         "pose_range",
                         "windows")}
                        for side, foot in feet.items()}})
    print("MCP_MOTION_SAVED_AUDIT=" + json.dumps(rows, sort_keys=True))
    return 0 if all(not row["open_error"] and not row["error"] for row in rows) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--rig", choices=("dummy", "xbot"), default="dummy")
    parser.add_argument("--max-slide", type=float, default=0.016,
                        help="Played stance-slide cap in metres")
    parser.add_argument("--contact-threshold", type=float,
                        help="Explicit contact height in metres (default uses rig-scaled ceiling)")
    parser.add_argument("--ops", choices=OPS, nargs="*",
                        help="Subset of saved clips to audit; defaults to all")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
