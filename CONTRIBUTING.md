Here is a professional `CONTRIBUTING.md` tailored specifically for Apple platform developers. It emphasizes the strict Swift 6 concurrency model and modular architecture used in Quantum Badger.

---

# Contributing to Quantum Badger

First off, thank you for considering contributing to Quantum Badger! 🦡

We are building the next generation of privacy-focused AI assistants for macOS and iOS. To maintain the high performance and security standards of this project, we follow a strict set of guidelines tailored to the modern Apple development ecosystem.

## 🛠 Prerequisites

Before you start, ensure your development environment meets these requirements:

* **Xcode 16.0+** (Required for Swift 6 strict concurrency checks)
* **macOS 15.0+** (Sequoia) or **iOS 18.0+**
* **Apple Silicon Mac** (Strongly recommended for local inference testing)

## 🚀 Getting Started

1. **Fork and Clone**
```bash
git clone https://github.com/irgordon/quantum-badger.git
cd quantum-badger

```


2. **Open the Project**
Open `QuantumBadger.xcodeproj`. Xcode will automatically resolve the Swift Package Manager (SPM) dependencies (`MLX`, `BadgerCore`, etc.).
3. **Verify the Build**
Select the **Quantum Badger (macOS)** scheme and press `Cmd+B`. Ensure there are **zero warnings** regarding concurrency. We treat concurrency warnings as errors.

## 🏗 Project Architecture

To contribute effectively, it helps to understand the three-tier modular architecture:

* **`BadgerApp` (UI Layer):** Contains all SwiftUI Views, ViewModels, and the App Coordinator. This is the only layer that should import `SwiftUI`.
* **`BadgerRuntime` (Logic Layer):** Handles the "Brain." This includes the `ShadowRouter`, `LocalInferenceEngine` (MLX), `CloudInferenceService`, and System Monitoring actors.
* **`BadgerCore` (Data Layer):** Shared data models, protocols, and entities. This layer has **no dependencies** on UI or heavy runtime logic.

> **Tip:** When adding a new feature, try to implement the logic in `BadgerRuntime` and only use `BadgerApp` for the visual representation.

## 📐 Coding Guidelines

We adhere to **Strict Swift 6** and **Apple's Human Interface Guidelines**.

### 1. Swift 6 Concurrency

This project uses Strict Concurrency Checking (`Target -> Build Settings -> Strict Concurrency -> Complete`).

* **Actors Everywhere:** Use `actor` for any shared mutable state (e.g., `VRAMMonitor`, `ServiceManagers`).
* **MainActor UI:** Ensure all ViewModels and UI-updates are annotated with `@MainActor`.
* **Sendable:** Ensure all data types passed between boundaries conform to `Sendable`.
* **No `DispatchQueue`:** Avoid Grand Central Dispatch (GCD). Use Swift structured concurrency (`Task`, `TaskGroup`, `async/await`) exclusively.

### 2. Style & Formatting

* **Naming:** Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
* **Linting:** We use `SwiftLint`. Please run `swiftlint` before committing to ensure your code is clean.
* **Documentation:** Public APIs must have documentation comments (`///`).

### 3. Apple HIG Compliance

* Use standard SF Symbols (`.symbolRenderingMode(.hierarchical)` is preferred).
* Respect system materials (`.ultraThinMaterial`, `.regularMaterial`) for backgrounds.
* Ensure all distinct actions have clear feedback (e.g., haptics or visual transitions).

## 🧪 Testing

We rely on XCTest for stability.

* **Unit Tests:** If you add logic to `BadgerRuntime`, add a corresponding test case.
* **UI Tests:** Critical user flows (Onboarding, Chat) are covered by UI tests. Run `Cmd+U` to verify regressions.

**Note on Models:** Do not commit large `.gguf` model weights to the repository. The app handles downloading these in the "Settings" menu.

## 📮 Submission Process

1. **Create a Branch:** `git checkout -b feature/my-new-feature`
2. **Commit Changes:** Keep commit messages clear and imperative (e.g., "Add thermal throttling logic," not "Added thermal stuff").
3. **Push:** `git push origin feature/my-new-feature`
4. **Open a Pull Request:**
* Link to any relevant Issues.
* Include screenshots if your changes affect the UI.
* Verify that all CI checks (Build, Test, Lint) pass.



## 🛡️ Security Policy

Because this is a privacy-focused assistant:

* **Never** log raw user prompts or PII to the console (`print()`). Use the `AuditLogService` for secure, redacted logging.
* **Never** disable `App Transport Security` exceptions without a documented reason.
* If you find a security vulnerability, please report it privately via [Security Advisory Link] instead of opening a public issue.

## 🤝 Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all, regardless of level of experience, gender identity and expression, sexual orientation, disability, personal appearance, body size, race, ethnicity, age, religion, nationality, or other similar characteristic.

By participating in this project, you agree to abide by our Code of Conduct.

---

Happy Coding! 
