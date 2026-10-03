"""Exercise rig pose_apply dry/write/save through the live Godot AI route."""

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


def arm_snapshot(result: dict) -> dict:
    if result.get("error"):
        return result
    for bone in result.get("bones", []):
        if bone.get("name") == BONE:
            return {"pose_rotation": bone.get("pose_rotation"),
                    "pose_position": bone.get("pose_position")}
    return {"error": "bone missing from rig_get"}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_rig_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    target = folder / "pose_apply.tscn"
    copy_scene(args.project_root / "repair_rig_fixture.tscn", target)
    scene = f"res://repair_rig_audit/{run_id}/pose_apply.tscn"
    pose = {"format": "godot-ai-animation-pose", "version": 1,
            "rest_relative": True, "bones": {BONE: {
                "rotation": {"kind": "quaternion", "x": 0, "y": math.sin(0.3),
                             "z": 0, "w": math.cos(0.3)},
                "position": {"kind": "vector3", "x": 0, "y": 0, "z": 0},
                "scale": {"kind": "vector3", "x": 1, "y": 1, "z": 1},
            }}}
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"scene": scene, "run_id": run_id}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        params = {"op": "pose_apply", "skeleton_path": SKELETON,
                  "pose": pose}
        inspect = {"op": "rig_get", "skeleton_path": SKELETON}
        row["before"] = arm_snapshot(await call(client, "custom_animation_rig", inspect))
        row["dry"] = await call(client, "custom_animation_rig",
                                {**params, "dry_run": True})
        row["after_dry"] = arm_snapshot(await call(client, "custom_animation_rig", inspect))
        row["write"] = await call(client, "custom_animation_rig", params)
        row["after"] = arm_snapshot(await call(client, "custom_animation_rig", inspect))
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted"] = arm_snapshot(await call(client, "custom_animation_rig", inspect))
        row["invalid"] = await call(client, "custom_animation_rig",
            {**params, "skeleton_path": "/DefinitelyMissingSkeleton"})
    failures = []
    for stage in ("open", "dry", "write", "save", "reopen"):
        if row[stage].get("error"):
            failures.append(f"{stage}: {row[stage]['error']}")
    if row["before"] != row["after_dry"]:
        failures.append("dry run changed the bone")
    if row["before"] == row["after"]:
        failures.append("write did not change the bone")
    if row["after"] != row["persisted"]:
        failures.append("pose change did not persist after save/reopen")
    if not row["invalid"].get("error", "").startswith("NODE_NOT_FOUND:"):
        failures.append("invalid skeleton lacked typed error")
    row["failures"] = failures
    print("MCP_RIG_POSE_APPLY=" + json.dumps(row, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path,
                        default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
