"""Full-song stem separation via overlapping-segment + weighted overlap-add
(the P2 pipeline prototype). Runs the single htdemucs ONNX over the whole
song in segments with crossfade, so the user can judge real end-to-end
quality. Usage: fullsong_separate.py <model.onnx> <seg_samples> <outdir>"""
import sys, time, os, numpy as np, onnxruntime as ort, warnings
warnings.filterwarnings("ignore")

model, SEG, outdir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
SR, SRC = 44100, ["drums", "bass", "other", "vocals"]
audio = np.fromfile("/tmp/mers_44k.raw", dtype=np.float32).reshape(-1, 2).T  # (2, N)
N = audio.shape[1]

overlap = 0.25
stride = int(SEG * (1 - overlap))
# Triangular fade weight per segment so overlaps crossfade smoothly.
w = np.bartlett(SEG).astype(np.float32); w[w == 0] = 1e-3

so = ort.SessionOptions()
so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_BASIC
so.intra_op_num_threads = 6
sess = ort.InferenceSession(model, so, providers=["CPUExecutionProvider"])
name = sess.get_inputs()[0].name

out = np.zeros((4, 2, N), np.float32)
wsum = np.zeros(N, np.float32)
t0 = time.time(); pos = 0; nseg = 0
while pos < N:
    chunk = audio[:, pos:pos + SEG]
    L = chunk.shape[1]
    if L < SEG:
        chunk = np.pad(chunk, ((0, 0), (0, SEG - L)))
    y = sess.run(None, {name: chunk[None].astype(np.float32)})[0][0]  # (4,2,SEG)
    out[:, :, pos:pos + L] += (y[:, :, :L] * w[:L])
    wsum[pos:pos + L] += w[:L]
    pos += stride; nseg += 1
out /= np.maximum(wsum, 1e-6)
dt = time.time() - t0
print(f"separated {N/SR:.0f}s song in {dt:.0f}s ({nseg} segs @ {SEG/SR:.1f}s, {overlap:.0%} overlap)")

os.makedirs(outdir, exist_ok=True)
for i, nm in enumerate(SRC):
    out[i].T.astype(np.float32).tofile("/tmp/_fs.raw")
    os.system(f"ffmpeg -v error -y -f f32le -ar {SR} -ac 2 -i /tmp/_fs.raw {outdir}/{nm}.wav")
print("stems saved to", outdir)
