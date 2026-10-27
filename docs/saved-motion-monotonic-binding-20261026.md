# Correct Windows motion-evidence ordering

CI40346567647 (head e70d22c, actual tested merge44d3a8e15eb54b583f9c1d4fe4a75e1c03700c61)
fails only Windows/core4.3.0 live collection with `audit binding ambiguous`.
The original completed tool gates and raw traces are preserved privately at
ci-e70d22c-r001/windows-430-artifact. This is distinct from the Linux crash.

Actual audit and subsequent snapshot have equal wall-clock time_ns
1793027583914539200. Their recorded execution_ns values are301822869900 and
301823712900, correctly ordered843000ns apart. Strict wall-clock inequality
incorrectly rejects the actual completed public call.

The saved-motion adapter now uses existing monotonic execution_ns for every
generation/save/witness/navigation/reload/audit interval. Both timestamp fields
must remain integers; no order predicate is removed. Twelve controls pass,
including equal/reversed wall clocks and rejection of nonincreasing monotonic
time. Historical reinterpretation now binds all30actual raw observations,
12within its scoped effect contract. No engine result, source or input changed.

Private monotonic-binding-diagnosis-r001.json SHA256:
c2f41982ea52f02d55895e8d956c4b59992016f49ce95b92477d64b60aee3389.
It retains original tested source and current observer hash. This diagnostic is
not a fresh candidate qualification; a new normal CI run remains required.
