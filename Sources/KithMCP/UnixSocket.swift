import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Minimal Unix domain sockets: the app listens, `kith-mcp` connects and relays stdio.
///
/// Why a relay. Claude Desktop starts MCP servers as child processes over stdio. A child
/// process that read EventKit itself would ask for Calendar access on behalf of whoever
/// launched it (Claude, or the Terminal), not Kith, and couldn't show a confirmation. So
/// the app owns the data, the permissions and the confirmations, and `kith-mcp` only
/// copies bytes between its stdio and the app's socket.
public enum UnixSocket {
    public enum Failure: Error, CustomStringConvertible {
        case system(String, Int32)
        case pathTooLong(String)

        public var description: String {
            switch self {
            case .system(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
            case .pathTooLong(let path): return "socket path is too long: \(path)"
            }
        }
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        return addr
    }

    static func makeSocket() throws -> Int32 {
        #if canImport(Darwin)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
            let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw Failure.system("socket", errno) }
        return fd
    }

    /// Creates a listening socket readable and writable only by the current user.
    public static func openListener(at path: String) throws -> Int32 {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let fd = try makeSocket()
        var addr = try address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw Failure.system("bind", e)
        }
        chmod(path, 0o600)
        #if canImport(Darwin)
            let listening = Darwin.listen(fd, 8)
        #else
            let listening = Glibc.listen(fd, 8)
        #endif
        guard listening == 0 else {
            let e = errno
            close(fd)
            throw Failure.system("listen", e)
        }
        return fd
    }

    public static func openConnection(to path: String) throws -> Int32 {
        let fd = try makeSocket()
        var addr = try address(path)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let e = errno
            close(fd)
            throw Failure.system("connect", e)
        }
        return fd
    }

    /// Blocks until a client connects. Returns nil once the listener is closed.
    public static func acceptConnection(_ listener: Int32) -> Int32? {
        while true {
            let fd = accept(listener, nil, nil)
            if fd >= 0 { return fd }
            if errno == EINTR { continue }
            return nil
        }
    }

    /// Copies bytes from one descriptor to another until end of file. Blocking.
    public static func pump(from source: Int32, to destination: Int32) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            if n <= 0 { return }
            var offset = 0
            while offset < n {
                let w = buffer.withUnsafeBytes { write(destination, $0.baseAddress! + offset, n - offset) }
                if w < 0, errno == EINTR { continue }
                if w <= 0 { return }
                offset += w
            }
        }
    }

    public static func shutdownWrites(_ fd: Int32) {
        #if canImport(Darwin)
            _ = shutdown(fd, SHUT_WR)
        #else
            _ = shutdown(fd, Int32(SHUT_WR))
        #endif
    }

    public static func closeDescriptor(_ fd: Int32) {
        close(fd)
    }
}
