"""Capture independent public timing cases, then play the saved four-rig clips."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from uuid import uuid4

GROUPS = ((.35, .137, 1.0, 60), (1.4, .137, 1.0, 60),
          (.35, .537, 1.0, 60), (1.4, .537, 1.0, 60),
          (.9, .137, .7, 40), (.9, .537, .7, 40))


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("core-root", "project-root", "output", "walk-reference", "idle-reference", "godot"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--ws-port", type=int, default=9500)
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=False)
    repo = Path(__file__).resolve().parents[1]
    recipe = a.output / "empty-explicit-recipe.json"
    recipe.write_text('{"responsive": {}}\n', encoding="utf-8")
    receipt = a.output / "timing-matrix.json"
    report = {"passed": False, "state": "running", "groups": [], "public_clips": 0, "native_runs": 0}
    report.update(public_requests=0, typed_nonmutating_refusals=0)
    def save(): receipt.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    def capture(folder, operation, options):
        command = [sys.executable, str(repo / "tools/mcp_run_quality_review.py"),
            "--repo", str(repo), "--core-root", str(a.core_root), "--project-root", str(a.project_root),
            "--port", str(a.port), "--ws-port", str(a.ws_port), "--phase", "prototype", "--recipes", str(recipe),
            "--styles", "responsive", "--root-modes", "extracted", "in_place", "--operation", operation,
            "--revision", "timing-" + folder.name, "--output", str(folder), *options]
        with (a.output / (folder.name + "-capture.log")).open("w", encoding="utf-8") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300, check=True)
    save()
    try:
        custom = a.output / "walk-period-0.7"
        capture(custom, "walk_cycle", ["--duration", ".7", "--samples", "40"])
        for number, (duration, phase, period, samples) in enumerate(GROUPS):
            for operation in ("walk_start", "walk_stop"):
                folder = a.output / f"{number}-{operation}"
                capture(folder, operation, ["--allow-reach-refusals", "--duration", str(duration), "--gait-phase", str(phase),
                    "--gait-duration", str(period), "--gait-samples", str(samples)])
                for root_mode in ("responsive", "responsive-in-place"):
                    original_path = folder / root_mode / "route.json"
                    original = read(original_path)
                    assert original['passed'] and len(original['cases']) == 4
                    accepted = dict(original)
                    accepted['cases'] = [row for row in original['cases'] if not row.get('refused')]
                    refused = [row['id'] for row in original['cases'] if row.get('refused')]
                    accepted['expected_case_count'] = len(accepted['cases'])
                    accepted_path = folder / (root_mode + '-accepted.json')
                    accepted_path.write_text(json.dumps(accepted, indent=2) + '\n', encoding='utf-8')
                    paths = [accepted_path, folder / "responsive/route.json",
                        (custom if period == .7 else a.walk_reference) / root_mode / "route.json",
                        a.idle_reference / root_mode / "route.json"]
                    for path in paths:
                        route = read(path)
                        assert route["passed"]
                        for row in route["cases"]:
                            if row.get('refused'): continue
                            scene = a.project_root / row["scene"].removeprefix("res://")
                            assert hashlib.sha256(scene.read_bytes()).hexdigest() == row["scene_sha256"]
                    output = folder / (root_mode + "-native.json")
                    cmd = [str(a.godot), "--headless", "--path", str(a.project_root), "--script",
                        "res://tools/check_start_stop_quality.gd", "--", *map(str, paths), str(output)]
                    with output.with_suffix(".log").open("w", encoding="utf-8") as log:
                        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=120)
                    native = read(output)
                    expected = {(r['id'], f, m) for r in accepted['cases']
                        for f in (30, 60, 120) for m in ("player", "tree")}
                    complete = {(r['id'], r['fps'], r['mixer']) for r in native['runs']} == expected and len(native['runs']) == len(expected)
                    row = {"operation": operation, "duration": duration, "phase": phase,
                        "gait_period": period, "gait_samples": samples, "root_mode": root_mode,
                        "report": str(output), "passed": native['passed'] and complete and result.returncode == 0,
                        "accepted_ids": [r['id'] for r in accepted['cases']], "refused_ids": refused,
                        "failures": native['failures'], "engine_errors": native['engine_errors'],
                        "input_sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}}
                    report['groups'].append(row); report['public_requests'] += 4
                    report['public_clips'] += len(accepted['cases']); report['native_runs'] += len(expected)
                    report['typed_nonmutating_refusals'] += len(refused); save()
                    print(f"Timing {number}/{operation}/{root_mode}: pass={row['passed']}", flush=True)
        report.update(state="complete", passed=len(report['groups']) == 24 and all(r['passed'] for r in report['groups']))
    except Exception as error:
        report.update(state="failed", error=f"{type(error).__name__}: {error}")
        raise
    finally: save()
    print("TRANSITION_TIMING_RESULT=" + json.dumps({k:v for k,v in report.items() if k != 'groups'}))
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == "__main__": main()
