#!/usr/bin/env python3
"""Validate v2 inventory; release mode additionally requires exact-source receipts.
Historical proof never becomes candidate qualification merely by regenerating docs.
"""
import argparse
import hashlib
from functools import lru_cache
import json
from pathlib import Path, PureWindowsPath
import subprocess
import sys

OPERATION_NAMES = {
    'animation_edit': 'retime retarget reverse mirror offset ease_range set_interp trim split_at merge amplitude loop key_edit cleanup smooth resample reduce add_noise overlap layer'.split(),
    'animation_fx': 'shake zoom_punch hit_flash damage_bar typewriter progress_fill counter dialog_pop transition wave spring pendulum path_follow flipbook sprite_frames audio_cue'.split(),
    'animation_graph': 'state_machine blend_space blend_tree wire graph_get locomotion one_shot_layer additive_lean'.split(),
    'animation_inspect': 'describe timeline audit compare stats motion_report motion_audit rig_profile sample preview dry_run help'.split(),
    'animation_library': 'template_save template_apply template_list template_delete spec_export spec_import spec_apply'.split(),
    'animation_motion': 'walk_cycle run_cycle idle_cycle cycle character_setup secondary_motion jump turn_cycle strafe_cycle walk_start walk_stop'.split(),
    'animation_presets': 'pulse bounce orbit sweep drift spin float stagger showcase'.split(),
    'animation_rig': 'pose_save pose_apply pose_blend pose_to_clip pose_list rig_get rig_chain walk_cycle idle_breathing blink jumping_jack squat punch bake_pose_sequence'.split(),
    'animation_rig_modifiers': 'ik_setup spring_setup look_at_setup retarget_setup twist_setup'.split(),
    'animation_sequence': 'compose'.split(),
}
EXPECTED_OPERATIONS = {family + "." + op for family, ops in OPERATION_NAMES.items() for op in ops}
STATES = {"pass", "fail", "pending", "not_applicable"}
CORES = {"4.2.1": "bfc264200584ea5823f18356acb164781f57796d", "4.3.0": "b82b5c519b1b17228f70d8effce1626f391bd1dd"}
CHECKS = ["mcp_invocation", "valid_effect", "track_paths_types", "dry_run", "undo_redo", "save_reopen", "playback", "visual_review", "reported_errors", "source_unchanged", "typed_errors", "file_effect"]


@lru_cache(maxsize=None)
def git_blob(root, source, rel):
    return subprocess.check_output(["git", "rev-parse", f"{source}:{rel}"], cwd=root, text=True).strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_effect(key):
    family, op = key.split(".", 1)
    if family == "animation_inspect":
        return "render" if op == "preview" else "read"
    if family == "animation_graph":
        return "read" if op == "graph_get" else "scene_structure"
    if family == "animation_rig_modifiers":
        return "scene_structure"
    if family == "animation_library":
        if op in {"template_list", "spec_import"}: return "read"
        if op in {"template_save", "template_delete", "spec_export"}: return "file_write"
    if family == "animation_rig":
        if op in {"pose_list", "rig_get"}: return "read"
        if op in {"pose_save", "pose_blend"}: return "file_write"
        if op in {"pose_apply", "rig_chain"}: return "scene_structure"
    return "scene_write"


def artifact_is_valid(artifact, receipt_dir):
    """Only portable files confined to the receipt tree may qualify a release."""
    raw = artifact.get("path", "")
    if not isinstance(raw, str) or not raw or Path(raw).is_absolute() or PureWindowsPath(raw).drive:
        return False
    receipt_root = receipt_dir.resolve()
    path = (receipt_root / raw).resolve()
    if not path.is_relative_to(receipt_root):
        return False
    return path.is_file() and sha256(path) == artifact.get("sha256")


def required_checks(effect):
    required = {"mcp_invocation", "valid_effect", "reported_errors", "source_unchanged", "typed_errors"}
    if effect in {"scene_write", "scene_structure"}:
        required |= {"dry_run", "undo_redo", "save_reopen", "playback", "visual_review"}
    if effect == "scene_write":
        required.add("track_paths_types")
    if effect == "file_write":
        required |= {"dry_run", "file_effect"}
    if effect == "render":
        required |= {"file_effect", "visual_review"}
    return required


def validate_inventory(doc):
    errors = []
    if doc.get("schema_version") != 2:
        return ["inventory schema_version must be 2"]
    rows = doc.get("operations", [])
    keys = [r.get("key") for r in rows]
    if set(keys) != EXPECTED_OPERATIONS or len(rows) != 103 or len(set(keys)) != len(keys):
        errors.append("inventory must preserve 103 distinct operation rows")
    for row in rows:
        key = row.get("key", "<missing>")
        if key != row.get("family", "") + "." + row.get("op", ""):
            errors.append(f"{key}: family/op identity mismatch")
        availability = row.get("availability", {})
        if availability.get("status") not in {"supported", "unavailable"}:
            errors.append(f"{key}: invalid availability")
        if availability.get("status") == "unavailable" and not availability.get("reason"):
            errors.append(f"{key}: unavailable without reason")
        if row.get("advertised") != (availability.get("status") == "supported"):
            errors.append(f"{key}: unsupported advertising")
        effect = row.get("effect_kind")
        if effect not in {"scene_write", "scene_structure", "file_write", "read", "render"}:
            errors.append(f"{key}: invalid effect_kind")
        if key not in EXPECTED_OPERATIONS or effect != expected_effect(key):
            errors.append(f"{key}: effect classification differs from operation contract")
        checks = row.get("checks", {})
        required = required_checks(effect)
        for name in CHECKS:
            check = checks.get(name, {})
            if not isinstance(check, dict) or check.get("status") not in STATES:
                errors.append(f"{key}.{name}: invalid check")
                continue
            if check["status"] == "not_applicable" and (name in required or not check.get("reason")):
                errors.append(f"{key}.{name}: unjustified N/A")
            refs = check.get("evidence_refs", [])
            if check["status"] == "pass" and not refs:
                errors.append(f"{key}.{name}: pass without evidence")
            for ref in refs:
                if ref not in row.get("evidence_records", {}):
                    errors.append(f"{key}.{name}: missing evidence {ref}")
        derived = "verified" if all(checks.get(n, {}).get("status") == "pass" for n in required) else "partial"
        # Historical inventory cannot certify an exact candidate.
        if row.get("status") != derived or row.get("qualification") != "pending":
            errors.append(f"{key}: status is not derived or claims candidate qualification")
    return errors


def validate_release(doc, receipt, root, source, receipt_dir):
    errors = validate_inventory(doc)
    if receipt.get("schema_version") != 2 or not receipt.get("tested_source"):
        errors.append("qualification schema/source does not match requested commit")
    tested_source = receipt.get("tested_source", "")
    try:
        source_files = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", source, "addons/godot_ai_animation"], cwd=root, text=True).splitlines()
        production = receipt.get("production_dependencies", {})
        if set(source_files) != set(production):
            errors.append("qualification production dependency manifest incomplete")
        for rel, digest in production.items():
            blob = git_blob(str(root), source, rel)
            tested_blob = git_blob(str(root), tested_source, rel)
            if digest != blob or digest != tested_blob:
                errors.append(f"qualification production dependency changed: {rel}")
    except subprocess.CalledProcessError:
        errors.append("qualification production source/dependency cannot be resolved")
    operations = receipt.get("operations", {})
    expected = {r["key"] for r in doc["operations"]}
    if set(operations) != expected:
        errors.append("qualification operation keys differ from inventory")
    matrix = receipt.get("compatibility", [])
    for entry in matrix:
        artifacts = entry.get("artifacts", [])
        if not artifacts:
            errors.append("compatibility pass lacks raw artifact evidence")
        for artifact in artifacts:
            if not artifact_is_valid(artifact, receipt_dir):
                errors.append("compatibility artifact missing or changed")
    actual = {(m.get("platform"), m.get("core_version")) for m in matrix if m.get("status") == "pass" and m.get("engine") == "4.7.2" and m.get("core_commit") == CORES.get(m.get("core_version")) and m.get("tested_source") == tested_source}
    if actual != {(p, c) for p in ("windows", "linux") for c in CORES}:
        errors.append("exact-source Windows/Linux released-core 4.2.1/4.3.0 matrix incomplete")
    for row in doc["operations"]:
        key = row["key"]
        item = operations.get(key, {})
        records = item.get("evidence_records", {})
        required = required_checks(row["effect_kind"])
        if row["availability"]["status"] == "unavailable":
            required = {"mcp_invocation", "typed_errors", "source_unchanged", "reported_errors"}
        invocation_refs = item.get("checks", {}).get("mcp_invocation", {}).get("evidence_refs", [])
        invocation_matrix = {(records.get(ref, {}).get("platform"), records.get(ref, {}).get("core_version")) for ref in invocation_refs if records.get(ref, {}).get("core_commit") == CORES.get(records.get(ref, {}).get("core_version"))}
        if invocation_matrix != {(p, c) for p in ("windows", "linux") for c in CORES}:
            errors.append(f"{key}: public invocation released-core/platform coverage incomplete")
        for name in required:
            check = item.get("checks", {}).get(name, {})
            refs = check.get("evidence_refs", [])
            if check.get("status") != "pass" or not refs:
                errors.append(f"{key}.{name}: missing candidate pass")
            for ref in refs:
                evidence = records.get(ref, {})
                if evidence.get("tested_source") != tested_source or evidence.get("scope") != "candidate":
                    errors.append(f"{key}.{name}/{ref}: stale/noncandidate evidence")
                if evidence.get("engine") != "4.7.2" or not evidence.get("case_ids") or not evidence.get("dependencies"):
                    errors.append(f"{key}.{name}/{ref}: missing engine/cases/dependencies")
                if name == "mcp_invocation" and evidence.get("route") != "public_godot_ai":
                    errors.append(f"{key}: public Godot AI route missing")
                if name == "visual_review":
                    assessment = evidence.get("assessment", {})
                    if assessment.get("reviewer_type") != "independent" or not assessment.get("continuous_media") or not assessment.get("findings") or assessment.get("human_approved") is True:
                        errors.append(f"{key}: independent continuous assessment missing or mislabeled")
                if name != "visual_review" and not any(rel.startswith("test_project/") or rel.startswith("tools/") for rel in evidence.get("dependencies", {})):
                    errors.append(f"{key}/{ref}: checker/test dependency missing")
                for rel, digest in evidence.get("dependencies", {}).items():
                    try:
                        actual_blob = git_blob(str(root), source, rel)
                        tested_blob = git_blob(str(root), tested_source, rel)
                        if actual_blob != digest or tested_blob != digest:
                            errors.append(f"{key}/{ref}: stale dependency {rel}")
                    except subprocess.CalledProcessError:
                        errors.append(f"{key}/{ref}: missing source dependency {rel}")
                artifacts = evidence.get("artifacts", [])
                if not artifacts:
                    errors.append(f"{key}/{ref}: missing artifacts")
                for artifact in artifacts:
                    if not artifact_is_valid(artifact, receipt_dir):
                        errors.append(f"{key}/{ref}: missing/changed artifact {artifact.get('path')}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source")
    parser.add_argument("--receipt-dir", type=Path)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--inventory-only", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    doc = json.loads((args.inventory or root / "docs/operation-audit.json").read_text(encoding="utf-8-sig"))
    if args.inventory_only:
        errors = validate_inventory(doc)
    else:
        if not args.source or not args.receipt_dir:
            parser.error("release mode requires --source and --receipt-dir")
        source = subprocess.check_output(["git", "rev-parse", args.source + "^{commit}"], cwd=root, text=True).strip()
        path = args.receipt_dir / "operation-qualification.json"
        if not path.is_file():
            print("RELEASE_AUDIT_FAIL: missing operation-qualification.json")
            return 1
        errors = validate_release(doc, json.loads(path.read_text(encoding="utf-8-sig")), root, source, args.receipt_dir)
    for error in errors:
        print("RELEASE_AUDIT_FAIL: " + error)
    if errors:
        return 1
    pending = [r["key"] for r in doc["operations"] if r["status"] != "verified"]
    print(f"OPERATION_INVENTORY_OK: 103 rows, {len(pending)} historical partial, candidate qualification pending")
    if not args.inventory_only:
        print("RELEASE_AUDIT_PASS: exact-source qualification complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
