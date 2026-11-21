import COnnxRuntime
import Foundation

/// onnxruntime's C library (1.23.2), opened at run time; runs kokoro-v1.0.onnx on the CPU provider.
final class Ort {
    private let api: OrtApi
    private var env: OpaquePointer?
    private var session: OpaquePointer?
    private var memory: OpaquePointer?

    init(library: String, model: String, threads: Int) throws {
        guard let handle = dlopen(library, RTLD_NOW | RTLD_LOCAL) else { throw Fail(message: "failed to load onnxruntime: \(String(cString: dlerror()))") }
        guard let symbol = dlsym(handle, "OrtGetApiBase") else { throw Fail(message: "failed to load onnxruntime: no OrtGetApiBase") }
        let base = unsafeBitCast(symbol, to: (@convention(c) () -> UnsafePointer<OrtApiBase>?).self)()
        guard let found = base?.pointee.GetApi(UInt32(ORT_API_VERSION)) else { throw Fail(message: "onnxruntime does not offer API \(ORT_API_VERSION)") }
        api = found.pointee
        var options: OpaquePointer?
        try check(api.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "kokoro", &env))
        try check(api.CreateSessionOptions(&options))
        defer { api.ReleaseSessionOptions(options) }
        try check(api.SetIntraOpNumThreads(options, Int32(threads)))
        try check(api.CreateSession(env, model, options, &session))
        try check(api.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory))
    }

    private func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        let message = api.GetErrorMessage(status).map { String(cString: $0) } ?? "onnxruntime error"
        api.ReleaseStatus(status)
        throw Fail(message: message)
    }

    /// inputs tokens int64 [1,n], style float32 [1,256], speed float32 [1]; output audio float32 [samples]
    func run(tokens: [Int64], style: [Float], speed: Float) throws -> [Float] {
        var tokens = tokens, style = style, speed = speed
        var inputs: [OpaquePointer?] = [nil, nil, nil]
        defer { for v in inputs { api.ReleaseValue(v) } }
        var shapeTokens: [Int64] = [1, Int64(tokens.count)], shapeStyle: [Int64] = [1, 256], shapeSpeed: [Int64] = [1]
        try tokens.withUnsafeMutableBytes { try check(api.CreateTensorWithDataAsOrtValue(memory, $0.baseAddress, $0.count, &shapeTokens, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &inputs[0])) }
        try style.withUnsafeMutableBytes { try check(api.CreateTensorWithDataAsOrtValue(memory, $0.baseAddress, $0.count, &shapeStyle, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputs[1])) }
        try withUnsafeMutableBytes(of: &speed) { try check(api.CreateTensorWithDataAsOrtValue(memory, $0.baseAddress, $0.count, &shapeSpeed, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputs[2])) }
        var output: OpaquePointer?
        defer { api.ReleaseValue(output) }
        let names: [UnsafeMutablePointer<CChar>] = ["tokens", "style", "speed", "audio"].map { (word: String) in strdup(word)! }
        defer { for n in names { free(n) } }
        var inputNames: [UnsafePointer<CChar>?] = names[0..<3].map { UnsafePointer($0) }, outputNames: [UnsafePointer<CChar>?] = [UnsafePointer(names[3])]
        try check(api.Run(session, nil, &inputNames, &inputs, 3, &outputNames, 1, &output))
        var data: UnsafeMutableRawPointer?, info: OpaquePointer?, count = 0
        try check(api.GetTensorMutableData(output, &data))
        try check(api.GetTensorTypeAndShape(output, &info))
        defer { api.ReleaseTensorTypeAndShapeInfo(info) }
        try check(api.GetTensorShapeElementCount(info, &count))
        return Array(UnsafeBufferPointer(start: data!.assumingMemoryBound(to: Float.self), count: count))
    }
}
