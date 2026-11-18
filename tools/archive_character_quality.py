"""Preserve a completed baseline review and mark its human gate as pending.

Does not grant approval or change addon motion. Media/assets stay local.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--repo", type=Path, required=True)
    args = p.parse_args()
    route = json.loads((args.folder / "route.json").read_text())
    checks = json.loads((args.folder / "native-check.json").read_text())
    media = json.loads((args.folder / "media.json").read_text())
    if not route["passed"] or len(checks["runs"]) != 12 or checks["structural_failures"] or checks["engine_errors"] or set(media["videos"]) != {"clean", "diagnostic"}:
        raise ValueError("Baseline capture/route evidence is incomplete")
    for row in route["cases"]:
        scene = args.repo / "test_project" / row["scene"].removeprefix("res://")
        if digest(scene) != row["scene_sha256"]: raise ValueError("Saved scene changed since invocation")
    for video in media["videos"].values():
        if digest(Path(video["path"])) != video["sha256"]: raise ValueError("Review video changed since verification")
    source_archive = args.folder / "baseline-source.zip"
    subprocess.run(["git", "archive", "--format=zip", "--output", str(source_archive), route["source_head"]], cwd=args.repo, check=True)
    scenes = args.folder / "native-scenes-and-local-rigs.zip"
    with zipfile.ZipFile(scenes, "w", zipfile.ZIP_DEFLATED) as archive:
        for record in (route, json.loads((args.folder / "default_nonloop_route.json").read_text())):
            for row in record["cases"]:
                path = args.repo / "test_project" / row["scene"].removeprefix("res://")
                archive.write(path, path.relative_to(args.repo).as_posix())
        for asset in ("models/human_dummy/HumanCharacterDummy_F.fbx", "models/x_bot/X Bot.fbx"):
            path = args.repo / "test_project" / asset
            archive.write(path, path.relative_to(args.repo).as_posix())
    tracked_tooling = ["tools/mcp_character_quality_baseline.py", "tools/compose_character_quality.py",
        "tools/archive_character_quality.py", "test_project/tools/character_quality_native.gd",
        "test_project/tools/check_character_quality.gd", "test_project/tools/render_character_quality.gd"]
    tooling_hashes = {path: digest(args.repo / path) for path in tracked_tooling}
    state_path = args.repo / "docs/character-quality-review.json"
    state = json.loads(state_path.read_text())
    if any(value is not None for value in state["approvals"].values()):
        raise ValueError("Cannot overwrite a review that already has human decisions")
    state.update(state="awaiting_baseline_video_feedback", updated_utc=datetime.now(timezone.utc).isoformat(),
        next_action="Read and record human timestamped baseline feedback before changing motion or producing candidate profiles.",
        recovery_folder=str(args.folder), route={"run_id": route["run_id"], "passed": True, "required_rigs_present": 4},
        numeric={"runs": 12, "actual_fps": [30, 60, 120], "engine_errors": [], "structural_failures": [],
                 "thresholds_pass": all(r["thresholds_pass"] for r in checks["runs"]),
                 "limits": "Played ankles/declared markers; no skinned-sole or COM proof."},
        videos={mode: {k: video[k] for k in ("path", "sha256", "decoded_frames", "decoded_duration_s")} for mode, video in media["videos"].items()},
        chapters=[{"rig": r["id"], "start_s": i * 6, "end_s": (i + 1) * 6} for i, r in enumerate(route["cases"])],
        observed_concerns=["Tall Z-up rig keeps arms raised despite passing ankle contact checks; human review pending."],
        capture_tooling_sha256=tooling_hashes)
    state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    copies = ("docs/character-quality-plan.md", "docs/character-quality-review.json", "docs/character-quality-baseline-validation.md", "FIX_ROADMAP.md")
    with zipfile.ZipFile(args.folder / "review-tooling-and-docs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in (*tracked_tooling, *copies): archive.write(args.repo / relative, relative)
    receipts = {}
    for path in args.folder.iterdir():
        if path.is_file() and path.name != "receipts.json": receipts[path.name] = {"sha256": digest(path), "bytes": path.stat().st_size}
    (args.folder / "receipts.json").write_text(json.dumps({"source_head": route["source_head"], "files": receipts, "tooling": tooling_hashes}, indent=2), encoding="utf-8")
    print(json.dumps({"state": state["state"], "scenes": 8, "videos": 2, "source_head": route["source_head"], "receipted_files": len(receipts)}))
if __name__ == "__main__": main()
