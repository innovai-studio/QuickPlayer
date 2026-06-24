# Stem Separation Feasibility Spike (htdemucs_ft)

Date: 2026-05-25. Goal: measure Demucs timing/quality on desktop and
decide the v2.0 on-device path. Background + rationale in the
`moises-competitor-analysis` notes — stem separation is the one feature
Reddit users actually pay Moises for, so it's the intended first paid
hook.

## Setup

- Machine: i7-8750H (6c/12t), 31 GB RAM, **RTX 2060 Mobile 6 GB**, Ubuntu.
- Isolated venv (`stem_spike/`, git-ignored), `torch 2.5.1+cu121`,
  `demucs 4.0.1`, ffmpeg 6.1.
- Test track: `~/Music/MERs.mp3`, **6:10** (370 s), 128 kbps. Note this
  is *longer* than Moises' 5-min free cap — a real-world case Moises
  free truncates.

## Measured results

| Config | Model | Device | Wall clock | Mem peak |
|--------|-------|--------|-----------|----------|
| Best quality | htdemucs_ft (bag of 4) | RTX 2060 | **2:04** (124 s) | 1.6 GB VRAM |
| Mobile proxy | htdemucs (single) | CPU (12t) | **3:58** (238 s) | 2.4 GB RAM |

- GPU is ~3x realtime even with the 4x bag. VRAM 1.6 GB → runs on a 4 GB
  card. A cloud T4/L4 would do this song in well under 2 min.
- Single-model CPU = 238 s for 370 s audio ≈ **0.64x realtime** on a
  decent x86 desktop CPU.

## Quality (objective sanity check; subjective audition pending)

All 4 stems non-silent and spectrally distinct:

| Stem | full mean | <250 Hz mean | reading |
|------|-----------|--------------|---------|
| bass | −23.9 dB | −24.3 dB | energy concentrated low (−0.4 dB) ✓ |
| vocals | −22.3 dB | −28.4 dB | mostly mid/high (−6.1 dB drop) ✓ |
| drums | −23.2 dB | −23.9 dB | broadband (kick + snare/hat) ✓ |

Separation is genuinely working. Stems copied to `~/Music/MERs_stems/`
for listening — final quality call is the user's ears.

## Model sizes (the mobile bundling math)

- Each Demucs model: **80 MB fp32**.
- `htdemucs_ft` = 4 fine-tuned models = **320 MB** → too big to bundle.
- Single `htdemucs` = **80 MB** fp32 → ~40 MB fp16 → ~20 MB int8.
- Mobile ships the single model, accepting slightly lower SDR than the
  bag.

## Mobile extrapolation

The Pixel 3 XL test device (Snapdragon 845, 2018) and typical mid-range
ARM CPUs run this kind of multithreaded NN inference roughly **2–4x
slower** than this i7. So single-model, pure-CPU:

- Mid-range phone: ~238 s × 3 ≈ **8–14 min** for a 6-min song.
- Flagship CPU: maybe ~5–8 min.

Pure-CPU foreground is a non-starter UX-wise; it's only acceptable as a
**backgrounded job** (foreground service + notification progress +
permanent cache), which is exactly what the research said users want
("split once, cached forever", "don't make me keep the app open").

### Accelerator options (ranked by effort/payoff)

1. **On-device CPU, backgrounded, single model + int8** — lowest risk,
   ships first. Honest progress bar, foreground service (we already have
   the just_audio_background plumbing). Slow but private, no backend
   cost, no length cap. int8 may claw back ~2x but Demucs is a hybrid
   time/spectral net (STFT/ISTFT + LSTM) — quantizing cleanly is fiddly
   and costs some SDR.
2. **NNAPI / GPU-delegate (TFLite) or vendor NPU** — flagship phones
   could hit ~1–3 min. But Demucs → TFLite conversion is hard (custom
   ops, complex graph). High engineering risk; treat as a later
   optimization with CPU fallback, not the MVP.
3. **Cloud GPU** — 124 s on a ~$0.50/hr GPU ≈ **$0.017/song**, trivially
   cheap, fast. BUT it breaks the "100% local, no upload" differentiator
   that the Reddit research flagged as the privacy wedge vs Moises. Keep
   as an optional opt-in "fast cloud mode" at most, never the default.

## Recommendation for v2.0

Ship **on-device, single `htdemucs`, int8 where it survives quality,
run as a backgrounded foreground-service job with a real progress bar
and a permanent per-track stem cache.** Lead the store copy with the
three things Moises users complain about: no length cap, no upload,
no silent failures. Defer NNAPI/NPU acceleration to a fast-follow once
the CPU path proves the funnel.

Open questions before committing engineering:
- Convert htdemucs to ONNX Runtime Mobile vs TFLite — which handles the
  STFT/LSTM graph with least custom-op pain? (next spike)
- int8 quality delta on real songs (measure SDR vs fp32).
- Stem cache format: 4× WAV is ~250 MB/song (way too big) — store as
  Opus/AAC (~10–15 MB/song total) and decode on playback.
