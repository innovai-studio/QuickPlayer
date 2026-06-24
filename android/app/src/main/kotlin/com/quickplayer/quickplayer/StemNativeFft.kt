package com.quickplayer.quickplayer

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Native FFT + STFT/iSTFT for v2.1 (STFT-out-of-graph) stem separation.
 *
 * Replaces the matmul-DFT that used to live inside the ONNX graph. The
 * spec/audio functions must EXACTLY replicate complex_free.py's _spec
 * and _ispec (verified via desktop parity vs torch.stft to ~1e-4), so
 * the ONNX model — exported with the matching v2.1 forward — gets the
 * same numeric input/output it would have computed internally.
 *
 * Layout: spec is laid out as flat float [B, C, Fr, T, 2] in row-major
 * order (last dim is re/im pair) so it maps directly to the ONNX input
 * tensor shape (1, 2, 2048, T, 2) with no extra copy.
 */

/** In-place radix-2 Cooley-Tukey FFT. Precomputes twiddle tables once. */
class Fft(private val n: Int) {
    init { require(n > 0 && (n and (n - 1)) == 0) { "FFT size must be power of 2, got $n" } }

    // Twiddle: cos/sin for e^{-j 2π k / n}, k = 0..n/2-1.
    private val cosT = FloatArray(n / 2) { cos(-2.0 * PI * it / n).toFloat() }
    private val sinT = FloatArray(n / 2) { sin(-2.0 * PI * it / n).toFloat() }

    fun forward(re: FloatArray, im: FloatArray) {
        require(re.size == n && im.size == n)
        // Bit-reversal permutation.
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                val tr = re[i]; re[i] = re[j]; re[j] = tr
                val ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        // Butterflies.
        var size = 2
        while (size <= n) {
            val half = size shr 1
            val step = n / size
            var i = 0
            while (i < n) {
                var k = 0
                for (jj in i until i + half) {
                    val ai = jj + half
                    val tr = re[ai] * cosT[k] - im[ai] * sinT[k]
                    val ti = re[ai] * sinT[k] + im[ai] * cosT[k]
                    re[ai] = re[jj] - tr; im[ai] = im[jj] - ti
                    re[jj] = re[jj] + tr; im[jj] = im[jj] + ti
                    k += step
                }
                i += size
            }
            size = size shl 1
        }
    }

    /** Inverse via conjugate-forward-conjugate-scale. Operates in-place. */
    fun inverse(re: FloatArray, im: FloatArray) {
        require(re.size == n && im.size == n)
        for (i in 0 until n) im[i] = -im[i]
        forward(re, im)
        val inv = 1.0f / n
        for (i in 0 until n) { re[i] *= inv; im[i] = -im[i] * inv }
    }
}

/** STFT/iSTFT helpers mirroring complex_free.py _spec / _ispec exactly. */
object SpecOps {

    /** Reflect-pad an array by (left, right) using torch's reflect semantics
     *  (boundary sample excluded). */
    fun reflectPad1d(x: FloatArray, left: Int, right: Int): FloatArray {
        val out = FloatArray(left + x.size + right)
        for (i in 0 until left) out[i] = x[left - i]   // x[1..left] reversed (boundary excluded)
        for (i in x.indices)    out[left + i] = x[i]
        for (i in 0 until right) out[left + x.size + i] = x[x.size - 2 - i]
        return out
    }

    // PyTorch's torch.hann_window default is PERIODIC (divides by n, not n-1).
    // Matching this is critical for parity with the model's expected STFT.
    private fun hannWindow(n: Int): FloatArray =
        FloatArray(n) { 0.5f * (1f - cos(2.0 * PI * it / n).toFloat()) }

    /** Match _spec(mix) in complex_free.py:
     *   reflect_pad1d(x, pad, pad + le*hl - L) where pad = hl*3/2, le = ceil(L/hl);
     *   conv_spectro (center pad nFft/2 reflect, hann, normalized);
     *   drop last freq bin, crop 2 frames each side.
     *
     * @param mix  (C, L) planar audio
     * @return flat (C, Fr=nFft/2, T, 2) row-major float array + (Fr, T) shape
     */
    data class Spec(val data: FloatArray, val c: Int, val fr: Int, val t: Int)

    fun stft(mix: Array<FloatArray>, nFft: Int, hop: Int): Spec {
        val C = mix.size
        val L = mix[0].size
        val le = (L + hop - 1) / hop                              // ceil(L / hop)
        val outerLeft = hop * 3 / 2                               // 1536 for hop=1024
        val outerRight = outerLeft + le * hop - L                 // 1536 when le*hop==L
        val win = hannWindow(nFft)
        val scale = 1.0f / sqrt(nFft.toFloat())
        val fft = Fft(nFft)
        val centerPad = nFft / 2                                  // 2048

        // After outer + center pad, frame count produced by STFT:
        val paddedLen = L + outerLeft + outerRight + 2 * centerPad
        val nFramesRaw = (paddedLen - nFft) / hop + 1             // before cropping 2 each side
        val tOut = nFramesRaw - 4                                  // crop 2 each side
        val frOut = nFft / 2                                       // drop last freq bin -> nFft/2

        val out = FloatArray(C * frOut * tOut * 2)
        val frameRe = FloatArray(nFft)
        val frameIm = FloatArray(nFft)

        for (c in 0 until C) {
            val outerPadded = reflectPad1d(mix[c], outerLeft, outerRight)
            val fullPadded = reflectPad1d(outerPadded, centerPad, centerPad)
            for (frame in 0 until nFramesRaw) {
                val start = frame * hop
                for (i in 0 until nFft) { frameRe[i] = fullPadded[start + i] * win[i]; frameIm[i] = 0f }
                fft.forward(frameRe, frameIm)
                if (frame < 2 || frame >= nFramesRaw - 2) continue
                val t = frame - 2
                // Layout: [c, k, t, reim] — index = ((c*frOut + k)*tOut + t)*2 + reim
                var base = ((c * frOut) * tOut + t) * 2
                val stride = tOut * 2
                for (k in 0 until frOut) {
                    out[base]     = frameRe[k] * scale
                    out[base + 1] = frameIm[k] * scale
                    base += stride
                }
            }
        }
        return Spec(out, C, frOut, tOut)
    }

    /** Match _ispec(z, length) in complex_free.py:
     *   pad last freq bin (Fr -> Fr+1), pad 2 frames each side (T -> T+4),
     *   conv_ispectro (overlap-add via shifted hop-blocks, NOLA divide),
     *   crop center padding (hl*3/2 each side, return length samples).
     *
     * @param zout flat (S, C, Fr, T, 2) for one batch — masked spec per (source, channel)
     * @return (S, C, length) planar audio
     */
    fun istft(zout: FloatArray, s: Int, c: Int, fr: Int, t: Int, nFft: Int, hop: Int, length: Int): Array<Array<FloatArray>> {
        val frPadded = fr + 1                                      // 2048 -> 2049 = nFft/2+1
        val tPadded = t + 4                                        // pad 2 each side
        val win = hannWindow(nFft)
        val winSq = FloatArray(nFft) { win[it] * win[it] }
        val fft = Fft(nFft)

        // Reconstruct length follows conv_ispectro: hop*ceil(length/hop) + 2*pad outer
        val outerLeft = hop * 3 / 2
        val le = (length + hop - 1) / hop
        val outerLen = hop * le + 2 * outerLeft                    // length passed to conv_ispectro

        // OLA buffer length = nFft + hop*(tPadded - 1)
        val olaLen = nFft + hop * (tPadded - 1)
        val frameRe = FloatArray(nFft)
        val frameIm = FloatArray(nFft)

        val out = Array(s) { Array(c) { FloatArray(length) } }

        for (src in 0 until s) {
            for (ch in 0 until c) {
                val ola = FloatArray(olaLen)
                val norm = FloatArray(olaLen)
                for (tt in 0 until tPadded) {
                    // Pull the spec frame (with padding) into a complex nFft array
                    // using hermitian symmetry: frame[k] for k=0..fr (frPadded bins)
                    // frame[nFft-k] = conj(frame[k]) for k=1..nFft/2-1
                    for (i in 0 until nFft) { frameRe[i] = 0f; frameIm[i] = 0f }
                    if (tt in 2 until tPadded - 2) {
                        val tIn = tt - 2
                        // src,ch,k,tIn,reim — index = (((src*c + ch)*fr + k)*t + tIn)*2 + reim
                        var base = (((src * c + ch) * fr) * t + tIn) * 2
                        val stride = t * 2
                        for (k in 0 until fr) {
                            frameRe[k] = zout[base]
                            frameIm[k] = zout[base + 1]
                            base += stride
                        }
                        // frame[fr] (Nyquist) stays 0 from the padding step.
                        // Hermitian mirror for k = fr+1..nFft-1: frame[nFft-k] = conj(frame[k])
                        for (k in 1 until fr) {
                            frameRe[nFft - k] = frameRe[k]
                            frameIm[nFft - k] = -frameIm[k]
                        }
                    }
                    fft.inverse(frameRe, frameIm)
                    // After iFFT, the real part is the time-domain frame.
                    // conv_ispectro multiplies by sqrt(n_fft) (undoes the
                    // normalized=True scale) and by the hann window.
                    val scale = sqrt(nFft.toFloat())
                    val base = tt * hop
                    for (i in 0 until nFft) {
                        val v = frameRe[i] * scale * win[i]
                        ola[base + i] += v
                        norm[base + i] += winSq[i]
                    }
                }
                // NOLA normalize + crop center padding (n_fft//2 each side
                // is implicit in conv_ispectro; then outerLeft crop on top).
                val centerPad = nFft / 2
                val totalCrop = centerPad + outerLeft
                for (i in 0 until length) {
                    val idx = totalCrop + i
                    out[src][ch][i] = ola[idx] / maxOf(norm[idx], 1e-8f)
                }
            }
        }
        return out
    }
}
