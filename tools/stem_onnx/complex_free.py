"""Complex-free, ONNX-exportable patches for htdemucs (single model).

Replaces torch.stft/istft with conv/matmul DFT and carries re/im as a
real trailing dim so the whole graph is real-valued. Inference-only:
also disables use_train_segment (feed fixed 7.8s segments) and the
random positional-embedding shift (no-op at eval). See
docs/STEM_ONNX_EXPORT_SPIKE.md.
"""
import math, types
import torch
import torch.nn.functional as F
from demucs.transformer import create_sin_embedding


def reflect_pad1d(x, left, right):
    """torch reflect-pad semantics (excludes the boundary sample), built
    from flip+concat so the legacy ONNX exporter can trace it -- its
    reflect-mode Pad op fails symbolic shape inference after a reshape."""
    parts = []
    if left > 0:
        parts.append(x[..., 1:left + 1].flip(-1))
    parts.append(x)
    if right > 0:
        parts.append(x[..., -right - 1:-1].flip(-1))
    return torch.cat(parts, dim=-1)


def _dft_bases(n_fft, device, dtype):
    k = torch.arange(n_fft, device=device, dtype=dtype)
    f = torch.arange(n_fft // 2 + 1, device=device, dtype=dtype).unsqueeze(1)
    ang = -2 * math.pi * f * k / n_fft
    return torch.cos(ang), torch.sin(ang)            # (F, n_fft) each


def conv_spectro(x, n_fft, hop):
    """Match torch.stft(normalized=True, center=True, reflect). Returns
    (re, im) of shape (..., F, frames)."""
    *other, length = x.shape
    x = x.reshape(-1, length)
    win = torch.hann_window(n_fft, device=x.device, dtype=x.dtype)
    pad = n_fft // 2
    xp = reflect_pad1d(x, pad, pad)                    # (B, Lp)
    # Frame without Tensor.unfold (it exports to a Slice/Concat soup that
    # breaks ORT shape inference). n_fft == R*hop, so a frame is R
    # consecutive hop-blocks; build frames by reshaping into hop-blocks
    # and concatenating R shifted views.
    b, Lp = xp.shape
    R = n_fft // hop
    nblocks = Lp // hop
    blocks = xp[:, :nblocks * hop].reshape(b, nblocks, hop)
    nframes = nblocks - R + 1
    frames = torch.cat([blocks[:, r:r + nframes, :] for r in range(R)], dim=-1)  # (b,nframes,n_fft)
    frames = frames * win
    cos_b, sin_b = _dft_bases(n_fft, x.device, x.dtype)
    scale = 1.0 / math.sqrt(n_fft)
    re = (frames @ cos_b.T) * scale                   # (B, T, F)
    im = (frames @ sin_b.T) * scale
    Fdim, T = re.shape[-1], re.shape[-2]
    re = re.transpose(1, 2).reshape(*other, Fdim, T)
    im = im.transpose(1, 2).reshape(*other, Fdim, T)
    return re, im


def conv_ispectro(re, im, hop, length):
    """Match torch.istft(normalized=True, center=True). re/im (..., F, frames)."""
    *other, Fdim, T = re.shape
    n_fft = 2 * Fdim - 2
    re = re.reshape(-1, Fdim, T)
    im = im.reshape(-1, Fdim, T)
    win = torch.hann_window(n_fft, device=re.device, dtype=re.dtype)
    n = torch.arange(n_fft, device=re.device, dtype=re.dtype)
    k = torch.arange(Fdim, device=re.device, dtype=re.dtype).unsqueeze(1)
    w2 = torch.ones(Fdim, device=re.device, dtype=re.dtype); w2[1:-1] = 2.0
    icos = w2.unsqueeze(1) * torch.cos(2 * math.pi * k * n / n_fft)   # (F, n_fft)
    isin = w2.unsqueeze(1) * torch.sin(2 * math.pi * k * n / n_fft)
    scale = math.sqrt(n_fft)
    frames = (re.transpose(1, 2) @ icos - im.transpose(1, 2) @ isin) / n_fft * scale
    frames = frames * win                              # (B, T, n_fft)
    # Overlap-add. n_fft is an exact integer multiple of hop for htdemucs
    # (the _spec assert: hop == n_fft//4), so OLA is a sum of R shifted
    # sub-blocks -- pure reshape/pad/add, no F.fold (its col2im symbolic
    # is broken in the opset-18 exporter) and no giant identity kernel.
    R = n_fft // hop
    nblocks = T + R - 1

    def _ola(fr):                                      # fr: (b, T, n_fft)
        b = fr.shape[0]
        sub = fr.reshape(b, T, R, hop)
        acc = 0
        for r in range(R):
            seg = sub[:, :, r, :]                      # (b, T, hop)
            seg = F.pad(seg, (0, 0, r, R - 1 - r))     # pad T dim -> (b, nblocks, hop)
            acc = seg if r == 0 else acc + seg
        return acc.reshape(b, nblocks * hop)

    y = _ola(frames)
    win_sq = (win ** 2).unsqueeze(0).expand(T, n_fft).unsqueeze(0)   # (1, T, n_fft)
    norm = _ola(win_sq).reshape(-1)                    # (out_len,)
    y = y / norm.clamp_min(1e-8)
    pad = n_fft // 2
    y = y[:, pad:pad + length]
    return y.reshape(*other, length)


def patch(model):
    """Patch a single HTDemucs in place to be complex-free + export-ready."""
    model.use_train_segment = False

    # --- pos embedding: kill random shift (0 at inference) ---
    ct = model.crosstransformer
    def _pos(self, T, B, C, device):
        return create_sin_embedding(T, C, shift=0, device=device, max_period=self.max_period)
    ct._get_pos_embedding = types.MethodType(_pos, ct)

    # --- _spec: complex z -> real-stacked (B, C, Fr, T, 2) ---
    def _spec(self, x):
        hl, nfft = self.hop_length, self.nfft
        le = int(math.ceil(x.shape[-1] / hl))
        pad = hl // 2 * 3
        x = reflect_pad1d(x, pad, pad + le * hl - x.shape[-1])
        re, im = conv_spectro(x, nfft, hl)
        re, im = re[..., :-1, :], im[..., :-1, :]      # drop last freq bin
        re, im = re[..., 2:2 + le], im[..., 2:2 + le]  # drop 2 frames each side
        return torch.stack([re, im], dim=-1)           # (B, C, Fr, T, 2)

    def _magnitude(self, z):                            # z real-stacked
        B, C, Fr, T, _ = z.shape
        m = z.permute(0, 1, 4, 2, 3).reshape(B, C * 2, Fr, T)
        return m

    def _mask(self, z, m):                              # returns real-stacked
        B, S, C2, Fr, T = m.shape
        out = m.view(B, S, -1, 2, Fr, T).permute(0, 1, 2, 4, 5, 3)  # (B,S,C,Fr,T,2)
        return out.contiguous()

    def _ispec(self, z, length=None):                   # z real-stacked (...,Fr,T,2)
        hl = self.hop_length
        re, im = z[..., 0], z[..., 1]                   # (B,S,C,Fr,T)
        re = F.pad(re, (0, 0, 0, 1)); im = F.pad(im, (0, 0, 0, 1))   # +1 freq bin
        re = F.pad(re, (2, 2)); im = F.pad(im, (2, 2))               # +2 frames each side
        pad = hl // 2 * 3
        le = hl * int(math.ceil(length / hl)) + 2 * pad
        x = conv_ispectro(re, im, hl, length=le)
        x = x[..., pad:pad + length]
        return x

    model._spec = types.MethodType(_spec, model)
    model._magnitude = types.MethodType(_magnitude, model)
    model._mask = types.MethodType(_mask, model)
    model._ispec = types.MethodType(_ispec, model)
    return model
