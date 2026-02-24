import Foundation
import Testing
@testable import BadgerApp
@testable import BadgerCore
@testable import BadgerRuntime

@Suite("Response Formatter Tests")
struct ResponseFormatterTests {

    // MARK: - Basic Detection Tests

    @Test("Format Detection Result creation")
    func testFormatDetectionResult() async throws {
        let detection = FormatDetectionResult(
            containsCode: true,
            containsTable: false,
            containsMarkdown: true,
            estimatedCharacterCount: 1500,
            recommendedFormat: .markdownFile
        )

        #expect(detection.containsCode == true)
        #expect(detection.containsTable == false)
        #expect(detection.containsMarkdown == true)
        #expect(detection.estimatedCharacterCount == 1500)
        #expect(detection.exceedsMessageLimit == false)
    }

    @Test("Format detection - code blocks")
    func testCodeBlockDetection() async throws {
        let formatter = ResponseFormatter()

        // Test backticks
        let codeContent1 = "```swift\nfunc test() {}\n```"
        let detection1 = await formatter.detectFormat(in: codeContent1)
        #expect(detection1.containsCode == true)

        // Test tildes
        let codeContent2 = "~~~python\nprint('hello')\n~~~"
        let detection2 = await formatter.detectFormat(in: codeContent2)
        #expect(detection2.containsCode == true)
    }

    @Test("Format detection - inline code")
    func testInlineCodeDetection() async throws {
        let formatter = ResponseFormatter()

        let inlineContent = "Use the `print()` function to debug."
        let detection = await formatter.detectFormat(in: inlineContent)

        #expect(detection.containsCode == true)

        // If it has code blocks, it shouldn't flag as inline code internally,
        // but containsCode should still be true
        let mixedContent = "```\ncode\n```\nand `inline` code"
        let mixedDetection = await formatter.detectFormat(in: mixedContent)
        #expect(mixedDetection.containsCode == true)
    }

    @Test("Format detection - tables")
    func testTableDetection() async throws {
        let formatter = ResponseFormatter()

        // Pipe-delimited table
        let tableContent = """
        | Name | Value |
        |------|-------|
        | A    | 1     |
        """

        let detection = await formatter.detectFormat(in: tableContent)
        #expect(detection.containsTable == true)

        // Separator-only (though less common without pipes)
        let separatorContent = "--- | --- | ---"
        let detection2 = await formatter.detectFormat(in: separatorContent)
        #expect(detection2.containsTable == true)
    }

    @Test("Format detection - markdown elements")
    func testMarkdownDetection() async throws {
        let formatter = ResponseFormatter()

        let scenarios = [
            ("# Heading", true),
            ("## Heading 2", true),
            ("### Heading 3", true),
            ("- List item", true),
            ("* List item", true),
            ("> Blockquote", true),
            ("[Link](https://example.com)", true),
            ("Just plain text", false)
        ]

        for (content, expected) in scenarios {
            let detection = await formatter.detectFormat(in: content)
            #expect(detection.containsMarkdown == expected, "Failed for: \(content)")
        }
    }

    // MARK: - Language Detection Tests

    @Test("Language detection - Swift")
    func testSwiftLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "import Foundation\n\nfunc calculate() -> Int {\n  let x = 10\n  return x\n}"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "swift")
        } else {
            // It might be detected as plain text if no code blocks/backticks are present
            // but the detectFormat logic uses recommendedFormat based on containsCode
            // and containsCode requires backticks or ~~~.
        }

        // Let's add backticks to ensure it recommends codeFile
        let codeContent = "```\n" + content + "\n```"
        let codeDetection = await formatter.detectFormat(in: codeContent)

        if case .codeFile(let language) = codeDetection.recommendedFormat {
            #expect(language == "swift")
        } else {
            Issue.record("Expected .codeFile(language: 'swift'), got \(codeDetection.recommendedFormat)")
        }
    }

    @Test("Language detection - Python")
    func testPythonLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "```\ndef hello_world():\n    print(\"Hello\")\n\nif __name__ == \"__main__\":\n    hello_world()\n```"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "python")
        } else {
            Issue.record("Expected .codeFile(language: 'python')")
        }
    }

    @Test("Language detection - JavaScript")
    func testJavaScriptLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "```\nconst x = 10;\nfunction add(a, b) {\n  console.log(a);\n  return a + b;\n}\n```"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "javascript")
        } else {
            Issue.record("Expected .codeFile(language: 'javascript')")
        }
    }

    @Test("Language detection - JSON")
    func testJSONLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "```\n{\n  \"id\": 123,\n  \"name\": \"Test\",\n  \"tags\": [\"a\", \"b\"]\n}\n```"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "json")
        } else {
            Issue.record("Expected .codeFile(language: 'json')")
        }
    }

    @Test("Language detection - Bash")
    func testBashLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "```\n#!/bin/bash\necho \"Running script\"\nls -la\nchmod +x script.sh\n```"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "bash")
        } else {
            Issue.record("Expected .codeFile(language: 'bash')")
        }
    }

    @Test("Language detection - SQL")
    func testSQLLanguageDetection() async throws {
        let formatter = ResponseFormatter()
        let content = "```\nSELECT * FROM users WHERE id = 1;\nUPDATE profile SET name = 'John';\n```"
        let detection = await formatter.detectFormat(in: content)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "sql")
        } else {
            Issue.record("Expected .codeFile(language: 'sql')")
        }
    }

    // MARK: - Recommended Format Tests

    @Test("Recommended format - Priority")
    func testRecommendedFormatPriority() async throws {
        let formatter = ResponseFormatter()

        // Code should take priority over Markdown/Table
        let mixedContent = """
        # Results
        Here is the code:
        ```swift
        let x = 1
        ```
        | Col |
        |---|
        | 1 |
        """

        let detection = await formatter.detectFormat(in: mixedContent)

        #expect(detection.containsCode == true)
        #expect(detection.containsTable == true)
        #expect(detection.containsMarkdown == true)

        if case .codeFile(let language) = detection.recommendedFormat {
            #expect(language == "swift")
        } else {
            Issue.record("Expected .codeFile due to presence of code block")
        }
    }

    @Test("Recommended format - Markdown File")
    func testRecommendedFormatMarkdown() async throws {
        let formatter = ResponseFormatter()

        // No code, but contains markdown or table
        let content = "# Report\n\n- Point 1\n- Point 2"
        let detection = await formatter.detectFormat(in: content)

        #expect(detection.containsMarkdown == true)
        #expect(detection.containsCode == false)

        if case .markdownFile = detection.recommendedFormat {
            // Correct
        } else {
            Issue.record("Expected .markdownFile")
        }
    }

    // MARK: - Edge Cases

    @Test("Format detection - character limits")
    func testCharacterLimits() async throws {
        let formatter = ResponseFormatter()

        // Boundary check: exactly limit (4000)
        let exactLimitContent = String(repeating: "A", count: 4000)
        let detection1 = await formatter.detectFormat(in: exactLimitContent)
        #expect(detection1.estimatedCharacterCount == 4000)
        #expect(detection1.exceedsMessageLimit == false)

        // Boundary check: just over limit (4001)
        let overLimitContent = String(repeating: "A", count: 4001)
        let detection2 = await formatter.detectFormat(in: overLimitContent)
        #expect(detection2.estimatedCharacterCount == 4001)
        #expect(detection2.exceedsMessageLimit == true)
    }

    @Test("Format detection - empty content")
    func testEmptyContent() async throws {
        let formatter = ResponseFormatter()

        let detection = await formatter.detectFormat(in: "")
        #expect(detection.estimatedCharacterCount == 0)
        #expect(detection.containsCode == false)
        #expect(detection.containsTable == false)
        #expect(detection.containsMarkdown == false)

        if case .plainText = detection.recommendedFormat {
            // Correct
        } else {
            Issue.record("Expected .plainText for empty content")
        }
    }

    @Test("Response Formatter initialization")
    func testResponseFormatterInitialization() async throws {
        let formatter = ResponseFormatter()
        #expect(true) // Should initialize without crashing
    }
}
