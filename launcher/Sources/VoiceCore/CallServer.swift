import Foundation

/// One running call server: `node server.mjs <project>`, its output in the log.
/// The launcher holds the write end of a pipe on the server's stdin and never writes to it. If the launcher crashes or is
/// force-quit, the system closes that pipe, the server reads the end of its input and hangs up (server.mjs, CALL_LAUNCHER).
public final class CallServer: @unchecked Sendable {
    public enum Ending: Sendable {
        /// Ctrl-C in a terminal: hang up and open the call's work in the Claude app.
        case handOver
        /// Hang up and keep the work for later; the log says how to open it.
        case plain
    }

    private let process = Process()
    private let input = Pipe()

    public init(node: URL, server: URL, project: URL, environment: [String: String], log: URL) throws {
        let out = try FileHandle(forWritingTo: log)
        out.seekToEndOfFile()
        process.executableURL = node
        process.arguments = [server.path, project.path]
        process.currentDirectoryURL = project
        process.environment = environment
        process.standardInput = input
        process.standardOutput = out
        process.standardError = out
    }

    public var pid: Int32 { process.processIdentifier }

    /// onExit gets the exit status; it runs on a background thread.
    public func start(onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
    }

    /// SIGINT or SIGTERM through Process, which never signals a process id that has already been reaped and reused.
    public func end(_ how: Ending) { how == .handOver ? process.interrupt() : process.terminate() }

    /// The last resort when it will not end: the server and everything it started.
    public func forceQuit() { for p in [pid] + descendants(of: pid) { kill(p, SIGKILL) } }
}

/// Every process started by pid, its children's children included.
public func descendants(of pid: Int32) -> [Int32] {
    var count = proc_listchildpids(pid, nil, 0)
    guard count > 0 else { return [] }
    var kids = [Int32](repeating: 0, count: Int(count) * 2)
    count = proc_listchildpids(pid, &kids, Int32(kids.count * MemoryLayout<Int32>.size))
    let direct = kids.prefix(Int(max(count, 0))).filter { $0 > 0 }
    return direct + direct.flatMap(descendants(of:))
}

/// Whether a process is still alive (a zombie waiting to be reaped counts as gone).
public func alive(_ pid: Int32) -> Bool {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    return size == Int32(MemoryLayout<proc_bsdinfo>.size) && info.pbi_status != UInt32(SZOMB)
}

/// The first port in range the call server could listen on.
public func freePort(in range: ClosedRange<Int>, isFree: (Int) -> Bool = portIsFree) -> Int? { range.first(where: isFree) }

/// Whether the call server could listen on port: binds it as Node does (address reuse on), then lets it go.
public func portIsFree(_ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(UInt16(port).bigEndian)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
    }
}

/// The call server's log: one file per call, the one before kept beside it. Only the user can read it: it holds the call's key.
public enum CallLog {
    public static func folder(home: URL) -> URL { home.appending(path: "Library/Logs/\(Product.folder)", directoryHint: .isDirectory) }
    public static func current(home: URL) -> URL { folder(home: home).appending(path: "call.log") }

    public static func fresh(home: URL) throws -> URL {
        let fm = FileManager.default, log = current(home: home)
        try fm.createDirectory(at: folder(home: home), withIntermediateDirectories: true)
        let previous = folder(home: home).appending(path: "call-previous.log")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: log, to: previous)
        guard fm.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: log.path])
        }
        return log
    }
}
