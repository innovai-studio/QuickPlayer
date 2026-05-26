"""Export htdemucs (single model) to an ONNX file runnable by ONNX Runtime.

    python export_onnx.py [out.onnx]

Applies the complex-free / export-ready patches from complex_free.py,
exports with the legacy exporter at opset 18, and verifies ORT output
matches PyTorch. Requires the spike venv (torch + demucs + onnx*).
See docs/STEM_ONNX_EXPORT_SPIKE.md for the why behind each patch.
"""
import sys, warnings, numpy as np, torch
warnings.filterwarnings("ignore")
from demucs.pretrained import get_model
import complex_free as cf

out = sys.argv[1] if len(sys.argv) > 1 else "htdemucs_cf.onnx"
model = cf.patch(get_model("htdemucs").models[0].eval())
seg = int(round(model.segment * model.samplerate))   # 7.8 s @ 44.1k
x = torch.randn(1, 2, seg)

torch.onnx.export(
    model, (x,), out,
    input_names=["mix"], output_names=["stems"],
    opset_version=18, do_constant_folding=True,
)

# Parity check vs PyTorch eager.
import onnxruntime as ort
sess = ort.InferenceSession(out, providers=["CPUExecutionProvider"])
y_ort = sess.run(None, {sess.get_inputs()[0].name: x.numpy()})[0]
with torch.no_grad():
    y_pt = model(x).numpy()
d = np.abs(y_pt - y_ort)
print(f"exported {out} | input {tuple(x.shape)} -> stems {tuple(y_ort.shape)}")
print(f"ORT vs PyTorch: max abs diff={d.max():.3e}  rel={d.max()/np.abs(y_pt).max():.3e}")
