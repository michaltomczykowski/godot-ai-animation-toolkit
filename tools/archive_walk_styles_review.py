"""Archive R1 review media without converting technical checks into approval.

Historical pre-v2 golden differences remain explicit pending gates. This is a
review-delivery receipt, never a release-ready or fully-green CI receipt.
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

STYLES = ("responsive", "grounded", "relaxed", "heavy", "sneaky")
RIGS = ("dummy", "xbot", "short", "zup_tall")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--reference-root", type=Path, required=True)
    args = p.parse_args()
    expected = {(rig, fps) for rig in RIGS for fps in (30, 60, 120)}
    records = []
    videos = []
    heads = set()
    for style in STYLES:
        folder = args.folder / style
        route, native, media = (read(folder / name) for name in
                                ("route.json", "native-check.json", "media.json"))
        if not route["passed"] or tuple(row["id"] for row in route["cases"]) != RIGS:
            raise ValueError("Incomplete public style route: " + style)
        if (len(native["runs"]) != 12 or {(x["id"], x["fps"]) for x in native["runs"]} != expected
                or native["engine_errors"] or native["structural_failures"]
                or not all(x["thresholds_pass"] for x in native["runs"])):
            raise ValueError("Failed actual-FPS style gate: " + style)
        heads.add(route["source_head"])
        records.append(route)
        reference_style = "grounded" if style == "grounded" else "responsive"
        reference = read(args.reference_root / reference_style / "route.json")
        if set(media["videos"]) != {"clean", "diagnostic"}:
            raise ValueError("Missing review modes: " + style)
        for mode, video in media["videos"].items():
            render = video["render"]
            chapters = [(r["id"], r["angle"], r["baseline_scene"], r["candidate_scene"])
                        for r in render["cases"]]
            required = [(r["id"], angle, next(x["scene"] for x in reference["cases"] if x["id"] == r["id"]), r["scene"])
                        for r in route["cases"] for angle in ("FRONT", "SIDE")]
            if (video["decoded_frames"] != 2880 or abs(video["decoded_duration_s"] - 48) > 0.017
                    or render["errors"] or render["source_head"] != route["source_head"]
                    or render["baseline_source_head"] != reference["source_head"]
                    or render["profile"] != style or render["revision"] != route["revision"]
                    or chapters != required or render["root_consumers_per_view"] != 1
                    or digest(Path(video["path"])) != video["sha256"]):
                raise ValueError("Invalid exact-source continuous media: " + style + "/" + mode)
            videos.append({"style": style, "mode": mode, **{k: video[k] for k in
                           ("path", "sha256", "bytes", "decoded_frames", "decoded_duration_s")}})
    if len(heads) != 1:
        raise ValueError("Mixed animation source revisions")
    source = heads.pop()
    for style in ("responsive", "grounded"):
        matched = read(args.folder / (style + "-matched") / "route.json")
        parity = read(args.folder / (style + "-matched") / "parity.json")
        if (not matched["passed"] or matched["source_head"] != source or not parity["passed"]
                or parity["candidate_source"] != source or len(parity["rows"]) != 12
                or {(r["rig"], r["fps"]) for r in parity["rows"]} != expected):
            raise ValueError("Missing original r004 playback parity: " + style)
        records.append(matched)
    reload = read(args.folder / "core-reload.json")
    if (not reload["passed"] or len(reload["phases"]) != 2
            or any(len(phase["rows"]) != 20 or not all(row["passed"] for row in phase["rows"])
                   for phase in reload["phases"])):
        raise ValueError("Incomplete style reload gate")
    tests = read(args.folder / "editor-motion-second.json")["tests"]
    if (tests["total"] != 58 or tests["skipped"] != 0 or tests["failed"] != 1
            or [x["test"] for x in tests["failures"]] != ["test_the_walk_matches_its_golden"]):
        raise ValueError("Unexpected editor failure; only preserved historical walk golden may be pending")
    tiers = read(args.folder / "tier1-summary.json")
    if len(tiers["rows"]) != 14 or [x["suite"] for x in tiers["rows"] if not x["passed"]] != ["tier1_proportions"]:
        raise ValueError("Unexpected headless gate gap")
    # Preserve originals; check every scene before archiving or recording review.
    originals = [read(args.reference_root / style / "route.json") for style in ("responsive", "grounded")]
    with zipfile.ZipFile(args.folder / "native-scenes-and-local-rigs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        seen = set()
        for record in (*records, *originals):
            for row in record["cases"]:
                relative = row["scene"].removeprefix("res://")
                path = args.project_root / relative
                if digest(path) != row["scene_sha256"]:
                    raise ValueError("Saved scene changed: " + relative)
                if relative not in seen:
                    archive.write(path, "project/" + relative)
                    seen.add(relative)
        for relative in ("models/human_dummy/HumanCharacterDummy_F.fbx", "models/x_bot/X Bot.fbx"):
            archive.write(args.project_root / relative, "project/" + relative)
    subprocess.run(["git", "archive", "--format=zip", "--output", str(args.folder / "animation-source.zip"), source],
                   cwd=args.repo, check=True)
    destination = args.folder / "review-videos"
    destination.mkdir(exist_ok=True)
    for video in videos:
        target = destination / Path(video["path"]).name
        shutil.copy2(video["path"], target)
        if digest(target) != video["sha256"]:
            raise ValueError("Review copy differs")
        video["path"] = str(target)
    (destination / "START-HERE.txt").write_text(
        "Start with walk-default-responsive-r005-clean.mp4 (the ordinary call, no style/recipe/sampling overrides).\n"
        "Then grounded, relaxed, heavy and sneaky clean videos. Diagnostic copies are optional for checking contacts.\n"
        "LEFT: original accepted r004 Responsive (Grounded for grounded). RIGHT: actual normal-call candidate style.\n"
        "Default speeds are chosen by each style; captions report travel, not a false same-speed claim.\n"
        "Each video is 48 seconds: dummy 00-12, X Bot 12-24, short 24-36, tall Z-up 36-48.\n"
        "Each rig has six continuous seconds front and six side.\n"
        "Please approve/revise the default and each optional style; all four rigs need coverage.\n"
        "Historical golden updates and final green CI remain pending feedback. No release has been made.\n", encoding="utf-8")
    receipt = {"state": "awaiting_promoted_walk_styles_feedback", "animation_source": source,
               "technical_review_delivery_complete": True, "release_ready": False,
               "pending_gates": ["human default/optional-style review", "historical golden migration after review",
                                 "full green Windows/Linux regression", "R2-R5 closure"],
               "videos": videos, "public_clips": 28, "contact_runs": 60, "r004_parity_runs": 24,
               "reload_dry_calls": 40, "created_utc": datetime.now(timezone.utc).isoformat()}
    state_path = args.repo / "docs/character-quality-review.json"
    state = read(state_path)
    same_delivery = (state.get("revision") == "walk-default-styles-r005"
                     and state.get("promoted_walk_review", {}).get("animation_source") == source)
    if not same_delivery:
        state["previous_candidate_delivery"] = state.get("candidate_delivery")
    approvals = (state.get("promoted_walk_review", {}).get("approvals", {})
                 if same_delivery else {})
    delivery = state.get("candidate_delivery", {}) if same_delivery else {}
    if same_delivery:
        if state.get("state") != receipt["state"] or any(value is not None for value in approvals.values()):
            raise ValueError("Feedback is already recorded; do not reset the review gate")
        receipt["created_utc"] = state["promoted_walk_review"]["created_utc"]
    write(args.folder / "review-delivery.json", receipt)
    next_action = ("Stop for explicit Responsive/default, Grounded, relaxed, heavy and sneaky feedback covering all four rigs."
                   if delivery.get("explorer_open_requested") else
                   "Open PC Explorer with r005 review videos, then stop for explicit Responsive/default, Grounded, relaxed, heavy and sneaky feedback covering all four rigs.")
    state.update(revision="walk-default-styles-r005", state=receipt["state"],
                 recovery_folder=str(args.folder), updated_utc=receipt["created_utc"],
                 next_action=next_action + " Preserve goldens until feedback; do not start run/R2 or release.",
                 promoted_walk_review={**receipt, "approvals": {style: approvals.get(style) for style in STYLES}},
                 candidate_delivery={**delivery, "method": "PC File Explorer, user views remotely", "files": videos,
                                     "playback_confirmed_by_user": delivery.get("playback_confirmed_by_user", False),
                                     "explorer_open_requested": delivery.get("explorer_open_requested", False)})
    write(state_path, state)
    tooling = ("tools/record_walk_styles.ps1", "tools/archive_walk_styles_review.py", "tools/mcp_walk_default_suite.py",
               "tools/mcp_walk_revision_reload.py", "tools/mcp_character_quality_baseline.py", "tools/compose_character_quality.py",
               "test_project/tools/check_walk_default_parity.gd", "test_project/tools/character_quality_native.gd",
               "test_project/tools/check_character_quality.gd", "test_project/tools/render_walk_comparison.gd",
               "docs/character-quality-review.json", "docs/walk-default-integration-validation.md",
               "docs/release-wrap-up-plan.md", "FIX_ROADMAP.md", "AGENTS.md")
    with zipfile.ZipFile(args.folder / "review-tooling-and-docs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in tooling: archive.write(args.repo / relative, relative)
    write(args.folder / "receipts.json", {"animation_source": source,
          "files": {str(path.relative_to(args.folder)): {"sha256": digest(path), "bytes": path.stat().st_size}
                    for path in args.folder.rglob("*") if path.is_file() and path.suffix in (".json", ".zip", ".mp4")
                    and path.name != "receipts.json"}})
    print(json.dumps({"state": receipt["state"], "videos": len(videos), "source": source, "folder": str(destination)}))


if __name__ == "__main__":
    main()
