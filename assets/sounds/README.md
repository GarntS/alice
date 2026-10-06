# Notification chime

`notification.wav` is an original, synthesized chime created for Alice, licensed
under the project's GNU GPL v3 license (see ../../LICENSE). No sampled or third-party
audio is used.

It is 0.42 seconds of mono, 44.1 kHz, signed 16-bit PCM WAV. The signal combines
880 Hz and 1320 Hz sine waves (relative amplitudes 1 and 0.35), at 0.16 scale,
with a 15 ms attack, exponential decay `exp(-10*t)`, and 40 ms release.

The native binary embeds the file; installed playback requires no source tree.
