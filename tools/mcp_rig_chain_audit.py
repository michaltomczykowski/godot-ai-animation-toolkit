"""Check rig_chain append on the imported dummy via live Godot AI."""

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


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_rig_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    copy_scene(args.project_root / "repair_rig_fixture.tscn",
                    folder / "rig_chain.tscn")
    scene = f"res://repair_rig_audit/{run_id}/rig_chain.tscn"
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    row = {"run_id": run_id, "scene": scene}
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        row["open"] = await call(client, "scene_open", {"path": scene})
        inspect = {"op": "rig_get", "skeleton_path": SKELETON}
        params = {"op": "rig_chain", "skeleton_path": SKELETON,
                  "bones": [{"name": "repair_tool_tip",
                             "parent": "B-hand.R",
                             "position": [0, 0.05, 0]}]}
        row["before"] = await call(client, "custom_animation_rig", inspect)
        row["dry"] = await call(client, "custom_animation_rig",
                                {**params, "dry_run": True})
        row["after_dry"] = await call(client, "custom_animation_rig", inspect)
        row["write"] = await call(client, "custom_animation_rig", params)
        row["after"] = await call(client, "custom_animation_rig", inspect)
        row["save"] = await call(client, "scene_save", {})
        row["reopen"] = await call(client, "scene_open", {
            "path": scene, "force_reload": True})
        row["persisted"] = await call(client, "custom_animation_rig", inspect)
        row["invalid"] = await call(client, "custom_animation_rig", {
            **params, "skeleton_path": "/DefinitelyMissingSkeleton"})
    compact = {k: {"bone_count": v.get("bone_count"),
                   "tip": next((b for b in v.get("bones", [])
                                if b.get("name") == "repair_tool_tip"), None),
                   "error": v.get("error")}
               for k, v in row.items() if k in ("before", "after_dry",
                                                 "after", "persisted")}
    row["snapshots"] = compact
    for k in compact:
        del row[k]
    failures = []
    for stage in ("open", "dry", "write", "save", "reopen"):
        if row[stage].get("error"):
            failures.append(f"{stage}: {row[stage]['error']}")
    if compact["before"]["bone_count"] != compact["after_dry"]["bone_count"]:
        failures.append("dry run changed bone count")
    if compact["after"]["bone_count"] != compact["before"]["bone_count"] + 1:
        failures.append("write did not add bone")
    if compact["persisted"]["bone_count"] != compact["after"]["bone_count"]:
        failures.append("appended bone did not persist")
    if not row["invalid"].get("error", "").startswith("INVALID_PARAMS:"):
        failures.append("invalid parent lacks typed error")
    row["failures"] = failures
    print("MCP_RIG_CHAIN=" + json.dumps(row, sort_keys=True))
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
