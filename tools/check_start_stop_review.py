"""Measure all 80 public transitions against independent saved approved references."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from review_receipts import write_json

STYLES = ("responsive", "grounded", "relaxed", "heavy", "sneaky")
RIGS = ("dummy", "xbot", "short", "zup_tall")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value: dict) -> None:
    write_json(path, value)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--walk-reference", type=Path, required=True)
    p.add_argument("--idle-reference", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--godot", type=Path, required=True)
    args = p.parse_args()
    attempt = args.folder / ("native-" + uuid4().hex)
    attempt.mkdir()
    repo = Path(__file__).resolve().parents[1]
    expected = {(rig, fps, mode) for rig in RIGS for fps in (30, 60, 120) for mode in ("player", "tree")}
    summary = {"state": "running", "passed": False, "rows": [], "native_runs": 0,
               "failures": [], "checker_sha256": {relative: hashlib.sha256((repo / relative).read_bytes()).hexdigest()
                    for relative in ("tools/check_start_stop_review.py", "test_project/tools/check_start_stop_quality.gd",
                                     "test_project/tools/character_quality_native.gd")}}
    write(attempt / "matrix.json", summary)
    sources = set()
    try:
        for operation in ("walk_start", "walk_stop"):
            for style in STYLES:
                for root_mode in ("extracted", "in_place"):
                    label = style if root_mode == "extracted" else style + "-in-place"
                    folder = args.folder / operation / label
                    route_path = folder / "route.json"
                    pair_path = args.folder / operation / style / "route.json"
                    walk_path = args.walk_reference / label / "route.json"
                    idle_path = args.idle_reference / label / "route.json"
                    route = read(route_path)
                    references = [read(path) for path in (pair_path, walk_path, idle_path)]
                    if not (route["passed"] and route["operation"] == operation and route["profile"] == style
                            and route["root_mode"] == root_mode and route["invocation_kind"] == "ordinary call"
                            and tuple(row["id"] for row in route["cases"]) == RIGS
                            and all(row.get("history", {}).get("passed") == 1 for row in route["cases"])
                            and references[1]["operation"] == "walk_cycle" and references[2]["operation"] == "idle_cycle"):
                        raise ValueError("Incomplete public transition/reference route: " + str(folder))
                    for manifest in (route, *references):
                        if not manifest["passed"]:
                            raise ValueError("Failed reference route")
                        for row in manifest["cases"]:
                            path = args.project_root / row["scene"].removeprefix("res://")
                            if hashlib.sha256(path.read_bytes()).hexdigest() != row["scene_sha256"]:
                                raise ValueError("Saved scene changed: " + str(path))
                    sources.add(route["source_head"])
                    name = operation + "-" + label
                    output = attempt / (name + ".json")
                    command = [str(args.godot), "--headless", "--path", str(args.project_root), "--script",
                               "res://tools/check_start_stop_quality.gd", "--", str(route_path), str(pair_path),
                               str(walk_path), str(idle_path), str(output)]
                    with (attempt / (name + ".log")).open("w", encoding="utf-8") as log:
                        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120)
                    native = read(output)
                    coverage = {(row["id"], row["fps"], row["mixer"]) for row in native["runs"]}
                    complete = coverage == expected and len(native["runs"]) == len(expected)
                    row = {"operation": operation, "style": style, "root_mode": root_mode,
                           "report": str(output), "exit_code": result.returncode, "complete": complete,
                           "native_runs": len(native["runs"]), "failures": native["failures"],
                           "engine_errors": native["engine_errors"], "passed": native["passed"] and complete and result.returncode == 0,
                           "input_sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                            for path in (route_path, pair_path, walk_path, idle_path)}}
                    summary["rows"].append(row)
                    summary["native_runs"] += len(native["runs"])
                    if not row["passed"]: summary["failures"].append(name)
                    write(attempt / "matrix.json", summary)
                    print(f"Measured {name}: {len(native['runs'])} runs, pass={row['passed']}, engine errors={len(row['engine_errors'])}", flush=True)
        summary.update(state="complete", source_head=next(iter(sources)) if len(sources) == 1 else None,
                       passed=not summary["failures"] and len(sources) == 1 and summary["native_runs"] == 480)
    except Exception as error:
        summary.update(state="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        write(attempt / "matrix.json", summary)
    print(f"START_STOP_MATRIX_RESULT={summary['native_runs']} runs; passed={summary['passed']}; report={attempt / 'matrix.json'}")
    raise SystemExit(0 if summary["passed"] else 1)


if __name__ == "__main__":
    main()
