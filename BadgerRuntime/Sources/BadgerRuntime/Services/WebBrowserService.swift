import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BadgerCore

// MARK: - Web Browser Errors

public enum WebBrowserError: Error, Sendable {
    case invalidURL
    case networkError(Error)
    case fetchTimeout
    case contentTooLarge
    case parsingFailed
    case securityBlocked(String)
    case rateLimited
    case unsupportedContentType
}

// MARK: - Fetched Content

/// Represents sanitized web content for RAG
public struct FetchedContent: Sendable {
    public let url: URL
    public let title: String
    public let textContent: String
    public let summary: String
    public let metadata: [String: String]
    public let fetchDate: Date
    public let contentSize: Int
    
    public var estimatedTokenCount: Int {
        textContent.count / 4
    }
    
    public var exceedsContextLimit: Bool {
        estimatedTokenCount > 8000
    }
    
    public init(
        url: URL,
        title: String,
        textContent: String,
        summary: String,
        metadata: [String: String] = [:],
        fetchDate: Date = Date(),
        contentSize: Int
    ) {
        self.url = url
        self.title = title
        self.textContent = textContent
        self.summary = summary
        self.metadata = metadata
        self.fetchDate = fetchDate
        self.contentSize = contentSize
    }
}

// MARK: - Browser Security Policy

public struct BrowserSecurityPolicy: Sendable {
    public let maxContentSize: Int
    public let timeout: TimeInterval
    public let allowedDomains: [String]
    public let blockedDomains: [String]
    public let allowJavaScript: Bool = false
    public let fetchMedia: Bool = false
    public let userAgent: String
    
    public init(
        maxContentSize: Int = 10 * 1024 * 1024,
        timeout: TimeInterval = 30.0,
        allowedDomains: [String] = [],
        blockedDomains: [String] = [
            "doubleclick.net",
            "googleadservices.com",
            "facebook.com/tr",
            "analytics",
            "tracking"
        ],
        userAgent: String = "QuantumBadger/1.0 (Secure Content Fetcher)"
    ) {
        self.maxContentSize = maxContentSize
        self.timeout = timeout
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.userAgent = userAgent
    }
    
    public static let `default` = BrowserSecurityPolicy()
    
    public static let strict = BrowserSecurityPolicy(
        maxContentSize: 5 * 1024 * 1024,
        timeout: 15.0,
        allowedDomains: [],
        blockedDomains: [
            "doubleclick.net",
            "googleadservices.com",
            "facebook.com",
            "twitter.com",
            "analytics",
            "tracking",
            "ads",
            "pixel"
        ]
    )
}

// MARK: - Web Browser Service

public actor WebBrowserService {
    
    private let urlSession: URLSession
    private let securityPolicy: BrowserSecurityPolicy
    private let inputSanitizer: InputSanitizer
    private let privacyFilter: PrivacyEgressFilter
    private let auditService: AuditLogService
    
    private var activeTasks: [UUID: Task<FetchedContent, Error>] = [:]
    private var rateLimitStore: [String: Date] = [:]
    
    public init(
        securityPolicy: BrowserSecurityPolicy = .default,
        inputSanitizer: InputSanitizer = InputSanitizer(),
        privacyFilter: PrivacyEgressFilter = PrivacyEgressFilter(),
        auditService: AuditLogService = AuditLogService()
    ) {
        self.securityPolicy = securityPolicy
        self.inputSanitizer = inputSanitizer
        self.privacyFilter = privacyFilter
        self.auditService = auditService
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = securityPolicy.timeout
        config.timeoutIntervalForResource = securityPolicy.timeout * 2
        config.httpAdditionalHeaders = [
            "User-Agent": securityPolicy.userAgent,
            "Accept": "text/html, text/plain, text/markdown",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        config.httpCookieStorage = nil
        
        self.urlSession = URLSession(configuration: config)
    }
    
    public func fetchContent(
        from urlString: String,
        extractSummary: Bool = true
    ) async throws -> FetchedContent {
        guard let url = URL(string: urlString),
              url.scheme?.hasPrefix("http") == true else {
            throw WebBrowserError.invalidURL
        }
        
        try await performSecurityChecks(url: url)
        try checkRateLimit(for: url.host ?? "unknown")
        
        let taskId = UUID()
        
        let task = Task<FetchedContent, Error> {
            defer { Task { await self.removeTask(taskId) } }
            
            let (data, response) = try await performFetch(url: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebBrowserError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            
            guard httpResponse.statusCode == 200 else {
                throw WebBrowserError.networkError(NSError(domain: "HTTP \(httpResponse.statusCode)", code: httpResponse.statusCode))
            }
            
            guard data.count <= securityPolicy.maxContentSize else {
                throw WebBrowserError.contentTooLarge
            }
            
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? "text/html"
            guard isAllowedContentType(contentType) else {
                throw WebBrowserError.unsupportedContentType
            }
            
            let (title, textContent) = try await parseAndSanitize(data: data, contentType: contentType)
            let filteredContent = privacyFilter.redactSensitiveContent(textContent)
            let summary = extractSummary ? generateSummary(filteredContent) : ""
            
            let metadata: [String: String] = [
                "source": url.absoluteString,
                "contentType": contentType,
                "contentLength": String(data.count)
            ]
            
            try await auditService.log(
                type: .remoteCommandReceived,
                source: "WebBrowser",
                details: "Fetched \(url.host ?? "unknown"), size: \(data.count) bytes"
            )
            
            return FetchedContent(
                url: url,
                title: title,
                textContent: filteredContent,
                summary: summary,
                metadata: metadata,
                contentSize: data.count
            )
        }
        
        await addTask(task, id: taskId)
        
        do {
            return try await task.value
        } catch is CancellationError {
            throw WebBrowserError.fetchTimeout
        }
    }
    
    private func performSecurityChecks(url: URL) async throws {
        guard let host = url.host?.lowercased() else {
            throw WebBrowserError.securityBlocked("Invalid host")
        }
        
        for blocked in securityPolicy.blockedDomains {
            if host.contains(blocked) {
                throw WebBrowserError.securityBlocked("Domain blocked: \(blocked)")
            }
        }
        
        if !securityPolicy.allowedDomains.isEmpty {
            let isAllowed = securityPolicy.allowedDomains.contains { allowed in
                host.contains(allowed.lowercased())
            }
            guard isAllowed else {
                throw WebBrowserError.securityBlocked("Domain not in allowlist")
            }
        }
        
        if inputSanitizer.containsMaliciousPatterns(url.absoluteString) {
            throw WebBrowserError.securityBlocked("URL contains suspicious patterns")
        }
    }
    
    private func checkRateLimit(for host: String) throws {
        let now = Date()
        if let lastRequest = rateLimitStore[host] {
            if now.timeIntervalSince(lastRequest) < 1.0 {
                throw WebBrowserError.rateLimited
            }
        }
        rateLimitStore[host] = now
    }
    
    private func performFetch(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = securityPolicy.timeout
        return try await urlSession.data(for: request)
    }
    
    private func isAllowedContentType(_ contentType: String) -> Bool {
        let normalized = contentType.lowercased()
        return normalized.contains("text/html") || 
               normalized.contains("text/plain") ||
               normalized.contains("text/markdown")
    }
    
    private func parseAndSanitize(data: Data, contentType: String) async throws -> (title: String, content: String) {
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw WebBrowserError.parsingFailed
        }
        
        let title = extractTitle(from: htmlString) ?? "Untitled"
        var textContent = stripHTML(htmlString)
        textContent = stripJavaScript(textContent)
        textContent = normalizeWhitespace(textContent)
        textContent = inputSanitizer.sanitize(textContent).sanitized
        
        return (title, textContent)
    }
    
    private func extractTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>([^<]+)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else {
            return nil
        }
        if let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func stripHTML(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeHTMLEntities(result)
    }
    
    private func stripJavaScript(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"javascript:[^\s\"']+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"on\w+\s*=\s*['\"]?[^'\"\s>]+"#, with: "", options: .regularExpression)
        return result
    }
    
    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
    
    private func generateSummary(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        let firstParagraphs = paragraphs.prefix(3)
        var summary = firstParagraphs.joined(separator: "\n\n")
        if summary.count > 500 {
            summary = String(summary.prefix(500)) + "..."
        }
        return summary
    }
    
    private func addTask(_ task: Task<FetchedContent, Error>, id: UUID) {
        activeTasks[id] = task
    }
    
    private func removeTask(_ id: UUID) {
        activeTasks.removeValue(forKey: id)
    }
}

extension WebBrowserService {
    public func quickFetch(_ urlString: String) async throws -> String {
        let content = try await fetchContent(from: urlString)
        return content.textContent
    }
}
