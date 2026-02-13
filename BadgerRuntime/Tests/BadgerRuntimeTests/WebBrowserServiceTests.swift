import Foundation
import Testing
@testable import BadgerRuntime
@testable import BadgerCore

@Suite("Web Browser Service Tests")
struct WebBrowserServiceTests {
    
    @Test("Browser security policy creation")
    func testSecurityPolicy() async throws {
        let defaultPolicy = BrowserSecurityPolicy.default
        #expect(defaultPolicy.maxContentSize == 10 * 1024 * 1024)
        #expect(defaultPolicy.timeout == 30.0)
        #expect(defaultPolicy.allowJavaScript == false)
        #expect(defaultPolicy.fetchMedia == false)
        
        let strictPolicy = BrowserSecurityPolicy.strict
        #expect(strictPolicy.maxContentSize == 5 * 1024 * 1024)
        #expect(strictPolicy.timeout == 15.0)
    }
    
    @Test("Fetched content creation")
    func testFetchedContent() async throws {
        let content = FetchedContent(
            url: URL(string: "https://example.com")!,
            title: "Test",
            textContent: String(repeating: "word ", count: 100),
            summary: "Summary",
            contentSize: 1000
        )
        
        #expect(content.title == "Test")
        #expect(content.estimatedTokenCount == 125) // 500 chars / 4
        #expect(content.exceedsContextLimit == false)
    }
    
    @Test("Fetched content exceeds limit")
    func testContentExceedsLimit() async throws {
        let longContent = String(repeating: "word ", count: 10000)
        let content = FetchedContent(
            url: URL(string: "https://example.com")!,
            title: "Long",
            textContent: longContent,
            summary: "Summary",
            contentSize: 50000
        )
        
        #expect(content.exceedsContextLimit == true)
    }
    
    @Test("Web browser service initialization")
    func testServiceInitialization() async throws {
        let service = WebBrowserService()
        #expect(true) // Should initialize without crashing
    }
    
    @Test("Invalid URL handling")
    func testInvalidURL() async throws {
        let service = WebBrowserService()
        
        do {
            _ = try await service.fetchContent(from: "not-a-valid-url")
            #expect(Bool(false)) // Should throw
        } catch WebBrowserError.invalidURL {
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }
    
    @Test("Security blocked domain")
    func testBlockedDomain() async throws {
        let service = WebBrowserService()
        
        // URLs containing blocked domains should be rejected
        let blockedURL = "https://tracking-pixel.doubleclick.net/tracker"
        
        do {
            _ = try await service.fetchContent(from: blockedURL)
            #expect(Bool(false)) // Should throw
        } catch WebBrowserError.securityBlocked {
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }
    
    @Test("Malicious URL pattern detection")
    func testMaliciousURLPattern() async throws {
        let service = WebBrowserService()
        
        // URLs with suspicious patterns should be blocked
        let suspiciousURL = "https://example.com/page?param=';DROP TABLE users;--"
        
        do {
            _ = try await service.fetchContent(from: suspiciousURL)
            #expect(Bool(false)) // Should throw
        } catch WebBrowserError.securityBlocked {
            #expect(true)
        } catch {
            #expect(Bool(false))
        }
    }
    
    @Test("Quick fetch convenience method exists")
    func testQuickFetchExists() async throws {
        let service = WebBrowserService()
        
        // We can't actually fetch without network, but we can verify the method exists
        // and properly validates URLs
        do {
            _ = try await service.quickFetch("invalid-url")
            #expect(Bool(false))
        } catch {
            #expect(true) // Should throw for invalid URL
        }
    }
    
    @Test("Check accessibility method")
    func testCheckAccessibility() async throws {
        let service = WebBrowserService()
        
        // Blocked domain should not be accessible
        let blockedAccessible = await service.checkAccessibility("https://doubleclick.net/tracker")
        #expect(blockedAccessible == false)
        
        // Regular domain should be accessible (security check passes)
        let normalAccessible = await service.checkAccessibility("https://example.com")
        #expect(normalAccessible == true)
    }
    
    @Test("Rate limiting")
    func testRateLimiting() async throws {
        let service = WebBrowserService()
        
        // First check should pass
        let firstCheck = await service.checkAccessibility("https://example.com")
        #expect(firstCheck == true)
        
        // Immediate second check to same host should also pass (1 second window)
        // but actual rate limit is tested in the fetchContent method
    }
}