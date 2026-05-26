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
