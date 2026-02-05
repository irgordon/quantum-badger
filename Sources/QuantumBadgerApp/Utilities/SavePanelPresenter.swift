import AppKit
import Foundation

@MainActor
enum SavePanelPresenter {
    static func present(defaultFileName: String, allowedFileTypes: [String]) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = defaultFileName
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowedFileTypes = allowedFileTypes

            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
