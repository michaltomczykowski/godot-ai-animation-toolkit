# Strafe and jump measured completion

2026-10-15, implementation scope of release-completion-plan. Human review is
waived; independent recorded assessment and played numerical checks remain.

## Baseline and fixed scope

Preserve all16 Responsive strafe public clips/96 native runs and16 jump public
clips (stationary/forward0.5m, both extraction flags, four rigs). First strafe
clean movie exposes raised Z-up arms; jump diagnostics expose unreported solve
clamps and rapid arm reversal (~88deg in0.1s) at takeoff. Preserve all failed
checks and full continuous baselines. Do not replace accepted gait fixtures.

## Strafe

Add independent motion-specific Responsive/Grounded upper-body profiles,
decorated by existing style multipliers. Use measured rig-up arm lowering,
restrained torso/head articulation and forearm/wrist/finger follow-through.
Keep support/root/foot schedules intact unless played checks demonstrate a bug.
Qualify both directions/five styles/four rigs/two movement modes (80clips,
480native Player/Tree/FPS runs). In-place uses exactly one external driver.
Timing checks compute expected root trajectory from native saved interpolation,
not speed*time for a partial nonlinear cycle. Bind cached checks to exact route,
checker and transitive helper hashes; preserve outdated checks unchanged.

## Jump

Use a reachable neutral pelvis and consistent feet/pelvis motion through
anticipation, takeoff, flight, landing absorption and recovery. A world-unit
ballistic vertical flight at9.81m/s2 gives flight time2sqrt(2*height/9.81).
Omitted standalone duration is max(1s,flight/0.55); explicit durations remain
exact and refuse if flight exceeds68% of the requested clip. The intentional
setup wrapper duration1.2s remains explicit. Flight needs at least four authored
intervals. Reject nonpositive heights rather than report an inert jump.

Takeoff at22% of clip; landing is takeoff+flight time. Hermite ground push-off
and landing absorption match ballistic endpoint vertical velocity. Feet follow
pelvis rise with a small bounded airborne tuck, so the leg solve stays reachable;
contacts remain anchored before takeoff/after landing. Count every solve/clamp
and refuse unreachable geometry before commit. Report contact windows, physical
flight events, ownership, timing and reach evaluation. Shared contact events use
the same saved marker name for both feet; no coincident-marker overwrites.

Reduce implicit arm swing and spread its reversal across takeoff/flight rather
than forcing88deg through0.1s. Use measured rig axes and coordinate parents.
Explicit amplitude controls remain exact; no threshold widening hides failures.
Rooted forward jumps have one actor carrier; unextracted dedicated forward jumps
retain skeletal travel with no added controller displacement. Setup's nonzero
forward unextracted jump is refused because OneShot fade would erase displacement.

## Qualification

Play saved clips at30/60/120FPS via Player/Tree: stance slide<=min(2%leg,3cm),
penetration<=1%leg, no clamps/knee flips/nonfinite output, correct endpoint and
contact timing. Report frame velocity and rotation changes in world units and
localize extreme steps; a velocity bound alone is not continuity proof.
Corruption controls must fail doubled/reversed travel, contact loss/shift,
stance movement, inert output and knee discontinuities. Capture continuous
fixed-camera front/side clean/diagnostic MP4s, assess timing/body response and
recovery, run relevant full/public regression and preserve protected outputs.
