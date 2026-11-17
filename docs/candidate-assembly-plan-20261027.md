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

Subsequent local replay now supplies the two Windows preview cases for this
same tested checkout. A detached checkout at `a0acf2d`, the original tested
ZIP, separate user settings and exact released cores were used. Both actual
public preview calls pass the strict trace, PNG and saved-source restoration
adapter. Execution receipt SHA-256
`4340a6990ec262fb3d3b818cf3eeb124078c82b283fdd06697b673a71e583f29`
under private `windows-previews-a0acf2d-r001`.
All 16 original PNGs from both platforms and cores were viewed at native
320×240 in an ordered contact sheet. The four distinct poses are legible and
the full character stays in frame. This is a static preview assessment only,
not approval of animation quality or release. Assessment SHA-256
`621f371f0b16e06692e0481f9dd214121a6f255561b6b6594c3761e8bdeded83`.

The six historical motion effect cases and three-clock setup replay are
indexed under private `ci-f75c324-r001/motion-supplement-index-r001.json`
(SHA-256 `47bb2055368522c12726691ddcf61990f4f0048bcbc61def2d5e3f24c10f7011`).
Raw artifact hashes and case IDs were checked. The idle/turn source differs
only by the later Spring helper UID; the other four effects and fresh setup
executor have equal addon Git blobs. Original source identities remain
unchanged, and none of these older receipts is relabeled candidate evidence.

The full release-side preview checker was also run against both archived Linux
bundles. It initially rejected both: its expected dependency scope omitted
five scene fixtures plus the dummy model, sprite sheet and audio fixture that
the actual producer records. The producer and verifier now use one Git
dependency selector. Exact dependency-set/blob comparison remains mandatory.
The actual two-bundle check passes with the fix; 30 targeted controls pass.

Private `ci-f75c324-r001/case-gap-ledger-with-preview-r001.json`
(SHA-256 `c833a5a65a891aef5f0147dae26ca97e25edfba2dd87e99b31777c4152e9a400`)
adds the four verified same-source preview cases to the relevant cells, with
context and trace hashes. All 103 operations now have passing public case
coverage in each cell, and 96 have all required machine checks. Seven
valid-effect joins and 82 visual-review bindings per cell remain pending in
this ledger. These are missing bindings, not 89 reported failures. The
historical motion scope and static preview assessment remain separate inputs.

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

CI 44105449468 now has verified Linux 4.2.1 and 4.3.0 successes for both
enable orders at actual checkout `644fffd509300a60f353f647a3ccef174cb9f56f`.
All four route logs include the allocation-gate pass and all four editor log
hashes match the clean-install receipts. This was the run before adding the
allocation progress capture, so it does not identify the original stall.

## Native editor abort

Godot issue [#124603](https://github.com/godotengine/godot/issues/124603)
reports the same two documentation queue writers and allocator abort on the
official 4.7.2 Linux binary. The report was archived without a linked patch;
the reporter's smaller fixture did not reproduce their original crash.
Our actual public fixture and debugger evidence are recorded separately in
doc-loader-watch-assessment-20261026.md.

The repair PR now runs a separate official-binary postmortem pass for both
released Godot AI cores. The normal preview jobs and the release gate keep
their existing inputs. The diagnostic pass captures bounded debugger text if
the editor aborts and deletes the raw core. A passing diagnostic run cannot
establish that the intermittent crash is fixed.

Both postmortem jobs in run 44106923913 passed and reported
`no_observed_native_crash`. Each produced four images; the kernel pattern
was restored and no core was uploaded. Linux clean install on the instrumented
run 44106189254 was still active at this checkpoint.

## Last three recording cases

The independently verified recording inputs include 2,670 artifacts and all
60 decoded observations. The project technical review viewed all eight
ordered sheets plus full-resolution examples. Secondary motion matches
reference and redo at sampled times, the create case adds an unconnected root,
and the append case adds the expected linked child. No visible clipping or
unexpected topology change. This is a technical review of the unskinned
witnesses and static topology, with independent release assessment still
required. Private root technical assessment SHA-256:
`ad7d547663752822d5e3ebbfb17b59156e12f72f8cd1c09278bb3e5c2133774c`.

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
