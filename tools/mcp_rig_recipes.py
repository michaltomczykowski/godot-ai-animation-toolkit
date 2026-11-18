"""Invoke six rig clip recipes through live Godot AI on separate dummy scenes."""

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
CASES = {
    "walk_cycle": {"duration": 1.0, "loop_mode": "linear"},
    "idle_breathing": {"duration": 3.0, "loop_mode": "linear"},
    "blink": {"bones": ["B-jaw"], "duration": 0.2, "blinks": 2},
    "jumping_jack": {"duration": 1.0, "loop_mode": "linear"},
    "squat": {"duration": 2.0, "bob": 0.25, "loop_mode": "linear"},
    "punch": {"duration": 0.8, "cycles": 2, "loop_mode": "linear"},
}


async def inspect(client: Client, name: str) -> dict:
    value = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER, "animation_name": name})
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
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    rows = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, extras in CASES.items():
            copy_scene(args.project_root / "repair_rig_fixture.tscn",
                            folder / f"{op}.tscn")
            scene = f"res://repair_rig_audit/{run_id}/{op}.tscn"
            row = {"op": op, "scene": scene}
            row["open"] = await call(client, "scene_open", {"path": scene})
            params = {"op": op, "skeleton_path": SKELETON,
                      "player_path": PLAYER, "animation_name": op, **extras}
            row["before"] = await inspect(client, op)
            row["dry"] = await call(client, "custom_animation_rig",
                                    {**params, "dry_run": True})
            row["after_dry"] = await inspect(client, op)
            row["write"] = await call(client, "custom_animation_rig", params)
            row["after"] = await inspect(client, op)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = await inspect(client, op)
            row["invalid"] = await call(client, "custom_animation_rig", {
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
            failures.append(f"{op}: missing clip or unresolved track")
        if not row["invalid"].get("error", "").startswith("NODE_NOT_FOUND:"):
            failures.append(f"{op}: invalid skeleton lacks typed error")
    print("MCP_RIG_RECIPES=" + json.dumps({"run_id": run_id,
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
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
