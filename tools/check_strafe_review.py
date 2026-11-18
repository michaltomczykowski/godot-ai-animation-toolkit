"""Validate each preserved public strafe scene with independent engine playback."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from review_receipts import write_json


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--godot", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--styles", nargs="+", default=["responsive", "grounded", "relaxed", "heavy", "sneaky"])
    p.add_argument("--directions", nargs="+", default=["left", "right"])
    a = p.parse_args()
    receipt = {"passed": False, "rows": [], "failures": [], "clips": 0, "native_runs": 0}
    heads = set()
    checker = Path(__file__).resolve().parents[1] / "test_project/tools/check_strafe_quality.gd"
    checker_hash = hashlib.sha256(checker.read_bytes()).hexdigest()
    helper_hash = hashlib.sha256((checker.parent / "character_quality_native.gd").read_bytes()).hexdigest()
    expected = {(r, fps, mixer) for r in ("dummy", "xbot", "short", "zup_tall") for fps in (30, 60, 120) for mixer in ("player", "tree")}
    for direction in a.directions:
        for style in a.styles:
            for mode in ("extracted", "in_place"):
                folder = a.folder / direction / (style if mode == "extracted" else style + "-in-place")
                route_path = folder / "route.json"
                route = json.loads(route_path.read_text(encoding="utf-8-sig"))
                if not route.get("passed") or route["operation"] != "strafe_cycle" or route["root_mode"] != mode or route["profile"] != style:
                    raise ValueError(f"Invalid public route {route_path}")
                for row in route["cases"]:
                    if row["params"]["direction"] != direction or row.get("history", {}).get("passed") != 1:
                        raise ValueError("Missing direction/history coverage")
                    scene = a.project_root / row["scene"].removeprefix("res://")
                    if hashlib.sha256(scene.read_bytes()).hexdigest() != row["scene_sha256"]:
                        raise ValueError("Saved scene differs from public receipt")
                heads.add(route["source_head"])
                route_hash = hashlib.sha256(route_path.read_bytes()).hexdigest()
                output = folder / "native-check.json"
                if output.exists():
                    cached = json.loads(output.read_text(encoding="utf-8-sig"))
                    if (cached.get("route_sha256") != route_hash or cached.get("checker_sha256") != checker_hash
                            or cached.get("native_helper_sha256") != helper_hash):
                        # Preserve historical checks. A changed checker/route gets
                        # a distinct immutable output, never a relabeled pass.
                        identity = hashlib.sha256((route_hash + checker_hash + helper_hash).encode()).hexdigest()[:16]
                        output = folder / f"native-check-{identity}.json"
                command = [str(a.godot), "--headless", "--path", str(a.project_root), "--script", "res://tools/check_strafe_quality.gd", "--", str(route_path), str(output)]
                # Baseline reports are immutable once checked; verify and reuse them.
                if not output.exists():
                    with output.with_suffix(".log").open("w", encoding="utf-8") as stream:
                        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
                    output.with_suffix(".exit").write_text(str(result.returncode), encoding="utf-8")
                native = json.loads(output.read_text(encoding="utf-8-sig"))
                passed = (native.get("passed") is True and native["source_head"] == route["source_head"] and not native["engine_errors"]
                          and len(native["runs"]) == 24 and native.get("route_sha256") == route_hash
                          and native.get("checker_sha256") == checker_hash and native.get("native_helper_sha256") == helper_hash
                          and {(r["id"], r["fps"], r["mixer"]) for r in native["runs"]} == expected)
                receipt["rows"].append({"direction": direction, "style": style, "root_mode": mode, "route": str(route_path),
                    "route_sha256": hashlib.sha256(route_path.read_bytes()).hexdigest(), "native": str(output),
                    "native_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "passed": passed})
                receipt["clips"] += len(route["cases"])
                receipt["native_runs"] += len(native["runs"])
                if not passed: receipt["failures"].extend(native.get("failures", [f"Incomplete {folder}"]))
                write_json(a.folder / "native-matrix.json", receipt)
                print(f"{direction}/{style}/{mode}: {'PASS' if passed else 'FAIL'}", flush=True)
    if len(heads) != 1: raise ValueError("Mixed public generation sources")
    receipt.update(passed=not receipt["failures"], source_head=heads.pop(), checker_sha256=hashlib.sha256(checker.read_bytes()).hexdigest())
    write_json(a.folder / "native-matrix.json", receipt)
    return int(not receipt["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
