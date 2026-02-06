import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case memory
    case advanced

    var id: String { rawValue }
}
