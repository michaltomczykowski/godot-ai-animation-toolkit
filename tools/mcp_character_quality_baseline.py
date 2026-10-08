"""Save four mandatory walk baselines or opt-in candidates via Godot AI.

Defaults remain implicit for a baseline. Candidate tuning is supplied explicitly
and preserved in the route receipt; no profile is promoted by this script.
Progress is persisted after every rig so interruption cannot erase completed work.
"""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor

RIGS = (
    ("dummy", "Bundled dummy", "repair_rig_fixture.tscn", "RepairRigFixture", "Dummy/Skeleton3D", "AnimationPlayer", False),
    ("xbot", "X Bot", "repair_xbot_fixture.tscn", "MotionXBot", "XBot/Skeleton3D", "WalkAnim", False),
    ("short", "Short synthetic", "repair_synthetic_short.tscn", "RepairRigFixture", "Dummy/Skeleton3D", "AnimationPlayer", True),
    ("zup_tall", "Tall Z-up synthetic", "repair_synthetic_zup_tall.tscn", "RepairRigFixture", "Dummy/Skeleton3D", "AnimationPlayer", True),
)

def save(path: Path, report: dict) -> None:
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")

async def run(args: argparse.Namespace) -> int:
    run_id = uuid4().hex
    folder = args.project_root / "repair_character_quality" / run_id
    folder.mkdir(parents=True)
    args.output.mkdir(parents=True, exist_ok=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.project_root.parent, text=True).strip()
    overrides = json.loads(args.overrides.read_text(encoding="utf-8")) if args.overrides else {}
    baseline = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
    report = {"schema_version": 1, "revision": args.revision, "source_head": head,
              "created_utc": datetime.now(timezone.utc).isoformat(), "run_id": run_id,
              "operation": "walk_cycle", "profile": args.profile, "fps": 60,
              "seconds_per_rig": 6, "cases": [], "failures": [], "passed": False}
    record = args.output / "route.json"
    save(record, report)
    async with connected_editor(args) as (client, connection):
        report["connection"] = connection
        for rig_id, label, fixture, scene_root, rig_path, player_path, synthetic in RIGS:
            target = folder / f"walk_{rig_id}.tscn"
            copy_scene(args.project_root / fixture, target)
            scene = f"res://repair_character_quality/{run_id}/{target.name}"
            player = f"/{scene_root}/{player_path}"
            params = {"op": "walk_cycle", "player_path": player,
                      "skeleton_path": f"/{scene_root}/{rig_path}",
                      "animation_name": "quality_baseline_walk", "root_motion": True,
                      "loop_mode": "linear"}
            if overrides:
                params["animation_name"] = "quality_candidate_walk"
                params["overrides"] = overrides
                params["samples"] = 60.0
            if baseline:
                reference = next(row for row in baseline["cases"] if row["id"] == rig_id)
                params["speed"] = reference["write"]["speed"]
            row = {"id": rig_id, "label": label, "scene": scene,
                   "skeleton": rig_path, "player": player_path,
                   "synthetic": synthetic, "params": params}
            row["open"] = await call(client, "scene_open", {"path": scene, "force_reload": True})
            row["before"] = await inspect(client, params["animation_name"], player)
            row["dry"] = await call(client, "custom_manage", {"op": "invoke", "params": {
                "tool_name": "animation_motion", "params": {**params, "dry_run": True}}})
            row["after_dry"] = await inspect(client, params["animation_name"], player)
            row["write"] = await call(client, "custom_manage", {"op": "invoke", "params": {
                "tool_name": "animation_motion", "params": params}})
            row["after"] = await inspect(client, params["animation_name"], player)
            row["save"] = await call(client, "scene_save", {})
            row["reopen"] = await call(client, "scene_open", {"path": scene, "force_reload": True})
            row["persisted"] = await inspect(client, params["animation_name"], player)
            row["scene_sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
            row["roles"] = row["write"].get("roles", row["write"].get("data", {}).get("roles", {}))
            for stage in ("open", "dry", "write", "save", "reopen"):
                if row[stage].get("error"):
                    report["failures"].append(f"{rig_id}/{stage}: {row[stage]['error']}")
            if row["before"] != row["after_dry"]:
                report["failures"].append(f"{rig_id}: dry run changed scene")
            if row["after"] != row["persisted"]:
                report["failures"].append(f"{rig_id}: save/reopen changed clip")
            clips = row["persisted"].get("clips", [])
            if not row["roles"] or len(clips) != 1 or not clips[0].get("tracks") or not all(t.get("node_resolved") for t in clips[0]["tracks"]):
                report["failures"].append(f"{rig_id}: roles/clip/tracks missing or unresolved")
            report["cases"].append(row)
            save(record, report)
            print(f"Saved {rig_id}: {scene}", flush=True)
    report["passed"] = len(report["cases"]) == 4 and not report["failures"]
    save(record, report)
    print(json.dumps({"passed": report["passed"], "failures": report["failures"], "record": str(record)}))
    return 0 if report["passed"] else 1

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--core-root", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--port", type=int, default=18131)
    p.add_argument("--ws-port", type=int, default=18132)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--revision", default="walk-baseline-r001")
    p.add_argument("--profile", default="current default")
    p.add_argument("--overrides", type=Path)
    p.add_argument("--baseline", type=Path, help="Hold the recorded baseline speed per rig for comparisons")
    raise SystemExit(asyncio.run(run(p.parse_args())))
