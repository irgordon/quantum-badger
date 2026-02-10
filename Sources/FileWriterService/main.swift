import Foundation
import BadgerCore
import Security

// MARK: - Service Implementation

final class FileWriterService: NSObject, FileWriterXPCProtocol {

    /// Serial queue to protect `tasks` state.
    private let stateQueue = DispatchQueue(label: "com.quantumbadger.filewriter.state")

    /// Active write tasks, keyed by Request ID.
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func writeFile(
        _ requestId: NSUUID,
        bookmarkData: Data,
        contents: String,
        maxBytes: Int,
        withReply reply: @escaping (String?, Bool, String?) -> Void
    ) {
        let id = requestId as UUID
        let payloadBytes = contents.utf8.count

        // Safety Ceiling check.
        if maxBytes > 0 && payloadBytes > maxBytes {
            reply(nil, false, "File contents exceed the configured size limit.")
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            defer {
                self?.stateQueue.async { self?.tasks[id] = nil }
            }

            if Task.isCancelled {
                reply(nil, false, "Cancelled.")
                return
            }

            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                reply(nil, false, "Unable to resolve the saved file location.")
                return
            }

            if isStale {
                reply(nil, true, "Saved location needs to be chosen again.")
                return
            }

            // Scope Start
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                // Scope End
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            if Task.isCancelled {
                reply(nil, false, "Cancelled.")
                return
            }

            do {
                // Atomic Write
                try Data(contents.utf8).write(to: url, options: [.atomic])
                reply(url.path, false, nil)
            } catch {
                reply(nil, false, "Couldn’t write the file: \(error.localizedDescription)")
            }
        }

        stateQueue.async { self.tasks[id] = task }
    }

    func cancel(_ requestId: NSUUID) {
        let id = requestId as UUID
        stateQueue.async {
            self.tasks[id]?.cancel()
            self.tasks[id] = nil
        }
    }
}

// MARK: - Listener Delegate (Team ID Enforcement)

final class FileWriterListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let allowedTeamIDs: Set<String>

    override init() {
        // Automatically allow our own Team ID.
        if let selfTeam = Self.currentTeamIdentifier() {
            allowedTeamIDs = [selfTeam]
        } else {
            // In development (unsigned), we might allow nil or handle differently.
            // For Fortress Architecture, we fail secure: default to empty (reject all).
            print("⚠️ [FileWriter] Could not determine own Team ID. Service may reject connections.")
            allowedTeamIDs = []
        }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Enforce Team ID matching.
        guard let teamID = auditTeamIdentifier(for: newConnection) else {
            print("❌ [FileWriter] Connection rejected: Could not determine remote Team ID.")
            return false
        }
        
        guard allowedTeamIDs.contains(teamID) else {
            print("❌ [FileWriter] Connection rejected: Team ID '\(teamID)' not allowed.")
            return false
        }

        // Configure interface.
        newConnection.exportedInterface = NSXPCInterface(with: FileWriterXPCProtocol.self)
        newConnection.exportedObject = FileWriterService()
        newConnection.resume()
        return true
    }

    private func auditTeamIdentifier(for connection: NSXPCConnection) -> String? {
        // 1. Get Audit Token
        var token = audit_token_t()
        connection.getAuditToken(&token)
        
        // 2. Derive Guest Code
        // Note: kSecGuestAttributeAudit is preferred over PID for stability, but
        // `audit_token_to_pid` is used in the snippet. We'll stick to the snippet's
        // general logic but mapped to available Swift APIs if possible.
        // Actually, creating a SecCode from an audit token matches `SecCodeCopyGuestWithAttributes`.
        
        // We need to wrap the audit token data for the attribute dictionary.
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attributes: [String: Any] = [kSecGuestAttributeAudit as String: tokenData]
        
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest)
        guard status == errSecSuccess, let guestCode = guest else { return nil }
        
        return Self.getTeamIdentifier(for: guestCode)
    }

    private static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let selfCode = code else { return nil }
        return getTeamIdentifier(for: selfCode)
    }
    
    private static func getTeamIdentifier(for code: SecCode) -> String? {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

// MARK: - Main Entry Point

let delegate = FileWriterListenerDelegate()
let listener = NSXPCListener(machServiceName: "com.quantumbadger.FileWriter")
listener.delegate = delegate
listener.resume()

// Keep the service alive.
RunLoop.main.run()
