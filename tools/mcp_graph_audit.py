"""Smoke graph operations through Godot AI using a saved 4.7.2 clip fixture."""

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


PLAYER = "/RepairGraphFixture/AnimationPlayer"
TREE = "/RepairGraphFixture/AnimationTree"
BASE = {"op": "state_machine", "player_path": PLAYER,
        "states": [{"name": "idle", "animation": "idle"},
                   {"name": "walk", "animation": "walk"}],
        "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1}]}
WIRE_BASE = {"op": "state_machine", "player_path": PLAYER,
             "states": [{"name": "idle", "animation": "idle"},
                        {"name": "walk", "animation": "walk"}],
             "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1,
                              "condition": "walking"}]}
CASES = {
    "state_machine": {"params": BASE},
    "blend_space": {"params": {"op": "blend_space", "player_path": PLAYER,
        "dimensions": 1, "min": 0, "max": 2,
        "points": [{"animation": "idle", "position": 0},
                   {"animation": "walk", "position": 1},
                   {"animation": "run", "position": 2}]}},
    "blend_tree": {"params": {"op": "blend_tree", "player_path": PLAYER,
        "root": {"type": "blend2", "inputs": [
            {"type": "animation", "animation": "idle"},
            {"type": "animation", "animation": "walk"}]} }},
    "wire": {"params": {"op": "wire", "player_path": PLAYER}},
    "wire_parameter": {"setup": WIRE_BASE, "params": {
        "op": "wire", "player_path": PLAYER, "active": True,
        "parameter_path": "parameters/conditions/walking", "parameter_value": True}},
    "graph_get": {"setup": BASE, "params": {"op": "graph_get", "tree_path": TREE}},
    "locomotion": {"params": {"op": "locomotion", "player_path": PLAYER,
                               "mode": "blend_space"}},
    "one_shot_layer": {"setup": BASE, "params": {
        "op": "one_shot_layer", "player_path": PLAYER, "animation": "jump"}},
    "additive_lean": {"setup": BASE, "params": {
        "op": "additive_lean", "player_path": PLAYER, "animation": "lean"}},
}


async def hierarchy(client: Client) -> dict:
    return await call(client, "scene_get_hierarchy", {"depth": 2})


def verify_row(row: dict) -> list[str]:
    failures = []
    for stage in ("open", "setup", "dry", "create", "save", "reopen", "persisted"):
        if row.get(stage, {}).get("error"):
            failures.append(f"{row['op']}: {stage}: {row[stage]['error']}")
    before = {n.get("path") for n in row.get("before", {}).get("nodes", [])}
    after_dry = {n.get("path") for n in row.get("after_dry", {}).get("nodes", [])}
    if before != after_dry:
        failures.append(f"{row['op']}: dry run changed scene hierarchy")
    if row.get("graph_before_dry") != row.get("graph_after_dry"):
        failures.append(f"{row['op']}: dry run changed graph root or parameters")
    persisted = row.get("persisted", {})
    if not persisted.get("anim_player_resolved") or not persisted.get("tree_path"):
        failures.append(f"{row['op']}: saved AnimationTree cannot resolve its player")
    if row["op"] == "graph_get":
        root = persisted.get("root", {})
        states = {state.get("name") for state in root.get("states", [])}
        transitions = {(edge.get("from"), edge.get("to"))
                       for edge in root.get("transitions", [])}
        if (root.get("type") != "state_machine" or states != {"idle", "walk"}
                or ("idle", "walk") not in transitions
                or set(persisted.get("animations", [])) != {"idle", "walk"}):
            failures.append("graph_get: saved state/transition topology differs from fixture")
        if row.get("create") != persisted:
            failures.append("graph_get: response changed after save/reopen")
        if not row.get("invalid", {}).get("error", "").startswith("NODE_NOT_FOUND:"):
            failures.append("graph_get: missing tree lacks typed NODE_NOT_FOUND")
    if row["op"] == "wire_parameter":
        if not persisted.get("active"):
            failures.append("wire_parameter: saved tree was not activated")
        if "parameters/conditions/walking" not in persisted.get("parameters", []):
            failures.append("wire_parameter: saved walking condition is unavailable")
        if row.get("create", {}).get("parameter_set") != {
                "path": "parameters/conditions/walking", "value": True}:
            failures.append("wire_parameter: reply did not report the requested value")
    if row["op"] == "wire":
        if not row.get("create", {}).get("created"):
            failures.append("wire: tree was not created")
        if persisted.get("root") != {} or persisted.get("active"):
            failures.append("wire: bare tree unexpectedly owns playback")
    return failures


async def run(args: argparse.Namespace) -> int:
    transport = StdioTransport(
        sys.executable,
        ["-m", "godot_ai", "attach", "--port", str(args.port),
         "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False,
    )
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    run_dir = args.project_root / "repair_graph_audit" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    rows = []
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, case in CASES.items():
            if args.only and op not in args.only:
                continue
            copy_scene(args.project_root / "repair_graph_fixture.tscn", run_dir / f"{op}.tscn")
            scene = f"res://repair_graph_audit/{run_id}/{op}.tscn"
            row = {"op": op, "scene": scene}
            row["open"] = await call(client, "scene_open", {"path": scene})
            if case.get("setup"):
                row["setup"] = await call(client, "custom_animation_graph", case["setup"])
            row["before"] = await hierarchy(client)
            row["graph_before_dry"] = await call(client, "custom_animation_graph", {
                "op": "graph_get", "tree_path": TREE})
            row["dry"] = await call(client, "custom_animation_graph", {
                **case["params"], "dry_run": True})
            row["after_dry"] = await hierarchy(client)
            row["graph_after_dry"] = await call(client, "custom_animation_graph", {
                "op": "graph_get", "tree_path": TREE})
            row["create"] = await call(client, "custom_animation_graph", case["params"])
            row["after"] = await hierarchy(client)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = await call(client, "custom_animation_graph", {
                "op": "graph_get", "tree_path": TREE})
            if op == "graph_get":
                row["invalid"] = await call(client, "custom_animation_graph", {
                    "op": "graph_get", "tree_path": "/DefinitelyMissingAnimationTree"})
            rows.append(row)
    failures = [message for row in rows for message in verify_row(row)]
    print("MCP_GRAPH_AUDIT=" + json.dumps({
        "run_id": run_id, "operations": rows, "failures": failures,
    }, sort_keys=True))
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--only", nargs="*", default=[])
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
