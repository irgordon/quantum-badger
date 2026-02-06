import Foundation
import QuantumBadgerRuntime
import Security

final class FileWriterService: NSObject, FileWriterXPCProtocol {
    private let stateQueue = DispatchQueue(label: "com.quantumbadger.filewriter.state")
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
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            if Task.isCancelled {
                reply(nil, false, "Cancelled.")
                return
            }
            do {
                try Data(contents.utf8).write(to: url, options: [.atomic])
                reply(url.path, false, nil)
            } catch {
                reply(nil, false, "Couldn’t write the file.")
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

final class FileWriterListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let allowedTeamIDs: Set<String>

    override init() {
        if let selfTeam = currentTeamIdentifier() {
            allowedTeamIDs = [selfTeam]
        } else {
            allowedTeamIDs = []
        }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        if let teamID = auditTeamIdentifier(for: newConnection), !allowedTeamIDs.contains(teamID) {
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: FileWriterXPCProtocol.self)
        newConnection.exportedObject = FileWriterService()
        newConnection.resume()
        return true
    }

    private func auditTeamIdentifier(for connection: NSXPCConnection) -> String? {
        var token = audit_token_t()
        connection.getAuditToken(&token)
        var pid: pid_t = 0
        pid = audit_token_to_pid(token)
        let attributes: [String: Any] = [kSecGuestAttributePid as String: pid]
        var guest: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest)
        guard status == errSecSuccess, let guest else { return nil }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(guest, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func currentTeamIdentifier() -> String? {
        var code: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoStatus == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

let delegate = FileWriterListenerDelegate()
let listener = NSXPCListener(machServiceName: "com.quantumbadger.FileWriter")
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
