# Assessment media identity hardening plan

Bind each assessment media entry to a real relative file within the receipt tree and the same path/SHA256 in its evidence artifact manifest. Reuse artifact_is_valid confinement/hash checks; preserve schema2, source guards, operation/case matching and continuous-media requirements. No normalizer, promotion, private assets or engine work.

Use small explicit synthetic placeholder bytes only for structural tests, never visual evidence. Controls: missing path/file/manifest binding, changed bytes/hash, wrong path, absolute/traversal paths, wrong operation/case and superseded case IDs. No inference that valid bytes are a decodable movie or independently reviewed content.

Validation: all15 test_release_audit controls passed (including full103-row synthetic release validation and existing source/production guards). New media tests cover absent manifest/file/path, wrong SHA/changed bytes, same bytes at unmanifested path, absolute/traversal paths, other operation, superseded case and omitted second take. No decodability or actual visual assessment is inferred.
