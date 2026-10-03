"""Build and persist an active graph through the Godot AI graph tool."""

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


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_graph_active"
    folder.mkdir(exist_ok=True)
    target = folder / f"{args.mode}_{run_id}.tscn"
    copy_scene(args.project_root / "repair_graph_fixture.tscn", target)
    scene = "res://repair_graph_active/" + target.name
    transport = StdioTransport(sys.executable, [
        "-m", "godot_ai", "attach", "--port", str(args.port),
        "--ws-port", str(args.ws_port),
    ], cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        output = {"scene": scene}
        output["open"] = await call(client, "scene_open", {"path": scene})
        if args.mode == "locomotion":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "locomotion", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "mode": "blend_space",
            })
            output["wire"] = await call(client, "custom_animation_graph", {
                "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "parameter_path": "parameters/blend_position",
                "parameter_value": 1.5,
            })
        elif args.mode == "locomotion_state":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "locomotion", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "mode": "state_machine", "start": "idle",
            })
            output["wire"] = await call(client, "custom_animation_graph", {
                "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "parameter_path": "parameters/conditions/walking",
                "parameter_value": True,
            })
        elif args.mode == "blend":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "blend_space", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "dimensions": 1, "min": 0, "max": 2, "active": True,
                "points": [{"animation": "idle", "position": 0},
                           {"animation": "walk", "position": 1},
                           {"animation": "run", "position": 2}],
            })
            output["wire"] = await call(client, "custom_animation_graph", {
                "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "parameter_path": "parameters/blend_position",
                "parameter_value": 1.5,
            })
        elif args.mode == "blend_tree":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "blend_tree", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True,
                "root": {"type": "blend2", "name": "Mix", "inputs": [
                    {"type": "animation", "animation": "idle"},
                    {"type": "animation", "animation": "walk"}]},
            })
            output["wire"] = await call(client, "custom_animation_graph", {
                "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "parameter_path": "parameters/Mix/blend_amount",
                "parameter_value": 1.0,
            })
        elif args.mode == "one_shot":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "one_shot_layer", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "base": "idle", "animation": "jump", "fadein": 0.05,
                "fadeout": 0.1,
            })
        elif args.mode == "nested_one_shot":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "blend_tree", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "root": {"type": "one_shot", "inputs": [
                    {"type": "animation", "animation": "idle"},
                    {"type": "animation", "animation": "jump"}]},
            })
        elif args.mode == "additive":
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "additive_lean", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "base": "idle", "animation": "lean",
            })
            output["wire"] = await call(client, "custom_animation_graph", {
                "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "parameter_path": "parameters/Add2/add_amount",
                "parameter_value": 1.0,
            })
        else:
            output["build"] = await call(client, "custom_animation_graph", {
                "op": "state_machine", "player_path": "/RepairGraphFixture/AnimationPlayer",
                "active": True, "start": "idle" if args.mode == "condition" else "walk",
                "states": [{"name": "idle", "animation": "idle"},
                           {"name": "walk", "animation": "walk"}],
                "transitions": [{"from": "idle", "to": "walk", "xfade": 0.1,
                                 "condition": "walking"}] if args.mode == "condition" else
                               [{"from": "idle", "to": "walk", "xfade": 0.1}],
            })
            if args.mode == "condition":
                output["wire"] = await call(client, "custom_animation_graph", {
                    "op": "wire", "player_path": "/RepairGraphFixture/AnimationPlayer",
                    "active": True, "parameter_path": "parameters/conditions/walking",
                    "parameter_value": True,
                })
        output["graph"] = await call(client, "custom_animation_graph", {
            "op": "graph_get", "tree_path": "/RepairGraphFixture/AnimationTree"})
        output["save"] = await call(client, "scene_save", {})
        output["reopen"] = await call(client, "scene_open", {"path": scene, "force_reload": True})
        output["persisted"] = await call(client, "custom_animation_graph", {
            "op": "graph_get", "tree_path": "/RepairGraphFixture/AnimationTree"})
    print("MCP_GRAPH_ACTIVE=" + json.dumps(output, sort_keys=True))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path.cwd() / "test_project")
    parser.add_argument("--session-hint", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--mode", choices=["blend", "blend_tree", "one_shot", "nested_one_shot", "additive", "locomotion", "locomotion_state", "state_machine", "condition"], default="blend")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
