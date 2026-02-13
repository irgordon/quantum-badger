import Foundation
import Testing
@testable import BadgerCore

@Suite("Input Sanitizer Tests")
struct InputSanitizerTests {
    
    let sanitizer = InputSanitizer()
    
    @Test("SQL injection detection")
    func testSQLInjectionDetection() async throws {
        let maliciousInputs = [
            "'; DROP TABLE users; --",
            "1 OR 1=1",
            "admin' --",
            "' UNION SELECT * FROM passwords --",
            "1; DELETE FROM users WHERE '1'='1"
        ]
        
        for input in maliciousInputs {
            let result = sanitizer.sanitize(input)
            #expect(result.wasSanitized, "Failed to detect SQL injection in: \(input)")
        }
    }
    
    @Test("Shell injection detection")
    func testShellInjectionDetection() async throws {
        let maliciousInputs = [
            "$(whoami)",
            "`cat /etc/passwd`",
            "; rm -rf /",
            "| bash",
            "|| cat /etc/shadow"
        ]
        
        for input in maliciousInputs {
            let result = sanitizer.sanitize(input)
            #expect(result.wasSanitized, "Failed to detect shell injection in: \(input)")
        }
    }
    
    @Test("Path traversal detection")
    func testPathTraversalDetection() async throws {
        let maliciousInputs = [
            "../../../etc/passwd",
            "..\\..\\windows\\system32\\config\\sam",
            "%2e%2e%2fetc%2fpasswd"
        ]
        
        for input in maliciousInputs {
            let result = sanitizer.sanitize(input)
            #expect(result.wasSanitized, "Failed to detect path traversal in: \(input)")
        }
    }
    
    @Test("PII redaction")
    func testPIIRedaction() async throws {
        let inputsWithPII = [
            ("My SSN is 123-45-6789", "123-45-6789"),
            ("Email me at test@example.com", "test@example.com"),
            ("Call me at 555-123-4567", "555-123-4567"),
            ("API key: sk-1234567890abcdef", "sk-1234567890abcdef")
        ]
        
        for (input, _) in inputsWithPII {
            let result = sanitizer.sanitize(input)
            #expect(result.wasSanitized, "Failed to detect PII in: \(input)")
            #expect(result.sanitized.contains("[REDACTED_PII]") || 
                   result.sanitized.contains("[REDACTED_"), "PII not properly redacted in: \(input)")
        }
    }
    
    @Test("Clean input preservation")
    func testCleanInput() async throws {
        let cleanInputs = [
            "Hello, how are you today?",
            "Please help me write a Swift function",
            "What is the capital of France?",
            "Explain quantum computing in simple terms"
        ]
        
        for input in cleanInputs {
            let result = sanitizer.sanitize(input)
            #expect(!result.wasSanitized, "False positive on clean input: \(input)")
            #expect(result.sanitized == input, "Clean input was modified: \(input)")
        }
    }
    
    @Test("XSS detection")
    func testXSSDetection() async throws {
        let maliciousInputs = [
            "<script>alert('xss')</script>",
            "javascript:alert('xss')",
            "<iframe src='evil.com'>"
        ]
        
        for input in maliciousInputs {
            let result = sanitizer.sanitize(input)
            #expect(result.wasSanitized, "Failed to detect XSS in: \(input)")
        }
    }
    
    @Test("Contains malicious patterns check")
    func testContainsMaliciousPatterns() async throws {
        let malicious = "'; DROP TABLE users; --"
        let clean = "Hello world"
        
        #expect(sanitizer.containsMaliciousPatterns(malicious) == true)
        #expect(sanitizer.containsMaliciousPatterns(clean) == false)
    }
    
    @Test("Whitelist sanitization")
    func testWhitelistSanitization() async throws {
        let input = "Hello123!@#World"
        let sanitized = InputSanitizer.whitelistSanitize(input, allowedCharacters: .alphanumerics)
        
        #expect(sanitized == "Hello123World")
    }
    
    @Test("Regex escape helper")
    func testRegexEscape() async throws {
        let input = "Hello.world*test+"
        let escaped = InputSanitizer.escapeForRegex(input)
        
        #expect(escaped == "Hello\\.world\\*test\\+")
    }
    
    @Test("Custom sanitizer initialization")
    func testCustomSanitizer() async throws {
        let sqlOnlySanitizer = InputSanitizer(includeSQL: true, includeShell: false, includePath: false, includeXSS: false, includePII: false)
        let shellOnlySanitizer = InputSanitizer(includeSQL: false, includeShell: true, includePath: false, includeXSS: false, includePII: false)
        
        let sqlInput = "'; DROP TABLE users; --"
        let shellInput = "$(whoami)"
        
        let sqlResult = sqlOnlySanitizer.sanitize(sqlInput)
        let shellResult = sqlOnlySanitizer.sanitize(shellInput)
        
        #expect(sqlResult.wasSanitized == true)
        #expect(shellResult.wasSanitized == false) // Shell patterns not included
        
        let shellSqlResult = shellOnlySanitizer.sanitize(sqlInput)
        let shellShellResult = shellOnlySanitizer.sanitize(shellInput)
        
        #expect(shellSqlResult.wasSanitized == false) // SQL patterns not included
        #expect(shellShellResult.wasSanitized == true)
    }
    
    @Test("String extension sanitization")
    func testStringExtension() async throws {
        let malicious = "'; DROP TABLE; --"
        let clean = "Hello world"
        
        #expect(malicious.containsMaliciousPatterns == true)
        #expect(clean.containsMaliciousPatterns == false)
        #expect(malicious.sanitized.contains("[REDACTED_SQL]") == true)
    }
}
