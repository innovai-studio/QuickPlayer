# stem_onnx — htdemucs → ONNX conversion

Spike tooling that exports the single `htdemucs` model to an
ONNX-Runtime-compatible `.onnx`. Findings + rationale in
[`docs/STEM_ONNX_EXPORT_SPIKE.md`](../../docs/STEM_ONNX_EXPORT_SPIKE.md).

## Files

- `complex_free.py` — inference-only, export-ready patches for htdemucs:
  conv/matmul STFT+ISTFT (replacing `torch.stft`/`istft`), real-stacked
  re/im flow (no complex tensors), manual reflect pad, unfold-free
  framing, fold-free overlap-add, and the two trivial patches
  (`use_train_segment=False`, fixed positional-embedding shift).
- `export_onnx.py` — applies the patches, exports at opset 18, and
  verifies ORT output matches PyTorch.

## Usage

Needs the spike venv (torch 2.5 + demucs 4 + onnx/onnxruntime/onnxscript):

```bash
# from repo root, with the spike venv
cd tools/stem_onnx
../../stem_spike/bin/python export_onnx.py htdemucs_cf.onnx
```

Expected: `ORT vs PyTorch: max abs diff ~6e-4`. The `.onnx` (~241 MB
fp32) is intentionally **not** committed — regenerate it with the
command above.

## Status

fp32 export works end-to-end and matches the approved stem quality.
int8 dynamic quant is a dead end (slower + broken); fp16 halves size
but needs a Cast-node fixup to load and isn't CPU-accelerated. See the
spike doc for the full table and the v2.0 build recommendation.
