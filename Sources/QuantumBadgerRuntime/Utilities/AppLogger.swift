import Foundation
import os

enum AppLogger {
    static let subsystem = "com.quantumbadger.app"
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let security = Logger(subsystem: subsystem, category: "security")
    static let policy = Logger(subsystem: subsystem, category: "policy")
}
