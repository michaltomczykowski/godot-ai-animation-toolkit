"""Fail-closed corruption checks for the release ledger gate."""
import copy
import json
from pathlib import Path
import unittest
import subprocess
import tempfile
import hashlib
import os
from check_release_audit import validate_inventory, validate_release, required_checks, CORES, git_blob, artifact_is_valid, operation_binding_errors, qualified_audit


class AuditGateTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[1]
        self.doc = json.loads((self.root / "docs/operation-audit.json").read_text(encoding="utf-8-sig"))

    def qualification_fixture(self, directory):
        source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()
        paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", source, "addons/godot_ai_animation"], cwd=self.root, text=True).splitlines()
        artifact = Path(directory) / "synthetic-test-report.json"
        artifact.write_text(json.dumps({"cases": [{"id": row["key"] + "::synthetic", "operation": row["key"], "checks": {n: "pass" for n in required_checks(row["effect_kind"])}} for row in self.doc["operations"]]}))
        assessment = Path(directory) / "synthetic-assessments.json"
        assessment.write_text(json.dumps({"assessments": [{"operation": row["key"], "case_ids": [row["key"] + "::synthetic"], "status": "pass", "reviewer_type": "independent", "human_approved": False, "continuous_media": True, "method": "Synthetic structure test only", "media": [{"kind": "video", "sha256": "a" * 64}], "findings": ["Synthetic structure test; never release evidence"]} for row in self.doc["operations"]]}))
        artifacts = [{"role": "operation_case_results", "path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}, {"role": "independent_assessment", "path": assessment.name, "sha256": hashlib.sha256(assessment.read_bytes()).hexdigest()}]
        dependency = "test_project/tools/export_operation_audit.gd"
        compatibility = []
        records = {}
        for platform in ["windows", "linux"]:
            for version, commit in CORES.items():
                label = platform + version
                record = {"scope": "candidate", "tested_source": source, "engine": "4.7.2", "route": "public_godot_ai", "platform": platform, "core_version": version, "core_commit": commit, "case_ids": ["synthetic_test_case"], "dependencies": {dependency: git_blob(str(self.root), source, dependency)}, "artifacts": artifacts, "assessment": {"reviewer_type": "independent", "continuous_media": True, "findings": "Synthetic structure test only", "human_approved": False}}
                records[label] = record
                compatibility.append({"status": "pass", "tested_source": source, "engine": "4.7.2", "platform": platform, "core_version": version, "core_commit": commit, "artifacts": artifacts})
        receipt = {"schema_version": 2, "tested_source": source, "production_dependencies": {rel: git_blob(str(self.root), source, rel) for rel in paths}, "compatibility": compatibility, "operations": {}}
        for row in self.doc["operations"]:
            bound_records = copy.deepcopy(records)
            for record in bound_records.values():
                record["operation_key"] = row["key"]
                record["case_ids"] = [row["key"] + "::synthetic"]
            receipt["operations"][row["key"]] = {"checks": {n: {"status": "pass", "evidence_refs": list(records)} for n in required_checks(row["effect_kind"])}, "evidence_records": bound_records}
        return source, receipt, artifact

    def test_complete_fixture_and_artifact_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            source, receipt, artifact = self.qualification_fixture(directory)
            self.assertEqual(validate_release(self.doc, receipt, self.root, source, Path(directory)), [])
            derived = qualified_audit(self.doc, receipt, source)
            self.assertTrue(all(r["qualification"] == "verified" and r["status"] == "verified" for r in derived["operations"]))
            self.assertTrue(all(r["qualification"] == "pending" for r in self.doc["operations"]))
            artifact.write_text("changed")
            self.assertTrue(any("changed artifact" in e for e in validate_release(self.doc, receipt, self.root, source, Path(directory))))

    def test_changed_dependency_and_false_human_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            source, receipt, artifact = self.qualification_fixture(directory)
            receipt["production_dependencies"][next(iter(receipt["production_dependencies"]))] = "0" * 40
            first = receipt["operations"][self.doc["operations"][0]["key"]]
            for record in first["evidence_records"].values(): record["assessment"]["human_approved"] = True
            errors = validate_release(self.doc, receipt, self.root, source, Path(directory))
            self.assertTrue(any("dependency changed" in e for e in errors))
            self.assertTrue(any("mislabeled" in e for e in errors))

    def test_artifact_parent_and_absolute_paths_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "receipts"
            receipt.mkdir()
            external = root / "private.json"
            external.write_text("private")
            digest = hashlib.sha256(external.read_bytes()).hexdigest()
            self.assertFalse(artifact_is_valid({"path": "../private.json", "sha256": digest}, receipt))
            self.assertFalse(artifact_is_valid({"path": str(external.resolve()), "sha256": digest}, receipt))
            self.assertFalse(artifact_is_valid({"path": "C:/private/report.json", "sha256": digest}, receipt))
            internal = receipt / "public.json"
            internal.write_text("public")
            self.assertTrue(artifact_is_valid({"path": "public.json", "sha256": hashlib.sha256(internal.read_bytes()).hexdigest()}, receipt))

    def test_artifact_link_escape_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            receipt = root / "receipts"
            external = root / "external"
            receipt.mkdir()
            external.mkdir()
            report = external / "report.json"
            report.write_text("external")
            link = receipt / "escape"
            try:
                os.symlink(external, link, target_is_directory=True)
            except OSError:
                if os.name != "nt": raise
                # Junction creation does not require Windows symlink privilege.
                result = subprocess.run(["powershell", "-NoProfile", "-Command", "New-Item -ItemType Junction -Path '" + str(link).replace("'", "''") + "' -Target '" + str(external).replace("'", "''") + "' | Out-Null"], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertFalse(artifact_is_valid({"path": "escape/report.json", "sha256": hashlib.sha256(report.read_bytes()).hexdigest()}, receipt))

    def test_case_binding_rejects_other_operation_missing_case_and_nonpass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "results.json"
            key = "animation_fx.shake"
            def evidence(document, operation=key, ids=None):
                artifact.write_text(json.dumps(document))
                return {"operation_key": operation, "case_ids": ids or ["case1"], "artifacts": [{"role": "operation_case_results", "path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}]}
            good = {"cases": [{"id": "case1", "operation": key, "checks": {"playback": "pass"}}]}
            self.assertEqual(operation_binding_errors(evidence(good), key, "playback", root), [])
            self.assertTrue(operation_binding_errors(evidence(good, operation="animation_fx.pendulum"), key, "playback", root))
            other = {"cases": [{"id": "case1", "operation": "animation_fx.pendulum", "checks": {"playback": "pass"}}]}
            self.assertTrue(operation_binding_errors(evidence(other), key, "playback", root))
            self.assertTrue(operation_binding_errors(evidence(good, ids=["invented"]), key, "playback", root))
            failed = {"cases": [{"id": "case1", "operation": key, "checks": {"playback": "fail"}}]}
            self.assertTrue(operation_binding_errors(evidence(failed), key, "playback", root))
            duplicate = {"cases": good["cases"] * 2}
            self.assertTrue(operation_binding_errors(evidence(duplicate), key, "playback", root))

    def test_assessment_requires_actual_operation_media_method_and_findings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "assessment.json"
            key = "animation_fx.shake"
            entry = {"operation": key, "case_ids": ["case1"], "status": "pass", "reviewer_type": "independent", "human_approved": False, "continuous_media": True, "method": "Synthetic temporal fixture", "media": [{"kind": "video", "sha256": "a" * 64}], "findings": ["Synthetic observation"]}
            def check(value):
                artifact.write_text(json.dumps({"assessments": [value]}))
                record = {"operation_key": key, "case_ids": ["case1"], "artifacts": [{"role": "independent_assessment", "path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}]}
                return operation_binding_errors(record, key, "visual_review", root)
            self.assertEqual(check(entry), [])
            for field, value in [("operation", "animation_fx.pendulum"), ("media", []), ("findings", True), ("method", ""), ("status", "partial"), ("human_approved", True)]:
                broken = copy.deepcopy(entry)
                broken[field] = value
                self.assertTrue(check(broken), field)

    def test_inventory_accepts_honest_pending(self):
        self.assertEqual(validate_inventory(self.doc), [])

    def test_no_manual_verified(self):
        self.doc["operations"][0]["status"] = "verified"
        self.assertTrue(validate_inventory(self.doc))

    def test_effect_cannot_hide_producing_checks(self):
        self.doc["operations"][0]["effect_kind"] = "read"
        self.assertTrue(validate_inventory(self.doc))

    def test_unjustified_na_fails(self):
        self.doc["operations"][0]["checks"]["mcp_invocation"] = {"status": "not_applicable", "reason": "convenient", "evidence_refs": []}
        self.assertTrue(validate_inventory(self.doc))

    def test_pass_without_resolvable_evidence_fails(self):
        self.doc["operations"][0]["checks"]["visual_review"] = {"status": "pass", "evidence_refs": ["nonexistent"]}
        self.assertTrue(validate_inventory(self.doc))

    def test_unsupported_advertising_fails(self):
        self.doc["operations"][0]["availability"] = {"status": "unavailable", "reason": "native unsupported"}
        self.assertTrue(validate_inventory(self.doc))

    def test_duplicate_or_missing_operation_fails(self):
        self.doc["operations"][0] = copy.deepcopy(self.doc["operations"][1])
        self.assertTrue(validate_inventory(self.doc))

    def test_historical_proof_cannot_qualify_release(self):
        receipt = {"schema_version": 2, "tested_source": "HEAD", "operations": {}}
        errors = validate_release(self.doc, receipt, self.root, "HEAD", self.root)
        self.assertTrue(any("missing candidate pass" in e for e in errors))
        self.assertTrue(any("matrix incomplete" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
