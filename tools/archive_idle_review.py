"""Require idle's public/native/regression/media gates before delivering PC review."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from archive_run_review import digest, read, require, write, STYLES, RIGS


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--prototype", type=Path, required=True)
    parser.add_argument("--gates", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--core-root", type=Path, required=True)
    parser.add_argument("--ci-receipt", type=Path, required=True)
    args = parser.parse_args()
    require(not (args.folder / "review-delivery.json").exists(), "Review already delivered; preserve its archive/feedback")
    matrix = read(args.folder / "native-matrix.json")
    require(matrix["passed"] and matrix["native_runs"] == 240 and len(matrix["rows"]) == 10, "Incomplete idle matrix")
    source = matrix["source_head"]
    records, videos = [], []
    expected = {(rig, fps, mixer) for rig in RIGS for fps in (30, 60, 120) for mixer in ("player", "tree")}
    for style in STYLES:
        baseline = read(args.baseline / (style + "-in-place") / "route.json")
        require(baseline["passed"] and baseline["operation"] == "idle_cycle", "Missing ordinary idle baseline")
        records.append(baseline)
        for root_mode in ("extracted", "in_place"):
            folder = args.folder / (style if root_mode == "extracted" else style + "-in-place")
            route, native = (read(folder / name) for name in ("route.json", "native-check.json"))
            require(route["passed"] and route["phase"] == "candidate" and route["operation"] == "idle_cycle"
                    and route["invocation_kind"] == "ordinary call" and route["source_head"] == source
                    and route["root_mode"] == root_mode and route["profile"] == style
                    and tuple(row["id"] for row in route["cases"]) == RIGS, "Incomplete ordinary idle route")
            for row in route["cases"]:
                params, history = row["params"], row["history"]
                require(not any(key in params for key in ("overrides", "duration", "samples", "speed", "loop_mode")), "Review call overrides defaults")
                require(("style" not in params) if style == "responsive" else params["style"] == style, "Wrong review style")
                require(params["root_motion"] == (root_mode == "extracted") and row["write"]["root_motion"] is False, "Wrong idle root policy")
                require(history["total"] == history["passed"] == 1 and history["failed"] == history["skipped"] == 0
                        and row["before"] == row["after_dry"] and row["pose_before"] == row["pose_after"]
                        and row["after"] == row["after_history"] == row["persisted"], "Failed actual public history/dry/save gate")
                require(row["write"]["reach_evaluated"] and row["write"]["clamped"] is False
                        and 0 < row["write"]["length"] <= 3.0, "Unknown/clamped/too-long idle output")
            require(native["passed"] and native["source_head"] == source and not native["engine_errors"]
                    and len(native["runs"]) == 24 and {(r["id"], r["fps"], r["mixer"]) for r in native["runs"]} == expected
                    and all(r["candidate_quality_pass"] and not r["active_root_position_track"] for r in native["runs"]), "Incomplete native idle gate")
            records.append(route)
            if root_mode == "extracted":
                media = read(folder / "media.json")
                require(set(media["videos"]) == {"clean", "diagnostic"}, "Both continuous modes required")
                chapters = [(row["id"], angle, next(r["scene"] for r in baseline["cases"] if r["id"] == row["id"]), row["scene"])
                            for row in route["cases"] for angle in ("FRONT", "SIDE")]
                for mode, video in media["videos"].items():
                    render = video["render"]
                    require(video["decoded_frames"] == 2880 and abs(video["decoded_duration_s"] - 48.0) <= 0.017
                            and render["frames"] == 2880 and render["fps"] == 60 and render["size"] == [1920, 1080]
                            and not render["errors"] and render["source_head"] == source
                            and render["root_consumers_per_view"] == 1
                            and render["baseline_source_head"] == baseline["source_head"]
                            and render["profile"] == style and render["revision"] == route["revision"]
                            and [(c["id"], c["angle"], c["baseline_scene"], c["candidate_scene"]) for c in render["cases"]] == chapters
                            and all(c["frames"] == 360 and c["duration_s"] == 6.0 for c in render["cases"])
                            and digest(Path(video["path"])) == video["sha256"], "Invalid idle review video")
                    for sample in video["qa_samples"]:
                        require(digest(folder / (mode + "_frames") / sample["frame"]) == sample["sha256"], "Changed QA frame")
                    videos.append({"style": style, "mode": mode, **{key: video[key] for key in ("path", "sha256", "bytes", "decoded_frames", "decoded_duration_s")}})
    for style in ("responsive", "grounded"):
        folder = args.prototype / (style + "-in-place")
        route, native = read(folder / "route.json"), read(folder / "native-check.json")
        require(route["passed"] and route["phase"] == "prototype" and native["passed"] and len(native["runs"]) == 24, "Missing reachable prototype")
        records.append(route)
    require(subprocess.run(["git", "diff", "--quiet", source, "HEAD", "--", "addons/godot_ai_animation"], cwd=args.repo).returncode == 0
            and subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "addons/godot_ai_animation"], cwd=args.repo).returncode == 0, "Animation changed after review capture")
    reload = read(args.folder / "core-reload.json")
    require(reload["passed"] and len(reload["phases"]) == 2
            and reload["phases"][0]["connection"]["session_id"] != reload["phases"][1]["connection"]["session_id"]
            and all(len(p["rows"]) == 20 and len(p["catalog"]) == 10 and len(p["promoted"]) == 8
                    and all(r["passed"] for r in p["rows"]) for p in reload["phases"]), "Missing idle/all-family core reload proof")
    focused = read(args.gates / "motion-suite-final-source.json")["tests"]
    require(focused["total"] == 64 and focused["passed"] == 63 and focused["failed"] == 1 and focused["skipped"] == 0
            and [r["test"] for r in focused["results"] if not r["passed"]] == ["test_the_idle_matches_its_golden"], "Unexpected focused failure")
    full = read(args.gates / "editor-full.json")
    require(full["expected_legacy_idle_golden_only"] and full["total"] == 389 and full["passed"] == 388
            and full["skipped"] == 0 and full["engine_errors"] == 0 and full["tool_route_pass_markers"] == 2, "Unexpected full editor result")
    tiers = read(args.gates / "tier1-summary.json")
    require(tiers["suites"] == 14 and tiers["engine_errors"] == 0, "Headless failure")
    ci = read(args.ci_receipt)
    require(ci["source_head"] == source and ci["expected_legacy_idle_golden_only"] and ci["all_other_source_jobs_pass"], "Unexpected candidate source CI")
    state_path = args.repo / "docs/character-quality-review.json"
    state = read(state_path)
    previous = state.get("idle_review", {})
    require(not any(previous.get("profile_approvals", {}).values()), "Idle feedback already recorded; do not reset")
    scene_files = []
    with zipfile.ZipFile(args.folder / "native-scenes-and-local-rigs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        seen = set()
        for record in records:
            for row in record["cases"]:
                relative = row["scene"].removeprefix("res://")
                path = args.project_root / relative
                require(digest(path) == row["scene_sha256"], "Changed saved scene")
                if relative not in seen:
                    archive.write(path, "project/" + relative)
                    scene_files.append({"path": relative, "sha256": row["scene_sha256"]})
                    seen.add(relative)
        for relative in ("models/human_dummy/HumanCharacterDummy_F.fbx", "models/x_bot/X Bot.fbx"):
            path = args.project_root / relative
            archive.write(path, "project/" + relative)
            scene_files.append({"path": relative, "sha256": digest(path)})
    source_zip = args.folder / "animation-source.zip"
    subprocess.run(["git", "archive", "--format=zip", "--output", str(source_zip), source], cwd=args.repo, check=True)
    destination = args.folder / "review-videos"
    destination.mkdir(exist_ok=True)
    for video in videos:
        target = destination / Path(video["path"]).name
        if not target.exists(): shutil.copy2(video["path"], target)
        require(digest(target) == video["sha256"], "Changed PC review copy")
        video["path"] = str(target)
    (destination / "START-HERE.txt").write_text(
        "Start with idle-review-r001-responsive-clean.mp4, then grounded, relaxed, heavy and sneaky.\n"
        "LEFT: preserved ordinary legacy idle. RIGHT: new ordinary idle, no recipe/timing/sampling overrides.\n"
        "48 continuous seconds, 1080p60. Each rig: six seconds FRONT, six SIDE (two new idle periods per view).\n"
        "00-12 dummy; 12-24 X Bot; 24-36 short; 36-48 tall Z-up. Diagnostic green is measured ankle contact band.\n"
        "Review quiet breathing/head motion, relaxed arms/wrists/fingers, weight shifts and standing foot plants.\n"
        "Approve or request changes for each of the five styles across the four rigs. No release yet.\n", encoding="utf-8")
    receipt = {"state": "awaiting_idle_styles_feedback", "animation_source": source,
               "core_source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.core_root, text=True).strip(),
               "created_utc": datetime.now(timezone.utc).isoformat(), "public_clips": 40, "native_runs": 240,
               "reload_dry_calls": 40, "prototype_runs": 48, "release_ready": False,
               "candidate_ci_receipt": str(args.ci_receipt), "videos": videos, "scene_files": scene_files,
               "source_zip_sha256": digest(source_zip), "scene_zip_sha256": digest(args.folder / "native-scenes-and-local-rigs.zip")}
    # Snapshot current review/checker tooling separately from the immutable
    # animation-source tree. Keep raw media and private rigs in local archives.
    with zipfile.ZipFile(args.folder / "tooling-and-phase-receipts.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for directory in ("tools", "test_project/tools"):
            for path in sorted((args.repo / directory).iterdir()):
                if path.suffix in (".py", ".ps1", ".gd", ".uid"):
                    archive.write(path, "repo/" + path.relative_to(args.repo).as_posix())
        for path in [args.repo / "AGENTS.md", args.repo / "FIX_ROADMAP.md", state_path,
                     *sorted((args.repo / "docs").glob("idle-*"))]:
            archive.write(path, "repo/" + path.relative_to(args.repo).as_posix())
        for path in sorted(args.folder.parent.rglob("*")):
            if path.is_file() and path.suffix in (".json", ".log"):
                archive.write(path, "receipts/" + path.relative_to(args.folder.parent).as_posix())
    receipt["tooling_zip_sha256"] = digest(args.folder / "tooling-and-phase-receipts.zip")
    previous.update(state=receipt["state"], animation_source=source, public_clips=40, native_runs=240,
                    videos=videos, profile_approvals={style: None for style in STYLES}, release_ready=False,
                    review_delivery=str(args.folder / "review-delivery.json"))
    state.update(state=receipt["state"], active_review_field="idle_review", idle_review=previous,
                 next_action="Open PC Explorer on idle Responsive clean; pause for explicit five-style/four-rig idle feedback.")
    write(args.folder / "review-delivery.json", receipt)
    write(state_path, state)
    print("IDLE_REVIEW_READY=10 continuous videos; 40 public history clips; 240 native runs; awaiting manual feedback")


if __name__ == "__main__":
    main()
