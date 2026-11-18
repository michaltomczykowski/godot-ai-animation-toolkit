"""Verify that the saved in-place contact audit detects wrong caller travel."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("route_root", type=Path)
    p.add_argument("--walk-reference", type=Path, required=True)
    p.add_argument("--idle-reference", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    p.add_argument("--godot", type=Path, required=True)
    a = p.parse_args()
    attempt = a.route_root / ("actor-controls-" + uuid4().hex)
    attempt.mkdir()
    results = []
    for operation in ("walk_start", "walk_stop"):
        route_path = a.route_root / operation / "responsive-in-place/route.json"
        original = read(route_path)
        assert original["passed"] and len(original["cases"]) == 4
        negative = copy.deepcopy(original)
        negative["control"] = "double the reported external actor travel; preserve every saved pose/scene"
        for row in negative["cases"]:
            scene = a.project_root / row["scene"].removeprefix("res://")
            assert hashlib.sha256(scene.read_bytes()).hexdigest() == row["scene_sha256"]
            assert row["params"]["root_motion"] is False
            assert row["write"]["declared_contacts"]
            for key in row["write"]["actor_translation_keys"]:
                key["offset"] = [2.0 * value for value in key["offset"]]
        control_path = attempt / (operation + "-double-travel-input.json")
        control_path.write_text(json.dumps(negative, indent=2) + "\n", encoding="utf-8")
        output = attempt / (operation + "-double-travel.json")
        command = [str(a.godot), "--headless", "--path", str(a.project_root), "--script",
                   "res://tools/check_start_stop_quality.gd", "--", str(control_path),
                   str(a.route_root / operation / "responsive/route.json"),
                   str(a.walk_reference / "responsive-in-place/route.json"),
                   str(a.idle_reference / "responsive-in-place/route.json"), str(output)]
        run = subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace", timeout=120)
        output.with_suffix(".log").write_text(run.stdout + run.stderr, encoding="utf-8")
        report = read(output)
        coverage = {(r["id"], r["fps"], r["mixer"]) for r in report["runs"]}
        expected = {(rig, fps, mode) for rig in ("dummy", "xbot", "short", "zup_tall")
                    for fps in (30, 60, 120) for mode in ("player", "tree")}
        assert coverage == expected and len(report["runs"]) == 24
        assert run.returncode == 1 and not report["passed"] and not report["engine_errors"]
        for r in report["runs"]:
            limit = min(0.02 * r["leg_length_m"], 0.03)
            assert any(f["max_declared_contact_slide_m"] > limit for f in r["feet"].values())
            assert any("declared support failure" in reason for reason in r["failures"])
        results.append({"operation": operation, "controls": 24, "detected": 24,
                        "input_sha256": hashlib.sha256(control_path.read_bytes()).hexdigest(),
                        "report_sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
        print(json.dumps(results[-1]), flush=True)
    (attempt / "summary.json").write_text(json.dumps({"passed": True, "detected": 48,
        "engine_errors": 0, "rows": results, "visual_approval": False}, indent=2) + "\n", encoding="utf-8")
    print("ACTOR_CONTROLS_COMPLETED=" + str(attempt), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
