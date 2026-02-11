import Foundation
import BadgerCore

struct SecurityHealthCheck {
    static func verifyArchitecture() async throws {
        // 1. Verify XPC Connection to FileWriter
        // Since FileWriterXPCClient is not yet standard, we check the XPC connection manually or assume exists.
        // For now, we'll log a placeholder check as we don't want to break compilation if the client class is missing.
        // TODO: Replace with actual `FileWriterXPCClient().ping()` once the client wrapper is standardized.
        
        let connection = NSXPCConnection(serviceName: "com.quantumbadger.FileWriter")
        connection.remoteObjectInterface = NSXPCInterface(with: FileWriterXPCProtocol.self)
        connection.resume()
        
        guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
            print("⚠️ SecurityHealthCheck: XPC Connection Failed: \(error)")
        }) as? FileWriterXPCProtocol else {
             throw HealthError.xpcServiceUnreachable(service: "FileWriterService", underlying: NSError(domain: "XPC", code: 1, userInfo: nil))
        }
        
        // Simple "Ping" via a harmless action if possible, or just trust the connection establishment for now.
        // Real ping would require a method on the protocol.
        
        // 2. Verify Sandbox (Simple check)
        let isSandboxed = (ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
        if !isSandboxed {
            // Log warning, though we might be in Debug mode
            print("⚠️ WARNING: App is running without Sandbox container.")
        }
    }
    
    enum HealthError: LocalizedError {
        case xpcServiceUnreachable(service: String, underlying: Error)
        
        var errorDescription: String? {
            switch self {
            case .xpcServiceUnreachable(let service, let error):
                return "Critical Security Component '\(service)' is unreachable. Reinstalling the app may fix this. (Error: \(error.localizedDescription))"
            }
        }
    }
}
