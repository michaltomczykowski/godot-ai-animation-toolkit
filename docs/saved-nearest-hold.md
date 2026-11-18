# Exact saved nearest-interpolation representative

The preserved `animation_edit.set_interp` representative is a one-second
linear loop with two position keys (0→100), changed from linear to nearest
interpolation. Every sampled phase strictly below the final key holds 0; wrapping
does not make the redo target progress. The linear undo reference does progress.

The planner calls `saved_effect_contracts.apply_representative_contract(case)`
before appending each case. Only this exact operation/variant is marked with
the `nearest_two_key_loop_0_to_100_hold` contract and held-output expectation.
The checker still requires both native clocks, a moving undo reference, visible
undo/redo difference, held redo position 0 throughout both takes, and actual
saved track metadata: Character:position, value type, two t0/t1 keys 0→100,
one-second loop, linear undo and nearest redo. Missing/wrong metadata fails.
Other operations retain their progression requirement. No product key or
interpolation mode is changed to satisfy presentation.
