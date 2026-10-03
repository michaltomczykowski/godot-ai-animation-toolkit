"""Exercise character_setup and secondary_motion through live Godot AI."""

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


PLAYER = "/RepairRigFixture/AnimationPlayer"
SKELETON = "/RepairRigFixture/Dummy/Skeleton3D"


async def inspect(client: Client, clip: str) -> dict:
    value = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER,
        "animation_name": clip, "max_tracks": 200})
    if value.get("error"):
        return value
    return {"clips": [{"name": c.get("name"), "length": c.get("length"),
        "key_count": c.get("key_count"), "tracks": [
            {"path": t.get("path"), "type": t.get("type"),
             "node_resolved": t.get("node_resolved")}
            for t in c.get("tracks", [])]} for c in value.get("clips", [])]}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_motion_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_rig_fixture.tscn",
               folder / "setup_secondary.tscn")
    scene = f"res://repair_motion_audit/{run_id}/setup_secondary.tscn"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"scene": scene, "run_id": run_id}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        setup = {"op": "character_setup", "player_path": PLAYER,
                 "skeleton_path": SKELETON, "duration": 1.0,
                 "run_duration": 0.7, "idle_duration": 2.0,
                 "speed": 0.7, "run_speed": 1.4, "root_motion": True,
                 "include_jump": True, "include_turn": True,
                 "active": False, "samples": 30}
        if args.auto_walk:
            setup.pop("speed")
        row["before_idle"] = await inspect(client, "idle")
        row["unreachable_setup"] = await call(client, "custom_animation_motion",
            {**setup, "speed": 8.0, "run_speed": 10.0})
        row["after_unreachable"] = await inspect(client, "idle")
        row["setup_dry"] = await call(client, "custom_animation_motion",
                                       {**setup, "dry_run": True})
        row["after_setup_dry"] = await inspect(client, "idle")
        row["setup_write"] = await call(client, "custom_animation_motion", setup)
        row["clips_after_setup"] = {name: await inspect(client, name)
                                    for name in ("idle", "walk", "run", "jump", "turn_left")}
        secondary = {"op": "secondary_motion", "player_path": PLAYER,
                     "skeleton_path": SKELETON, "animation_name": "walk",
                     "bones": ["B-jaw"], "stiffness": 80,
                     "damping": 12, "samples": 30}
        row["secondary_dry"] = await call(client, "custom_animation_motion",
                                           {**secondary, "dry_run": True})
        row["walk_after_secondary_dry"] = await inspect(client, "walk")
        row["secondary_write"] = await call(client, "custom_animation_motion", secondary)
        row["walk_after_secondary"] = await inspect(client, "walk")
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted"] = {name: await inspect(client, name)
                            for name in ("idle", "walk", "run", "jump", "turn_left")}
        row["invalid_setup"] = await call(client, "custom_animation_motion", {
            **setup, "skeleton_path": "/DefinitelyMissingSkeleton"})
        row["invalid_secondary"] = await call(client, "custom_animation_motion", {
            **secondary, "bones": ["DefinitelyMissingBone"]})
    failures = []
    for key in ("open", "setup_dry", "setup_write", "secondary_dry",
                "secondary_write", "save", "reopen"):
        if row[key].get("error"):
            failures.append(f"{key}: {row[key]['error']}")
    if row["before_idle"] != row["after_setup_dry"]:
        failures.append("character_setup dry run changed clip")
    if row["before_idle"] != row["after_unreachable"]:
        failures.append("unreachable character_setup changed clip")
    if not row["unreachable_setup"].get("error", "").startswith("VALUE_OUT_OF_RANGE:"):
        failures.append("unreachable character_setup lacks typed range error")
    elif "reachable" not in row["unreachable_setup"]["error"]:
        failures.append("unreachable character_setup was not rejected by the walk solver")
    if row["clips_after_setup"].get("walk") != row["walk_after_secondary_dry"]:
        failures.append("secondary_motion dry run changed clip")
    for name, desc in row["persisted"].items():
        clips = desc.get("clips", [])
        if len(clips) != 1 or not clips[0].get("tracks") or not all(
                t.get("node_resolved") for t in clips[0]["tracks"]):
            failures.append(f"{name}: missing persisted resolved tracks")
    walk = row["persisted"]["walk"].get("clips", [{}])[0]
    if not any(t.get("path") == "Dummy/Skeleton3D:B-jaw"
               for t in walk.get("tracks", [])):
        failures.append("secondary bone track did not persist")
    if row["walk_after_secondary"] != row["persisted"]["walk"]:
        failures.append("secondary clip changed on reopen")
    if not row["invalid_setup"].get("error", "").startswith("NODE_NOT_FOUND:"):
        failures.append("invalid setup skeleton lacks typed error")
    if not row["invalid_secondary"].get("error", "").startswith("NODE_NOT_FOUND:"):
        failures.append("invalid secondary bone lacks typed error")
    print("MCP_MOTION_SETUP_SECONDARY=" + json.dumps({
        "run_id": run_id, "row": row, "failures": failures}, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--auto-walk", action="store_true",
                        help="Omit walk speed so character_setup chooses its rig-relative default")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
