"""Require played jump checks to detect isolated clip corruptions."""
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
    p.add_argument("--checker", type=Path, default=Path(__file__).resolve().parents[1] / "test_project/tools/check_jump_quality.gd")
    a = p.parse_args()
    if a.output.exists():
        raise FileExistsError("Preserve previous control evidence")
    a.output.mkdir(parents=True)
    route = json.loads(a.route.read_text(encoding="utf-8-sig"))
    if any(not row["params"].get("root_motion") or float(row["write"].get("distance", 0)) <= 0 for row in route["cases"]):
        raise ValueError("Controls require extracted forward jumps")
    original = {row["scene"]: row["scene_sha256"] for row in route["cases"]}
    controls = {
        "positive": None,
        "tiny_hop": "Played apex height mismatch",
        "delayed_apex": "Played apex timing mismatch",
        "unrecovered_pose": "Final skeletal pose did not recover",
        "double_travel": "Authored travel ownership/endpoint mismatch",
        "reverse_travel": "Authored travel ownership/endpoint mismatch",
        "penetration": "l contact/slide/penetration/knee failure",
        "knee_discontinuity": "Played jump discontinuity",
    }
    identities = {(row["id"], fps, mode) for row in route["cases"]
                  for fps in (30, 60, 120) for mode in ("player", "tree")}
    if len(identities) != 24:
        raise ValueError("Require four distinct public cases")
    summary = {"passed": False, "rows": [], "route_sha256": hashlib.sha256(a.route.read_bytes()).hexdigest()}
    for control, reason in controls.items():
        output = a.output / (control + ".json")
        command = [str(a.godot), "--headless", "--path", str(a.project_root), "--script",
                   str(a.checker.resolve()), "--", str(a.route), str(output)]
        if reason:
            command.append(control)
        with output.with_suffix(".log").open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        report = json.loads(output.read_text(encoding="utf-8-sig")) if output.exists() else {}
        runs = report.get("runs", [])
        complete = (len(runs) == len(identities) and
                    {(row.get("id"), row.get("fps"), row.get("mixer")) for row in runs} == identities
                    and not report.get("engine_errors"))
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
    summary.update(scenes_unchanged=unchanged, positive_runs=sum(row["runs"] for row in summary["rows"] if row["control"] == "positive"),
                   negative_runs=sum(row["runs"] for row in summary["rows"] if row["control"] != "positive"),
                   passed=unchanged and all(row["passed"] for row in summary["rows"]))
    write_json(a.output / "summary.json", summary)
    return int(not summary["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
