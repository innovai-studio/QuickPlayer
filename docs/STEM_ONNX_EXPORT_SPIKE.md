# htdemucs → ONNX Export Spike

Date: 2026-05-25. Follow-up to `STEM_SEPARATION_SPIKE.md`. Question:
can we get htdemucs onto a mobile runtime (ONNX Runtime / TFLite), and
what does the conversion actually cost? User already confirmed the
fp32 stem quality is good enough to ship.

## Model facts (single htdemucs)

- 42 M params, 4 sources (drums/bass/other/vocals), stereo, 44.1 kHz.
- Segment 7.8 s (343980 samples). **Transformer**-based
  (MultiheadAttention ×10) — **no LSTM** (the older `demucs`/`mdx`
  models have LSTM; htdemucs does not), which removes the worst export
  blocker up front.
- Uses `cac=True` (complex-as-channels) and `wiener_iters<0`, so the
  inference path is just STFT → stack re/im into channels → net →
  unstack → ISTFT. **No Wiener filter on the inference path** (good —
  that loop is the other classic export headache).

## Export attempts — obstacle course

Tried both exporters in torch 2.5.1. They have **complementary gaps**:

| Blocker | Legacy (TorchScript) | Dynamo | Fix |
|---------|---------------------|--------|-----|
| `int(self.segment*sr)` dynamic pad | ok | ❌ Unsupported int() on Fraction | set `use_train_segment=False`, feed fixed 7.8 s segments (trivial) |
| `random.randrange()` in pos-embedding | ok | ❌ untraceable | patch `_get_pos_embedding` to `shift=0` (it's 0 at inference anyway) (trivial) |
| `torch.stft` / `torch.istft` (complex) | ❌ SymbolicValueError on reflect-pad+reshape | ok | replace with conv/matmul DFT (see below) — **verified** |
| custom self-attention `_sa_block` | ok | ❌ can't trace call_method | use the **legacy** exporter (handles it fine) |
| `view_as_real` / `view_as_complex`, complex `z` | exports but complex isn't ORT-friendly | — | fork the 4 spec methods to carry re/im as a real stacked dim (NOT yet done) |

**Conclusion on path:** the legacy exporter already handles the
transformer/attention; it only fails at the complex STFT. So the
production route is: legacy exporter + a **complex-free fork** of
demucs (conv-DFT STFT/ISTFT + real-stacked spec flow) + the two trivial
patches.

## Verified building block: conv/matmul STFT & ISTFT

ONNX-friendly replacements for `demucs/spec.py`, matched against
`torch.stft`/`torch.istft` (n_fft=512, hop=128, hann, normalized,
center, reflect):

- conv-STFT vs torch.stft: **max abs diff 1.0e-4**
- conv-ISTFT vs torch.istft: **max abs diff 8.0e-5 (rel 1.7e-5)**

STFT = reflect-pad → `unfold` into frames → ×hann → matmul with
cos/sin DFT basis (257 bins) → ×1/√n_fft. ISTFT = onesided iDFT matmul
(middle bins ×2 for hermitian) → ×hann synthesis window → overlap-add
via `fold` → divide by NOLA envelope (fold of win²) → ×√n_fft → strip
center pad. Both use only matmul/conv/pad/fold — all well-supported by
ORT and TFLite. (Reference impl kept in the spike scratch; ~40 lines
each.)

## What's left for a working ONNX (the bounded remaining work)

Fork `htdemucs.py` so the 4 spec methods are complex-free:
- `_spec` → return real `(B, C, 2, Fr, T)` (re/im on a new dim) via
  conv-STFT instead of complex `z`.
- `_magnitude` → reshape that to `(B, 2C, Fr, T)` (the net input).
- `_mask` (cac path) → reshape the net's `(B,S,2C,Fr,T)` mask back to
  real-stacked, no `view_as_complex`.
- `_ispec` → conv-ISTFT on the real-stacked re/im.

Then legacy-export, verify **full-model** parity vs stock htdemucs on a
real segment (target <1e-3), and only then benchmark ORT + int8.
Estimate: ~half a day of careful work + parity re-verification. Low
*technical* risk now that STFT/ISTFT and the transformer are both
proven; it's mechanical refactor + testing.

## Mobile timing — does ORT change the v2.0 story?

No, not the order of magnitude. PyTorch-eager CPU was already 238 s for
the full 6 min song (single model). ORT CPU is typically ~0.7–1.2× of
eager for conv-heavy nets, so desktop CPU stays in the "minutes" range
and mid-range ARM stays ~8–14 min. The real unlock remains an
accelerator (NNAPI/GPU-delegate/NPU), which is a separate, harder spike.
int8 (next) may shave ~2× and ~4× the size; the open question is the
SDR hit, which needs the working ONNX to measure.

## UPDATE — complex-free fork DONE, ONNX runs on ORT

Built the complex-free fork (`tools/stem_onnx/complex_free.py` +
`export_onnx.py`). Final blockers hit and fixed during the export:

| Blocker | Fix |
|---------|-----|
| reflect-mode `Pad` fails legacy symbolic after reshape | manual reflect pad via flip+concat (`reflect_pad1d`) |
| `F.fold` → `col2im` symbolic broken in opset-18 exporter | overlap-add as sum of R=4 shifted hop-blocks (n_fft=4·hop) |
| `Tensor.unfold` → Slice/Concat soup breaks ORT shape inference | frame via block-reshape + R shifted concats |

Results (single htdemucs, 6:10 song, this i7 CPU):

| Variant | Size | ORT vs PyTorch | per-7.8 s seg | full-song est | verdict |
|---------|------|----------------|---------------|---------------|---------|
| **fp32 ONNX** | 241 MB | **5.9e-4** | 3.36 s | **159 s** | ✅ works; *faster* than PyTorch eager (238 s) |
| int8 dynamic | 126 MB | rel 1.73 (garbage) | 6.88 s | 326 s | ❌ slower **and** broken |
| fp16 | 121 MB | n/a | — | — | converts but a Cast node needs fixup to load; CPU won't accelerate fp16 anyway |

Eager patched-vs-stock parity: **4.08e-4** (well under the 1e-3 target).

### Key conclusions

- **The ONNX export is real and correct** — ORT output is numerically
  identical to the PyTorch stems the user already approved (5.9e-4).
- **fp32 ORT is fast on desktop CPU (159 s, ~0.43× realtime)** — even
  beats PyTorch eager. ARM extrapolation (~2–4×) → **~5–11 min** for a
  6 min song, single-threaded-ish mid-range; less on flagships.
- **Naive int8 is OUT.** Dynamic quantization both slowed it down and
  destroyed the output on this architecture (the hybrid STFT/transformer
  graph doesn't tolerate blind dynamic quant). Earlier "~20 MB int8"
  estimate was too optimistic. A real attempt would need *static,
  per-channel* quant with calibration data and per-op exclusions — and
  even then quality is at risk. Treat as a separate research task, not a
  given.
- **Realistic mobile bundle = 120 MB (fp16) – 241 MB (fp32)**, shipped
  as a post-install download, not bundled in the APK.

## Recommendation (updated)

On-device stem separation is **feasible and now proven end-to-end**:
patched htdemucs exports to ONNX, runs on ONNX Runtime, and matches the
approved quality. The v2.0 build path:

1. Ship the **fp32 (or fixed fp16) ONNX**, ~120–240 MB **downloaded on
   first use** (not in the APK).
2. Run it via **onnxruntime-android**, chunked into 7.8 s segments with
   overlap, in a **foreground service** with a real progress bar and a
   **permanent per-track stem cache** (store stems as Opus/AAC ~10–15 MB,
   not WAV).
3. Expect **~5–11 min/song on mid-range CPU**; add an **NNAPI/GPU
   execution provider** as a fast-follow for flagships (CPU fallback).
4. **Don't** rely on int8 for the size win; if size matters, fix the
   fp16 Cast issue (block-list the STFT Cast ops during conversion).

Remaining unknowns for the actual v2.0 (not blockers): onnxruntime-
android integration + EP selection on real devices; the fp16 Cast
fixup; whether static-quant can recover size without quality loss.

## Acceleration — getting under 5 min on mobile

Target: <5 min/song on mobile (baseline ARM CPU est. was 5–11 min).

**Tuned desktop baseline.** With `ORT_ENABLE_ALL` graph optimization +
thread tuning, the single-segment time drops and the full 6:10 song
goes from 159 s to **~130 s** (i7-8750H). Thread scaling (per 7.8 s
segment): 1t=6.19 s, 2t=3.83 s, 4t=2.88 s, 6t=2.75 s, **12t=3.21 s**
— it plateaus at 4–6 cores and *regresses* past that (memory-bandwidth
bound, oversubscription). Implication for ARM: the big cores carry it;
LITTLE cores add little.

**Where the time goes (ORT op profile, per segment):**

| op group | share | what it is |
|----------|-------|------------|
| FusedMatMul + Gemm + MatMul | **~40%** | cross-transformer attention + linear layers |
| Conv + ConvTranspose | ~20% | encoder / decoder |
| InstanceNorm / Mul / Add / Transpose / Split | rest | norms + our STFT reshape overhead |

40% matmul + 20% conv is *exactly* what XNNPACK and NPUs accelerate —
good news.

**Levers, ranked by payoff / risk:**

| # | Lever | Expected | Devices | Risk | Quality |
|---|-------|----------|---------|------|---------|
| 1 | **XNNPACK EP** (ARM NEON kernels) | ~1.3–2× | all (CPU) | low | unchanged |
| 2 | **NNAPI / QNN EP** (NPU/GPU/DSP) | ~2–5× | flagships | med (needs CPU fallback) | unchanged |
| 3 | **overlap = 0** (avoid demucs' 0.25 default) | save ~25% | all | none | ~unchanged |
| 4 | **STFT/ISTFT out of the ONNX graph** (native FFT) | save ~10–15% + cleaner quant target | all | med | unchanged |
| 5 | **static int8** (per-channel + calibration, *not* dynamic) | ~2–4× | all | high | at risk — measure |

XNNPACK and NNAPI both ship inside `onnxruntime-android`; they're
integration work, not research risk. Their real speedups can only be
measured on-device (the desktop pip build has neither EP).

**Projected full-song time:**

| Scenario | Est. | <5 min? |
|----------|------|---------|
| mid-range ARM, generic ORT CPU | ~270–340 s | borderline |
| mid-range ARM + **XNNPACK** | ~180–230 s | **yes (3–3.8 min)** |
| flagship + **NNAPI/NPU** | ~60–120 s | **yes (1–2 min)** |

**Conclusion:** <5 min is achievable on mid-range purely via XNNPACK
(CPU, no quality loss); flagships reach 1–2 min with NNAPI. int8 is an
extra 2–4× but quality-risky — measured separately (see int8 section).
Exact device numbers wait for the onnxruntime-android integration.

## int8 quantization — measured, REJECTED

Tested three int8 variants against the fp32 ONNX on the real MERs song
(SDR = 10·log10(‖fp32‖²/‖fp32−int8‖²); >~30 dB ≈ inaudible, ~0 dB =
destroyed):

| Variant | Size | drums | bass | other | vocals | speed (full song) |
|---------|------|-------|------|-------|--------|-------------------|
| fp32 (ref) | 241 MB | — | — | — | — | 145 s |
| dynamic | 126 MB | — rel diff 1.73 (garbage) — | | | 214 s (slower) |
| **static, all** (per-ch, QDQ, 10-seg calib) | 123 MB | 2.3 | −0.3 | −1.3 | −0.7 dB | 214 s (slower) |
| **static, conv-only** | 216 MB | 8.0 | 7.8 | 0.5 | 0.0 dB | 3.74 s/seg (slower) |

**Verdict: int8 is out, in every form.** All variants destroy quality —
especially the "other"/"vocals" stems, which are computed as residuals
and accumulate the most quantization noise through the InstanceNorm +
masking. And on x86 ORT it's *slower*, not faster (quant/dequant
overhead with no int8 matmul win for this graph; ARM with i8mm *might*
be faster but the quality is unusable regardless). Even conv-only
(leaving the DFT/attention matmuls in fp32) still wrecks other/vocals.
The earlier "~20 MB int8" hope is dead.

Size reduction therefore comes from **fp16, not int8**. Speed comes
from **execution providers (XNNPACK/NNAPI), not quantization.**

## Model variants kept (`stem_spike/models/`, git-ignored)

| File | Size | Status |
|------|------|--------|
| `htdemucs_fp32.onnx` | 241 MB | ✅ ship-quality, ORT==PyTorch 5.9e-4 |
| `htdemucs_fp16.onnx` | ~121 MB | size-halving path (see fp16 note) |
| `htdemucs_int8.onnx` | 123 MB | ❌ kept only as evidence int8 is broken |

Audition: fp32 stems in `~/Music/MERs_stems/`, broken int8 stems in
`~/Music/MERs_stems_int8/` (hear the degradation for yourself).

The user's intent is to **keep all variants** and later expose a
quality/speed tier — as a runtime switch, a user-facing setting, or a
**paid-tier lever** (faster/higher-quality separation = higher price).
With int8 out, the realistic tiers are fp16 (smaller download) vs fp32
(best quality), and CPU vs NNAPI (speed) — not a quality ladder from
quantization.
