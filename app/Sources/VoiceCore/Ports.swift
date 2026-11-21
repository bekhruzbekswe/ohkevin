import Foundation

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
