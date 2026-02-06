import AppKit

enum AppRestartManager {
    @MainActor
    static func relaunch(afterSave save: (@MainActor () async -> Void)? = nil) {
        Task {
            if let save {
                await save()
            }
            let appURL = Bundle.main.bundleURL
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
                NSApp.terminate(nil)
            }
        }
    }
}
