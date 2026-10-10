"""Require the complete native run matrix and explicit-prototype playback parity."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess

STYLES = ("responsive", "grounded", "relaxed", "heavy", "sneaky")
RIGS = ("dummy", "xbot", "short", "zup_tall")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--prototype", type=Path, required=True)
    p.add_argument("--godot", type=Path, required=True)
    p.add_argument("--project-root", type=Path, required=True)
    args = p.parse_args()
    summary = {"passed": False, "rows": [], "native_runs": 0, "parity_runs": 0}
    path = args.folder / "native-matrix.json"
    expected = {(rig, fps, mixer) for rig in RIGS for fps in (30, 60, 120)
                for mixer in ("player", "tree")}
    heads = set()
    for style in STYLES:
        for mode in ("extracted", "in_place"):
            folder = args.folder / (style if mode == "extracted" else style + "-in-place")
            route = read(folder / "route.json")
            if (not route["passed"] or tuple(x["id"] for x in route["cases"]) != RIGS
                    or route["root_mode"] != mode or route["profile"] != style
                    or route["invocation_kind"] != "ordinary call"
                    or any(not x.get("history", {}).get("passed") == 1 for x in route["cases"])):
                raise ValueError("Incomplete ordinary public history route: " + str(folder))
            heads.add(route["source_head"])
            command = [str(args.godot), "--headless", "--path", str(args.project_root),
                       "--script", "res://tools/check_run_quality.gd", "--",
                       str(folder / "route.json"), str(folder / "native-check.json")]
            with (folder / "native-check.log").open("w", encoding="utf-8") as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
            native = read(folder / "native-check.json")
            if (not native["passed"] or native["source_head"] != route["source_head"]
                    or len(native["runs"]) != 24
                    or {(x["id"], x["fps"], x["mixer"]) for x in native["runs"]} != expected):
                raise ValueError("Incomplete native matrix: " + str(folder))
            row = {"style": style, "root_mode": mode, "native_runs": 24, "passed": True}
            summary["rows"].append(row)
            summary["native_runs"] += 24
            if mode == "extracted":
                command = [str(args.godot), "--headless", "--path", str(args.project_root),
                           "--script", "res://tools/check_run_profile_parity.gd", "--",
                           str(args.prototype / style / "route.json"), str(folder / "route.json"),
                           str(folder / "prototype-parity.json")]
                with (folder / "prototype-parity.log").open("w", encoding="utf-8") as log:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
                parity = read(folder / "prototype-parity.json")
                if not parity["passed"] or len(parity["rows"]) != 12:
                    raise ValueError("Ordinary run differs from measured prototype: " + style)
                row["prototype_parity_runs"] = 12
                summary["parity_runs"] += 12
            path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
            print(f"Verified {style}/{mode}: 24 native runs", flush=True)
    if len(heads) != 1 or summary["native_runs"] != 240 or summary["parity_runs"] != 60:
        raise ValueError("Mixed source or incomplete run coverage")
    summary.update(passed=True, source_head=heads.pop())
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("RUN_MATRIX_PASS=240 native + 60 prototype comparisons", flush=True)


if __name__ == "__main__":
    main()
