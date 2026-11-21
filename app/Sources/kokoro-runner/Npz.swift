import Foundation

/// voices-v1.0.bin: a numpy .npz (a zip of stored, uncompressed .npy arrays), each voice float32 [510, 1, 256]; read in place.
final class Npz {
    private let data: Data
    private var offsets: [String: Int] = [:]
    static let rows = 510, width = 256

    init(path: String) throws {
        data = try Data(contentsOf: URL(filePath: path), options: .alwaysMapped)
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard let end = (0...max(0, data.count - 22)).reversed().first(where: { u32($0) == 0x06054b50 }) else { throw Fail(message: "not a zip file") }
        var entry = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard u32(entry) == 0x02014b50, u16(entry + 10) == 0 else { throw Fail(message: "voices file: unsupported zip entry") }
            let nameLength = u16(entry + 28), extraLength = u16(entry + 30), commentLength = u16(entry + 32), local = u32(entry + 42)
            var name = String(decoding: data[(entry + 46)..<(entry + 46 + nameLength)], as: UTF8.self)
            if name.hasSuffix(".npy") { name.removeLast(4) }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let headerLength = data[start + 6] == 1 ? u16(start + 8) : u32(start + 8)
            let header = String(decoding: data[(start + 10)..<(start + 10 + headerLength)], as: UTF8.self)
            guard header.contains("'<f4'"), header.contains("'fortran_order': False"), header.contains("(\(Npz.rows), 1, \(Npz.width))") else { throw Fail(message: "voices file: unexpected array \(name)") }
            offsets[name] = start + (data[start + 6] == 1 ? 10 : 12) + headerLength
            entry += 46 + nameLength + extraLength + commentLength
        }
    }

    var names: [String] { offsets.keys.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) } }
    func has(_ name: String) -> Bool { offsets[name] != nil }

    /// voice[row]: the style vector for a sentence of `row` tokens
    func style(_ name: String, row: Int) -> [Float] {
        let from = offsets[name]! + row * Npz.width * 4
        return data[from..<(from + Npz.width * 4)].withUnsafeBytes { raw in (0..<Npz.width).map { Float(bitPattern: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)) } }
    }
}
