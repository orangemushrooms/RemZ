# Titan audio

Eight baked, mono, 44.1 kHz / 16-bit WAV effects. Generated with
`python tools/build_titan_audio.py`; no sound is synthesized during combat.

The voice layers derive from the user's existing `../zombie_1.mp3` through
`../zombie_4.mp3` recordings, combined with newly synthesized irregular vocal-fold
subharmonics, filtered breath, saturation and restrained outdoor reflections.
Their original recording rights/provenance continue to apply. No third-party
sound library or film/game sample was downloaded for these effects.

`step_1`, `step_2` and `slam` are wholly procedural soil/gravel impacts with
decaying low-frequency resonance. All files have click-free endpoints, no loop,
a 26 Hz high-pass and 3.5 dB of measured oversampled peak headroom.

The runtime mixes them through a dedicated compressor/limiter under the master
volume, uses 3D distance filtering and briefly lowers music for prominent cries.
The reproducible analysis is written to `artifacts/titan-horror/audio-report.json`.
