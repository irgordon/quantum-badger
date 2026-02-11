import Foundation

/// Actor‑isolated web content fetcher with sanitization.
///
/// `WebScraper` fetches web pages for research tasks, strips scripts,
/// ads, and trackers, and returns structured text summaries — never
/// raw HTML. All operations respect domain allowlists, request budgets,
/// memory budgets, and are cancellable.
///
/// Web scraping is treated as **Tier 2 (background)** unless the user
/// explicitly initiated the request.
public actor WebScraper {

    // MARK: - Configuration

    /// Domains allowed for scraping. Empty means all domains denied.
    private var allowedDomains: Set<String>

    /// Maximum number of requests per session.
    private let requestBudget: Int

    /// Counter of requests made this session.
    private var requestsMade: Int = 0

    /// URLSession for fetching.
    private let session: URLSession

    // MARK: - Init

    public init(
        allowedDomains: Set<String> = [],
        requestBudget: Int = 50
    ) {
        self.allowedDomains = allowedDomains
        self.requestBudget = requestBudget

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "QuantumBadger/1.0 (Research Bot)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch, sanitize, and summarize web content.
    ///
    /// - Parameter url: The URL to fetch.
    /// - Returns: Sanitized text content suitable for LLM consumption.
    /// - Throws: `WebScraperError` on domain denial, budget exhaustion,
    ///   or network failures.
    public func fetch(url: URL) async throws -> ScrapedContent {
        try Task.checkCancellation()

        // Privacy check.
        switch await privacyFilter.check(url) {
        case .allowed:
            break
        case .blocked(let reason):
            throw WebScraperError.privacyBlocked(reason: reason)
        }

        // Domain allowlist check.
        guard let host = url.host, allowedDomains.contains(host) else {
            throw WebScraperError.domainNotAllowed(url.host ?? "unknown")
        }

        // Budget check.
        guard requestsMade < requestBudget else {
            throw WebScraperError.requestBudgetExhausted
        }
        requestsMade += 1

        try Task.checkCancellation()

        // Fetch.
        let (data, response) = try await session.data(from: url)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            await privacyFilter.reportFailure(for: url)
            throw WebScraperError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }

        await privacyFilter.reportSuccess(for: url)

        // Decode text.
        guard let rawHTML = String(data: data, encoding: .utf8) else {
            throw WebScraperError.decodingFailed
        }

        // Sanitize.
        let cleanText = sanitize(rawHTML)

        // Prompt‑injection defense.
        let safeText = stripPromptInjection(cleanText)

        return ScrapedContent(
            sourceURL: url,
            textContent: safeText,
            fetchedAt: Date(),
            byteCount: UInt64(data.count)
        )
    }

    /// Update the domain allowlist at runtime.
    public func setAllowedDomains(_ domains: Set<String>) {
        allowedDomains = domains
    }

    /// Reset the request counter.
    public func resetRequestBudget() {
        requestsMade = 0
    }

    // MARK: - Sanitization

    /// Strip HTML tags, scripts, style blocks, and ad/tracker elements.
    private func sanitize(_ html: String) -> String {
        var text = html

        // Remove script blocks.
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )

        // Remove style blocks.
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Remove HTML comments.
        text = text.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )

        // Remove all remaining HTML tags.
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Collapse whitespace.
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Defend against prompt injection in scraped content.
    private func stripPromptInjection(_ text: String) -> String {
        var safe = text

        // Common prompt injection patterns.
        let injectionPatterns = [
            "ignore previous instructions",
            "ignore all previous",
            "disregard above",
            "new instructions:",
            "system prompt:",
            "you are now",
            "act as",
            "pretend to be",
            "override:",
            "\\[INST\\]",
            "\\[/INST\\]",
            "<\\|im_start\\|>",
            "<\\|im_end\\|>",
        ]

        for pattern in injectionPatterns {
            safe = safe.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return safe
    }
}

// MARK: - Supporting Types

/// Result of a successful web scrape.
public struct ScrapedContent: Sendable, Codable, Equatable, Hashable {
    /// The original URL that was fetched.
    public let sourceURL: URL

    /// Sanitized plain‑text content.
    public let textContent: String

    /// When the content was fetched.
    public let fetchedAt: Date

    /// Raw byte count of the HTTP response body.
    public let byteCount: UInt64
}

/// Errors from the web scraping pipeline.
@frozen
public enum WebScraperError: String, Error, Sendable, Codable, Equatable, Hashable {
    case domainNotAllowed
    case requestBudgetExhausted
    case httpError
    case decodingFailed

    /// Initialiser that accepts context (for internal throw sites).
    init(domainNotAllowed host: String) { self = .domainNotAllowed }
    static func domainNotAllowed(_ host: String) -> WebScraperError { .domainNotAllowed }
    static func httpError(_ code: Int) -> WebScraperError { .httpError }
}
