"""Exercise sequence composition through a live Godot AI MCP editor session."""

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


PLAYER = "/RepairSequenceFixture/AnimationPlayer"
SKELETON = "/RepairSequenceFixture/Skeleton3D"


async def invoke(client: Client, params: dict) -> dict:
    return await call(client, "custom_manage", {"op": "invoke", "params": {
        "tool_name": "animation_sequence", "params": params}})


async def describe(client: Client, name: str = "audit_action") -> dict:
    return await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER, "animation_name": name})


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_dir = args.project_root / "repair_sequence_audit" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_sequence_fixture.tscn", run_dir / "compose.tscn")
    scene = f"res://repair_sequence_audit/{run_id}/compose.tscn"
    params = {"op": "compose", "player_path": PLAYER, "skeleton_path": SKELETON,
              "animation_name": "audit_action", "duration": 1.8,
              "segments": [
                  {"start": 0.0, "duration": 1.0, "source_animation": "approach"},
                  {"start": 0.8, "duration": 1.0, "source_animation": "kick",
                   "fade_in": 0.2, "contacts": [{"name": "impact", "time": 0.3}]},
              ]}
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row = {"scene": scene}
        row["open"] = await call(client, "scene_open", {"path": scene, "force_reload": True})
        row["before"] = await describe(client)
        row["dry"] = await invoke(client, {**params, "dry_run": True})
        row["after_dry"] = await describe(client)
        outside = {**params, "animation_name": "invalid_source",
                   "segments": [dict(segment) for segment in params["segments"]]}
        outside["segments"][1]["source_end"] = 2.0
        row["outside_source"] = await invoke(client, outside)
        late_start = {**params, "animation_name": "invalid_late_start",
                      "segments": [dict(segment) for segment in params["segments"]]}
        late_start["segments"][0]["start"] = 0.2
        row["late_start"] = await invoke(client, late_start)
        over_budget = {"op": "compose", "player_path": PLAYER,
                       "skeleton_path": SKELETON, "animation_name": "invalid_budget",
                       "duration": 10.0, "samples": 120,
                       "segments": [{"start": 0.0, "duration": 10.0,
                                     "source_animation": "approach"}]}
        row["over_budget"] = await invoke(client, over_budget)
        row["create"] = await invoke(client, params)
        row["created"] = await describe(client)
        pose_params = {"op": "compose", "player_path": PLAYER,
                       "skeleton_path": SKELETON, "animation_name": "audit_saved_pose",
                       "duration": 0.5, "segments": [{"start": 0.0,
                           "duration": 0.5, "pose_name": "sequence_root"}]}
        row["pose_dry"] = await invoke(client, {**pose_params, "dry_run": True})
        row["pose_after_dry"] = await describe(client, "audit_saved_pose")
        row["pose_create"] = await invoke(client, pose_params)
        row["pose_created"] = await describe(client, "audit_saved_pose")
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {"path": scene, "force_reload": True})
        row["persisted"] = await describe(client)
        row["pose_persisted"] = await describe(client, "audit_saved_pose")
    failures = []
    for stage in ("open", "dry", "create", "pose_dry", "pose_create", "save", "reopen"):
        if row[stage].get("error"):
            failures.append(f"{stage}: {row[stage]['error']}")
    if row["before"].get("clips") or row["after_dry"].get("clips"):
        failures.append("dry run changed the output AnimationPlayer")
    if row["pose_after_dry"].get("clips"):
        failures.append("saved-pose dry run changed the output AnimationPlayer")
    if not str(row["outside_source"].get("error", "")).startswith("VALUE_OUT_OF_RANGE"):
        failures.append("source range outside the clip did not return VALUE_OUT_OF_RANGE")
    if not str(row["late_start"].get("error", "")).startswith("INVALID_PARAMS"):
        failures.append("first segment starting after zero did not return INVALID_PARAMS")
    if not str(row["over_budget"].get("error", "")).startswith("VALUE_OUT_OF_RANGE"):
        failures.append("1,201-key sequence did not return VALUE_OUT_OF_RANGE")
    for stage in ("created", "persisted"):
        clips = row[stage].get("clips", [])
        if len(clips) != 1 or clips[0].get("track_count") != 1 \
                or clips[0].get("key_count", 0) < 30 \
                or not all(track.get("node_resolved") for track in clips[0].get("tracks", [])):
            failures.append(f"{stage}: no resolved sampled sequence clip")
    for stage in ("pose_created", "pose_persisted"):
        clips = row[stage].get("clips", [])
        if len(clips) != 1 or clips[0].get("track_count") != 3 \
                or not all(track.get("node_resolved") for track in clips[0].get("tracks", [])):
            failures.append(f"{stage}: no resolved saved-pose sequence clip")
    print("MCP_SEQUENCE_AUDIT=" + json.dumps({"run_id": run_id, "row": row,
        "failures": failures}, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
