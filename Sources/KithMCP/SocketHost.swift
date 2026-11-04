import Foundation
import MCP

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// Runs inside the Kith app: listens on a Unix socket and starts one MCP server per
/// connection from `kith-mcp`.
public final class SocketHost: @unchecked Sendable {
    public let path: String
    private let service: MCPService
    private let lock = NSLock()
    private var listener: Int32 = -1

    public init(path: String = SocketHost.defaultPath, service: MCPService) {
        self.path = path
        self.service = service
    }

    /// `~/Library/Application Support/Kith/mcp.sock` on macOS; `$TMPDIR/kith/mcp.sock` elsewhere.
    public static var defaultPath: String {
        #if os(macOS)
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base.appendingPathComponent("Kith/mcp.sock").path
        #else
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("kith/mcp.sock")
        #endif
    }

    public func start() throws {
        let fd = try UnixSocket.openListener(at: path)
        lock.lock()
        listener = fd
        lock.unlock()
        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "kith.mcp.accept"
        thread.start()
    }

    public func stop() {
        lock.lock()
        let fd = listener
        listener = -1
        lock.unlock()
        if fd >= 0 { UnixSocket.closeDescriptor(fd) }
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while let connection = UnixSocket.acceptConnection(fd) {
            let service = self.service
            Task.detached {
                await Self.serve(connection, service: service)
            }
        }
    }

    static func serve(_ fd: Int32, service: MCPService) async {
        let descriptor = FileDescriptor(rawValue: fd)
        let transport = StdioTransport(input: descriptor, output: descriptor)
        do {
            let server = try await service.serve(transport: transport)
            await server.waitUntilCompleted()
            await server.stop()
        } catch {
            // A client that disconnects mid-handshake is not an error worth surfacing.
        }
        UnixSocket.closeDescriptor(fd)
    }
}
