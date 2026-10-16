# Explicit Windows rendered-preview profile

Tool-only preparation; no actual renderer/editor/MCP processes were launched.
No runtime/addon or Linux CI changes are required. Existing failed artifacts stay
unchanged. This is not a Windows rendering qualification receipt.

## Integration boundary

Apply `docs/patches/windows-rendered-preview-profile.patch` to the current root
runner after its frozen public run. The patch was prepared against runner raw
SHA256 `4525b8d21bb5750471ccfa9229cd2e0427a1b22787fc0dec40bf54943c3d35a6`.
It adds one explicit argument and uses the standalone profile helper. The default
remains `linux-mesa-llvmpipe`: Linux host/context, DISPLAY, and actual llvmpipe
OpenGL log identity remain mandatory. Windows requires explicit
`--renderer-profile windows-native-opengl`, a Windows host and recorded context,
and actual API version/driver plus vendor/device lines from the complete editor
log. Known software/translation aliases fail. Vendors are not allowlisted.

Root can review/check with `git apply --check` then apply the patch. The patch is
an artifact, not an imported baseline file. Six standalone offline controls pass.
Python compilation of the patched runner succeeds; no execution is claimed.

## Root-owned actual command

In a fresh disposable copied project with released core prepared, Python carrying
FastMCP and Pillow, free isolated backend ports, and the desktop/native slot:

```powershell
python tools/ci_rendered_preview.py --renderer-profile windows-native-opengl --godot <Godot4.7.2-console.exe> --core-root <released-core-checkout> --project <fresh-project> --output <new-receipt-directory> --port 8123 --ws-port 9623
```

Run separately against each released core 4.2.1 and 4.3.0, with the actual intended
source checkout. The existing runner owns exactly its backend/editor; no editor
should already own that project. It records actual public calls, exact source/core
context, four fully decoded 320x240 PNGs with nonblank and all-pairs-distinct pixel
checks, exact source/timeline checkpoints, typed dry/missing/overwrite refusals,
complete engine error checks and portable hashes. These gates are unchanged.

## Required downstream binding before qualification

`operation_preview_adapter.verify_preview_bundle` already supports Windows actual
OpenGL lines, but must require the explicit Windows profile and call this helper
against the source-bound complete editor log, comparing recomputed identity with
report identity. Keep historical Linux reports without profile treated only as
the legacy Linux profile; never implicitly reinterpret Windows as native. Add the
helper's blob to required context dependencies. Existing native hardware strings
report a driver/device, not independent attestation of a physical GPU; unknown
software aliases remain a documented limitation. Pixel decoding/restoration
checks remain independent of identity and cannot be replaced by a profile label.

`check_rendered_preview_matrix.py` currently requires two Linux core artifacts.
Do not silently let Windows replace these. A later explicit Windows two-core
matrix can require the same source/core/dependency contracts with the new profile
and exact actual engine identity. No Windows CI/GPU capability is claimed here.
