"""Audit four modifier setup operations through Godot AI custom_manage."""

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


SKELETON = "/RepairRigFixture/Dummy/Skeleton3D"
CASES = {
    "ik_setup": {"kind": "two_bone", "chain": ["B-upperArm.L", "B-forearm.L", "B-hand.L"], "target_name": "AuditHandTarget"},
    "spring_setup": {"springs": [{"root_bone": "B-forearm.L", "end_bone": "B-hand.L", "stiffness": 0.3, "drag": 0.2, "gravity": 0.1, "radius": 0.02}]},
    "look_at_setup": {"bone": "B-head", "target_name": "AuditHeadTarget", "forward_axis": "+z"},
    "twist_setup": {"disperse": {"root_bone": "B-hips", "end_bone": "B-chest", "mode": "even"}},
}


async def invoke(client: Client, params: dict) -> dict:
    return await call(client, "custom_manage", {"op": "invoke", "params": {
        "tool_name": "animation_rig_modifiers", "params": params}})


async def rig(client: Client) -> dict:
    value = await call(client, "custom_animation_rig", {
        "op": "rig_get", "skeleton_path": SKELETON})
    if value.get("error"):
        return value
    return {"modifiers": value.get("modifiers", []),
            "twist_settings": value.get("twist_settings", [])}


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
                      "active": False, **extras}
            row["before"] = await rig(client)
            row["dry"] = await invoke(client, {**params, "dry_run": True})
            row["after_dry"] = await rig(client)
            row["write"] = await invoke(client, params)
            row["after"] = await rig(client)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = await rig(client)
            row["invalid"] = await invoke(client, {
                **params, "skeleton_path": "/DefinitelyMissingSkeleton"})
            if op == "spring_setup":
                row["invalid_leaf"] = await invoke(client, {
                    **params, "springs": [{"root_bone": "B-jaw"}]})
            rows.append(row)
    failures = []
    for row in rows:
        op = row["op"]
        for stage in ("open", "dry", "write", "save", "reopen"):
            if row[stage].get("error"):
                failures.append(f"{op}: {stage}: {row[stage]['error']}")
        if row["before"] != row["after_dry"]:
            failures.append(f"{op}: dry run changed skeleton")
        if row["after"] != row["persisted"]:
            failures.append(f"{op}: modifier changed on save/reopen")
        if len(row["persisted"].get("modifiers", [])) != 1:
            failures.append(f"{op}: expected one persistent modifier")
        if not row["invalid"].get("error", "").startswith("NODE_NOT_FOUND:"):
            failures.append(f"{op}: invalid target lacks typed error")
        if op == "spring_setup" and not row.get("invalid_leaf", {}).get(
                "error", "").startswith("INVALID_PARAMS:"):
            failures.append("spring_setup: inert leaf lacks typed error")
    print("MCP_RIG_MODIFIERS=" + json.dumps({"run_id": run_id,
        "rows": rows, "failures": failures}, sort_keys=True))
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
