"""First live Godot AI contract pass for clip edits on fresh saved scenes."""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timezone
import json
import math
from fixture_copy import copy_scene
import sys
from pathlib import Path

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

from mcp_presets_audit import call


PLAYER = "/RepairGraphFixture/AnimationPlayer"
CASES = {
    "retime": {"factor": 0.5},
    "reverse": {},
    "mirror": {"axis": "x"},
    "trim": {"from": 0.2, "to": 0.8},
    "amplitude": {"factor": 0.5},
    "resample": {"fps": 30, "interpolation": "linear"},
    "layer": {"source_animation": "run", "layer_mode": "add", "weight": 0.4},
    "offset": {"delta": 0.2, "wrap": False},
    "loop": {"loop_mode": "pingpong"},
    "key_edit": {"action": "add", "track_path": "Character:position",
                 "time": 0.5, "value": {"x": 15, "y": 0}},
    "overlap": {"track_path": "Character:position", "delay": 0.1,
                "wrap": False},
    "offset_wrap_reject": {"delta": 0.2, "wrap": True},
    "overlap_wrap_reject": {"track_path": "Character:position", "delay": 0.1,
                            "wrap": True},
    "retarget": {"from_path": "Character", "to_path": "OtherCharacter"},
    "ease_range": {"from": 0.0, "to": 1.0, "transition": 2.0},
    "set_interp": {"interpolation": "nearest"},
    "split_at": {"time": 0.5, "head_name": "walk_head"},
    "merge": {"sources": [{"animation_name": "walk"},
                          {"animation_name": "run"}],
              "new_name": "walk_run", "_inspect": "walk_run"},
    "cleanup": {"_animation": "idle"},
    "smooth": {"_animation": "jump", "strength": 0.5, "passes": 1},
    "reduce": {"_prep": "resample", "value_tolerance": 0.01},
    "add_noise": {"_prep": "resample", "amount": 2.0,
                  "frequency": 2.0, "seed": 42},
}


async def describe(client: Client, clip: str = "walk") -> dict:
    result = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER, "animation_name": clip})
    clips = result.get("clips", [])
    if len(clips) != 1:
        return {"error": result.get("error", "clip absent")}
    described = clips[0]
    described["timeline"] = await call(client, "custom_animation_inspect", {
        "op": "timeline", "player_path": PLAYER, "animation_name": clip,
        "max_keys": 2000})
    return described


def equivalent(left: object, right: object) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(left, right, rel_tol=1e-6, abs_tol=1e-5)
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(
            equivalent(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(
            equivalent(a, b) for a, b in zip(left, right))
    return left == right


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_edit_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    rows = []
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, extras in CASES.items():
            copy_scene(args.project_root / "repair_edit_fixture.tscn",
                            folder / f"{op}.tscn")
            scene = f"res://repair_edit_audit/{run_id}/{op}.tscn"
            row = {"op": op, "scene": scene}
            row["open"] = await call(client, "scene_open", {"path": scene,
                "force_reload": True})
            rejected = op.endswith("_wrap_reject")
            actual_op = op.removesuffix("_wrap_reject") if rejected else op
            animation = extras.get("_animation", "walk")
            inspect_name = extras.get("_inspect", animation)
            if extras.get("_prep") == "resample":
                row["prep"] = await call(client, "custom_animation_edit", {
                    "op": "resample", "player_path": PLAYER,
                    "animation_name": animation, "fps": 30.0})
            params = {"op": actual_op, "player_path": PLAYER,
                      "animation_name": animation,
                      **{k: v for k, v in extras.items() if not k.startswith("_")}}
            row["before"] = await describe(client, inspect_name)
            row["dry"] = await call(client, "custom_animation_edit",
                                    {**params, "dry_run": True})
            row["after_dry"] = await describe(client, inspect_name)
            row["write"] = await call(client, "custom_animation_edit", params)
            row["after"] = await describe(client, inspect_name)
            if op == "split_at":
                row["head"] = await describe(client, "walk_head")
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {"path": scene,
                "force_reload": True})
            row["persisted"] = await describe(client, inspect_name)
            if op == "split_at":
                row["persisted_head"] = await describe(client, "walk_head")
            rows.append(row)
    failures = []
    for row in rows:
        rejected = row["op"].endswith("_wrap_reject")
        for stage in ("open", "save", "reopen") if rejected else ("open", "dry", "write", "save", "reopen"):
            if row[stage].get("error"):
                failures.append(f"{row['op']}: {stage}: {row[stage]['error']}")
        if rejected:
            for stage in ("dry", "write"):
                if "VALUE_OUT_OF_RANGE" not in str(row[stage].get("error", "")):
                    failures.append(f"{row['op']}: {stage} did not return typed rejection")
            if not equivalent(row["before"], row["after"]) or not equivalent(row["before"], row["persisted"]):
                failures.append(f"{row['op']}: rejected edit changed the clip")
            continue
        if row.get("prep", {}).get("error"):
            failures.append(f"{row['op']}: prep: {row['prep']['error']}")
        if row["before"] != row["after_dry"]:
            failures.append(f"{row['op']}: dry run changed the clip")
        if row["before"] == row["after"]:
            failures.append(f"{row['op']}: edit reported success without a described change")
        if not equivalent(row["after"], row["persisted"]):
            failures.append(f"{row['op']}: edit did not persist after reopen")
        if any(not track.get("node_resolved") for track in
               row["persisted"].get("tracks", [])):
            failures.append(f"{row['op']}: edited track path is unresolved")
        if row["op"] == "split_at" and (row["head"].get("error") or
                not equivalent(row["head"], row["persisted_head"])):
            failures.append("split_at: head clip absent or changed after reopen")
    print("MCP_EDIT_AUDIT=" + json.dumps({"run_id": run_id,
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
