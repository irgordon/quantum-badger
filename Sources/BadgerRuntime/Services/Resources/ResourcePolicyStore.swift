import Foundation
import Observation
import BadgerCore
import AppKit

@Observable
public final class ResourcePolicyStore {
    public static let shared = ResourcePolicyStore()
    
    private enum Keys {
        static let isSafeModeEnabled = "qb.resource.isSafeModeEnabled"
    }

    public var isSafeModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isSafeModeEnabled) }
        set { 
            UserDefaults.standard.set(newValue, forKey: Keys.isSafeModeEnabled)
            if newValue {
                Task { await ModelLoader.shared.unloadActiveRuntime() }
            }
        }
    }
    
    public var memoryPressure: DispatchSource.MemoryPressureEvent = .normal
    private var pressureSource: DispatchSourceMemoryPressure?
    
    /// Apps that consume significant RAM and should trigger an immediate LLM purge.
    private enum HeavyApps {
        static let identifiers = [
            "com.apple.dt.Xcode",
            "com.apple.FinalCut",
            "com.adobe.PremierePro",
            "com.apple.logic10",
            "com.blackmagic-design.DaVinciResolve"
        ]
    }
    
    // Simulate finding hardware specs
    var isBaselineHardware: Bool {
        return ProcessInfo.processInfo.physicalMemory < 16 * 1024 * 1024 * 1024
    }

    public init() {
        setupMemoryPressureMonitoring()
        setupHeavyAppMonitoring()
    }
    
    private func setupHeavyAppMonitoring() {
        // Watch for workspace app launches
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            if HeavyApps.identifiers.contains(bundleID) && self.isBaselineHardware {
                print("ResourcePolicy: Heavy app detected (\(bundleID)). Triggering proactive purge.")
                Task { await ModelLoader.shared.unloadActiveRuntime() }
            }
        }
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            self.memoryPressure = event
            
            // If we hit Warning or Critical on 8GB hardware, we purge immediately
            if (event == .warning || event == .critical) && self.isBaselineHardware {
                print("ResourcePolicy: System memory pressure is high. Evicting LLM.")
                Task { await ModelLoader.shared.unloadActiveRuntime() }
            }
        }
        
        source.resume()
        self.pressureSource = source
    }
}
