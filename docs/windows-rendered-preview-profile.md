# Explicit Windows rendered-preview profile

Tool integration complete; actual Windows renderer/MCP execution remains pending.
Existing failed artifacts stay unchanged. This is not a Windows rendering receipt.

## Integration boundary

Root applied `docs/patches/windows-rendered-preview-profile.patch` to the runner.
The preserved patch was prepared against runner raw
SHA256 `4525b8d21bb5750471ccfa9229cd2e0427a1b22787fc0dec40bf54943c3d35a6`.
It adds one explicit argument and uses the standalone profile helper. The default
remains `linux-mesa-llvmpipe`: Linux host/context, DISPLAY, and actual llvmpipe
OpenGL log identity remain mandatory. Windows requires explicit
`--renderer-profile windows-native-opengl`, a Windows host and recorded context,
and actual API version/driver plus vendor/device lines from the complete editor
log. Known software/translation aliases fail. Vendors are not allowlisted.

The adapter now recomputes the exact complete-log identity and requires the helper
dependency for explicit profiles. Linux CI passes its profile explicitly.25
profile/runner/adapter controls pass; no actual Windows execution is claimed.

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

## Downstream binding

`operation_preview_adapter.verify_preview_bundle` requires the explicit Windows
profile and calls the helper against the source-bound complete editor log,
comparing its complete identity with the report. Legacy Linux receipts without
a helper dependency retain their previous llvmpipe contract; fresh explicit
profiles require the helper dependency. Windows is never inferred. Hardware strings
report a driver/device, not independent attestation of a physical GPU; unknown
software aliases remain a documented limitation. Pixel decoding/restoration
checks remain independent of identity and cannot be replaced by a profile label.

`check_rendered_preview_matrix.py` currently requires two Linux core artifacts.
Do not silently let Windows replace these. A later explicit Windows two-core
matrix can require the same source/core/dependency contracts with the new profile
and exact actual engine identity. No Windows CI/GPU capability is claimed here.
