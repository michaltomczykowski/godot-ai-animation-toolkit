"""Inventory existing saved gait audits; deliberately never awards valid_effect."""
import argparse
import hashlib
import json
from pathlib import Path

TARGETS = {"walk_cycle", "run_cycle", "cycle"}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inventory(bundle):
    bundle = Path(bundle)
    report = json.loads((bundle / "operation-case-results.json").read_text(encoding="utf-8"))
    artifacts = {r["path"]: r["sha256"] for r in report["raw_artifacts"]}
    context = report["context_sha256"]
    events = []
    for path in sorted((bundle / "public-calls").glob("*.jsonl")):
        rel = path.relative_to(bundle).as_posix()
        if artifacts.get(rel) != sha(path):
            raise ValueError("Raw artifact hash mismatch: " + rel)
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
        for row in rows:
            if row.get("context_sha256") != context:
                raise ValueError("Trace context mismatch: " + str(row.get("id")))
            row = dict(row, _artifact=rel, _artifact_sha=artifacts[rel])
            events.append(row)
    ids = [r["id"] for r in events]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate public event ID")
    ordered = sorted(events, key=lambda r: r["time_ns"])
    rows = []
    for audit in ordered:
        if audit.get("driver") != "mcp_motion_audit_saved.py" or audit.get("operation") != "animation_inspect.motion_audit":
            continue
        request, observed = audit["request"], audit["response"]
        name = request.get("animation_name")
        if name not in TARGETS:
            continue
        earlier = [r for r in ordered if r["time_ns"] < audit["time_ns"]]
        opens = [r for r in earlier if r.get("driver") == audit["driver"] and r.get("public_tool") == "scene_open"]
        opened = opens[-1] if opens else None
        scene = opened.get("request", {}).get("path") if opened else None
        saves = [r for r in earlier if r.get("driver") == "mcp_motion_remaining_cycles.py" and r.get("public_tool") == "scene_save" and r.get("response", {}).get("path") == scene]
        save = saves[-1] if saves else None
        candidates = [r for r in earlier if save and r["time_ns"] < save["time_ns"] and r.get("driver") == "mcp_motion_remaining_cycles.py" and r.get("operation") == "animation_motion." + name and r.get("request", {}).get("animation_name") == name and not r.get("request", {}).get("dry_run") and not r.get("response", {}).get("error")]
        generated = candidates[-1] if candidates else None
        # These are candidate path joins, never persisted-byte identity claims.
        blockers = ["persisted_scene_sha_missing", "native_audit_does_not_attest_saved_bytes", "request_travel_or_independent_default_resolution_missing"]
        if not opened or not save or not generated:
            blockers.append("generation_save_open_join_missing")
        if generated and generated["request"].get("speed") is not None:
            blockers.remove("request_travel_or_independent_default_resolution_missing")
        rows.append({"audit_event": audit["id"], "raw_artifact": audit["_artifact"], "raw_sha256": audit["_artifact_sha"], "scene": scene,
                     "generation_event": generated.get("id") if generated else None, "generation_request": generated.get("request") if generated else None,
                     "save_event": save.get("id") if save else None, "open_event": opened.get("id") if opened else None,
                     "open_reloaded_from_disk": opened.get("response", {}).get("reloaded_from_disk") if opened else None,
                     "animation": name, "samples": request.get("samples"), "motion_kind": request.get("motion_kind"),
                     "observed_body_travel": observed.get("body_travel"), "observed_check_names": [c.get("check") for c in observed.get("checks", [])],
                     "valid_effect": "pending", "blockers": blockers})
    return {"kind": "saved_motion_audit_identity_inventory", "tested_source": report["tested_source"], "context_sha256": context,
            "operation_report_sha256": sha(bundle / "operation-case-results.json"), "dependencies": report["dependencies"],
            "scope": "Candidate path joins and observations only; no physical qualification or persisted identity inferred", "rows": rows}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle")
    parser.add_argument("output")
    args = parser.parse_args()
    target = Path(args.output)
    with target.open("x", encoding="utf-8") as stream:
        json.dump(inventory(args.bundle), stream, indent=2)
