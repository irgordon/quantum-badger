# Quantum Badger

<p align="center">
  <img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

## Overview
Quantum Badger is your private, always‑available digital assistant that works quietly in the background to keep life running smoothly. It remembers what matters, helps manage tasks, and delivers timely updates—only reaching out when it’s genuinely useful. Thoughtfully designed with privacy at its core, Quantum Badger connects securely to trusted services when needed, while keeping you firmly in control. No noise, no surprises—just a dependable partner that stays one step ahead, so you don’t have to.

## Why Quantum Badger
- Local‑first by default: inference, memory, and logs stay on-device.
- Strong guardrails: explicit approvals, scoped capabilities, and auditable actions.
- Native macOS behavior: SwiftUI-first UI, App Sandbox, security-scoped bookmarks.
- Secure storage: CryptoKit + Keychain/Secure Enclave for secrets and vault data.

## System Requirements
- macOS 13 (Ventura) or newer
- Apple Silicon recommended (Intel supported if models allow)
- Xcode 15+ or Swift 5.9+ toolchain

## Quick Start
1. Open the repository as a Swift Package in Xcode.
2. Build and run the `QuantumBadgerApp` target.
3. In Settings, choose a local model and configure allowed tools/web domains.

## Architecture
- **UI Shell**: SwiftUI + Observation for state management.
- **Orchestrator**: intent → plan → policy evaluation → tool/model execution.
- **Tool Runtime**: capability-gated tools with timeouts, limits, and audit logs.
- **Model Runtime**: pluggable local/cloud adapters with policy‑gated prompts.
- **Security Layer**: Keychain/SE keys, redaction, permissions, audit chain.
- **XPC Helpers**: isolated parsing for untrusted content.

## Key Technologies (Tech Stack)
- Swift 6, SwiftUI, Observation (`@Observable`)
- SwiftData (local persistence)
- CryptoKit + Keychain + Secure Enclave
- App Sandbox + security-scoped bookmarks
- Network framework + URLSession (policy‑gated)
- NSSharingService + AppIntents (messaging drafts)
- XPC services for untrusted parsing

## Contributing
- Keep changes scoped and reviewable.
- Prefer safety and correctness over cleverness.
- Follow the existing approval, policy, and audit patterns.

## Documentation & License
- Documentation: `Sources/QuantumBadgerApp/XCODE_PROJECT.md`, `AUDIT_REPORT.md`
- License: MIT License `LICENSE.md`
