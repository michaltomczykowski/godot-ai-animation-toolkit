"""Set up/read an unsaved imported-dummy pose action for editor undo/redo."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
import math
from fixture_copy import copy_scene
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


SKELETON = "/RepairRigFixture/Dummy/Skeleton3D"
BONE = "B-upperArm.L"


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"mode": args.mode}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        if args.mode == "setup":
            run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            folder = args.project_root / "repair_ui_undo"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"rig_pose_{run_id}.tscn"
            copy_scene(args.project_root / "repair_rig_fixture.tscn", target)
            row["scene"] = "res://repair_ui_undo/" + target.name
            row["open"] = await call(client, "scene_open", {"path": row["scene"]})
            row["create"] = await call(client, "custom_animation_rig", {
                "op": "pose_apply", "skeleton_path": SKELETON,
                "pose": {"bones": {BONE: {
                    "rotation": {"kind": "quaternion", "x": 0,
                                 "y": math.sin(0.3), "z": 0,
                                 "w": math.cos(0.3)},
                    "position": {"kind": "vector3", "x": 0, "y": 0, "z": 0},
                    "scale": {"kind": "vector3", "x": 1, "y": 1, "z": 1}}}}})
        result = await call(client, "custom_animation_rig", {
            "op": "rig_get", "skeleton_path": SKELETON})
        if result.get("error"):
            row["inspect"] = result
        else:
            row["inspect"] = next((bone for bone in result.get("bones", [])
                                   if bone.get("name") == BONE), {})
    print("MCP_RIG_UI_UNDO=" + json.dumps(row, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=["setup", "inspect"], required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
