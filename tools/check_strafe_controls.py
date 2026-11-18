"""Require played strafe checks to detect isolated clip corruptions."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from review_receipts import write_json


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for field in ("route", "project-root", "godot", "output"):
        p.add_argument("--" + field, type=Path, required=True)
    a = p.parse_args()
    if a.output.exists():
        raise FileExistsError("Preserve previous control evidence")
    a.output.mkdir(parents=True)
    route = json.loads(a.route.read_text(encoding="utf-8-sig"))
    rigs = {"dummy", "xbot", "short", "zup_tall"}
    if (route["root_mode"] != "extracted" or len(route["cases"]) != 4
            or {r["id"] for r in route["cases"]} != rigs
            or not all(r["params"].get("direction") == "left" and r["params"].get("root_motion") is True for r in route["cases"])):
        raise ValueError("Controls require extracted left strafe for known support timing")
    original = {row["scene"]: row["scene_sha256"] for row in route["cases"]}
    controls = {
        "positive": None,
        "missing_contacts": "Incomplete contact markers",
        "inert": "Inert skeletal playback",
        "double_travel": "Root cycle differs from reported speed/direction",
        "reverse_travel": "Root cycle differs from reported speed/direction",
        "stance_slide": "r contact/slide/penetration/knee failure",
        "missing_root_track": "Extracted position track missing",
        "pose_pop": "Played bone discontinuity",
    }
    summary = {"passed": False, "rows": [], "route_sha256": hashlib.sha256(a.route.read_bytes()).hexdigest()}
    for control, reason in controls.items():
        output = a.output / (control + ".json")
        command = [str(a.godot), "--headless", "--path", str(a.project_root), "--script",
                   "res://tools/check_strafe_quality.gd", "--", str(a.route), str(output), "full"]
        if reason:
            command.append(control)
        with output.with_suffix(".log").open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        report = json.loads(output.read_text(encoding="utf-8-sig")) if output.exists() else {}
        runs = report.get("runs", [])
        expected = {(rig, fps, mixer) for rig in rigs for fps in [30, 60, 120] for mixer in ["player", "tree"]}
        complete = (len(runs) == len(expected) and not report.get("engine_errors")
                    and {(r["id"], r["fps"], r["mixer"]) for r in runs} == expected)
        passed = (complete and result.returncode == 1 and report.get("passed") is False
                  and all(reason in row["failures"] for row in runs)) if reason else (
                  complete and result.returncode == 0 and report.get("passed") is True)
        summary["rows"].append({"control": control, "expected_failure": reason, "runs": len(runs),
                                "exit_code": result.returncode, "passed": passed,
                                "report_sha256": hashlib.sha256(output.read_bytes()).hexdigest() if output.exists() else None})
        write_json(a.output / "summary.json", summary)
        print(json.dumps(summary["rows"][-1]), flush=True)
    unchanged = all(hashlib.sha256((a.project_root / path.removeprefix("res://")).read_bytes()).hexdigest() == digest
                    for path, digest in original.items())
    summary.update(scenes_unchanged=unchanged,
                   positive_runs=sum(r["runs"] for r in summary["rows"] if r["expected_failure"] is None),
                   negative_runs=sum(r["runs"] for r in summary["rows"] if r["expected_failure"] is not None),
                   passed=unchanged and all(row["passed"] for row in summary["rows"]))
    write_json(a.output / "summary.json", summary)
    return int(not summary["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
