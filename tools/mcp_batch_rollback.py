"""Check Godot AI batch rollback using a live toolkit clip mutation."""

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


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_batch_rollback"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{run_id}.tscn"
    copy_scene(args.project_root / "repair_rig_fixture.tscn", target)
    scene = "res://repair_batch_rollback/" + target.name
    player = "/RepairRigFixture/AnimationPlayer"
    skeleton = "/RepairRigFixture/Dummy/Skeleton3D"
    name = "batch_rollback_walk"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row = {"scene": scene}
        row["open"] = await call(client, "scene_open", {"path": scene})
        row["batch"] = await call(client, "batch_execute", {"undo": True,
            "commands": [
                {"command": "custom_tool:animation_motion", "params": {
                    "op": "walk_start", "player_path": player,
                    "skeleton_path": skeleton, "animation_name": name,
                    "duration": 0.5, "samples": 30,
                    "loop_mode": "none", "root_motion": True}},
                {"command": "custom_tool:animation_motion", "params": {
                    "op": "__expected_invalid__", "player_path": player,
                    "skeleton_path": skeleton}},
            ]})
        row["after"] = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": player, "animation_name": name})
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted"] = await call(client, "custom_animation_inspect", {
            "op": "describe", "player_path": player, "animation_name": name})
        row["file_family_preflight"] = await call(client, "batch_execute", {
            "undo": True, "commands": [{
                "command": "custom_tool:animation_library", "params": {
                    "op": "list"}}]})
        row["rig_family_preflight"] = await call(client, "batch_execute", {
            "undo": True, "commands": [{
                "command": "custom_tool:animation_rig", "params": {
                    "op": "rig_profile"}}]})
    failures = []
    if row["open"].get("error") or row["save"].get("error") or row["reopen"].get("error"):
        failures.append("scene route failed")
    batch = row["batch"]
    if (batch.get("error", {}).get("code") != "VALUE_OUT_OF_RANGE"
            or batch.get("succeeded") != 1 or batch.get("stopped_at") != 1
            or not batch.get("rolled_back")):
        failures.append("batch did not report one success and rollback at second command")
    if not row["after"].get("error") or not row["persisted"].get("error"):
        failures.append("rolled-back clip remains in editor or saved scene")
    for family in ("file_family_preflight", "rig_family_preflight"):
        if "CUSTOM_TOOL_NOT_UNDOABLE" not in str(row[family].get("error", "")):
            failures.append(f"{family} was not rejected before execution")
    row["failures"] = failures
    print("MCP_BATCH_ROLLBACK=" + json.dumps(row, sort_keys=True))
    return int(bool(failures))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
