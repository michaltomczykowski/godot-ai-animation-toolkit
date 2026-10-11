"""Compare fresh public walk/run output with approved saved engine playback.

This gate preserves every reference/candidate scene and requires exactly zero
measured bone/root differences at 30, 60 and 120 FPS, across all five styles.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import zipfile
from archive_run_review import STYLES, RIGS, digest, read, require, write


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--walk-reference", type=Path, required=True)
    parser.add_argument("--run-reference", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    require(not (args.folder / "parity-summary.json").exists(), "Preserve prior parity result; use a new attempt")
    rows, sources, scenes = [], set(), {}
    checker = args.project_root / "tools/check_protected_gait_parity.gd"
    for motion in ("walk", "run"):
        reference_root = getattr(args, motion + "_reference")
        for style in STYLES:
            reference_path = reference_root / style / "route.json"
            candidate_path = args.folder / motion / style / "route.json"
            reference, candidate = read(reference_path), read(candidate_path)
            require(reference["passed"] and candidate["passed"] and candidate["phase"] == "baseline"
                    and candidate["invocation_kind"] == "ordinary call" and candidate["operation"] == motion + "_cycle"
                    and tuple(r["id"] for r in candidate["cases"]) == RIGS, "Missing protected public gait")
            sources.add(candidate["source_head"])
            for route in (reference, candidate):
                for row in route["cases"]:
                    path = args.project_root / row["scene"].removeprefix("res://")
                    require(path.is_file() and digest(path) == row["scene_sha256"], "Changed approved/candidate saved scene")
                    scenes[row["scene"]] = {"path": path, "sha256": row["scene_sha256"]}
            report_path = candidate_path.parent / "protected-parity.json"
            command = [str(args.godot), "--headless", "--path", str(args.project_root), "--script",
                       "res://tools/check_protected_gait_parity.gd", "--", str(reference_path), str(candidate_path), str(report_path)]
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
            (candidate_path.parent / "protected-parity.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            report = read(report_path)
            exact = (result.returncode == 0 and report["passed"] and not report["engine_errors"]
                     and len(report["rows"]) == 12
                     and {(r["rig"], r["fps"]) for r in report["rows"]} == {(rig, fps) for rig in RIGS for fps in (30, 60, 120)}
                     and all(r["passed"] and r["max_position_error"] == r["max_rotation_error"] == r["max_root_error"] == 0
                             for r in report["rows"]))
            rows.append({"motion": motion, "style": style, "reference_source": reference["source_head"],
                         "candidate_source": candidate["source_head"], "report": str(report_path),
                         "report_sha256": digest(report_path), "native_runs": len(report["rows"]), "exact": exact})
            write(args.folder / "parity-progress.json", {"rows": rows, "passed": all(r["exact"] for r in rows)})
            print(f"PROTECTED_{motion.upper()}_{style.upper()}={'EXACT' if exact else 'FAIL'}", flush=True)
    require(len(sources) == 1, "Mixed candidate sources")
    with zipfile.ZipFile(args.folder / "protected-scenes.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for scene, item in scenes.items():
            archive.write(item["path"], "project/" + scene.removeprefix("res://"))
    summary = {"source_head": sources.pop(), "rows": rows, "native_runs": sum(r["native_runs"] for r in rows),
               "passed": len(rows) == 10 and all(r["exact"] for r in rows), "scene_count": len(scenes),
               "scene_zip_sha256": digest(args.folder / "protected-scenes.zip"),
               "checker_sha256": digest(checker), "wrapper_sha256": digest(Path(__file__)),
               "playback_helper_sha256": digest(args.project_root / "tools/check_walk_default_parity.gd"),
               "native_loader_sha256": digest(args.project_root / "tools/character_quality_native.gd")}
    write(args.folder / "parity-summary.json", summary)
    require(summary["passed"] and summary["native_runs"] == 120, "Protected gait output changed; renewed review required")
    print("IDLE_PROTECTED_GAITS_PASS=120 exact played comparisons")


if __name__ == "__main__":
    main()
