# Xcode Project Creation (Manual)

These steps create an Xcode project for the existing SwiftPM-based app and include the current sandbox entitlements file.

## Option A: Create Project From `Package.swift` (Recommended)
1. Open Xcode.
2. Choose **File > Open…**.
3. Select `Package.swift` at the repository root.
4. When prompted, select **Open as a Project**.
5. Wait for SwiftPM to resolve the package.
6. Select the `QuantumBadger` scheme and run.

## Option B: Generate an Xcode Project File
If you prefer a dedicated `.xcodeproj`:
1. Open Terminal.
2. Run this from the repository root:
   ```sh
   swift package generate-xcodeproj
   ```
3. Open the generated `QuantumBadger.xcodeproj`.

Note: If you see permission warnings related to SwiftPM cache directories, grant access or re-run with sufficient permissions.

## Add Sandbox Entitlements
1. Ensure the app target has **App Sandbox** enabled in **Signing & Capabilities**.
2. Attach the existing entitlements file at `Sources/QuantumBadgerApp/QuantumBadger.entitlements`.

Current baseline entitlements (least-privilege defaults):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

Why `read-write`? The app uses `NSSavePanel` for exporting logs and security-scoped bookmarks for local model folders and local search roots, both of which require user-selected read/write access.

## Add Biometric Usage Description (Touch ID)
In the target **Info** tab (or Info.plist), add:
- **Key**: `NSFaceIDUsageDescription`
- **Value**: `Quantum Badger requires authentication to access your encrypted vault.`

## Keychain Sharing (Only If Required)
If you need Keychain access across multiple apps or extensions, enable **Keychain Sharing** in **Signing & Capabilities**.  
For a single app with no sharing, this is optional.

## Optional Capabilities (Only If Required)
- **Network client** (`com.apple.security.network.client`): only if a user explicitly enables cloud connectors in-app.
- **Apple Events**: only if you later add user-mediated automation.

## Notes
- Quantum Badger is local-first and should default to no network access.
- Use security-scoped bookmarks for any file access beyond the user-selected access window.

## XPC Helper (Untrusted Parser)
Quantum Badger includes a minimal XPC helper for untrusted parsing.

1. In Xcode, add a new **XPC Service** target and set its bundle identifier to:
   - `com.quantumbadger.UntrustedParser`
2. Use `Sources/QuantumBadgerUntrustedParser/main.swift` as the service entry point.
3. Ensure the main app and XPC service are both sandboxed.
4. Attach the entitlements file:
   - `Sources/QuantumBadgerUntrustedParser/QuantumBadgerUntrustedParser.entitlements`
4. If you change the service bundle identifier, update the client in:
   - `Sources/QuantumBadgerRuntime/Tools/XPC/UntrustedParsingXPC.swift`

Note: SwiftPM builds the helper target as an executable. Xcode needs the XPC Service target wired so the app can launch it as a mach service.

## XPC Helpers (High-Risk Tools)
Filesystem writes and database queries run in isolated XPC services.

### File Writer XPC
1. Add an **XPC Service** target with bundle identifier:
   - `com.quantumbadger.FileWriter`
2. Set its entry point to:
   - `Sources/QuantumBadgerFileWriter/main.swift`
3. Attach entitlements:
   - `Sources/QuantumBadgerFileWriter/QuantumBadgerFileWriter.entitlements`
4. Ensure the Info.plist for the service uses the Mach service name:
   - `Sources/QuantumBadgerFileWriter/Info.plist`
5. If you rename the service, update:
   - `Sources/QuantumBadgerRuntime/Tools/XPC/FileWriterXPC.swift`

### Secure DB XPC
1. Add an **XPC Service** target with bundle identifier:
   - `com.quantumbadger.SecureDB`
2. Set its entry point to:
   - `Sources/QuantumBadgerSecureDB/main.swift`
3. Attach entitlements:
   - `Sources/QuantumBadgerSecureDB/QuantumBadgerSecureDB.entitlements`
4. Ensure the Info.plist for the service uses the Mach service name:
   - `Sources/QuantumBadgerSecureDB/Info.plist`
5. If you rename the service, update:
   - `Sources/QuantumBadgerRuntime/Tools/XPC/DatabaseQueryXPC.swift`

### Entitlement Notes
- Both services use `com.apple.security.inherit` so they inherit the app sandbox.
- The app target should remain sandboxed with user-selected read/write access only.
