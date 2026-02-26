
import Foundation

// --- Mocks ---

class Benchmark {
    static let scriptRegex = try! NSRegularExpression(pattern: #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#)
    static let styleRegex = try! NSRegularExpression(pattern: #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#)
    static let htmlTagRegex = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    static let jsSchemeRegex = try! NSRegularExpression(pattern: #"javascript:[^\s\"']+"#)
    static let eventHandlerRegex = try! NSRegularExpression(pattern: #"on\w+\s*=\s*['\"]?[^'\"\s>]+"#)
    static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
}

// --- Helper Functions ---

func replaceMatches(in text: String, regex: NSRegularExpression, with template: String) -> String {
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}

func current_stripHTML(_ html: String) -> String {
    var result = html
    result = replaceMatches(in: result, regex: Benchmark.scriptRegex, with: "")
    result = replaceMatches(in: result, regex: Benchmark.styleRegex, with: "")
    result = replaceMatches(in: result, regex: Benchmark.htmlTagRegex, with: " ")
    return current_decodeHTMLEntities(result)
}

func current_stripJavaScript(_ text: String) -> String {
    var result = text
    result = replaceMatches(in: result, regex: Benchmark.jsSchemeRegex, with: "")
    result = replaceMatches(in: result, regex: Benchmark.eventHandlerRegex, with: "")
    return result
}

func current_normalizeWhitespace(_ text: String) -> String {
    replaceMatches(in: text, regex: Benchmark.whitespaceRegex, with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func current_decodeHTMLEntities(_ text: String) -> String {
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

func current_process(_ input: String) -> String {
    var textContent = current_stripHTML(input)
    textContent = current_stripJavaScript(textContent)
    textContent = current_normalizeWhitespace(textContent)
    // Assume inputSanitizer does something similar (creates copies)
    return textContent
}


// --- Optimized ---

func optimized_process(_ input: String) -> String {
    let mutableString = NSMutableString(string: input)

    // stripHTML
    optimized_replaceMatches(in: mutableString, regex: Benchmark.scriptRegex, with: "")
    optimized_replaceMatches(in: mutableString, regex: Benchmark.styleRegex, with: "")
    optimized_replaceMatches(in: mutableString, regex: Benchmark.htmlTagRegex, with: " ")
    optimized_decodeHTMLEntities(mutableString)

    // stripJavaScript
    optimized_replaceMatches(in: mutableString, regex: Benchmark.jsSchemeRegex, with: "")
    optimized_replaceMatches(in: mutableString, regex: Benchmark.eventHandlerRegex, with: "")

    // normalizeWhitespace
    optimized_replaceMatches(in: mutableString, regex: Benchmark.whitespaceRegex, with: " ")
    // trimming (requires String conversion or CFStringTrim)
    // For simplicity, convert to String at the end and trim

    return (mutableString as String).trimmingCharacters(in: .whitespacesAndNewlines)
}

func optimized_replaceMatches(in mutableString: NSMutableString, regex: NSRegularExpression, with template: String) {
    regex.replaceMatches(in: mutableString, options: [], range: NSRange(location: 0, length: mutableString.length), withTemplate: template)
}

func optimized_decodeHTMLEntities(_ mutableString: NSMutableString) {
    let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
    ]
    for (entity, replacement) in entities {
        mutableString.replaceOccurrences(of: entity, with: replacement, options: .literal, range: NSRange(location: 0, length: mutableString.length))
    }
}


// --- Test Data ---

let sampleHTML = """
<html>
<head>
    <title>Sample Page</title>
    <style>body { font-family: sans-serif; }</style>
    <script>console.log('test');</script>
</head>
<body>
    <h1>  Hello   World!  &amp; More  </h1>
    <p onclick="alert('xss')">This is a paragraph.</p>
    <a href="javascript:void(0)">Link</a>
</body>
</html>
"""

let iterations = 1000

// --- Measure ---

func measure(name: String, operation: () -> Void) {
    let startTime = DispatchTime.now()
    operation()
    let endTime = DispatchTime.now()
    let nanoTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
    let timeInterval = Double(nanoTime) / 1_000_000_000
    print("\(name): \(timeInterval) seconds")
}

print("Running benchmark with \(iterations) iterations...")

measure(name: "Current Implementation") {
    for _ in 0..<iterations {
        _ = current_process(sampleHTML)
    }
}

measure(name: "Optimized Implementation") {
    for _ in 0..<iterations {
        _ = optimized_process(sampleHTML)
    }
}
