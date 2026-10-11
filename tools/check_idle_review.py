"""Measure saved public idle clips; preserve failures and exact checker provenance."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

STYLES = ("responsive", "grounded", "relaxed", "heavy", "sneaky")
RIGS = ("dummy", "xbot", "short", "zup_tall")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value: dict) -> None:
    path.write_bytes((json.dumps(value, indent=2) + "\n").encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--phase", choices=("baseline", "candidate"), default="baseline")
    args = parser.parse_args()
    baseline = args.phase == "baseline"
    final_matrix = args.folder / "native-matrix.json"
    if not baseline and final_matrix.exists():
        raise FileExistsError("Preserve the completed candidate matrix before a new attempt")
    attempt = args.folder / ("native-" + uuid.uuid4().hex)
    attempt.mkdir()
    summary = {"passed": False, "phase": args.phase, "attempt": str(attempt), "rows": [],
               "native_runs": 0, "state": "running", "failures": [], "checker_sha256": {}}
    repo = Path(__file__).resolve().parents[1]
    for relative in ("test_project/tools/check_idle_quality.gd",
                     "test_project/tools/character_quality_native.gd", "tools/check_idle_review.py"):
        summary["checker_sha256"][relative] = hashlib.sha256((repo / relative).read_bytes()).hexdigest()
    path = attempt / "matrix.json"
    write(path, summary)
    modes = ("player",) if baseline else ("player", "tree")
    expected = {(rig, fps, mixer) for rig in RIGS for fps in (30, 60, 120) for mixer in modes}
    heads = set()
    try:
        for style in STYLES:
            for root_mode in (("in_place",) if baseline else ("in_place", "extracted")):
                folder = args.folder / (style + "-in-place" if root_mode == "in_place" else style)
                route_path = folder / "route.json"
                route = read(route_path)
                if (not route["passed"] or route.get("operation") != "idle_cycle"
                        or tuple(row["id"] for row in route["cases"]) != RIGS
                        or route["root_mode"] != root_mode or route["profile"] != style
                        or route["invocation_kind"] != "ordinary call"
                        or any(row["params"]["root_motion"] != (root_mode == "extracted") for row in route["cases"])
                        or (not baseline and any(row.get("history", {}).get("passed") != 1 for row in route["cases"]))):
                    raise ValueError("Incomplete ordinary public idle route: " + str(folder))
                heads.add(route["source_head"])
                name = f"{style}-{root_mode}"
                output = attempt / (name + ".json")
                command = [str(args.godot), "--headless", "--path", str(args.project_root),
                           "--script", "res://tools/check_idle_quality.gd", "--", str(route_path),
                           str(output), args.phase]
                with (attempt / (name + ".log")).open("w", encoding="utf-8") as log:
                    process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90)
                native = read(output)
                covered = {(row["id"], row["fps"], row["mixer"]) for row in native["runs"]}
                complete = covered == expected and len(native["runs"]) == len(expected)
                row = {"style": style, "root_mode": root_mode, "report": str(output),
                       "route_sha256": hashlib.sha256(route_path.read_bytes()).hexdigest(),
                       "exit_code": process.returncode, "native_runs": len(native["runs"]),
                       "complete": complete, "passed": bool(native["passed"] and complete and process.returncode == 0),
                       "failures": native["failures"], "engine_errors": native["engine_errors"],
                       "generation_clamp_metadata_known": all(r["generation_clamp_metadata_known"] for r in native["runs"])}
                summary["rows"].append(row)
                summary["native_runs"] += len(native["runs"])
                if not row["passed"]: summary["failures"].append(name)
                write(path, summary)
                print(f"Measured {name}: {len(native['runs'])} runs, passed={row['passed']}, clamp metadata known={row['generation_clamp_metadata_known']}", flush=True)
        total = 60 if baseline else 240
        summary.update(state="complete", source_head=next(iter(heads)) if len(heads) == 1 else None,
                       passed=not summary["failures"] and len(heads) == 1 and summary["native_runs"] == total)
    except Exception as error:
        summary.update(state="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        write(path, summary)
    print(f"IDLE_MATRIX_RESULT={summary['native_runs']} runs; passed={summary['passed']}; report={path}", flush=True)
    if summary["passed"] and not baseline:
        # Promote only a fully successful, exact-coverage attempt. Failed
        # attempts remain immutable and never become a recorder input.
        for row in summary["rows"]:
            folder = args.folder / (row["style"] + "-in-place" if row["root_mode"] == "in_place" else row["style"])
            destination = folder / "native-check.json"
            if destination.exists():
                raise FileExistsError("Preserve prior native report: " + str(destination))
            destination.write_bytes(Path(row["report"]).read_bytes())
        write(final_matrix, summary)
    raise SystemExit(0 if summary["passed"] else 1)


if __name__ == "__main__":
    main()
