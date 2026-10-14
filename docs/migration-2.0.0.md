# Migrating to 2.0.0

2.0.0 changes generation defaults. Existing Animation resources and saved clips
remain intact. Review regenerated motion before replacing clips in a project.
Omitted/default style resolves to Responsive; choose `grounded` explicitly for
that variant. Explicit timing and root-motion controls retain their contracts.

Use Godot 4.7.2 and a stable Godot AI release >=4.2.1. Qualification covers
Windows/Linux on released 4.2.1 and 4.3.0. Development main is advisory. Missing,
unreadable, malformed, prerelease or older core metadata produces a dependency
diagnostic and prevents registration. Enable the two plugins in either order.

Godot AI's Tools tab lists each family under **Custom tools (addon-registered)**.
Each checkbox applies immediately, persists in the project and controls discovery
and invocation. The native animation-domain checkbox controls core animation
tools; it is not a toolkit-wide suite selector. Eight families are promoted;
invoke `animation_sequence` and `animation_rig_modifiers` through `custom_manage`.

The supported motion scope is humanoid rigs on level surfaces. A skeleton clip
does not supply collision resolution or an actor controller. Assign exactly one
translation owner when consuming root motion. Rendered inspection needs rendering
support; headless calls return a typed refusal when rendering is unavailable.
Scene history and library/file effects have different Undo semantics. Consult
the operation inventory for each capability and contextual refusal.

Install by extracting the addon ZIP into a clean project's root. The archive
contains `addons/godot_ai_animation` and LICENSE, not the core addon, test fixtures,
models or review footage. Install Godot AI separately. Validate the checksum and
package manifest against the published source before enabling the addon.

This document describes the candidate contract. A version bump alone does not
mean release qualification or publication is complete.
