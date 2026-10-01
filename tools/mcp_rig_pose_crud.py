"""Audit rig pose save/list/blend/to_clip through live Godot AI."""

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
PLAYER = "/RepairRigFixture/AnimationPlayer"
BONE = "B-upperArm.L"


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_rig_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_rig_fixture.tscn",
                    folder / "poses.tscn")
    pose_dir = f"res://animation_toolkit/repair_audit/rig_poses_{run_id}"
    disk_dir = args.project_root / "animation_toolkit" / "repair_audit" / f"rig_poses_{run_id}"
    scene = f"res://repair_rig_audit/{run_id}/poses.tscn"
    arm_pose = {"format": "godot-ai-animation-pose", "version": 1,
                "rest_relative": True, "bones": {BONE: {
                    "rotation": {"kind": "quaternion", "x": 0, "y": math.sin(0.3),
                                 "z": 0, "w": math.cos(0.3)},
                    "position": {"kind": "vector3", "x": 0, "y": 0, "z": 0},
                    "scale": {"kind": "vector3", "x": 1, "y": 1, "z": 1}}}}
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"run_id": run_id, "scene": scene, "pose_dir": pose_dir}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        save_base = {"op": "pose_save", "skeleton_path": SKELETON,
                     "pose_dir": pose_dir}
        row["save_dry"] = await call(client, "custom_animation_rig",
            {**save_base, "name": "dry_rest", "dry_run": True})
        row["dry_file_exists"] = (disk_dir / "dry_rest.json").exists()
        row["save_rest"] = await call(client, "custom_animation_rig",
            {**save_base, "name": "rest"})
        row["rest_file_exists"] = (disk_dir / "rest.json").exists()
        row["apply_arm"] = await call(client, "custom_animation_rig",
            {"op": "pose_apply", "skeleton_path": SKELETON, "pose": arm_pose})
        row["save_arm"] = await call(client, "custom_animation_rig",
            {**save_base, "name": "arm"})
        row["list"] = await call(client, "custom_animation_rig",
            {"op": "pose_list", "directory": pose_dir})
        blend_base = {"op": "pose_blend", "pose_dir": pose_dir,
                      "from": "rest", "to": "arm", "factor": 0.5}
        row["blend_dry"] = await call(client, "custom_animation_rig",
            {**blend_base, "name": "dry_half", "dry_run": True})
        row["blend_dry_file_exists"] = (disk_dir / "dry_half.json").exists()
        row["blend_half"] = await call(client, "custom_animation_rig",
            {**blend_base, "name": "half"})
        row["half_file_exists"] = (disk_dir / "half.json").exists()
        clip_base = {"op": "pose_to_clip", "pose_dir": pose_dir,
                     "player_path": PLAYER, "skeleton_path": SKELETON,
                     "animation_name": "arm_wave", "loop_mode": "linear",
                     "keys": [{"name": "rest", "time": 0.0},
                              {"name": "arm", "time": 0.5},
                              {"name": "rest", "time": 1.0}]}
        describe = {"op": "describe", "player_path": PLAYER,
                    "animation_name": "arm_wave"}
        row["clip_before"] = await call(client, "custom_animation_inspect", describe)
        row["clip_dry"] = await call(client, "custom_animation_rig",
            {**clip_base, "dry_run": True})
        row["clip_after_dry"] = await call(client, "custom_animation_inspect", describe)
        row["clip_write"] = await call(client, "custom_animation_rig", clip_base)
        row["clip_after"] = await call(client, "custom_animation_inspect", describe)
        row["save_scene"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["clip_persisted"] = await call(client, "custom_animation_inspect", describe)
        row["missing_pose"] = await call(client, "custom_animation_rig",
            {**blend_base, "from": "definitely_missing"})
    failures = []
    for name, value in row.items():
        if name in ("open", "save_rest", "apply_arm", "save_arm", "list",
                    "blend_half", "clip_write", "save_scene", "reopen") \
                and isinstance(value, dict) and value.get("error"):
            failures.append(f"{name}: {value['error']}")
    if row["dry_file_exists"] or row["blend_dry_file_exists"]:
        failures.append("dry run wrote a pose file")
    if not row["rest_file_exists"] or not row["half_file_exists"]:
        failures.append("pose file write missing")
    if row["clip_before"] != row["clip_after_dry"]:
        failures.append("clip dry run changed the scene")
    if row["clip_after"] != row["clip_persisted"]:
        failures.append("clip failed persistence")
    if len(row["clip_persisted"].get("clips", [])) != 1:
        failures.append("saved arm clip missing")
    if not row["missing_pose"].get("error", "").startswith("INVALID_PARAMS:"):
        failures.append("missing pose lacks typed error")
    row["failures"] = failures
    print("MCP_RIG_POSE_CRUD=" + json.dumps(row, sort_keys=True))
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
