import Foundation

/// Centralized application file paths.
///
/// - Note: Using a struct with static 'live' and 'test' configurations allows
///         for safe unit testing without wiping user data.
public struct AppPaths: Sendable {
    public let rootDirectory: URL
    public let taskGoalsURL: URL
    public let auditEventsURL: URL

    /// The production configuration using the User's Application Support directory.
    public static let shared: AppPaths = {
        // 🔒 SAFETY: Safe fallback if sandbox is broken
        // Force unwrap removed to prevent crash-on-launch
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = paths.first ?? FileManager.default.temporaryDirectory
        return AppPaths(root: root.appendingPathComponent("QuantumBadger", isDirectory: true))
    }()

    public init(root: URL) {
        self.rootDirectory = root
        self.taskGoalsURL = root.appendingPathComponent("task_goals.json")
        self.auditEventsURL = root.appendingPathComponent("audit_events.json")
    }

    /// Explicit setup method to handle filesystem side effects.
    /// Call this early in App startup (e.g., AppDelegate or App init).
    public func ensureDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

/// Robust JSON persistence utility.
public struct JSONStore {
    
    public enum LoadError: Error {
        case fileNotFound
        case corruption(Error)
    }

    /// Load a `Decodable` value from a file URL.
    ///
    /// - Returns: The decoded value.
    /// - Throws: `LoadError.fileNotFound` if safe to ignore,
    ///           or `LoadError.corruption` if data exists but is invalid.
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Distinguish missing file from access denied
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                throw LoadError.fileNotFound
            }
            throw error
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LoadError.corruption(error)
        }
    }
    
    /// Save an `Encodable` value to a file URL.
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // ⚡️ Easier debugging
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
