"""Preserve ordinary four-rig gait/idle/transition clips through public Godot AI.

No pose or animation is authored here. Each scene mutation happens once; a new
attempt gets a new UUID. Partial receipts survive failure or interruption.
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
from mcp_character_quality_baseline import RIGS
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json

STYLES = ("responsive", "grounded", "relaxed", "heavy", "sneaky")


def save(path: Path, report: dict) -> None:
    write_json(path, report)


async def run(args: argparse.Namespace) -> int:
    motion = args.operation.removesuffix("_cycle")
    transition = args.operation in ("walk_start", "walk_stop")
    turn = args.operation == "turn_cycle"
    if args.allow_reach_refusals and (not transition or args.phase != "prototype"):
        raise ValueError("Reach refusal receipts are only valid for explicit transition prototypes")
    if motion == "walk" and args.phase == "candidate":
        raise ValueError("Walk support here is for protected baseline regression, not a new review candidate")
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.repo, text=True).strip()
    recipes = json.loads(args.recipes.read_text(encoding="utf-8")) if args.recipes else None
    if (args.phase == "prototype") != bool(recipes):
        raise ValueError("Explicit recipes are required only for prototype measurement")
    timing = {"duration": args.duration, "samples": args.samples, "phase": args.gait_phase,
              "gait_duration": args.gait_duration, "gait_samples": args.gait_samples}
    if any(value is not None for value in timing.values()) and args.phase != "prototype":
        raise ValueError("Explicit timing is a prototype input; ordinary review calls omit timing")
    if any(timing[field] is not None for field in ("phase", "gait_duration", "gait_samples")) and not transition:
        raise ValueError("Gait reference timing is only valid for transition prototypes")
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "addons/godot_ai_animation"], cwd=args.repo).returncode:
        raise RuntimeError("Commit the animation source before creating exact-source review scenes")
    run_id = uuid4().hex
    scene_folder = args.project_root / f"repair_{motion}_quality" / run_id
    scene_folder.mkdir(parents=True)
    args.output.mkdir(parents=True, exist_ok=True)
    progress_path = args.output / f"attempt-{run_id}.json"
    progress = {"source_head": source, "run_id": run_id, "state": "creating", "current": None,
                "created_utc": datetime.now(timezone.utc).isoformat(), "reports": [], "failures": []}
    save(progress_path, progress)
    async with connected_editor(args) as (client, connection):
        for style in args.styles:
            for root_mode in args.root_modes:
                folder = args.output / (style if root_mode == "extracted" else style + "-in-place")
                folder.mkdir(exist_ok=True)
                record = folder / "route.json"
                if record.exists():
                    raise FileExistsError(f"Preserve the previous attempt; choose a new output folder: {record}")
                report = {"schema_version": 1, "revision": f"{args.revision}-{style}",
                          "source_head": source, "operation": args.operation, "profile": style,
                          "root_mode": root_mode, "phase": args.phase, "run_id": run_id,
                          "invocation_kind": "explicit prototype" if recipes else "ordinary call",
                          "connection": connection, "created_utc": progress["created_utc"],
                          "tooling_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                          "cases": [], "failures": [], "passed": False}
                save(record, report)
                for rig_id, label, fixture, scene_root, rig_path, player_path, synthetic in RIGS:
                    target = scene_folder / f"{style}_{root_mode}_{rig_id}.tscn"
                    copy_scene(args.project_root / fixture, target)
                    if args.phase == "candidate" or transition or turn:
                        with target.open("a", encoding="utf-8", newline="\n") as stream:
                            marker = "PublicTransitionHistory" if transition else f"Public{motion.title()}History"
                            stream.write(f'\n[node name="{marker}" type="Node" parent="."]\n'
                                         f'metadata/player_path = NodePath("{player_path}")\n')
                            if transition or turn:
                                stream.write(f'metadata/operation = "{args.operation}"\n')
                    scene = "res://" + target.relative_to(args.project_root).as_posix()
                    player = f"/{scene_root}/{player_path}"
                    params = {"op": args.operation, "player_path": player,
                              "skeleton_path": f"/{scene_root}/{rig_path}",
                              "animation_name": f"quality_{motion}", "root_motion": root_mode == "extracted"}
                    # Ordinary Responsive/default call. No duration, sample,
                    # speed, loop or recipe override in the reviewed default.
                    if style != "responsive":
                        params["style"] = style
                    for field in ("direction", "angle", "steps"):
                        value = getattr(args, field, None)
                        if value is not None:
                            if not turn:
                                raise ValueError(f"{field} is currently a turn review control")
                            params[field] = value
                    if recipes:
                        params["overrides"] = recipes[style]
                        report["recipe_sha256"] = hashlib.sha256(args.recipes.read_bytes()).hexdigest()
                    for field, value in timing.items():
                        if value is not None:
                            params[field] = value
                    row = {"id": rig_id, "label": label, "scene": scene,
                           "skeleton": rig_path, "player": player_path,
                           "synthetic": synthetic, "params": params,
                           "fixture_sha256": hashlib.sha256((args.project_root / fixture).read_bytes()).hexdigest()}
                    report["cases"].append(row)

                    async def stage(name: str, tool: str, inputs: dict) -> dict:
                        progress["current"] = f"{style}/{root_mode}/{rig_id}/{name}"
                        save(progress_path, progress)
                        value = await call(client, tool, inputs)
                        row[name] = value
                        save(record, report)
                        return value

                    await stage("open", "scene_open", {"path": scene, "force_reload": True})
                    row["before"] = await inspect(client, params["animation_name"], player)
                    if args.allow_reach_refusals or turn:
                        row["binding_before"] = await call(client, "node_get_properties", {"path": player, "fields": ["root_motion_track"]})
                    row["pose_before"] = await stage("pose_before", "custom_animation_rig", {
                        "op": "pose_save", "skeleton_path": params["skeleton_path"]})
                    await stage("dry", "custom_manage", {"op": "invoke", "params": {
                        "tool_name": "animation_motion", "params": {**params, "dry_run": True}}})
                    row["after_dry"] = await inspect(client, params["animation_name"], player)
                    if turn:
                        await stage("binding_after_dry", "node_get_properties", {"path": player, "fields": ["root_motion_track"]})
                    await stage("pose_after_dry", "custom_animation_rig", {
                        "op": "pose_save", "skeleton_path": params["skeleton_path"]})
                    await stage("write", "custom_manage", {"op": "invoke", "params": {
                        "tool_name": "animation_motion", "params": params}})
                    row["after"] = await inspect(client, params["animation_name"], player)
                    if turn:
                        await stage("binding_after", "node_get_properties", {"path": player, "fields": ["root_motion_track"]})
                    await stage("pose_after", "custom_animation_rig", {
                        "op": "pose_save", "skeleton_path": params["skeleton_path"]})
                    if args.allow_reach_refusals and row["write"].get("error"):
                        row["binding_after"] = await call(client, "node_get_properties", {"path": player, "fields": ["root_motion_track"]})
                        row["refused"] = True
                        row["passed"] = (str(row["dry"].get("error", "")).startswith("VALUE_OUT_OF_RANGE:")
                            and row["dry"] == row["write"] and row["before"] == row["after_dry"] == row["after"]
                            and row["pose_before"] == row["pose_after_dry"] == row["pose_after"]
                            and row["binding_before"] == row["binding_after"] and not row["binding_before"].get("error"))
                        if not row["passed"]: report["failures"].append(f"{rig_id}: untyped or mutating refusal")
                        save(record, report)
                        print(f"Refused {style}/{root_mode}/{rig_id}: {'PASS' if row['passed'] else 'FAIL'}", flush=True)
                        continue
                    if turn and (row["dry"].get("error") or row["write"].get("error")):
                        progress.update(state="failed", failures=[f"{style}/{root_mode}/{rig_id}: {row['write']}"])
                        save(progress_path, progress)
                        raise RuntimeError(f"Turn request refused before history witness: {row['write']}")
                    if args.phase == "candidate" or transition or turn:
                        history = await stage("history", "test_run", {
                            "suite": "animation_motion",
                            "test_name": f"test_{motion}_undo_redo_restores_written_{motion}", "verbose": True})
                        if (history.get("passed") != 1 or history.get("failed") != 0
                                or history.get("skipped") != 0):
                            raise RuntimeError(f"Public {motion} Undo/Redo failed: {history}")
                        row["after_history"] = await inspect(client, params["animation_name"], player)
                        if row["after_history"] != row["after"]:
                            raise RuntimeError(f"Public {motion} Undo/Redo changed inspected clip")
                    await stage("save", "scene_save", {})
                    await stage("reopen", "scene_open", {"path": scene, "force_reload": True})
                    row["persisted"] = await inspect(client, params["animation_name"], player)
                    row["scene_sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
                    row["roles"] = row["write"].get("roles", {})
                    problems = [f"{rig_id}/{key}: {row[key]['error']}" for key in
                                ("open", "pose_before", "dry", "pose_after_dry", "write", "pose_after", "save", "reopen")
                                if row[key].get("error")]
                    if row["before"] != row["after_dry"]:
                        problems.append(f"{rig_id}: dry run changed clip")
                    if row["pose_before"] != row["pose_after_dry"]:
                        problems.append(f"{rig_id}: dry run changed the edited pose")
                    if row["pose_before"] != row["pose_after"]:
                        problems.append(f"{rig_id}: generation changed the edited pose")
                    if row["after"] != row["persisted"]:
                        problems.append(f"{rig_id}: save/reopen changed clip")
                    if turn and (row["binding_before"].get("error") or row["binding_before"] != row["binding_after_dry"] or row["binding_before"] != row["binding_after"]):
                        problems.append(f"{rig_id}: turn changed caller root extraction binding")
                    clips = row["persisted"].get("clips", [])
                    if not row["roles"] or len(clips) != 1 or not clips[0].get("tracks") or not all(
                            track.get("node_resolved") for track in clips[0]["tracks"]):
                        problems.append(f"{rig_id}: missing roles/clip or unresolved tracks")
                    row["passed"] = not problems
                    report["failures"].extend(problems)
                    save(record, report)
                    print(f"Preserved {style}/{root_mode}/{rig_id}: {'PASS' if row['passed'] else 'FAIL'}", flush=True)
                report["passed"] = len(report["cases"]) == 4 and not report["failures"]
                save(record, report)
                progress["reports"].append(str(record))
                progress["failures"].extend(f"{style}/{root_mode}: {x}" for x in report["failures"])
                save(progress_path, progress)
    progress.update(state="complete" if not progress["failures"] else "failed", current=None)
    save(progress_path, progress)
    print(json.dumps({"state": progress["state"], "reports": len(progress["reports"]),
                      "failures": progress["failures"], "receipt": str(progress_path)}))
    return int(bool(progress["failures"]))


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--core-root", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--ws-port", type=int, default=9500)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--phase", choices=("baseline", "prototype", "candidate"), default="baseline")
    p.add_argument("--operation", choices=("walk_cycle", "run_cycle", "idle_cycle", "walk_start", "walk_stop", "turn_cycle"), default="run_cycle")
    p.add_argument("--direction", choices=("left", "right"))
    p.add_argument("--angle", type=float, help="Requested turn angle; omit for ordinary 90 degrees")
    p.add_argument("--steps", type=int, help="Requested turn steps; use two for a 180-degree turn")
    p.add_argument("--recipes", type=Path, help="Explicit prototype recipes; final candidates use ordinary defaults")
    p.add_argument("--duration", type=float, help="Explicit prototype period; ordinary calls omit duration")
    p.add_argument("--samples", type=float, help="Explicit prototype authoring density; ordinary calls omit samples")
    p.add_argument("--allow-reach-refusals", action="store_true", help="Verify typed nonmutation for unsupported explicit transition prototypes")
    p.add_argument("--gait-phase", type=float, help="Explicit prototype transition phase; ordinary calls omit phase")
    p.add_argument("--gait-duration", type=float, help="Prototype period of the independent walk reference")
    p.add_argument("--gait-samples", type=float, help="Prototype sample rate of the independent walk reference")
    p.add_argument("--revision", default="run-baseline-r001")
    p.add_argument("--styles", choices=STYLES, nargs="+", default=list(STYLES))
    p.add_argument("--root-modes", choices=("extracted", "in_place"), nargs="+", default=["extracted"])
    raise SystemExit(asyncio.run(run(p.parse_args())))
