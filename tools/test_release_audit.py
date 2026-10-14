"""Fail-closed corruption checks for the release ledger gate."""
import copy
import json
from pathlib import Path
import unittest
import subprocess
import tempfile
import hashlib
from check_release_audit import validate_inventory, validate_release, required_checks, CORES, git_blob


class AuditGateTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[1]
        self.doc = json.loads((self.root / "docs/operation-audit.json").read_text(encoding="utf-8-sig"))

    def qualification_fixture(self, directory):
        source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()
        paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", source, "addons/godot_ai_animation"], cwd=self.root, text=True).splitlines()
        artifact = Path(directory) / "synthetic-test-report.json"
        artifact.write_text('{"fixture_only": true}')
        artifacts = [{"path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}]
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
            receipt["operations"][row["key"]] = {"checks": {n: {"status": "pass", "evidence_refs": list(records)} for n in required_checks(row["effect_kind"])}, "evidence_records": copy.deepcopy(records)}
        return source, receipt, artifact

    def test_complete_fixture_and_artifact_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            source, receipt, artifact = self.qualification_fixture(directory)
            self.assertEqual(validate_release(self.doc, receipt, self.root, source, Path(directory)), [])
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
