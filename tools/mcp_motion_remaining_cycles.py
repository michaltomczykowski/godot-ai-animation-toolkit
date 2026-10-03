"""Exercise saved motion clips, including the run preset, through live Godot AI."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from fixture_copy import copy_scene
from mcp_presets_audit import call


SKELETON = "/RepairRigFixture/Dummy/Skeleton3D"
PLAYER = "/RepairRigFixture/AnimationPlayer"
CASES = {
    "walk_cycle": {"duration": 1.0, "loop_mode": "linear",
                   "root_motion": True},
    "idle_cycle": {"duration": 2.0, "loop_mode": "linear",
                   "root_motion": False},
    "cycle": {"preset": "walk", "duration": 1.0,
              "loop_mode": "linear", "root_motion": True},
    "run_cycle": {"preset": "run", "duration": 1.0,
                  "loop_mode": "linear", "root_motion": True},
    "jump": {"duration": 1.0, "loop_mode": "none",
             "root_motion": True, "height": 0.3, "distance": 0.5},
    "turn_cycle": {"duration": 1.0, "loop_mode": "none",
                   "root_motion": False},
    "strafe_cycle": {"duration": 1.0, "loop_mode": "linear",
                     "root_motion": True},
    "walk_start": {"duration": 0.5, "loop_mode": "none",
                   "root_motion": True},
    "walk_stop": {"duration": 0.5, "loop_mode": "none",
                  "root_motion": True},
}


async def inspect(client: Client, name: str, player: str) -> dict:
    value = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": player,
        "animation_name": name, "max_tracks": 200})
    if value.get("error"):
        return value
    return {"clips": [{"name": c.get("name"), "length": c.get("length"),
        "loop_mode": c.get("loop_mode"), "key_count": c.get("key_count"),
        "tracks": [{"path": t.get("path"), "type": t.get("type"),
                    "node_resolved": t.get("node_resolved")}
                   for t in c.get("tracks", [])]}
        for c in value.get("clips", [])]}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_motion_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = []
    xbot = args.rig == "xbot"
    fixture = ("repair_xbot_fixture.tscn" if xbot else
               args.fixture or "repair_rig_fixture.tscn")
    skeleton = "/MotionXBot/XBot/Skeleton3D" if xbot else SKELETON
    player = "/MotionXBot/WalkAnim" if xbot else PLAYER
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        selected = args.ops if args.ops else list(CASES)
        for op in selected:
            extras = CASES[op]
            copy_scene(args.project_root / fixture,
                       folder / f"{op}.tscn")
            scene = f"res://repair_motion_audit/{run_id}/{op}.tscn"
            row = {"op": op, "scene": scene}
            row["open"] = await call(client, "scene_open", {"path": scene})
            params = {"op": op, "player_path": player,
                      "skeleton_path": skeleton, "animation_name": op,
                      "samples": 30, **extras}
            if args.use_default_root_motion and op == "strafe_cycle":
                params.pop("root_motion")
            if args.direction is not None and op == "strafe_cycle":
                params["direction"] = args.direction
            if args.phase is not None and op in ("walk_start", "walk_stop"):
                params["phase"] = args.phase
            if args.knee_bend is not None and op in ("cycle", "strafe_cycle", "walk_start", "walk_stop"):
                params["knee_bend"] = args.knee_bend
            if args.sway is not None and op in ("cycle", "run_cycle", "strafe_cycle", "walk_start", "walk_stop"):
                params["sway"] = args.sway
            if args.stride is not None and op in ("cycle", "strafe_cycle", "walk_start", "walk_stop"):
                params["stride"] = args.stride
            if args.style is not None and op in ("cycle", "strafe_cycle", "walk_start", "walk_stop"):
                params["style"] = args.style
            row["before"] = await inspect(client, op, player)
            row["dry"] = await call(client, "custom_animation_motion",
                                    {**params, "dry_run": True})
            row["after_dry"] = await inspect(client, op, player)
            row["write"] = await call(client, "custom_animation_motion", params)
            row["after"] = await inspect(client, op, player)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = await inspect(client, op, player)
            row["invalid"] = await call(client, "custom_animation_motion", {
                **params, "skeleton_path": "/DefinitelyMissingSkeleton"})
            rows.append(row)
    failures = []
    for row in rows:
        op = row["op"]
        for stage in ("open", "dry", "write", "save", "reopen"):
            if row[stage].get("error"):
                failures.append(f"{op}: {stage}: {row[stage]['error']}")
        if row["before"] != row["after_dry"]:
            failures.append(f"{op}: dry run changed clip")
        if row["after"] != row["persisted"]:
            failures.append(f"{op}: clip failed save/reopen")
        clips = row["persisted"].get("clips", [])
        if len(clips) != 1 or not clips[0]["tracks"] or not all(
                t.get("node_resolved") for t in clips[0]["tracks"]):
            failures.append(f"{op}: missing clip or unresolved target")
        if not row["invalid"].get("error", "").startswith("NODE_NOT_FOUND:"):
            failures.append(f"{op}: invalid skeleton lacks typed error")
    print("MCP_MOTION_REMAINING=" + json.dumps({"run_id": run_id,
        "operations": rows, "failures": failures}, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--rig", choices=("dummy", "xbot"), default="dummy")
    parser.add_argument("--fixture", help="Scene filename under project root for a dummy-layout synthetic rig")
    parser.add_argument("--direction", choices=("left", "right"),
                        help="Strafe direction to exercise through Godot AI")
    parser.add_argument("--use-default-root-motion", action="store_true",
                        help="Omit strafe root_motion to exercise the public default")
    parser.add_argument("--ops", choices=list(CASES), nargs="*",
                        help="Subset of operations to test; defaults to all")
    parser.add_argument("--phase", type=float,
                        help="Override gait phase for walk_start/walk_stop review")
    parser.add_argument("--knee-bend", type=float,
                        help="Override walk knee bend for visual review")
    parser.add_argument("--sway", type=float,
                        help="Override gait pelvis sway in metres for visual review")
    parser.add_argument("--stride", type=float,
                        help="Override walk stride angle in degrees for visual review")
    parser.add_argument("--style", choices=("default", "relaxed", "heavy", "sneaky"),
                        help="Walk style to exercise through Godot AI")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
