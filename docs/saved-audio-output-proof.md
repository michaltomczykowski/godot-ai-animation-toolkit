# Saved audio output check (2026-10-16)

The preserved `animation_fx.audio_cue:new` scene has a native audio track on
`CuePlayer` (AudioStreamPlayer2D), time zero, no trims, and the saved 0.3-second
`tests/fixtures/cue.wav`. Its input SHA256 is
`7f2c69c8c6ec02433e08c8850492386af7f5ef5f921e13b46f7a532fbfa9be00`.
The test's original request and saved scene remain unchanged.

The first complete r005 capture passed native playing-state checks but its
actual 12-second stereo PCM was entirely zero. That failed output and its new
`audio-check.json` are preserved. The comparison renderer had isolated the scene
in a SubViewport without enabling positional audio processing. Godot's
[Viewport contract](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-property-audio-listener-enable-2d)
requires its 2D listener to be enabled. This was a capture harness defect;
no toolkit audio track, stream or player setting was changed.

The renderer now enables positional listeners for audio cases and records their
actual settings in every frame, across both fresh reset takes. The native
checker rejects missing listeners. `check_saved_audio.py` checks actual PCM,
independently comparing onset, duration, waveform/pitch, level consistency and
clipping against the input WAV. Silence, missing second cue, wrong pitch,
late cues and truncated movies are rejected by focused controls. Scope is this
untrimmed time-zero fixture; arbitrary cue timing/trimming is not inferred.

Fresh r006 capture uses Godot4.7.2/OpenGL, 720 complete1400x800 PNGs, two fresh
six-second takes, unchanged project.godot and safely removed owned override.
Native checks pass, with no engine errors. Actual recorded PCM48kHz/stereo32-bit:

| Take | Audible interval | Input waveform correlation | RMS |
| --- | --- | --- | --- |
| 1 | 0.020–0.320s | 0.999459708 | 0.120330496 |
| 2 | 6.025–6.315s | 0.999825385 | 0.120117029 |

Recorded WAV SHA256:
`682a3cad299b24497d7038df6c501abbf40998da758b44cefc2be5680fe21f0b`.
Private evidence: `E:/GodotAI-toolkit-release-2.0.0/20261014/effects/`, immutable
`plan-r006.json`, `candidate-r006-case15/{startup,native-observations,native-check,audio-check}.json`,
full PNG sequence, frame.wav and complete renderer/error logs.

The first native checker CLI invocation used obsolete positional arguments and
failed argument validation after capture; the corrected explicit CLI succeeded
without regenerating media. This does not convert earlier silent audio into a pass.
Movie encoding, decoded audio/video delivery and independent continuous visual
assessment remain separate. No human approval or release qualification is claimed.
