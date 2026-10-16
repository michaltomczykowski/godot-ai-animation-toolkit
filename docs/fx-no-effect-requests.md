# FX requests with no effect

The following requests return typed `OPERATION_UNAVAILABLE` before authoring a
clip, attaching an animation library, changing a target or creating undo history:

- `damage_bar` and `progress_fill`: approximately equal resolved `from`/`to`.
  This includes omitted endpoints when the target is already at the default
  destination (0 for damage bar, 1 for progress fill).
- `counter`: every sampled key formats to exactly the same final text, including
  prefix/suffix. Distinct numeric inputs may still be identical after integer
  rounding or a low-precision/literal format. A range that produces any distinct
  sampled text remains supported.
- `spring`: a zero 2D or 3D displacement vector.

Dry and write calls use the same refusal. Existing duration, delay, step count,
frequency, damping and type validation runs first; invalid durations retain
`VALUE_OUT_OF_RANGE`. No alternative visual effect or arbitrary destination is
substituted. Choose a distinct destination, more precise counter format, wider
range or nonzero displacement. Valid default recipes retain their existing keys.

The guards apply in pure builders, including library/template callers. Editor
tests exercise default/explicit refusals, unchanged target/nodes/library/history,
and positive dry/write controls. Pure tests cover counter formatting collisions
and original invalid-duration precedence. Integrated execution remains required.
No checker static whitelist or family-wide disable is introduced.
