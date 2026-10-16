"""Replay immutable saved production setups with dynamic inputs and owned-helper corruptions.

No generation, editor calls, scene writes or replacement modifiers. Run serially
only after the root operator grants the native process slot.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

FPS = (30, 60, 120)
NEGATIVE = ("disabled", "missing", "wrong_path", "wrong_order", "partial_influence", "saved_same_rig_tree", "saved_same_rig_autoplay", "internal_nonempty_simulator")

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def data(value):
    for _ in range(4):
        if "clips" in value:
            return value
        for key in ("data", "result", "response"):
            if isinstance(value.get(key), dict):
                value = value[key]
                break
        else:
            break
    return value

def base_specs(row):
    meta = data(row.get("write", {}))
    if "clips" not in meta:
        meta = data(row.get("setup_response", {}))
    if row.get("quality_specs"):
        return copy.deepcopy(row["quality_specs"])
    walk, run = (float(meta["speed_values"][key]) for key in ("walk", "run"))
    rooted = bool(meta["root_motion"])
    specs = [dict(kind="blend", speed_mps=speed, duration_s=6.0,
                  controller_speed_mps=0.0 if rooted else speed)
             for speed in (walk/2, walk, (walk+run)/2, run)]
    if "jump" in meta.get("clips", {}):
        specs.append(dict(kind="jump", speed_mps=0.0, controller_speed_mps=0.0))
    return specs

def dynamic_specs(row):
    meta = data(row.get("write", {}))
    if "clips" not in meta:
        meta = data(row.get("setup_response", {}))
    walk, run = (float(meta["speed_values"][key]) for key in ("walk", "run"))
    rooted = bool(meta["root_motion"])
    specs = []
    for lo, hi in ((0.0, walk), (walk, run)):
        for weight in (.25, .5, .75):
            speed = lo + (hi-lo)*weight
            specs.append(dict(kind="blend", speed_mps=speed, duration_s=6.0,
                              controller_speed_mps=0.0 if rooted else speed))
    for lo, hi in ((0.0, run), (run, 0.0)):
        specs.append(dict(kind="blend", speed_mps=lo, speed_end_mps=hi, duration_s=6.0,
                          controller_speed_mps=0.0 if rooted else lo,
                          controller_speed_end_mps=0.0 if rooted else hi))
    specs.append(dict(kind="blend", speed_mps=(walk+run)/2, duration_s=6.0,
                      controller_speed_mps=0.0 if rooted else (walk+run)/2,
                      reset_at_s=3.0))
    return specs

def identity(runs):
    return {(row.get("id"), row.get("fps"), json.dumps(row.get("spec"), sort_keys=True)) for row in runs}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("route", "project-root", "godot", "output"):
        parser.add_argument("--"+key, type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Preserve previous controls and failed attempts")
    route = json.loads(args.route.read_text(encoding="utf-8-sig"))
    if not route.get("cases") or len({r["id"] for r in route["cases"]}) != len(route["cases"]):
        raise ValueError("Require distinct immutable public setup rows")
    scenes = {args.project_root / row["scene"].removeprefix("res://"): row["scene_sha256"] for row in route["cases"]}
    if any(digest(path) != expected for path, expected in scenes.items()):
        raise ValueError("Original saved scene hash changed")
    args.output.mkdir(parents=True)
    root = Path(__file__).resolve().parents[1]
    checker = root / "test_project/tools/check_setup_grounding_controls.gd"
    summary = dict(passed=False, route_sha256=digest(args.route),
                   checker_sha256=digest(checker), runtime_sha256=digest(root / "addons/godot_ai_animation/runtime/setup_grounding.gd"), rows=[])
    for control in ("positive", "dynamic", "recover_residual", "saved_unrelated_rig_tree", *NEGATIVE):
        manifest = copy.deepcopy(route)
        for row in manifest["cases"]:
            row["grounding_control"] = "positive" if control == "dynamic" else control
            row["quality_specs"] = dynamic_specs(row) if control == "dynamic" else base_specs(row)
        manifest_path = args.output / (control+"-manifest.json")
        manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        output = args.output / (control+".json")
        command = [str(args.godot), "--headless", "--path", str(args.project_root), "--script", str(checker), "--", str(manifest_path), str(output)]
        with output.with_suffix(".log").open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=300)
        report = json.loads(output.read_text(encoding="utf-8-sig")) if output.exists() else {}
        runs = report.get("runs", [])
        expected = {(row["id"], fps, json.dumps(spec, sort_keys=True))
                    for row in manifest["cases"] for spec in row["quality_specs"] for fps in FPS}
        complete = len(runs)==len(expected) and identity(runs)==expected and not report.get("engine_errors")
        if control in NEGATIVE:
            valid = complete and result.returncode==1 and report.get("passed") is False and all(not row.get("passed") and any("ground" in str(error).lower() or "modification_processed" in str(error) or "Saved competing mixer" in str(error) or "Foreign active modifier" in str(error) for error in row.get("failures", [])) for row in runs)
        else:
            valid = complete and result.returncode==0 and report.get("passed") is True and all(row.get("passed") for row in runs)
        if control == "recover_residual":
            valid = valid and all(float(row.get("grounding", {}).get("max_residual_m", 0))>=1.0 and float(row.get("grounding", {}).get("evaluation_residual_m", 1))<=float(row.get("grounding", {}).get("target_tolerance_m", 0)) for row in runs)
        summary["rows"].append(dict(control=control, passed=valid, runs=len(runs), exit_code=result.returncode,
                                    manifest_sha256=digest(manifest_path), report_sha256=digest(output) if output.exists() else None))
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps(summary["rows"][-1]), flush=True)
    summary["scenes_unchanged"] = all(digest(path)==expected for path, expected in scenes.items())
    summary["passed"] = summary["scenes_unchanged"] and all(row["passed"] for row in summary["rows"])
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return int(not summary["passed"])

if __name__ == "__main__":
    raise SystemExit(main())
