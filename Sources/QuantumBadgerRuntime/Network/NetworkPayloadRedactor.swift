import Foundation

enum NetworkPayloadRedactor {
    // Scrub JSON payloads by redacting sensitive strings while preserving structure.
    static func redactJSONPayload(_ data: Data) -> (data: Data, didRedact: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return (data, false)
        }
        let (redactedObject, didRedact) = redactValue(object)
        guard didRedact else {
            return (data, false)
        }
        guard JSONSerialization.isValidJSONObject(redactedObject),
              let redactedData = try? JSONSerialization.data(withJSONObject: redactedObject, options: []) else {
            return (data, false)
        }
        return (redactedData, true)
    }

    static func isLikelyJSON(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
    }

    private static func redactValue(_ value: Any) -> (Any, Bool) {
        if let dict = value as? [String: Any] {
            var updated: [String: Any] = [:]
            updated.reserveCapacity(dict.count)
            var didRedact = false
            for (key, entry) in dict {
                let (newValue, changed) = redactValue(entry)
                updated[key] = newValue
                didRedact = didRedact || changed
            }
            return (updated, didRedact)
        }

        if let array = value as? [Any] {
            var updated: [Any] = []
            updated.reserveCapacity(array.count)
            var didRedact = false
            for entry in array {
                let (newValue, changed) = redactValue(entry)
                updated.append(newValue)
                didRedact = didRedact || changed
            }
            return (updated, didRedact)
        }

        if let string = value as? String {
            let result = PromptRedactor.redact(string)
            return (result.redactedText, result.hadSensitiveData)
        }

        return (value, false)
    }
}
