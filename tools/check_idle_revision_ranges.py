"""Require increased played head/torso/pelvis motion versus a saved idle review."""
from __future__ import annotations
import argparse
from pathlib import Path
import subprocess
from archive_run_review import STYLES, RIGS, read, write, digest, require


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--previous", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    summary_path = args.folder / "revision-native-ranges.json"
    require(not summary_path.exists(), "Preserve the completed range comparison")
    rows, sources = [], set()
    for style in STYLES:
        reference = args.previous / (style + "-in-place") / "route.json"
        candidate = args.folder / (style + "-in-place") / "route.json"
        for path in (reference, candidate):
            route = read(path)
            require(route["passed"] and route["phase"] == "candidate" and route["operation"] == "idle_cycle"
                    and tuple(r["id"] for r in route["cases"]) == RIGS, "Missing saved ordinary idle")
            for case in route["cases"]:
                require(digest(args.project_root / case["scene"].removeprefix("res://")) == case["scene_sha256"],
                        "Saved idle changed")
        output = args.folder / (style + "-in-place") / "revision-ranges.json"
        result = subprocess.run([str(args.godot), "--headless", "--path", str(args.project_root),
                                 "--script", "res://tools/check_idle_revision_ranges.gd", "--",
                                 str(reference), str(candidate), str(output)], capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=90)
        output.with_suffix(".log").write_text(result.stdout + result.stderr, encoding="utf-8")
        report = read(output)
        require(result.returncode == 0 and report["passed"] and not report["engine_errors"]
                and len(report["rows"]) == 12
                and {(r["id"], r["fps"]) for r in report["rows"]} == {(rig, fps) for rig in RIGS for fps in (30, 60, 120)},
                "Played idle motion did not increase: " + style)
        sources.add(report["source_head"])
        rows.append({"style": style, "report": str(output), "sha256": digest(output),
                     "previous_route_sha256": digest(reference), "candidate_route_sha256": digest(candidate),
                     "native_runs": 12, "passed": True})
        print(f"IDLE_{style.upper()}_RANGES_PASS=12", flush=True)
    require(len(sources) == 1, "Mixed candidate sources")
    write(summary_path, {"passed": True, "source_head": sources.pop(), "native_runs": 60, "rows": rows,
                        "checker_sha256": digest(args.project_root / "tools/check_idle_revision_ranges.gd"),
                        "wrapper_sha256": digest(Path(__file__))})


if __name__ == "__main__":
    main()
