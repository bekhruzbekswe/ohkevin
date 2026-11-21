import Foundation

/// Runs a program to completion and returns its exit status and standard output, or nil if it could not start
/// or took longer than timeout (it is then killed). Output is read as it comes, so a chatty program cannot block.
public func run(_ program: URL, _ arguments: [String], environment: [String: String]? = nil, in folder: URL? = nil,
                timeout: TimeInterval = 10, until done: (@Sendable (Data) -> Bool)? = nil) -> (status: Int32, output: Data)? {
    let process = Process(), pipe = Pipe(), finished = DispatchSemaphore(value: 0)
    let output = Locked(Data())
    process.executableURL = program
    process.arguments = arguments
    if let environment { process.environment = environment }
    if let folder { process.currentDirectoryURL = folder }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        let enough = output.with { data -> Bool in
            data.append(chunk)
            return chunk.isEmpty || done?(data) == true
        }
        if enough { handle.readabilityHandler = nil; finished.signal() }
    }
    do { try process.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; return nil }
    guard finished.wait(timeout: .now() + timeout) == .success else {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) } // an interactive shell ignores SIGTERM
        return nil
    }
    if done != nil { return (0, output.with { $0 }) } // got what it needed; a shell's background jobs may keep the pipe open
    process.waitUntilExit()
    return (process.terminationStatus, output.with { $0 })
}

/// A value shared between threads.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func with<T>(_ body: (inout Value) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

/// A Mac app started from Finder gets a bare PATH. The user's own shell knows where Node and Claude Code live,
/// so the app asks it once, the way Terminal would start it, and gives the call server that environment.
public enum Shell {
    static let mark = "__CALL_ENV__"

    public static func environment(shell: String? = nil, timeout: TimeInterval = 10) -> [String: String]? {
        let shell = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = "printf %s \(mark); /usr/bin/env -0; printf %s \(mark)"
        let end = Data(mark.utf8)
        // -i and -l: interactive login, so every file Terminal reads (.zprofile and .zshrc both) is read.
        guard let result = run(URL(filePath: shell), ["-i", "-l", "-c", script], timeout: timeout,
                               until: { data in data.ranges(of: end).count >= 2 })
        else { return nil }
        return parse(result.output)
    }

    /// The variables between the two marks of `env -0` output; whatever the shell printed around them is ignored.
    public static func parse(_ data: Data) -> [String: String]? {
        let marks = data.ranges(of: Data(mark.utf8))
        guard marks.count >= 2 else { return nil }
        var env: [String: String] = [:]
        for entry in data[marks[0].upperBound..<marks[1].lowerBound].split(separator: 0) {
            guard let text = String(data: Data(entry), encoding: .utf8), let eq = text.firstIndex(of: "="), eq != text.startIndex else { continue }
            env[String(text[..<eq])] = String(text[text.index(after: eq)...])
        }
        return env.isEmpty ? nil : env
    }

    /// Used only when the shell cannot be asked: the places installers put node and claude.
    public static func fallback(home: URL, base: [String: String]) -> [String: String] {
        var env = base
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home.path)/.local/bin", "\(home.path)/.volta/bin",
                    "\(home.path)/.local/share/mise/shims", "\(home.path)/.asdf/shims"]
        env["PATH"] = (dirs + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return env
    }

    /// The first executable called name on PATH.
    public static func which(_ name: String, path: String?) -> URL? {
        for dir in (path ?? "").split(separator: ":") {
            let url = URL(filePath: String(dir)).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
