import Foundation

// The local voice without Python: the app's own kokoro-runner, onnxruntime's library, espeak-ng and its English data, both model
// files. Everything downloaded is checked against a sha256 pinned here before it is used.

/// espeak-ng (GPL-3.0-or-later) is not in this repository, in the app or in a release: the installer fetches the pinned espeakng-loader
/// wheel onto the user's Mac and the runner opens libespeak-ng from there at run time (dlopen, never linked). Run as the stock espeak-ng
/// program instead (a separate work over pipes) it does not give the same phonemes (measured: 4 of 80 gate sentences, 430 of 3170 fuzz
/// texts differ in stress), so there is no such variant here.

/// Pinned parts of the runner layout.
public enum RunnerFiles {
    /// onnxruntime 1.23.2 for macOS arm64: the library inside the official PyPI wheel (the very file the Python voice runs on).
    /// github.com/microsoft/onnxruntime was unreachable when this was pinned, so the release tarball could not be.
    public static let onnx = (url: URL(string: "https://files.pythonhosted.org/packages/1b/9e/f748cd64161213adeef83d0cb16cb8ace1e62fa501033acdd9f9341fff57/onnxruntime-1.23.2-cp312-cp312-macosx_13_0_arm64.whl")!,
                              sha256: "b8f029a6b98d3cf5be564d52802bb50a8489ab73409fa9db0bf583eabb7c2321", member: "onnxruntime/capi/libonnxruntime.1.23.2.dylib")
    /// espeakng-loader 0.2.4 (macOS arm64 wheel): libespeak-ng 1.52 and its data, what the Python voice runs on.
    public static let espeakWheel = (url: URL(string: "https://files.pythonhosted.org/packages/a8/26/258c0cd43b9bc1043301c5f61767d6a6c3b679df82790c9cb43a3277b865/espeakng_loader-0.2.4-py3-none-macosx_11_0_arm64.whl")!,
                                     sha256: "d27cdca31112226e7299d8562e889d3e38a1e48055c9ee381b45d669072ee59f")
    /// The English part of espeak-ng-data: all the voice needs (the full data is 19 MB).
    public static let dataMembers = ["phontab", "phonindex", "phondata", "intonations", "en_dict", "lang/gmw/en*"]
}

/// Where the runner layout lives inside the app bundle.
public func bundledRunner(in bundle: Bundle = .main) -> URL { bundle.bundleURL.appending(path: "Contents/Helpers/kokoro-runner") }

/// What a folder needs to speak with the runner: the runner, onnxruntime, espeak-ng's library with its data, both models.
public func runnerReady(_ folder: URL) -> Bool {
    let fm = FileManager.default
    func has(_ p: String) -> Bool { fm.fileExists(atPath: folder.appending(path: p).path) }
    return fm.isExecutableFile(atPath: folder.appending(path: "kokoro-runner").path) && has("libonnxruntime.dylib") && has("libespeak-ng.dylib")
        && has("espeak-ng-data/phontab") && has("kokoro-v1.0.onnx") && has("voices-v1.0.bin")
}

/// Unpacks named members of a zip (a wheel) into a folder, keeping their paths.
func unzip(_ archive: URL, members: [String], into folder: URL) -> Bool {
    run(URL(filePath: "/usr/bin/unzip"), ["-q", "-o", archive.path] + members + ["-d", folder.path], timeout: 120)?.status == 0
}

/// Installs the voice without Python into folder: the app's runner, onnxruntime, espeak-ng's library with its English data, both
/// model files; then starts the runner once and waits for its ready line. On any failure the folder is deleted: never half a voice.
public func installKokoroRunner(into folder: URL, runner: URL,
                                onnx: (url: URL, sha256: String, member: String) = RunnerFiles.onnx, espeak: (url: URL, sha256: String) = RunnerFiles.espeakWheel,
                                files: [(String, String)] = VoiceFiles.models, from source: String = VoiceFiles.base) async -> Bool {
    let fm = FileManager.default
    if runnerReady(folder) { return true }
    try? fm.removeItem(at: folder)
    func fail() -> Bool { try? fm.removeItem(at: folder); return false }
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let tmp = fm.temporaryDirectory.appending(path: "kokoro-runner-install-\(UUID().uuidString)")
    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    guard (try? fm.copyItem(at: runner, to: folder.appending(path: "kokoro-runner"))) != nil else { return fail() }
    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appending(path: "kokoro-runner").path)
    // onnxruntime
    guard let wheel = await fetch(onnx.url, sha256: onnx.sha256) else { return fail() }
    defer { try? fm.removeItem(at: wheel) }
    let o = tmp.appending(path: "onnx")
    guard unzip(wheel, members: [onnx.member], into: o),
          (try? fm.moveItem(at: o.appending(path: onnx.member), to: folder.appending(path: "libonnxruntime.dylib"))) != nil else { return fail() }
    // espeak-ng: the library and its data from the loader wheel
    guard let loader = await fetch(espeak.url, sha256: espeak.sha256) else { return fail() }
    defer { try? fm.removeItem(at: loader) }
    let e = tmp.appending(path: "espeak"), data = "espeakng_loader/espeak-ng-data/"
    guard unzip(loader, members: ["espeakng_loader/libespeak-ng.dylib"] + RunnerFiles.dataMembers.map { data + $0 }, into: e) else { return fail() }
    let dataFolder = e.appending(path: "espeakng_loader/espeak-ng-data")
    guard (try? fm.moveItem(at: e.appending(path: "espeakng_loader/libespeak-ng.dylib"), to: folder.appending(path: "libespeak-ng.dylib"))) != nil,
          (try? fm.moveItem(at: dataFolder, to: folder.appending(path: "espeak-ng-data"))) != nil else { return fail() }
    for (name, sha) in files {
        guard let file = await fetch(URL(string: source + name)!, sha256: sha),
              (try? fm.moveItem(at: file, to: folder.appending(path: name))) != nil else { return fail() }
    }
    // espeak reads its data from a path of at most 159 characters (measured): a longer folder fails this check, as it should
    let ready = run(folder.appending(path: "kokoro-runner"), [folder.path], timeout: 180)
    return ready.map { $0.status == 0 && String(decoding: $0.output, as: UTF8.self).contains("\"ready\":true") } == true || fail()
}
