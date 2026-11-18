# Remaining read contract checkpoint

The original `pose_list` defect reproduced through the actual promoted Godot AI
tool on Windows, Godot4.7.2 and released core4.2.1 at
`d45f8341a9ac74babf254fdaf30e90c8c986caec`. A single `directory: []` request
returned success with directory `"[]"` and zero poses. Its advertised parameter
schema requires a String. Ordinary missing-String reads before/after were equal.
The editor quit publicly. Exact request, response, source, schema and raw calls
are preserved in private `pose-directory-before-fix-r001`.

The three-line guard rejects only a selected non-String `directory`, or the
legacy `pose_dir` when `directory` is absent. It returns `INVALID_PARAMS` before
directory access. Valid String, empty, omitted and missing-directory behavior is
preserved, as is an ignored legacy value when an explicit directory is selected.

This is the only production change in this increment. Existing modifier/physical
receipts retain their original source; do not claim all production blobs remain
identical after this read-only guard change. Their actual saved output/config and
unchanged runtime dependencies need explicit admission to the final candidate.

Three read witnesses now bracket the original `rig_get`, `pose_list` and
`graph_get` calls and their meaningful refusals, with stored scene/resource/file/
history observations and synchronous native logger slices. A separate native
graph observation checks the fixed authored idle/walk topology and binding.
Existing eleven inspect witnesses are unchanged. No repeated positive call or
new valid write is introduced. Parsing all four new/modified GDScripts in actual
Godot4.7.2 passes;42 combined Python controls pass. Fresh direct-suite and public
runtime execution remain required before qualification.
