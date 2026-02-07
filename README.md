# Quantum Badger

<p align="center">
  <img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

**Quantum Badger** is a local-first, privacy-obsessed autonomous agent for macOS. Built for the high-concurrency demands of 2026, it turns your Mac into a private sanctuary for AI reasoning, ensuring that your data, your intent, and your hardware remains entirely under your control.

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

Badger doesn't follow rigid scripts. It analyzes your intent using a local reasoning loop to build safe, multi-step plans.

* **Schema-Locked Tools:** Every tool is validated against the `AppIntentScanner` manifest. Badger can't use tools that haven't been verified.
* **Side-Effect-Free Reasoning:** Planning happens in a sandbox where tool-loop execution is physically disabled until the user approves the plan.

---

## 📉 Hardware Intelligence (The 8GB Baseline)

Quantum Badger is the first agent optimized for the "Unified Memory" constraints of 8GB M1/M2/M3 Macs. It treats your RAM as a scarce, shared commodity.

### The "Yield-First" Memory Policy

* **The 30-Second Rule:** On baseline hardware, local models are automatically purged from VRAM after **30 seconds of inactivity**, returning ~4GB of RAM to the OS instantly.
* **Context Capping:** To prevent system-wide OOM (Out of Memory) crashes, conversation context is capped at **2048 tokens** on 8GB machines.
* **Heavy-App Sentinel:** If you launch a professional tool (Xcode, Final Cut Pro, Premiere), Badger detects the launch and proactively evicts its LLM to give your project maximum headroom.

### Cloud-Only Safe Mode

When you need 100% of your local silicon for heavy creative tasks, toggle **Safe Mode**.

* **Zero Footprint:** Offloads all reasoning to **ChatGPT** via macOS 16’s native secure integration, pinning local RAM and NPU usage to zero.
* **The Redaction Gate:** Even in Safe Mode, Badger’s local policy engine redacts sensitive data from your prompts *before* they are sent to the cloud.

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

1. **Initialize Identity:** Create your local Root Identity and secure your Recovery Phrase.
2. **Onboarding Handshake:** Follow the context-aware primers to grant Accessibility and Biometric access.
3. **Sync Capabilities:** Badger will scan your Mac for trusted App Intents and Shortcuts.
4. **Start Tasking:** Type a goal (e.g., *"Message Sarah the summary of my last meeting"*) and watch the reasoning loop build a plan.

---

## 📝 Technical Whitepaper

For a deep dive into our actor-isolated runtime, debounced persistence logic, and NPU-affinity scheduling, see the `docs/WHITEPAPER.md`.

---

**Sovereignty isn't just a feature; it's the architecture.** Welcome to the workshop. 🦡
