import Foundation

@objc public protocol DatabaseQueryXPCProtocol {
    func query(
        _ requestId: NSUUID,
        bookmarkData: Data,
        sql: String,
        parametersJSON: String?,
        maxOutputBytes: Int,
        maxFileBytes: Int,
        maxQueryTokens: Int,
        withReply reply: @escaping (String?, String?, Bool, Bool, String?) -> Void
    )
    func cancel(_ requestId: NSUUID)
}

struct DatabaseQueryResponse {
    let columnsJSON: String
    let rowsJSON: String
    let truncated: Bool
    let isStale: Bool
}

enum DatabaseQueryXPCError: Error {
    case unavailable
    case cancelled
    case remote(String)
}

final class DatabaseQueryXPCClient {
    private let serviceName: String

    init(serviceName: String = "com.quantumbadger.SecureDB") {
        self.serviceName = serviceName
    }

    func query(
        requestId: UUID,
        bookmarkData: Data,
        sql: String,
        parametersJSON: String?,
        maxOutputBytes: Int,
        maxFileBytes: Int,
        maxQueryTokens: Int
    ) async throws -> DatabaseQueryResponse {
        var connection: NSXPCConnection?
        var proxy: DatabaseQueryXPCProtocol?
        var resumeOnce: ((Result<DatabaseQueryResponse, Error>) -> Void)?
        let requestUUID = NSUUID(uuid: requestId)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connectionInstance = NSXPCConnection(machServiceName: serviceName, options: [])
                connection = connectionInstance
                connectionInstance.remoteObjectInterface = NSXPCInterface(with: DatabaseQueryXPCProtocol.self)
                var didResume = false
                let localResumeOnce: (Result<DatabaseQueryResponse, Error>) -> Void = { result in
                    guard !didResume else { return }
                    didResume = true
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                resumeOnce = localResumeOnce

                connectionInstance.interruptionHandler = {
                    connectionInstance.invalidate()
                    localResumeOnce(.failure(DatabaseQueryXPCError.unavailable))
                }
                connectionInstance.invalidationHandler = {
                    localResumeOnce(.failure(DatabaseQueryXPCError.unavailable))
                }
                connectionInstance.resume()

                proxy = connectionInstance.remoteObjectProxyWithErrorHandler { _ in
                    connectionInstance.invalidate()
                    localResumeOnce(.failure(DatabaseQueryXPCError.unavailable))
                } as? DatabaseQueryXPCProtocol

                guard let proxy else {
                    connectionInstance.invalidate()
                    localResumeOnce(.failure(DatabaseQueryXPCError.unavailable))
                    return
                }

                proxy.query(
                    requestUUID,
                    bookmarkData: bookmarkData,
                    sql: sql,
                    parametersJSON: parametersJSON,
                    maxOutputBytes: maxOutputBytes,
                    maxFileBytes: maxFileBytes,
                    maxQueryTokens: maxQueryTokens
                ) { columnsJSON, rowsJSON, truncated, isStale, error in
                    connectionInstance.invalidate()
                    if let error {
                        localResumeOnce(.failure(DatabaseQueryXPCError.remote(error)))
                    } else {
                        localResumeOnce(.success(DatabaseQueryResponse(
                            columnsJSON: columnsJSON ?? "[]",
                            rowsJSON: rowsJSON ?? "[]",
                            truncated: truncated,
                            isStale: isStale
                        )))
                    }
                }
            }
        } onCancel: {
            resumeOnce?(.failure(CancellationError()))
            proxy?.cancel(requestUUID)
            connection?.invalidate()
        }
    }
}
