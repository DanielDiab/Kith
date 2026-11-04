import AgentCore
import Foundation
import KithMCP
import MCP
import PersonalData

/// kith-mcp: the command an MCP client launches.
///
///     kith-mcp                   relay stdio to the running Kith app (your data, confirmations in the app)
///     kith-mcp --demo            serve the synthetic week in-process; no app needed, writes are held and never run
///     kith-mcp --socket <path>   relay to a socket other than the default
///
/// Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json):
///
///     { "mcpServers": { "kith": { "command": "/path/to/kith-mcp" } } }
@main
struct KithMCPCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            print("usage: kith-mcp [--demo] [--socket <path>]")
            exit(0)
        }
        if arguments.contains("--demo") {
            await runDemo()
        }
        var path = SocketHost.defaultPath
        if let i = arguments.firstIndex(of: "--socket"), i + 1 < arguments.count {
            path = arguments[i + 1]
        }
        relay(to: path)
    }

    static func runDemo() async -> Never {
        let store = SyntheticData.store()
        let registry = ToolRegistry(PersonalTools.all(store: store, format: LocalFormat(timeZone: SyntheticData.timeZone)))
        let policy = PermissionPolicy.allowAll(registry.specs)
        let service = MCPService(
            registry: registry, policy: { policy }, pending: PendingWriteStore(), log: TraceLog(),
            knownNames: (try? await store.allContactNames()) ?? [])
        do {
            let server = try await service.serve(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            fail("\(error)")
        }
        exit(0)
    }

    /// stdin → app on a background thread; app → stdout here. Exits when the app closes the connection.
    static func relay(to path: String) -> Never {
        let fd: Int32
        do {
            fd = try UnixSocket.openConnection(to: path)
        } catch {
            fail("can't reach the Kith app at \(path) (\(error)). Open Kith and turn on MCP in Settings, or run with --demo.")
        }
        let upstream = Thread {
            UnixSocket.pump(from: 0, to: fd)
            UnixSocket.shutdownWrites(fd)
        }
        upstream.start()
        UnixSocket.pump(from: fd, to: 1)
        exit(0)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("kith-mcp: \(message)\n".utf8))
        exit(1)
    }
}
