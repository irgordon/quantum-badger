import Foundation

/// Shared protocol for the XPC File Writer Service.
///
/// This protocol must be visible to both the main app (client) and the XPC service (server).
@objc(FileWriterXPCProtocol)
public protocol FileWriterXPCProtocol {
    
    /// Request a file write operation.
    /// - Parameters:
    ///   - requestId: Unique ID for cancellation/tracking.
    ///   - bookmarkData: Security-scoped bookmark to the target file.
    ///   - contents: content to write.
    ///   - maxBytes: Safety ceiling for file size (pre-check).
    ///   - reply: Completion handler (path, isStale, error).
    func writeFile(
        _ requestId: NSUUID,
        bookmarkData: Data,
        contents: String,
        maxBytes: Int,
        withReply reply: @escaping (String?, Bool, String?) -> Void
    )
    
    /// Cancel a pending write.
    func cancel(_ requestId: NSUUID)
}
