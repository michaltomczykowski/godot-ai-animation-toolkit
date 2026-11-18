"""Audit rig_chain creation modes through live Godot AI and saved scenes."""

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


CASES = {
    "new_3d": {"skeleton_path": "/RepairChainFixture/New3D",
               "name": "New3D", "bones": [
                   {"name": "hip", "position": [0, 0.2, 0]},
                   {"name": "head", "parent": "hip", "position": [0, 0.4, 0]}]},
    "new_2d": {"skeleton_path": "/RepairChainFixture/New2D",
               "name": "New2D", "kind": "2d", "bones": [
                   {"name": "upper", "position": [0, 0]},
                   {"name": "lower", "parent": "upper", "position": [0, 40]}]},
    "subtree": {"node_path": "/RepairChainFixture/ArmatureRoot"},
}


def summary(value: dict) -> dict:
    if value.get("error"):
        return {"error": value["error"]}
    return {"kind": value.get("kind"), "bone_count": value.get("bone_count"),
            "bones": [{"name": b.get("name"), "parent": b.get("parent"),
                       "rest_position": b.get("rest_position")}
                      for b in value.get("bones", [])]}


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
        for mode, extras in CASES.items():
            copy_scene(args.project_root / "repair_chain_modes_fixture.tscn",
                            folder / f"{mode}.tscn")
            scene = f"res://repair_rig_audit/{run_id}/{mode}.tscn"
            row = {"mode": mode, "scene": scene}
            row["open"] = await call(client, "scene_open", {"path": scene})
            params = {"op": "rig_chain", **extras}
            skeleton = (extras.get("skeleton_path") or
                        "/RepairChainFixture/ArmatureRoot/ArmatureRootSkeleton")
            inspect = {"op": "rig_get", "skeleton_path": skeleton}
            row["before"] = summary(await call(client, "custom_animation_rig", inspect))
            row["dry"] = await call(client, "custom_animation_rig",
                                    {**params, "dry_run": True})
            row["after_dry"] = summary(await call(client, "custom_animation_rig", inspect))
            row["write"] = await call(client, "custom_animation_rig", params)
            row["after"] = summary(await call(client, "custom_animation_rig", inspect))
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = summary(await call(client, "custom_animation_rig", inspect))
            rows.append(row)
    failures = []
    for row in rows:
        mode = row["mode"]
        for stage in ("open", "dry", "write", "save", "reopen"):
            if row[stage].get("error"):
                failures.append(f"{mode}: {stage}: {row[stage]['error']}")
        if row["before"] != row["after_dry"]:
            failures.append(f"{mode}: dry run changed scene")
        if row["after"] != row["persisted"]:
            failures.append(f"{mode}: created skeleton lost on reopen")
        if row["persisted"].get("bone_count") not in (2, 3):
            failures.append(f"{mode}: wrong bone count")
    print("MCP_RIG_CHAIN_MODES=" + json.dumps({"run_id": run_id,
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
