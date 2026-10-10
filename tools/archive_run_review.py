"""Archive a verified run candidate and prepare PC review without granting approval."""
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
    path.write_bytes((json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--baseline", type=Path, required=True)
    p.add_argument("--prototype", type=Path, required=True)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--core-root", type=Path, required=True)
    args = p.parse_args()
    records, videos, heads = [], [], set()
    expected = {(rig, fps, mixer) for rig in RIGS for fps in (30, 60, 120) for mixer in ("player", "tree")}
    parity_expected = {(rig, fps) for rig in RIGS for fps in (30, 60, 120)}
    for style in STYLES:
        baseline = read(args.baseline / style / "route.json")
        prototype = read(args.prototype / style / "route.json")
        require(baseline["passed"] and prototype["passed"], "Missing diagnostic source route")
        records.extend((baseline, prototype))
        for root_mode in ("extracted", "in_place"):
            folder = args.folder / (style if root_mode == "extracted" else style + "-in-place")
            route, native = (read(folder / name) for name in ("route.json", "native-check.json"))
            require(route["passed"] and route["phase"] == "candidate"
                    and route["invocation_kind"] == "ordinary call" and route["root_mode"] == root_mode
                    and route["profile"] == style and tuple(x["id"] for x in route["cases"]) == RIGS,
                    "Incomplete ordinary candidate route: " + str(folder))
            for row in route["cases"]:
                require(not any(k in row["params"] for k in ("overrides", "duration", "samples", "speed", "loop_mode")),
                        "Review default has explicit recipe/timing overrides")
                require(("style" not in row["params"]) if style == "responsive" else row["params"]["style"] == style,
                        "Review style does not match ordinary call")
                require(row["history"]["total"] == row["history"]["passed"] == 1
                        and row["history"]["failed"] == row["history"]["skipped"] == 0
                        and row["before"] == row["after_dry"] and row["pose_before"] == row["pose_after"]
                        and row["after"] == row["after_history"] == row["persisted"],
                        "Failed public history/dry/save gate: " + row["id"])
            require(native["passed"] and not native["failures"] and not native["engine_errors"]
                    and len(native["runs"]) == 24 and native["source_head"] == route["source_head"]
                    and {(x["id"], x["fps"], x["mixer"]) for x in native["runs"]} == expected,
                    "Incomplete native matrix: " + str(folder))
            heads.add(route["source_head"])
            records.append(route)
            if root_mode == "extracted":
                parity = read(folder / "prototype-parity.json")
                require(parity["passed"] and not parity["engine_errors"] and len(parity["rows"]) == 12
                        and {(x["rig"], x["fps"]) for x in parity["rows"]} == parity_expected
                        and parity["candidate_source"] == route["source_head"]
                        and parity["reference_source"] == prototype["source_head"], "Prototype parity missing")
                media = read(folder / "media.json")
                require(set(media["videos"]) == {"clean", "diagnostic"}, "Missing continuous modes: " + style)
                for mode, video in media["videos"].items():
                    render = video["render"]
                    required_chapters = [(row["id"], angle, next(x["scene"] for x in baseline["cases"] if x["id"] == row["id"]), row["scene"])
                                         for row in route["cases"] for angle in ("FRONT", "SIDE")]
                    chapters = [(x["id"], x["angle"], x["baseline_scene"], x["candidate_scene"]) for x in render["cases"]]
                    require(video["decoded_frames"] == 2880 and abs(video["decoded_duration_s"] - 48) <= 0.017
                            and not render["errors"] and render["source_head"] == route["source_head"]
                            and render["baseline_source_head"] == baseline["source_head"]
                            and render["profile"] == style and render["revision"] == route["revision"]
                            and render["root_consumers_per_view"] == 1 and chapters == required_chapters
                            and digest(Path(video["path"])) == video["sha256"], "Invalid final continuous video")
                    for sample in video["qa_samples"]:
                        require(digest(folder / (mode + "_frames") / sample["frame"]) == sample["sha256"], "Changed native QA frame")
                    videos.append({"style": style, "mode": mode, **{k: video[k] for k in
                                   ("path", "sha256", "bytes", "decoded_frames", "decoded_duration_s")}})
    require(len(heads) == 1, "Mixed candidate source")
    source = heads.pop()
    require(subprocess.run(["git", "diff", "--quiet", source, "HEAD", "--", "addons/godot_ai_animation"], cwd=args.repo).returncode == 0,
            "Current animation differs from recorded candidate")
    require(subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "addons/godot_ai_animation"], cwd=args.repo).returncode == 0,
            "Uncommitted animation source")
    matrix = read(args.folder / "native-matrix.json")
    require(matrix["passed"] and matrix["native_runs"] == 240 and matrix["parity_runs"] == 60
            and matrix["source_head"] == source, "Incomplete aggregate native receipt")
    reload = read(args.folder / "core-reload.json")
    require(reload["passed"] and len(reload["phases"]) == 2
            and [x["phase"] for x in reload["phases"]] == ["before_reload", "after_reload"]
            and reload["phases"][0]["connection"]["session_id"] != reload["phases"][1]["connection"]["session_id"]
            and all(len(x["rows"]) == 20 and len(x["catalog"]) == 10 and len(x["promoted"]) == 8
                    and all(y["passed"] for y in x["rows"]) for x in reload["phases"]), "Incomplete public reload receipt")
    root = args.folder.parent
    tests = read(root / "editor-final-source-motion.json")["tests"]
    require(tests["total"] == 61 and tests["passed"] == 60 and tests["failed"] == 1 and tests["skipped"] == 0
            and [x["test"] for x in tests["results"] if not x["passed"]] == ["test_the_run_matches_its_golden"],
            "Unexpected focused editor failure")
    tiers = read(root / "tier1-summary.json")
    require(len(tiers["rows"]) == 14 and all(x["passed"] for x in tiers["rows"]), "Headless suite failure")
    state_path = args.repo / "docs/character-quality-review.json"
    state = read(state_path)
    previous = state.get("run_review", {})
    require(not any(previous.get("approvals", {}).values()), "Run feedback already recorded; do not reset approval")
    scene_files = []
    with zipfile.ZipFile(args.folder / "native-scenes-and-local-rigs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        seen = set()
        for record in records:
            for row in record["cases"]:
                relative = row["scene"].removeprefix("res://")
                path = args.project_root / relative
                require(digest(path) == row["scene_sha256"], "Changed saved scene: " + relative)
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
        if not target.exists():
            shutil.copy2(video["path"], target)
        require(digest(target) == video["sha256"], "Changed review copy")
        video["path"] = str(target)
    (destination / "START-HERE.txt").write_text(
        "Start with run-review-r001-responsive-clean.mp4; then grounded, relaxed, heavy and sneaky clean.\n"
        "LEFT: preserved ordinary legacy run. RIGHT: new ordinary profile, without recipe/timing/sampling overrides.\n"
        "Each video: 48 continuous seconds, 1080p60. Each rig has six seconds FRONT then six SIDE.\n"
        "00-12 dummy; 12-24 X Bot; 24-36 short; 36-48 tall Z-up. Diagnostic copies show authored contact/flight labels.\n"
        "Review running elbows, torso/head coordination, wrist/forearm/hand movement, flight and foot plants.\n"
        "Please approve or request changes for each style across the four rigs. Numerical checks do not grant approval.\n"
        "The old run golden remains preserved; versioned replacement/full green CI follow your approval. No release yet.\n",
        encoding="utf-8")
    core = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.core_root, text=True).strip()
    receipt = {"state": "awaiting_run_styles_feedback", "animation_source": source, "core_source": core,
               "technical_review_delivery_complete": True, "release_ready": False,
               "public_clips": 40, "native_runs": 240, "prototype_parity_runs": 60, "reload_dry_calls": 40,
               "focused_editor": {"total": 61, "passed": 60, "failed": 1, "skipped": 0,
                                  "preserved_failure": "test_the_run_matches_its_golden"},
               "headless_suites": 14, "videos": videos, "saved_scene_files": scene_files,
               "animation_source_zip_sha256": digest(source_zip),
               "scene_archive_sha256": digest(args.folder / "native-scenes-and-local-rigs.zip"),
               "pending_gates": ["explicit five-style/four-rig run feedback", "separate run golden after approval",
                                 "full green Windows/Linux regression", "remaining R2-R5 and final candidate review"],
               "approvals": {style: None for style in STYLES},
               "created_utc": previous.get("created_utc", datetime.now(timezone.utc).isoformat())}
    write(args.folder / "review-delivery.json", receipt)
    state.update(state=receipt["state"], active_review_field="run_review", run_review=receipt,
                 next_action="Open PC Explorer with run Responsive clean selected, then stop for explicit run feedback.")
    write(state_path, state)
    tools = {}
    with zipfile.ZipFile(args.folder / "review-tooling-and-docs.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for directory, pattern in (("tools", "*run*"), ("test_project/tools", "*.gd"), ("docs", "*run*")):
            for path in (args.repo / directory).glob(pattern):
                if path.is_file():
                    relative = path.relative_to(args.repo).as_posix()
                    archive.write(path, relative)
                    tools[relative] = digest(path)
        for name in ("AGENTS.md", "FIX_ROADMAP.md", "docs/character-quality-review.json",
                     "tools/compose_character_quality.py", "test_project/tests/test_animation_motion.gd",
                     "test_project/tests/tier1_proportions.gd"):
            path = args.repo / name
            archive.write(path, name)
            tools[name] = digest(path)
    write(args.folder / "tooling-sha256.json", tools)
    print(f"Archived {len(scene_files)-2} scenes, ten verified videos; waiting for human run feedback", flush=True)


if __name__ == "__main__":
    main()
