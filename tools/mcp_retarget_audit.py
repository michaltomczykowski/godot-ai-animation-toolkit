"""Audit retarget_setup through Godot AI custom_manage and saved scene."""

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


SOURCE = "/RepairRetargetFixture/Source"
TARGET = "/RepairRetargetFixture/Target"


async def invoke(client: Client, params: dict) -> dict:
    return await call(client, "custom_manage", {"op": "invoke", "params": {
        "tool_name": "animation_rig_modifiers", "params": params}})


async def rig(client: Client, skeleton_path: str) -> dict:
    value = await call(client, "custom_animation_rig", {
        "op": "rig_get", "skeleton_path": skeleton_path})
    if value.get("error"):
        return value
    return {"path": skeleton_path, "bone_count": len(value.get("bones", [])),
            "modifiers": value.get("modifiers", [])}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_rig_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_retarget_fixture.tscn",
               folder / "retarget_setup.tscn")
    scene = f"res://repair_rig_audit/{run_id}/retarget_setup.tscn"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"scene": scene, "run_id": run_id}
    params = {"op": "retarget_setup", "skeleton_path": SOURCE,
              "target_path": TARGET, "profile": "auto", "rotation": True,
              "active": False, "move_target": True}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        row["before_source"] = await rig(client, SOURCE)
        row["before_target"] = await rig(client, TARGET)
        row["dry"] = await invoke(client, {**params, "dry_run": True})
        row["after_dry_source"] = await rig(client, SOURCE)
        row["after_dry_target"] = await rig(client, TARGET)
        row["write"] = await invoke(client, params)
        moved_path = row["write"].get("target_path", "")
        row["after_source"] = await rig(client, SOURCE)
        row["after_target"] = await rig(client, moved_path)
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted_source"] = await rig(client, SOURCE)
        row["persisted_target"] = await rig(client, moved_path)
        row["invalid"] = await invoke(client, {
            **params, "target_path": "/DefinitelyMissingTarget"})
    failures = []
    for stage in ("open", "dry", "write", "save", "reopen"):
        if row[stage].get("error"):
            failures.append(f"{stage}: {row[stage]['error']}")
    if row["before_source"] != row["after_dry_source"] or \
            row["before_target"] != row["after_dry_target"]:
        failures.append("dry run changed source or target")
    if row["after_source"] != row["persisted_source"] or \
            row["after_target"] != row["persisted_target"]:
        failures.append("source or target changed on reopen")
    if len(row["persisted_source"].get("modifiers", [])) != 1 or \
            row["persisted_target"].get("bone_count") != 3:
        failures.append("modifier or moved target not persisted")
    if not row["invalid"].get("error", "").startswith("NODE_NOT_FOUND:"):
        failures.append("missing target lacks typed error")
    print("MCP_RETARGET=" + json.dumps({"row": row,
        "failures": failures}, sort_keys=True))
    return 1 if failures else 0


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
