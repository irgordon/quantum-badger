# 🦡 Quantum Badger

<p align="center">
<img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

**Quantum Badger** is a local‑first, privacy‑obsessed assistant for macOS that works quietly in the background and keeps your data where it belongs—on your Mac. It handles the busywork, remembers what matters, and helps you stay organized without ever trading away your privacy or control.

---

## 🏗️ Architecture: The Sovereign Assembly

The project utilizes a modular architecture to satisfy macOS Sandboxing requirements and avoid MLX framework collisions.

### 1. The App Layer (`/Sources/BadgerApp`)

- **Environment:** macOS 15.0+ (Sequoia+)
- **Responsibility:** SwiftUI View layer, App Lifecycle, User Entitlements, and Coordinator logic.
- **Linkage:** Imports `BadgerCore`, `BadgerRuntime`, and `BadgerRemote`.

### 2. The Runtime Layer (`/Sources/BadgerRuntime`)

- **Type:** Core Logic Library
- **Responsibility:** Contains the MLX Model Loaders, Orchestrator, and Tool implementations.
- **Dependencies:** Depends on `BadgerCore` and `mlx-swift`.

### 3. Shared & Remote Layers

- **BadgerCore (`/Sources/BadgerCore`):** Shared types, protocols, and distinct capabilities like Security and Logging.
- **BadgerRemote (`/Sources/BadgerRemote`):** Sandbox-safe networking and remote control handling.
- **FileWriterService (`/Sources/FileWriterService`):** XPC service for authorized disk I/O.

---

## 🛡️ Core Principles

Quantum Badger is founded on **Local-First Sovereignty**. Unlike traditional agents that act as "Cloud Proxies," Badger treats the cloud as a secondary utility.

### 1. Identity-Bound Sovereignty

Your agent's memory and permissions are cryptographically tethered to a hardware-backed **Root Identity**.

- **Stable Fingerprinting:** Uses `IdentityFingerprinter` to generate a stable, device-bound identity string from the Secure Enclave.
- **Biometric Guarding:** Sensitive actions require user authentication, ensuring that only the verified user can authorize critical operations.

### 2. Forensic Transparency

Badger creates a verifiable record of its operations.

- **Audit Logging:** An immutable `AuditLog` records all system events, network attempts, and security violations.
- **Transparency:** Designed to provide a clear, tamper-evident history of the agent's reasoning process (currently implementing console-based audit trails).

### 3. Dynamic Reasoning & Planning

Badger analyzes your intent using a local reasoning loop to build safe, multi-step plans.

- **Workflow Persistence:** Utilizes **SwiftData** via `WorkflowPersistence` to save and restore agent plans, ensuring state is preserved across app launches.
- **Schema-Locked Tools:** Tools are validated against a strict manifest.
- **Side-Effect-Free Reasoning:** Planning happens in a sandbox where execution is disabled until the user validates the plan.

---

## 📉 Hardware Intelligence (The 8GB Baseline)

Quantum Badger is the first agent optimized for the "Unified Memory" constraints of baseline M-series Macs. It treats your RAM as a scarce, shared commodity.

### The "Yield-First" Memory Policy

- **The 30-Second Rule:** On baseline hardware, local models are automatically purged from VRAM after **30 seconds of inactivity**, returning ~4GB of RAM to the OS instantly.
- **Context Capping:** Conversation context is capped at **2048 tokens** on 8GB machines to prevent system OOM (Out of Memory) crashes.
- **Heavy-App Sentinel:** If you launch a professional tool (Xcode, Final Cut Pro), Badger proactively evicts its LLM to give your project maximum headroom.

### Cloud-Only Safe Mode

When you need 100% of your local silicon for heavy creative tasks, toggle **Safe Mode**.

- **Zero Footprint:** Offloads all reasoning to **ChatGPT** via macOS 16’s native secure integration, pinning local RAM usage to zero.
- **The Redaction Gate:** Badger’s local policy engine redacts sensitive data from your prompts _before_ they are sent to the cloud.

---

## 🛠️ Security Architecture

| Feature        | Logic                            | Human-in-the-Loop (HITL)    |
| -------------- | -------------------------------- | --------------------------- |
| **Messaging**  | Delegate-verified native sharing | Mandatory User Confirmation |
| **Filesystem** | Vault-labeled path references    | Mandatory User Confirmation |
| **Automation** | System-operator capability scan  | Mandatory User Confirmation |
| **Identity**   | Stable Key-Data Fingerprinting   | Automated Validation        |

---

## 🚀 Getting Started

### Prerequisites

- **Xcode 16.0+**
- **macOS 15.0+**
- **Apple Silicon (M1/M2/M3/M4+)**: Required for MLX acceleration.

### Build Instructions

1. Clone the repository.
2. Open `Package.swift` or the generic workspace.
3. Ensure packages are resolved.
4. Select the **BadgerApp** Scheme and press `Cmd + B`.

---

## ⚖️ License

**The MIT License (MIT)**
Copyright (c) 2026 Quantum Badger Contributors.
_Permission is hereby granted, free of charge, to any person obtaining a copy of this software... (See LICENSE file for full text)._

---

**Sovereignty isn't just a feature; it's the architecture.** Welcome to the workshop. 🦡

---
