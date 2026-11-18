"""Exercise a rooted walk through the real Godot AI MCP route and disk replay."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport


def payload(result: object) -> dict:
    data = result.structured_content or {}
    if not data and result.content:
        data = json.loads(result.content[0].text)
    return data


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, [
        "-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port),
    ], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        await client.call_tool("scene_open", {"path": args.scene,
                                              "force_reload": True})
        params = {
            "op": args.op, "player_path": args.player_path,
            "skeleton_path": args.skeleton_path,
            "animation_name": args.animation_name, "duration": args.duration,
            "loop_mode": "linear", "root_motion": True, "samples": args.samples,
            "overwrite": True,
        }
        if args.overrides:
            params["overrides"] = json.loads(args.overrides)
        dry = payload(await client.call_tool("custom_animation_motion", {**params, "dry_run": True}))
        built = payload(await client.call_tool("custom_animation_motion", params))
        audit_args = {"op": "motion_audit", "player_path": params["player_path"],
                      "skeleton_path": params["skeleton_path"],
                      "animation_name": params["animation_name"], "samples": 120}
        audit = payload(await client.call_tool("custom_animation_inspect", audit_args))
        await client.call_tool("scene_save", {})
        await client.call_tool("scene_open", {"path": args.scene,
                                              "force_reload": True})
        after = payload(await client.call_tool("custom_animation_inspect", audit_args))
        preview = {}
        if args.preview:
            preview = payload(await client.call_tool("custom_animation_inspect", {
                "op": "preview", "player_path": params["player_path"],
                "skeleton_path": params["skeleton_path"],
                "animation_name": params["animation_name"], "samples": 8,
                "output_dir": "res://animation_toolkit/previews/repair_motion",
                "basename": "rooted_walk", "overwrite": True,
            }))
        summary = {
            "dry_run": dry,
            "built": built,
            "before_save": {"passed": audit.get("passed"), "body_travel": audit.get("body_travel"),
                            "feet": {side: {key: foot.get(key) for key in
                                            ("contact_time", "worst_slide", "max_penetration", "penetration_time", "penetration_budget", "knee_pole", "ground", "windows")}
                                     | {"trace_every_12": foot.get("trace", [])[::12],
                                        "trace_toe_off": foot.get("trace", [])[70:82],
                                        "trace_loop": foot.get("trace", [])[-8:]}
                                     for side, foot in audit.get("feet", {}).items()},
                            "failed_checks": audit.get("failed_checks")},
            "after_reopen": {"passed": after.get("passed"),
                             "body_travel": after.get("body_travel"),
                             "failed_checks": after.get("failed_checks")},
            "preview_paths": preview.get("paths", []),
        }
        print("MCP_MOTION_FIXTURE=" + json.dumps(summary, sort_keys=True))
        return 0 if audit.get("passed") and after.get("passed") \
            and float(after.get("body_travel", 0)) > 0.5 \
            and built.get("root_motion_track", "").endswith(":position") else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--op", choices=["walk_cycle", "run_cycle"], default="walk_cycle")
    parser.add_argument("--animation-name", default="repair_probe_walk")
    parser.add_argument("--samples", type=float, default=120.0)
    parser.add_argument("--duration", type=float, default=1.0)
    parser.add_argument("--overrides", default="")
    parser.add_argument("--scene", default="res://repair_motion_fixture.tscn")
    parser.add_argument("--player-path", default="/MotionWalk/WalkAnim")
    parser.add_argument("--skeleton-path", default="/MotionWalk/Dummy/Skeleton3D")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
