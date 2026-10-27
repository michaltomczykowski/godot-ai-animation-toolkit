"""Archive a checked walk revision and leave human approval pending.

Requires both candidate profiles, four rigs, actual-FPS checks, counterrotation,
continuous clean/diagnostic comparisons, and unchanged saved scenes/media.
Media and imported rigs stay on the PC. This script never grants approval.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

PROFILES = ("grounded", "responsive")
RIGS = ("dummy", "xbot", "short", "zup_tall")

def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))

def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--baseline", type=Path, required=True)
    p.add_argument("--revision", default="walk-review-r002")
    p.add_argument("--editor-tests", type=int, default=51)
    p.add_argument("--ci-report", type=Path)
    args = p.parse_args()
    records = ([read(args.baseline / "route.json")] if (args.baseline / "route.json").exists()
               else [read(args.baseline / profile / "route.json") for profile in PROFILES])
    references = list(records)
    for index, record in enumerate(references):
        label = PROFILES[index] if len(references) == 2 else "baseline"
        write(args.folder / f"reference-{label}-route.json", record)
    summaries = {}
    heads = set()
    for profile in PROFILES:
        folder = args.folder / profile
        route = read(folder / "route.json")
        reference = references[PROFILES.index(profile)] if len(references) == 2 else references[0]
        checks = read(folder / "native-check.json")
        upper = read(folder / "upper-body-check.json")
        media = read(folder / "media.json")
        if not route["passed"] or tuple(r["id"] for r in route["cases"]) != RIGS:
            raise ValueError(f"Incomplete public route: {profile}")
        expected = {(rig, fps) for rig in RIGS for fps in (30, 60, 120)}
        if len(checks["runs"]) != 12 or {(r["id"], r["fps"]) for r in checks["runs"]} != expected:
            raise ValueError(f"Incomplete actual-FPS checks: {profile}")
        if checks["structural_failures"] or checks["engine_errors"] or not all(r["thresholds_pass"] for r in checks["runs"]):
            raise ValueError(f"Native contact/loop checks failed: {profile}")
        if len(upper["runs"]) != 12 or {(r["id"], r["fps"]) for r in upper["runs"]} != expected or upper["engine_errors"]:
            raise ValueError(f"Incomplete native upper-body checks: {profile}")
        for run in upper["runs"]:
            extended_hand = any("forearm_twist" in row["params"].get("overrides", {}) for row in route["cases"])
            if extended_hand:
                relax = any(row["params"].get("overrides", {}).get("hand_relax", 0) > 0 for row in route["cases"])
                for side in ("l", "r"):
                    hand = run["hands"][side]
                    if not (hand["forearm_axial_max"] - hand["forearm_axial_min"] > 0.06
                            and hand["wrist_axis_cross_max"] > 0.5 and (not relax or hand["min_finger_curl_gain"] > 0.04)):
                        raise ValueError(f"Inert/wrong-direction hand articulation: {profile}/{run['id']}/{side}")
            if any("head_nod" in row["params"].get("overrides", {}) for row in route["cases"]):
                for role in ("head", "chest"):
                    spatial = run["spatial"][role]
                    pitch = spatial["max_pitch_deg"] - spatial["min_pitch_deg"]
                    if not (2 < pitch < 10 and run["ranges"][role]["loop_error_deg"] < 0.001
                            and run["ranges"][role]["max_step_deg"] < 2):
                        raise ValueError(f"Inert/discontinuous head/torso: {profile}/{run['id']}/{role}")
            if not run["initial_torso_opposes_hips"]:
                raise ValueError(f"Torso does not oppose hips: {profile}/{run['id']}")
            for side in ("l", "r"):
                wrist = run["ranges"]["hand_" + side]
                if not (2 < wrist["max_change_deg"] < (22 if extended_hand else 12)
                        and wrist["max_step_deg"] < (3 if extended_hand else 2) and wrist["loop_error_deg"] < 0.001):
                    raise ValueError(f"Inert/discontinuous wrist: {profile}/{run['id']}/{side}")
        if set(media["videos"]) != {"clean", "diagnostic"}:
            raise ValueError(f"Both continuous review modes required: {profile}")
        for mode, video in media["videos"].items():
            if video["decoded_frames"] != 2880 or abs(video["decoded_duration_s"] - 48) > 0.017 or video["render"]["errors"]:
                raise ValueError(f"Incomplete comparison video: {profile}/{mode}")
            render = video["render"]
            expected_chapters = [(row["id"], angle, next(r["scene"] for r in reference["cases"] if r["id"] == row["id"]), row["scene"])
                for row in route["cases"] for angle in ("FRONT", "SIDE")]
            chapters = [(row["id"], row["angle"], row["baseline_scene"], row["candidate_scene"]) for row in render["cases"]]
            if (render["source_head"] != route["source_head"] or render["revision"] != route["revision"]
                    or render["baseline_source_head"] != reference["source_head"] or render["profile"] != profile
                    or chapters != expected_chapters or render["root_consumers_per_view"] != 1):
                raise ValueError(f"Comparison does not match exact candidate/reference clips: {profile}/{mode}")
            if digest(Path(video["path"])) != video["sha256"]:
                raise ValueError("Review media changed after verification")
        detail = None
        if (folder / "hand-detail-media.json").exists():
            detail = read(folder / "hand-detail-media.json")
            if (detail["decoded_frames"] != 2880 or abs(detail["decoded_duration_s"] - 48) > 0.017
                    or detail["source_sha256"] != media["videos"]["clean"]["sha256"]
                    or digest(Path(detail["path"])) != detail["sha256"]):
                raise ValueError(f"Hand-detail media changed or is incomplete: {profile}")
        elif extended_hand:
            raise ValueError(f"Hand revision requires continuous enlarged detail: {profile}")
        feet = [f for run in checks["runs"] for f in run["feet"].values()]
        summaries[profile] = {"revision": route["revision"], "source_head": route["source_head"],
            "run_id": route["run_id"], "recovery_folder": str(folder), "route_passed": True,
            "numeric_runs": 12, "upper_body_runs": 12, "fps": [30, 60, 120],
            "max_slide_m": max(f["max_declared_stance_slide_m"] for f in feet),
            "max_rest_ankle_plane_penetration_m": max(f["max_rest_ankle_plane_penetration_m"] for f in feet),
            "max_root_error_m": max(r["root_error_m"] for r in checks["runs"]),
            "max_loop_position_error_m": max(r["loop_position_error_m"] for r in checks["runs"]),
            "max_loop_rotation_error_rad": max(r["loop_rotation_error_rad"] for r in checks["runs"]),
            "counterrotation_pass": True, "thresholds_pass": True,
            "head_torso_spatial": {run["id"]: run.get("spatial", {}) for run in upper["runs"] if run["fps"] == 60},
            "videos": {mode: {k: video[k] for k in ("path", "sha256", "bytes", "decoded_frames", "decoded_duration_s")}
                       for mode, video in media["videos"].items()},
            "chapters": media["videos"]["clean"]["render"]["cases"],
            "playback_confirmed_by_user": False, "visual_approval": None}
        if detail:
            summaries[profile]["hand_detail"] = {k: detail[k] for k in (
                "path", "sha256", "bytes", "source_sha256", "decoded_frames", "decoded_duration_s", "description")}
        summaries[profile]["hand_articulation"] = {run["id"]: run.get("hands", {})
            for run in upper["runs"] if run["fps"] == 60}
        heads.add(route["source_head"])
        records.append(route)
    if len(heads) != 1:
        raise ValueError("Candidate profiles must share an exact source revision")
    source_head = heads.pop()
    ci = read(args.ci_report or args.folder / "ci-source-671a2ff.json")
    if ci.get("headSha") != source_head or ci.get("conclusion") != "success" or sum(job["conclusion"] == "success" for job in ci["jobs"]) != 34:
        raise ValueError("Animation source must pass all 34 Windows/Linux validation jobs")
    api_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.repo, text=True).strip()
    for route in records:
        for row in route["cases"]:
            path = args.repo / "test_project" / row["scene"].removeprefix("res://")
            if digest(path) != row["scene_sha256"]: raise ValueError("Saved scene changed after invocation")
    editor = read(args.folder / "editor-motion-results.json")
    if editor.get("failed", 1) or editor.get("skipped", 1) or editor.get("passed") != args.editor_tests:
        raise ValueError("Fresh editor motion suite is incomplete")
    reload = read(args.folder / "core-reload.json")
    if not reload.get("passed") or len(reload.get("phases", [])) != 2 or any(len(phase["rows"]) != 8 or not all(row["passed"] for row in phase["rows"]) for phase in reload["phases"]):
        raise ValueError("Candidate routes must pass before and after core reload")
    subprocess.run(["git", "archive", "--format=zip", "--output", str(args.folder / "candidate-source.zip"), source_head], cwd=args.repo, check=True)
    subprocess.run(["git", "archive", "--format=zip", "--output", str(args.folder / "api-guard-source.zip"), api_head], cwd=args.repo, check=True)
    reference_heads = {record["source_head"] for record in references}
    for head in reference_heads:
        archive_path = args.folder / ("baseline-source.zip" if len(reference_heads) == 1 else f"reference-source-{head[:7]}.zip")
        subprocess.run(["git", "archive", "--format=zip", "--output", str(archive_path), head], cwd=args.repo, check=True)
    scene_paths = {args.repo / "test_project" / row["scene"].removeprefix("res://") for record in records for row in record["cases"]}
    with zipfile.ZipFile(args.folder / "native-scenes-and-local-rigs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(scene_paths):
            archive.write(path, path.relative_to(args.repo).as_posix())
        for asset in ("models/human_dummy/HumanCharacterDummy_F.fbx", "models/x_bot/X Bot.fbx"):
            path = args.repo / "test_project" / asset
            archive.write(path, path.relative_to(args.repo).as_posix())
    state_path = args.repo / "docs/character-quality-review.json"
    state = read(state_path)
    if any(state["approvals"][profile] is not None for profile in PROFILES):
        raise ValueError("Cannot overwrite a human-approved candidate review")
    if state["revision"] != args.revision:
        state.pop("candidate_delivery", None)
    state.update(revision=args.revision, state="awaiting_walk_upper_body_video_review",
        api_refusal_source=api_head,
        updated_utc=datetime.now(timezone.utc).isoformat(), candidate_review=summaries,
        next_action=f"Open Explorer with the {args.revision} comparison videos on the PC; ask for articulation and whole-walk feedback on both profiles/all four rigs, then stop. No default promotion or next operation before review.")
    state.pop("pending_candidate_source", None)
    state.pop("pending_candidate_recovery", None)
    if state.get("candidate_delivery", {}).get("explorer_window_verified"):
        state["next_action"] = f"Wait for human {args.revision} video feedback after Explorer was opened on the PC. Ask about both candidates/all four rigs, then stop; no default promotion or next motion before review."
    write(state_path, state)
    write(args.folder / "validation.json", {"source_head": source_head, "profiles": summaries,
        "human_approval": None, "limits": "Authored candidates and ankle/marker checks; finger curl uses validated named chains/palm geometry only, thumbs stay at rest; no skinned-sole collision or COM validation."})
    tooling = ["tools/mcp_character_quality_baseline.py", "tools/compose_character_quality.py",
        "tools/mcp_walk_revision_reload.py",
        "tools/deliver_walk_review.py",
        "tools/record_walk_review.ps1", "tools/archive_walk_revision.py", "test_project/tools/character_quality_native.gd",
        "test_project/tools/check_character_quality.gd", "test_project/tools/check_walk_upper_body.gd",
        "test_project/tools/render_character_quality.gd", "test_project/tools/render_walk_comparison.gd"]
    tooling += ["test_project/tools/measure_walk_hand_geometry.gd"]
    if (args.repo / "tools/compose_walk_hand_detail.py").exists():
        tooling += ["tools/compose_walk_hand_detail.py"]
    docs = ["AGENTS.md", "FIX_ROADMAP.md", "docs/character-quality-plan.md", "docs/character-quality-review.json",
        "docs/walk-upper-body-revision-plan.md", "docs/walk-upper-body-r002-validation.md",
        "docs/walk-upper-body-grounded-r002.json", "docs/walk-upper-body-responsive-r002.json"]
    docs += [path.relative_to(args.repo).as_posix() for path in (args.repo / "docs").glob("walk-head-torso-*")]
    docs += [path.relative_to(args.repo).as_posix() for path in (args.repo / "docs").glob("walk-hand-follow-through-*")]
    with zipfile.ZipFile(args.folder / "review-tooling-and-docs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in (*tooling, *docs): archive.write(args.repo / relative, relative)
    paths = [path for path in args.folder.iterdir() if path.is_file() and path.name != "receipts.json"]
    paths += [path for profile in PROFILES for path in (args.folder / profile).iterdir() if path.is_file()]
    write(args.folder / "receipts.json", {"source_head": source_head,
        "files": {path.relative_to(args.folder).as_posix(): {"sha256": digest(path), "bytes": path.stat().st_size} for path in paths},
        "tooling": {path: digest(args.repo / path) for path in tooling}})
    print(json.dumps({"state": state["state"], "profiles": 2, "scenes": len(scene_paths), "videos": 4, "source_head": source_head}))

if __name__ == "__main__": main()
