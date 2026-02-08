# 🦡 Quantum Badger

<p align="center">
<img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

**Quantum Badger** is a local-first, privacy-obsessed autonomous agent for macOS. Built for the high-concurrency demands of 2026, it turns your Mac into a private sanctuary for AI reasoning, ensuring that your data, your intent, and your hardware remains entirely under your control.

---

## 🏗️ Architecture: The Sovereign Assembly

The project utilizes a dual-layer architecture to satisfy macOS Sandboxing requirements and avoid MLX framework collisions.

### 1. The App Layer (`/QuantumBadgerApp`)

* **Environment:** macOS 14.0+ (Sonoma/Sequoia+)
* **Responsibility:** SwiftUI View layer, App Lifecycle, User Entitlements, and Coordinator logic.
* **Linkage:** Dynamically imports the `QuantumBadgerEngine` library.

### 2. The Runtime Layer (`/QuantumBadgerRuntime`)

* **Type:** Local Swift Package
* **Library Product:** `QuantumBadgerEngine` (Dynamic Library)
* **Logic:** Contains the MLX Model Loaders, SecureDB, and Protocol definitions.
* **XPC Helpers:** 5 independent executable targets for isolated, sandboxed tasks:
* `WebScout`: Sandboxed networking and scraping.
* `UntrustedParser`: Isolated file parsing.
* `SecureDB`: Encrypted local vector storage.
* `FileWriter`: Authorized disk I/O via Security Bookmarks.
* `Messaging`: Encrypted local communications.



---

## 🛡️ Core Principles

Quantum Badger is founded on **Local-First Sovereignty**. Unlike traditional agents that act as "Cloud Proxies," Badger treats the cloud as a secondary utility, not a requirement.

### 1. Identity-Bound Sovereignty

Your agent's memory, permissions, and encryption keys are cryptographically tethered to a hardware-backed **Root Identity**.

* **Handshake Integrity:** Onboarding is re-triggered automatically if your core local identity key data changes.
* **Biometric Guarding:** Sensitive actions (sending messages, modifying files) require mandatory Touch ID or Optic ID approval.

### 2. Forensic Transparency

Badger provides an immutable, append-only **Audit Log** of every thought and action.

* **Sovereignty Receipts:** Generate signed PDF receipts of any interaction, proving the provenance and integrity of the agent's reasoning.
* **Integrity Status:** Every message is cryptographically checked for tampered content.

### 3. Dynamic Reasoning & Planning

Badger analyzes your intent using a local reasoning loop to build safe, multi-step plans.

* **Schema-Locked Tools:** Every tool is validated against the `AppIntentScanner` manifest. Badger can't use tools that haven't been verified.
* **Side-Effect-Free Reasoning:** Planning happens in a sandbox where tool-loop execution is physically disabled until the user approves the plan.

---

## 📉 Hardware Intelligence (The 8GB Baseline)

Quantum Badger is the first agent optimized for the "Unified Memory" constraints of baseline M-series Macs. It treats your RAM as a scarce, shared commodity.

### The "Yield-First" Memory Policy

* **The 30-Second Rule:** On baseline hardware, local models are automatically purged from VRAM after **30 seconds of inactivity**, returning ~4GB of RAM to the OS instantly.
* **Context Capping:** Conversation context is capped at **2048 tokens** on 8GB machines to prevent system OOM (Out of Memory) crashes.
* **Heavy-App Sentinel:** If you launch a professional tool (Xcode, Final Cut Pro), Badger proactively evicts its LLM to give your project maximum headroom.

### Cloud-Only Safe Mode

When you need 100% of your local silicon for heavy creative tasks, toggle **Safe Mode**.

* **Zero Footprint:** Offloads all reasoning to **ChatGPT** via macOS 16’s native secure integration, pinning local RAM usage to zero.
* **The Redaction Gate:** Badger’s local policy engine redacts sensitive data from your prompts *before* they are sent to the cloud.

---

## 🛠️ Security Architecture

| Feature | Logic | Human-in-the-Loop (HITL) |
| --- | --- | --- |
| **Messaging** | Delegate-verified native sharing | Mandatory User Confirmation |
| **Filesystem** | Vault-labeled path references | Mandatory User Confirmation |
| **Automation** | System-operator capability scan | Mandatory User Confirmation |
| **Identity** | Stable Key-Data Fingerprinting | Automated Validation |

---

## 🚀 Getting Started

### Prerequisites

* **Xcode 26.3+**
* **macOS 14.0+**
* **Apple Silicon (M1/M2/M3/M4+)**: Required for MLX acceleration.

### Build Instructions

1. Clone the repository.
2. Open `Quantum Badger.xcworkspace`.
3. Ensure the `QuantumBadgerRuntime` local package is resolved (Right-click > Resolve Package Versions).
4. Select the **Quantum Badger** App Scheme and press `Cmd + B`.

---

## ⚖️ License

**The MIT License (MIT)**
Copyright (c) 2026 Quantum Badger Contributors.
*Permission is hereby granted, free of charge, to any person obtaining a copy of this software... (See LICENSE file for full text).*

---

**Sovereignty isn't just a feature; it's the architecture.** Welcome to the workshop. 🦡

---
