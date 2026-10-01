"""Invoke all FX operations through live Godot AI on fresh saved scenes."""

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


PLAYER = "/RepairFxFixture/AnimationPlayer"
CASES = {
    "shake": {"target_path": "Camera2D", "intensity": 10.0, "seed": 7},
    "zoom_punch": {"target_path": "Camera2D", "amount": 0.12},
    "hit_flash": {"target_path": "Flash", "color": "#ff0000", "count": 2},
    "damage_bar": {"target_path": "DamageBar", "to": 30.0},
    "typewriter": {"target_path": "TypeLabel", "steps": 10,
                   "duration": 1.0},
    "progress_fill": {"target_path": "FillBar", "to": 100.0},
    "counter": {"target_path": "ScoreLabel", "from": 0.0,
                "to": 100.0, "steps": 10},
    "dialog_pop": {"target_path": "DialogPanel"},
    "transition": {"target_path": "FadeOverlay", "mode": "fade_out"},
    "wave": {"target_paths": ["Card1", "Card2", "Card3"]},
    "spring": {"target_path": "SpringTarget", "offset": {"x": 0, "y": -60}},
    "pendulum": {"target_path": "PendulumTarget", "amplitude": 22},
    "path_follow": {"target_path": "Drone",
                    "path_node": "/RepairFxFixture/PatrolPath",
                    "duration": 2.0, "loop_mode": "none"},
    "flipbook": {"target_path": "Sprite2D", "frames": 4, "fps": 4},
    "sprite_frames": {"sprite_path": "/RepairFxFixture/SheetSprite",
                      "texture": "res://tests/fixtures/sheet.png",
                      "hframes": 4, "vframes": 1, "fps": 4},
    "sprite_frames_stopped": {"sprite_path": "/RepairFxFixture/SheetSprite",
                              "texture": "res://tests/fixtures/sheet.png",
                              "hframes": 4, "vframes": 1, "fps": 4,
                              "play": False},
    "audio_cue": {"target_path": "CuePlayer",
                  "stream": "res://tests/fixtures/cue.wav", "time": 0.2},
}


def equivalent(left: object, right: object) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(left, right, abs_tol=1e-5, rel_tol=1e-6)
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(
            equivalent(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(
            equivalent(a, b) for a, b in zip(left, right))
    return left == right


async def timeline(client: Client, op: str) -> dict:
    if op.startswith("sprite_frames"):
        result = await call(client, "node_get_properties", {
            "path": "/RepairFxFixture/SheetSprite"})
        if result.get("error"):
            return result
        props = {item["name"]: item.get("value") for item in
                 result.get("properties", [])}
        return {"assigned": bool(props.get("sprite_frames")),
                "animation": props.get("animation"),
                "frame": props.get("frame")}
    described = await call(client, "custom_animation_inspect", {
        "op": "describe", "player_path": PLAYER, "animation_name": op})
    detailed = await call(client, "custom_animation_inspect", {
        "op": "timeline", "player_path": PLAYER, "animation_name": op,
        "max_keys": 2000})
    return {"describe": described, "timeline": detailed}


async def run(args: argparse.Namespace) -> int:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    folder = args.project_root / "repair_fx_audit" / run_id
    folder.mkdir(parents=True, exist_ok=False)
    rows = []
    transport = StdioTransport(sys.executable, ["-m", "godot_ai", "attach",
        "--port", str(args.port), "--ws-port", str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport) as client:
        await client.call_tool("session_activate", {"session_id": args.session_hint})
        for op, extras in CASES.items():
            if args.ops and op not in args.ops:
                continue
            copy_scene(args.project_root / "repair_fx_fixture.tscn",
                            folder / f"{op}.tscn")
            scene = f"res://repair_fx_audit/{run_id}/{op}.tscn"
            row = {"op": op, "scene": scene}
            row["open"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            params = {"op": "sprite_frames" if op.startswith("sprite_frames") else op,
                      "player_path": PLAYER,
                      "animation_name": op, **extras}
            row["before"] = await timeline(client, op)
            row["dry"] = await call(client, "custom_animation_fx",
                                    {**params, "dry_run": True})
            row["after_dry"] = await timeline(client, op)
            row["write"] = await call(client, "custom_animation_fx", params)
            row["after"] = await timeline(client, op)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {
                "path": scene, "force_reload": True})
            row["persisted"] = await timeline(client, op)
            rows.append(row)
    failures = []
    for row in rows:
        op = row["op"]
        for stage in ("open", "dry", "write", "save", "reopen"):
            if row[stage].get("error"):
                failures.append(f"{op}: {stage}: {row[stage]['error']}")
        if not equivalent(row["before"], row["after_dry"]):
            failures.append(f"{op}: dry run changed the target")
        if equivalent(row["before"], row["after"]):
            failures.append(f"{op}: success without a reported effect")
        if not equivalent(row["after"], row["persisted"]):
            failures.append(f"{op}: effect did not persist")
        if op.startswith("sprite_frames"):
            if row["write"].get("playing") is not (op == "sprite_frames"):
                failures.append(f"{op}: response ignored play setting")
        else:
            clips = row["persisted"].get("describe", {}).get("clips", [])
            if len(clips) != 1 or not all(t.get("node_resolved") for t in clips[0].get("tracks", [])):
                failures.append(f"{op}: missing clip or unresolved track")
    print("MCP_FX_AUDIT=" + json.dumps({"run_id": run_id,
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
    parser.add_argument("--ops", nargs="*", choices=list(CASES),
                        help="run only the selected operations")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
