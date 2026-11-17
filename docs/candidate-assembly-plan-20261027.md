# Candidate audit and package: execution plan

This implements phase 5 of release-final-six-phases.md. Phase 4's final
three-case independent assessment is finishing separately. Publication remains
blocked by unresolved Linux instability; a green CI run does not close it.

## 1. Admit the latest completed four-cell evidence

Checkpoint, November 17: all four live-route bundles admitted. Actual tested
checkout `a0acf2d26449cefb8e8e831bfd8248d048604a26`; all addon blobs equal
branch `947f7fa`. Each cell has 2,049 cases, 835 verified raw artifact hashes,
217 refused/failed observations retained separately, and zero non-invocation
derived failures. Each still lacks 82 visual reviews and eight valid-effect
checks in the main bundle; preview accounts for the remaining invocation,
file-effect, source-preservation and error check gaps. This is before joining
any separate evidence.

Run `tools/audit_candidate_case_coverage.py` with the four explicit
`operation-evidence` directories under private `ci-f75c324-r001`. The saved
`case-gap-ledger-r001.json` SHA-256 is
`78bd9ac979b23f410679f275fc9908f5c7f225cd4e3fb89f7ad5053995fae282`.
The auditor checks executable/resource dependency hashes, permits the verified
Windows text checkout representation, and separately compares every addon Git
blob. Eight focused controls pass.

Supplement admission verified the package bytes against the same tested
checkout, all four clean install receipts, both enable orders and the eight
corresponding editor log hashes. The same-source Linux preview reports pass
the strict public trace and rendered output adapter for both cores.
Private `supplement-admission-r001.json` SHA-256:
`d9c0cc5afd7626a85d0649205a2aaf68a3ab7e648e61dda3fafc3d2ecc8435bb`.
This does not supply Windows rendered preview evidence, independent visual
assessment for these preview cases, or proof of Linux stability.

## Linux timeout diagnosis

Run 40359394495, Linux clean ZIP with core 4.2.1, reached the editor's
successful response for `rig_modifier_allocation` and then exceeded the
120-second driver limit. No prior driver milestone distinguishes MCP reply
receipt, stdio client teardown, or native playback. This is separate from the
observed native heap abort.

The allocation driver now records attach, activation, scene open, request,
client close, and native execution boundaries. The parent and native check
use the existing diagnostics writer to retain partial stdout/stderr and
the last stage. The 120/45-second limits and pass predicates are unchanged.
Artifacts are captured by the existing gate-diagnostics upload; both clean
install orders get distinct receipts. Local diagnostic unit tests, Python
compilation, and diff checks pass. Inspect the next failed job's progress
and timeout metadata before changing runtime behavior.

Use CI 40477883598 (PR head f75c32457dc64057e60f32bc7e61498c32ae420b).
Download the four live-route bundles, two rendered-preview bundles, four clean
ZIP bundles and package manifest to an exclusive private directory. Preserve
the API run/artifact responses and actual checkout identity from each context.
Do not substitute PR head or event merge identity for actual tested checkout.

Verify context/report identities, every raw artifact hash, exact dependency
Git blobs/content hashes, unique case IDs and core/platform separation before
using any check. Compare production dependencies with the current branch.
Keep observed failures/refusals and check-to-case lists, including absent checks.
This first output is a gap ledger, never a qualification receipt.

## 2. Join the existing scoped proofs

Join seven motion-intent checks and recorded assessments by exact operation,
case selectors, original source and input/output/media hashes. Retain producer,
native executor, renderer and assessor identities separately. Record dependency
changes explicitly; unchanged output does not establish unchanged implementation.
Missing or ambiguous joins stay pending. No new goldens or animation tuning.

Private X Bot assets and combined private footage remain local. Portable release
evidence may reference only explicitly admitted public-safe files; no recursive
media discovery or accidental recovery/model copying. User waived further human
review pauses, not independent assessment or actual engine qualification.

## 3. Freeze and validate one package

Once remaining necessary tooling/docs are committed, freeze its exact source.
Use tools/release_zip.ps1 and tools/validate_release_package.py to create and
verify addon + LICENSE bytes, version 2.0.0, entry safety, CRC and checksum.
Do not overwrite existing packages. Record actual CI-tested source and candidate
source separately and require their production Git blobs to match.

## 4. Apply the existing blocking gate

Assemble operation-qualification.json only from complete, admitted evidence.
Use check_release_audit.py unchanged: all 103 operations, applicable checks,
actual four-cell public invocation, dependency identities, portable artifacts
and independent assessments. Keep historical operation-audit.json untouched.
Generate the derived qualified audit only after the gate passes.

Phase 5 completes only after the actual package and complete audit pass. Phase 6
still requires stable official-engine qualification, both enable orders, UI
family persistence/reload/stale calls, clean installs and actual workflows before
merge/main qualification/tag/publication. The unresolved Linux allocation-gate
timeout needs stage evidence, not a larger timeout or an automatic retry.
