"""Play preserved public jump scenes through Player/Tree at 30/60/120 FPS."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from review_receipts import write_json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    for field in ("godot", "project-root"):
        p.add_argument("--" + field, type=Path, required=True)
    p.add_argument("--styles", nargs="+", default=["responsive", "grounded", "relaxed", "heavy", "sneaky"])
    p.add_argument("--variants", nargs="+", choices=["stationary", "forward"], default=["stationary", "forward"])
    a = p.parse_args()
    tools = a.project_root / "tools"
    hashes = {"checker_sha256": digest(tools / "check_jump_quality.gd"),
              "native_helper_sha256": digest(tools / "character_quality_native.gd"),
              "base_checker_sha256": digest(tools / "check_run_quality.gd")}
    expected = {(rig, fps, mixer) for rig in ["dummy", "xbot", "short", "zup_tall"]
                for fps in [30, 60, 120] for mixer in ["player", "tree"]}
    summary = {"passed": False, "rows": [], "clips": 0, "native_runs": 0, "failures": []}
    sources = set()
    identity = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()[:16]
    matrix = a.folder / ("native-matrix-" + identity + ".json")
    if matrix.exists():
        raise FileExistsError("Preserve previous matrix; native reports can be reused with a new matrix folder")
    for variant in a.variants:
        for style in a.styles:
            for mode in ["extracted", "in_place"]:
                folder = a.folder / variant / (style if mode == "extracted" else style + "-in-place")
                route_path = folder / "route.json"
                route = json.loads(route_path.read_text(encoding="utf-8-sig"))
                if not route.get("passed") or route["operation"] != "jump" or route["root_mode"] != mode or route["profile"] != style:
                    raise ValueError("Invalid public jump route: " + str(route_path))
                if len(route["cases"]) != 4 or {r["id"] for r in route["cases"]} != {r[0] for r in expected}:
                    raise ValueError("Incomplete rig matrix")
                for row in route["cases"]:
                    if row.get("history", {}).get("passed") != 1 or digest(a.project_root / row["scene"].removeprefix("res://")) != row["scene_sha256"]:
                        raise ValueError("History/scene identity mismatch")
                    distance = float(row["params"].get("distance", 0))
                    if (variant == "stationary") != (abs(distance) < 1e-8):
                        raise ValueError("Jump variant mismatch")
                sources.add(route["source_head"])
                identities = {**hashes, "route_sha256": digest(route_path)}
                case_identity = hashlib.sha256(json.dumps(identities, sort_keys=True).encode()).hexdigest()[:16]
                output = folder / ("native-check-" + case_identity + ".json")
                if not output.exists():
                    with output.with_suffix(".log").open("w", encoding="utf-8") as stream:
                        result = subprocess.run([str(a.godot), "--headless", "--path", str(a.project_root), "--script",
                                                 "res://tools/check_jump_quality.gd", "--", str(route_path), str(output)],
                                                stdout=stream, stderr=subprocess.STDOUT, timeout=120)
                    output.with_suffix(".exit").write_text(str(result.returncode), encoding="utf-8")
                native = json.loads(output.read_text(encoding="utf-8-sig"))
                passed = (native.get("passed") is True and not native["engine_errors"] and native["source_head"] == route["source_head"]
                          and all(native.get(k) == v for k, v in identities.items()) and len(native["runs"]) == 24
                          and {(r["id"], r["fps"], r["mixer"]) for r in native["runs"]} == expected)
                summary["rows"].append({"variant": variant, "style": style, "root_mode": mode, "passed": passed,
                                        "route": str(route_path), "route_sha256": identities["route_sha256"],
                                        "native": str(output), "native_sha256": digest(output)})
                summary["clips"] += 4
                summary["native_runs"] += len(native["runs"])
                if not passed:
                    summary["failures"].extend(native.get("failures") or [str(folder) + ": incomplete native proof"])
                write_json(matrix, summary)
                print(f"{variant}/{style}/{mode}: {'PASS' if passed else 'FAIL'}", flush=True)
    if len(sources) != 1:
        raise ValueError("Mixed generation sources")
    summary.update(passed=not summary["failures"], source_head=sources.pop(), **hashes)
    write_json(matrix, summary)
    return int(not summary["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
