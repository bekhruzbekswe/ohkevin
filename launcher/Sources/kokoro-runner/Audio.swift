import Foundation

// kokoro_onnx/trim.py, which is librosa 0.11's effects.trim as kokoro-onnx 0.5.0 extracted it, with its defaults:
// top_db=60, ref=np.max, frame_length=2048, hop_length=512, centred RMS frames.

/// numpy's pairwise summation (float32), what np.mean uses along an axis.
private func pairwise(_ a: UnsafePointer<Float>, _ n: Int) -> Float {
    if n < 8 { var r: Float = 0; for i in 0..<n { r += a[i] }; return r }
    if n <= 128 {
        var r = (0..<8).map { a[$0] }
        var i = 8
        while i < n - n % 8 { for j in 0..<8 { r[j] += a[i + j] }; i += 8 }
        var res = ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]))
        while i < n { res += a[i]; i += 1 }
        return res
    }
    var half = n / 2
    half -= half % 8
    return pairwise(a, half) + pairwise(a + half, n - half)
}

func trim(_ y: [Float]) -> [Float] {
    let frameLength = 2048, hop = 512, topDb: Float = 60
    var padded = [Float](repeating: 0, count: frameLength / 2) + y
    padded += [Float](repeating: 0, count: frameLength / 2)
    let frames = (padded.count - frameLength) / hop + 1
    var rms = [Float](repeating: 0, count: frames)
    padded.withUnsafeBufferPointer { p in
        var sq = [Float](repeating: 0, count: frameLength)
        for f in 0..<frames {
            for i in 0..<frameLength { let v = p[f * hop + i]; sq[i] = v * v }
            rms[f] = (sq.withUnsafeBufferPointer { pairwise($0.baseAddress!, frameLength) } / Float(frameLength)).squareRoot()
        }
    }
    // amplitude_to_db(ref=np.max, amin=1e-5, top_db=None): power_to_db(rms**2, ref=max**2, amin=1e-10)
    let amin = Float(1e-5 * 1e-5), top = rms.max() ?? 0
    let reference = 10 * log10f(max(amin, top * top))
    let nonSilent = rms.map { 10 * log10f(max(amin, $0 * $0)) - reference > -topDb }
    guard let first = nonSilent.firstIndex(of: true), let last = nonSilent.lastIndex(of: true) else { return [] }
    return Array(y[(first * hop)..<min(y.count, (last + 1) * hop)])
}

/// soundfile.write(path, samples, 24000): 16-bit PCM WAV, mono. libsndfile turns a float into a 32-bit integer (x * 2^31, rounded to
/// nearest even, clipped) and keeps its top 16 bits (an arithmetic shift, so a floor); checked sample for sample against soundfile.
func wav(_ samples: [Float], rate: Int = 24000) -> Data {
    var d = Data()
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + samples.count * 2); d.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(samples.count * 2)
    for s in samples { u16(Int(UInt16(bitPattern: Int16(clamping: Int((s * 2147483648.0).rounded(.toNearestOrEven).clamped()) >> 16)))) }
    return d
}

private extension Float {
    /// into Int32's range, as a Double so the conversion cannot trap
    func clamped() -> Double { isNaN ? 0 : Swift.max(-2147483648, Swift.min(2147483647, Double(self))) }
}
