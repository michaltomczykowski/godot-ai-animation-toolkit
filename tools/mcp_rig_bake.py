"""Audit bake_pose_sequence via the live Godot AI rig tool."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
from fixture_copy import copy_scene
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


SKELETON = "/RepairRigFixture/Dummy/Skeleton3D"
PLAYER = "/RepairRigFixture/AnimationPlayer"
BONE = "B-thigh.L"


def pose(result: dict) -> dict:
    if result.get("error"):
        return result
    bone = next((b for b in result.get("bones", []) if b.get("name") == BONE), {})
    return {"rotation": bone.get("pose_rotation"),
            "position": bone.get("pose_position")}


async def clip(client: Client) -> dict:
    value = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER,
        "animation_name": "walk_baked", "max_tracks": 200})
    if value.get("error"):
        return value
    return {"clips": [{"name": c.get("name"), "length": c.get("length"),
        "key_count": c.get("key_count"), "tracks": [
            {"path": t.get("path"), "type": t.get("type"),
             "node_resolved": t.get("node_resolved")}
            for t in c.get("tracks", [])]}
        for c in value.get("clips", [])]}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_rig_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_rig_fixture.tscn",
                    folder / "bake.tscn")
    scene = f"res://repair_rig_audit/{run_id}/bake.tscn"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"run_id": run_id, "scene": scene}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        row["source"] = await call(client, "custom_animation_rig", {
            "op": "walk_cycle", "skeleton_path": SKELETON,
            "player_path": PLAYER, "animation_name": "walk_source",
            "duration": 1.0, "loop_mode": "linear"})
        params = {"op": "bake_pose_sequence", "skeleton_path": SKELETON,
                  "player_path": PLAYER, "animation_name": "walk_baked",
                  "source_animation": "walk_source", "duration": 0.5,
                  "fps": 10, "loop_mode": "none"}
        inspect = {"op": "rig_get", "skeleton_path": SKELETON}
        row["before_pose"] = pose(await call(client, "custom_animation_rig", inspect))
        row["before_clip"] = await clip(client)
        row["dry"] = await call(client, "custom_animation_rig",
                                {**params, "dry_run": True})
        row["after_dry_pose"] = pose(await call(client, "custom_animation_rig", inspect))
        row["after_dry_clip"] = await clip(client)
        row["write"] = await call(client, "custom_animation_rig", params)
        row["after_pose"] = pose(await call(client, "custom_animation_rig", inspect))
        row["after_clip"] = await clip(client)
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted"] = await clip(client)
        row["invalid"] = await call(client, "custom_animation_rig", {
            **params, "source_animation": "definitely_missing"})
    failures = []
    for stage in ("open", "source", "dry", "write", "save", "reopen"):
        if row[stage].get("error"):
            failures.append(f"{stage}: {row[stage]['error']}")
    if row["before_pose"] != row["after_dry_pose"] or \
            row["before_clip"] != row["after_dry_clip"]:
        failures.append("dry run changed pose or clip")
    if row["before_pose"] != row["after_pose"]:
        failures.append("bake left the source skeleton posed")
    if row["after_clip"] != row["persisted"]:
        failures.append("baked clip lost on reopen")
    clips = row["persisted"].get("clips", [])
    if len(clips) != 1 or not clips[0].get("tracks") or not all(
            t.get("node_resolved") for t in clips[0]["tracks"]):
        failures.append("missing baked clip or unresolved track")
    if not row["invalid"].get("error", "").startswith("INVALID_PARAMS:"):
        failures.append("missing source lacks typed error")
    row["failures"] = failures
    print("MCP_RIG_BAKE=" + json.dumps(row, sort_keys=True))
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
