import Foundation
import Testing
@testable import BadgerCore

@Suite("Privacy Egress Filter Tests")
struct PrivacyEgressFilterTests {
    
    let filter = PrivacyEgressFilter()
    
    @Test("Detect SSN")
    func testSSNDetection() async throws {
        let text = "My SSN is 123-45-6789"
        let detections = filter.detectSensitiveData(in: text)
        
        #expect(detections.count == 1)
        #expect(detections.first?.type == .socialSecurityNumber)
    }
    
    @Test("Detect email address")
    func testEmailDetection() async throws {
        let text = "Contact me at test@example.com"
        let detections = filter.detectSensitiveData(in: text)
        
        #expect(detections.count == 1)
        #expect(detections.first?.type == .emailAddress)
    }
    
    @Test("Detect phone number")
    func testPhoneDetection() async throws {
        let text = "Call me at 555-123-4567"
        let detections = filter.detectSensitiveData(in: text)
        
        #expect(detections.count == 1)
        #expect(detections.first?.type == .phoneNumber)
    }
    
    @Test("Detect credit card")
    func testCreditCardDetection() async throws {
        let text = "Card: 4111111111111111"
        let detections = filter.detectSensitiveData(in: text)
        
        #expect(detections.count == 1)
        #expect(detections.first?.type == .creditCard)
    }
    
    @Test("Detect API key")
    func testAPIKeyDetection() async throws {
        let text = "API key: sk-abc123def456ghi789"
        let detections = filter.detectSensitiveData(in: text)
        
        #expect(detections.count == 1)
        #expect(detections.first?.type == .apiKey)
    }
    
    @Test("Redact sensitive content")
    func testRedaction() async throws {
        let text = "Email: test@example.com and phone: 555-123-4567"
        let redacted = filter.redactSensitiveContent(text)
        
        #expect(redacted.contains("test@example.com") == false)
        #expect(redacted.contains("555-123-4567") == false)
        #expect(redacted.contains("[REDACTED_EMAIL]") == true)
        #expect(redacted.contains("[REDACTED_PHONE]") == true)
    }
    
    @Test("Contains sensitive data check")
    func testContainsSensitiveData() async throws {
        let withPII = "My email is user@domain.com"
        let withoutPII = "This is just a regular sentence"
        
        #expect(filter.containsSensitiveData(withPII) == true)
        #expect(filter.containsSensitiveData(withoutPII) == false)
    }
    
    @Test("High risk data detection")
    func testHighRiskDetection() async throws {
        let highRiskText = "SSN: 123-45-6789"
        let lowRiskText = "IP: 192.168.1.1"
        
        #expect(filter.containsHighRiskData(highRiskText) == true)
        #expect(filter.containsHighRiskData(lowRiskText) == false)
    }
    
    @Test("Configuration high risk only")
    func testHighRiskOnlyConfiguration() async throws {
        let highRiskFilter = PrivacyEgressFilter(configuration: .highRiskOnly)
        let text = "Email: test@test.com, SSN: 123-45-6789"
        
        let detections = highRiskFilter.detectSensitiveData(in: text)
        #expect(detections.count == 1) // Only SSN, not email
        #expect(detections.first?.type == .socialSecurityNumber)
    }
    
    @Test("Sensitive data type properties")
    func testSensitiveDataTypeProperties() async throws {
        #expect(PrivacyEgressFilter.SensitiveDataType.socialSecurityNumber.isHighRisk == true)
        #expect(PrivacyEgressFilter.SensitiveDataType.emailAddress.isHighRisk == false)
        #expect(PrivacyEgressFilter.SensitiveDataType.creditCard.isHighRisk == true)
    }
    
    @Test("String extension redaction")
    func testStringExtension() async throws {
        let text = "Email me at secret@private.com"
        let redacted = text.redactedForPrivacy
        
        #expect(redacted.contains("secret@private.com") == false)
        #expect(redacted.contains("[REDACTED_EMAIL]") == true)
    }
    
    @Test("Static redact method")
    func testStaticRedact() async throws {
        let text = "Phone: 555-123-4567"
        let redacted = PrivacyEgressFilter.redact(text)
        
        #expect(redacted.contains("555-123-4567") == false)
    }
    
    @Test("Static isSafeForEgress")
    func testStaticIsSafeForEgress() async throws {
        let safe = "This is a safe message"
        let unsafe = "My SSN is 123-45-6789"
        
        #expect(PrivacyEgressFilter.isSafeForEgress(safe) == true)
        #expect(PrivacyEgressFilter.isSafeForEgress(unsafe) == false)
    }
}