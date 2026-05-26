"""Static int8 quantization of the fp32 htdemucs ONNX, calibrated on
real audio segments. Per-channel, QDQ. Unlike dynamic quant (which was
both slower and broken), static calibration gives ORT real ranges."""
import sys, numpy as np
from onnxruntime.quantization import quantize_static, QuantType, CalibrationDataReader, QuantFormat

SEG = 343980
RAW = "/tmp/mers_44k.raw"
FP32 = "../../stem_spike/models/htdemucs_fp32.onnx"
OUT = sys.argv[1] if len(sys.argv) > 1 else "../../stem_spike/models/htdemucs_int8.onnx"

def load_segments(n_calib=10):
    a = np.fromfile(RAW, dtype=np.float32).reshape(-1, 2).T  # (2, N)
    segs = []
    for i in range(0, a.shape[1] - SEG, SEG):
        segs.append(a[:, i:i + SEG][None].astype(np.float32))  # (1,2,SEG)
        if len(segs) >= n_calib:
            break
    return segs

class Reader(CalibrationDataReader):
    def __init__(self, name, segs):
        self.name = name; self.it = iter(segs)
    def get_next(self):
        s = next(self.it, None)
        return None if s is None else {self.name: s}

import onnxruntime as ort
name = ort.InferenceSession(FP32, providers=["CPUExecutionProvider"]).get_inputs()[0].name
segs = load_segments(10)
print(f"calibrating on {len(segs)} real segments...")
quantize_static(
    FP32, OUT, Reader(name, segs),
    quant_format=QuantFormat.QDQ,
    per_channel=True,
    weight_type=QuantType.QInt8,
    activation_type=QuantType.QInt8,
)
import os
print(f"int8 written: {OUT}  {os.path.getsize(OUT)/1e6:.1f} MB (fp32 was {os.path.getsize(FP32)/1e6:.1f} MB)")
