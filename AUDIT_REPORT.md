# Quantum Badger Audit Report (macOS 16 / Swift 6)

Date: 2026-02-05  
Scope: `Sources/QuantumBadgerApp`, `Sources/QuantumBadgerRuntime`, `Sources/QuantumBadgerUntrustedParser`, `Package.swift`, `QuantumBadger.entitlements`

## 1. Mental Model & Data Flow

**Entry points**
- `QuantumBadgerApp` (`Sources/QuantumBadgerApp/QuantumBadgerApp.swift`)
- `AppState` creates capability bundles and runtime services.

**Intent → Execution Path**
1. `ConsoleView` captures user prompt.
2. `Orchestrator.generateResponse()` evaluates prompt policy and loads runtime via `ModelLoader`.
3. `ToolRuntime.run()` executes tools under `PolicyEngine` with audit logging.
4. `MemoryManager`/`MemoryStore` writes encrypted entries with schema validation.
5. `AuditLog` persists tamper-evident records.

**Storage**
- App data: `AppPaths` → `applicationSupportDirectory/QuantumBadger/*`
- Vault, memory, audit logs encrypted using AES-GCM with KEK in Keychain/Secure Enclave.

**Network**
- `NetworkClient` enforces purpose policy, allowlist, HTTPS-only, pinning, redirects, and circuit breaker.
- `WebScoutTool` uses XPC parser for sanitization.

## 2. Entitlements & Sandbox

**Found entitlements** (`Sources/QuantumBadgerApp/QuantumBadger.entitlements`)
- `com.apple.security.app-sandbox` ✅
- `com.apple.security.files.user-selected.read-write` ✅

**Missing in repo**
- No `Info.plist` found (likely Xcode-managed). Ensure `NSFaceIDUsageDescription` is set for Touch ID usage.

## 3. Findings (Tagged by Severity)

| Severity | Component | Issue | Recommendation |
| --- | --- | --- | --- |
| **High** | `ToolRuntime` | Unknown tools are allowed to fall through to stub execution if `ToolCatalog` doesn’t contain the tool. | Hardened in `PolicyEngine.evaluate` to return “Unauthorized tool identifier.” (implemented). |
| **High** | `PolicyEngine.evaluatePrompt` | No explicit prompt-injection/override block for system-level creep. | Added explicit “system override/command injection” pattern check (implemented). |
| **Medium** | `ToolRuntime.buildSearchURL` | Uses `URL(string: ...)!` fallback (force unwrap). | Replace with safe default or guard to avoid crash on unexpected URL construction. |
| **Medium** | `NetworkPolicyStore` | No Info.plist verification in repo; `NSFaceIDUsageDescription` required for Touch ID prompts. | Ensure Info.plist contains Face ID usage description. |
| **Medium** | `LocalSearchTool` | Direct file reads use `Data(contentsOf:)` for whole file; risk on large files even with size guard. | Consider streaming reads for large files or strict extension allowlist. |
| **Low** | `AppPaths` | Uses `applicationSupportDirectory` correctly, but no explicit caches for temp artifacts. | Prefer `cachesDirectory` for derived/temporary outputs. |
| **Low** | `ModelLoader` | When memory pressure blocks load, returns stub runtime without UI hint unless event is handled. | Already posts SystemEvent and banner; verify UI remains visible in all views. |
| **Informational** | `NetworkClient` | HTTPS-only and pinning enforced, `URLSession` ephemeral. | Compliant; ensure allowlist entries include requiredPurpose for each host. |
| **Informational** | `VaultStore`/`MemoryStore` | AES-GCM encryption, Secure Enclave KEK; Keychain access is `WhenUnlockedThisDeviceOnly`. | Compliant with Apple platform security guidelines. |

## 4. Platform & Sandbox Alignment Notes

**Good**
- App Sandbox enabled; file access requires user selection.
- Security-scoped bookmarks used for file access.
- Save/export uses `NSSavePanel` (Powerbox).

**Watch**
- Any future direct `FileManager` writes should flow through `SavePanelPresenter` or security-scoped bookmarks.
- Avoid hard-coded paths (no `/tmp` or `~/` observed in runtime storage).

## 5. Networking & External Services

**Compliant**
- `NetworkClient` enforces HTTPS-only, purpose allowlist, redirect checks, pinning.
- Circuit breaker emits events and audit records.
- Web scouting uses XPC parser; results are filtered and redacted.

**Gaps**
- No `URLSession` usage in model runtime (good). Ensure future cloud runtimes do not bypass `NetworkClient`.

## 6. LLM & Model Safety

**Compliant**
- Model load is blocked during memory pressure.
- Prompt redaction policy applied before inference.

**Gaps**
- No explicit KV-cache optimization or streaming token loop (current stub). This is expected for now but should be noted as performance risk.

## 7. Concurrency & Thread Safety

**Compliant**
- `AppState` is `@MainActor`.
- `NetworkClient` is an actor.
- Tool runtime timeouts and cancellation are enforced.

**Gaps**
- Some heavy parsing/IO still occurs on main thread in a few UI flows (check `ConsoleView` and `SettingsView` for large JSON).

## 8. UI & macOS Standards

**Compliant**
- Privacy shield obscures UI when inactive.
- Menu bar extra shows mode + network state.

**Gaps**
- Accessibility labels for some custom toolbars should be verified.

## 9. Security Helpers & Enforcement

**Compliant**
- `PolicyEngine` is centralized.
- `SecretRedactor` is applied to tool output.
- `PromptRedactor` applied before model prompts.

**Gaps**
- Ensure any future direct `FileManager` usage is always under `BookmarkStore` / `SavePanelPresenter`.

## 10. Recommended Next Steps (Shortlist)
1. Replace force unwrap in `ToolRuntime.buildSearchURL` with safe guard + fallback.
2. Confirm `NSFaceIDUsageDescription` exists in Info.plist.
3. Add streaming file reads or strict extension allowlist to `LocalSearchTool`.
4. Validate any future cloud runtime uses `NetworkClient` exclusively.

