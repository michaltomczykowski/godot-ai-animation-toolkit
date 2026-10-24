# pose_list directory contract

`directory` selects the listing directory when present; otherwise legacy
`pose_dir` is used, with the existing default when both are omitted. The active
field must be a String. A non-String active value returns typed INVALID_PARAMS
before DirAccess, scene/history changes or file access. An ignored pose_dir does
not override an explicit valid directory. Null, Array, Dictionary, numeric and
Boolean values are invalid; there is no String coercion for the selected field.

All String semantics stay unchanged, including empty/default paths and missing
or unreadable directories returning a successful exists=false/count0 result.
Malformed pose files retain existing listing-summary behavior. No new producer,
format, availability or schema surface is added; the schema already says String.

Released421/430 promoted custom wrappers advertise the custom schema but their
run paths forward arguments through custom_invoke. Handler validation therefore
must protect this read consistently across public and direct dispatch. The
new witness requests directory=[] and requires the exact handler INVALID_PARAMS;
it does not manufacture a missing-directory error or reuse unrelated bone guards.

This is one narrow production read guard. Historical media/physical references
keep original source/dependencies; do not claim all previous production blobs
are identical after this change. Fresh candidate CI/public reads must cover the
new guard. Actual parse/direct/public execution is pending root's engine slot.


Root preserved the actual before-fix promoted public call on2026-10-24 at
source d45f834/core421/Godot4.7.2: directory=[] incorrectly returned success
with directory='[]', exists=false, pose_count0. Existing missing-String behavior
was unchanged before/after. Private raw/context/schema evidence is
E:/GodotAI-toolkit-release-2.0.0/20261014/pose-directory-before-fix-r001.
Schema SHA256:bb30a4dc0f4b509c82e868e00320f66edbaad7e6a5d11bdddaa2f7df10e4ca2a.
This is the concrete source-contract failure motivating only this selected-key
guard; post-fix actual direct/public execution remains pending.
