# Quantum Badger Remediation Plan

This plan outlines the required actions to address security vulnerabilities, architectural gaps, and code quality issues identified in the May 2026 Audit and the Deterministic Repository Scan.

## Classification Legend
*   **P0**: Build failure, missing core subsystem, or crash-on-start.
*   **P1**: Broken contract surface or missing required implementation.
*   **P2**: Unsafe patterns or nondeterministic behavior.
*   **P3**: Missing tests or incomplete coverage.
*   **P4**: Performance or maintainability issues.
*   **P5**: Cosmetic or documentation issues.

---

## P0 — Critical Implementation Failures

### 1. Shadow Router Data Exfiltration
*   **Issue**: User prompts are unconditionally sent to cloud providers for intent analysis, even if "Local First" is selected or no consent is given.
*   **Source**: `AUDIT-2026-05-07.md`, `BadgerRuntime/Sources/BadgerRuntime/Router/ShadowRouter.swift`.
*   **Remediation**:
    *   Implement a local heuristic-first intent analyzer.
    *   Gate cloud-based analysis behind explicit user consent.
    *   Default to local execution when in doubt.

### 2. Security Policy Non-Enforcement
*   **Issue**: `AppCoordinator` and `HybridExecutionManager` do not respect `isLockdown` or `allowsRemoteOperations` flags.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Inject `SecurityPolicyManager` into the execution pipeline.
    *   Add hard `guard` checks before any network or cloud inference calls.

---

## P1 — High Priority Architectural Gaps

### 1. Missing Core Security Services
*   **Issue**: `FileManagerService` and `RateLimiter` are referenced in specs but missing from implementation.
*   **Source**: `AUDIT-2026-05-07.md`, `scan_results.json` (File inventory).
*   **Remediation**:
    *   Implement `FileManagerService` to provide sandboxed file access and magic-number validation.
    *   Implement `RateLimiter` to prevent resource exhaustion and DoS.

### 2. PII Leakage in Audit Logs
*   **Issue**: Raw command prefixes are logged to the audit trail without sanitization.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Pipe all log data through `InputSanitizer` before persistence.
    *   Limit log verbosity for sensitive command types.

---

## P2 — Security & Stability Risks

### 1. Divergent Privacy Logic
*   **Issue**: `InputSanitizer` and `PrivacyEgressFilter` use inconsistent regex patterns for PII detection.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Consolidate patterns into a unified `PrivacyRegistry` in `BadgerCore`.

### 2. Unencrypted Persistent Logs
*   **Issue**: Audit logs are tamper-evident but readable by anyone with filesystem access.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Encrypt log blocks using `AES-GCM` with keys managed by the Secure Enclave.

### 3. Unsafe Programming Patterns (`try!`)
*   **Issue**: Use of `try!` for regex initialization could lead to runtime crashes if patterns are malformed.
*   **Source**: `scan_results.json`, `BadgerCore/Sources/BadgerCore/Privacy/PrivacyEgressFilter.swift:28`.
*   **Remediation**:
    *   Replace `try!` with proper error handling or static initialization that handles errors gracefully.

---

## P3 — Testing & Robustness

### 1. Incomplete Test Suites
*   **Issue**: Placeholder empty functions found in test files.
*   **Source**: `scan_results.json`, `BadgerCore/Tests/BadgerCoreTests/ShadowRouterTests.swift:23`.
*   **Remediation**:
    *   Implement missing test logic for `ShadowRouter` edge cases.

### 2. Brittle Intent Parsing
*   **Issue**: `ShadowRouter` uses regex for JSON parsing from cloud responses.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Implement robust JSON parsing with fallback and repair mechanisms.

---

## P4 — Maintenance & Performance

### 1. Versioning Inconsistency
*   **Issue**: Static version strings are duplicated across `BadgerRuntime` and `BadgerCore`.
*   **Source**: `AUDIT-2026-05-07.md`.
*   **Remediation**:
    *   Centralize versioning in a shared `.xcconfig` or build-time variable.

### 2. Benchmark Cleanup
*   **Issue**: Numerous `try!` instances in benchmark scripts.
*   **Source**: `scan_results.json`, `benchmark_html_processing.swift`.
*   **Remediation**:
    *   Refactor benchmarks to use safe pattern matching, ensuring reliability during automated CI runs.

---

## P5 — Cosmetic & Documentation

### 1. Repository TODOs
*   **Issue**: Placeholder comments in git hooks and documentation.
*   **Source**: `scan_results.json`.
*   **Remediation**:
    *   Review and resolve `TODO` markers in `.git/hooks/sendemail-validate.sample`.
