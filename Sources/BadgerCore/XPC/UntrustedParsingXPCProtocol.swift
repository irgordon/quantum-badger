import Foundation

/// The protocol that the UntrustedParser XPC Service must conform to.
/// This defines the "Safe Interface" for processing dangerous content.
///
/// - Note: This protocol uses 'Data' for inputs to minimize XPC serialization overhead
///         and avoid String encoding issues with malformed content.
@objc(UntrustedParsingXPCProtocol)
public protocol UntrustedParsingXPCProtocol {
    
    /// Parses raw data (e.g., HTML, Markdown) and returns a sanitized, simplified string.
    ///
    /// - Parameters:
    ///   - contentData: The raw bytes of the content. Using Data prevents implicit String decoding crashes.
    ///   - options: A dictionary of parsing options (e.g., ["extractLinks": "true"]).
    ///   - reply: Handler returning the sanitized string or an error.
    ///            The closure is @Sendable to satisfy Swift 6 concurrency strictness.
    func parse(
        contentData: Data, 
        options: [String: String], 
        reply: @escaping @Sendable (String?, Error?) -> Void
    )
    
    /// Parses a file via a secure Security-Scoped Bookmark.
    ///
    /// - Parameters:
    ///   - bookmark: The security-scoped bookmark data for the file. 
    ///               The service must resolve this to access the file.
    ///   - reply: Handler returning the extracted text or an error.
    func parseFile(
        bookmark: Data, 
        reply: @escaping @Sendable (String?, Error?) -> Void
    )
}
