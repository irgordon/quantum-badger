import AppKit
import Foundation

@MainActor
enum FolderPickerPresenter {
    static func present() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"

        let response = panel.runModal()
        if response == .OK {
            return panel.urls
        }
        return []
    }
}
