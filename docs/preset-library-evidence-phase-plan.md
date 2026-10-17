# Preset/library case evidence phase

1. Instrument the existing five-layout preset/template/spec history matrix in
   `test_preset_library_history.gd`; retain all original fixtures and assertions.
   Record exact dispatcher request/result, dry/error snapshots, local/global
   history versions, actual Undo/Redo success, saved/reopened snapshots and file
   hashes, peer/other-player/unrelated-clip isolation and recipe bytes.
2. Add independent fixed native sample expectations for the known requests.
   Native manual mixer evaluation is a test measurement only; compare actual
   target values at fixed times against constants, not output-key values.
   Capture actual track types separately. Restore fixture properties before
   history snapshots so sampling cannot become an undo baseline mutation.
3. Emit optional exact case rows only inside the collector's active public
   `test_run` span. Distinguish preset operation names from canonical library
   `template_apply` and `spec_apply`. A suite count is never operation evidence.
4. Add a distinct strict Python adapter with offline corruption controls for
   snapshots/history, typed errors, saved resource/recipe hashes and independent
   native expectations. Integrate the shared trace/collector through narrow
   separate commits, coordinated with their owner.
5. Root runs fresh integrated Godot/editor/public routes after its GPU queue.
   Until actual traces exist this source change supplies no qualification.
   Historical fixtures/receipts remain untouched; visual review stays separate.

Scope excludes library read/file operations, rig pose/file evidence, motion and
new production recipes. The root owns native processes and evidence generation.
