import Foundation

@objc public protocol FileWriterXPCProtocol {
    func writeFile(
        _ requestId: NSUUID,
        bookmarkData: Data,
        contents: String,
        maxBytes: Int,
        withReply reply: @escaping (String?, Bool, String?) -> Void
    )
    func cancel(_ requestId: NSUUID)
}

struct FileWriterResponse {
    let path: String?
    let isStale: Bool
}

enum FileWriterXPCError: Error {
    case unavailable
    case cancelled
    case remote(String)
}

final class FileWriterXPCClient {
    private let serviceName: String

    init(serviceName: String = "com.quantumbadger.FileWriter") {
        self.serviceName = serviceName
    }

    func writeFile(
        requestId: UUID,
        bookmarkData: Data,
        contents: String,
        maxBytes: Int
    ) async throws -> FileWriterResponse {
        var connection: NSXPCConnection?
        var proxy: FileWriterXPCProtocol?
        var resumeOnce: ((Result<FileWriterResponse, Error>) -> Void)?
        let requestUUID = NSUUID(uuid: requestId)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connectionInstance = NSXPCConnection(machServiceName: serviceName, options: [])
                connection = connectionInstance
                connectionInstance.remoteObjectInterface = NSXPCInterface(with: FileWriterXPCProtocol.self)
                var didResume = false
                let localResumeOnce: (Result<FileWriterResponse, Error>) -> Void = { result in
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
                    localResumeOnce(.failure(FileWriterXPCError.unavailable))
                }
                connectionInstance.invalidationHandler = {
                    localResumeOnce(.failure(FileWriterXPCError.unavailable))
                }
                connectionInstance.resume()

                proxy = connectionInstance.remoteObjectProxyWithErrorHandler { _ in
                    connectionInstance.invalidate()
                    localResumeOnce(.failure(FileWriterXPCError.unavailable))
                } as? FileWriterXPCProtocol

                guard let proxy else {
                    connectionInstance.invalidate()
                    localResumeOnce(.failure(FileWriterXPCError.unavailable))
                    return
                }

                proxy.writeFile(
                    requestUUID,
                    bookmarkData: bookmarkData,
                    contents: contents,
                    maxBytes: maxBytes
                ) { path, isStale, error in
                    connectionInstance.invalidate()
                    if let error {
                        localResumeOnce(.failure(FileWriterXPCError.remote(error)))
                    } else {
                        localResumeOnce(.success(FileWriterResponse(path: path, isStale: isStale)))
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
