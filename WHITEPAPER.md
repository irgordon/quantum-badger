# WHITEPAPER: The Quantum Badger Runtime

**Architecture, Concurrency, and Hardware-Aware Autonomy**

## 1. Executive Summary

Quantum Badger is a 2026-standard autonomous agent framework for macOS. It is designed to solve the "Agent's Dilemma": providing high-utility automation while maintaining absolute data sovereignty and system performance on baseline hardware (8GB Unified Memory). This paper details the technical implementation of our **Actor-Isolated Runtime**, **Heuristic Reasoning Loops**, and **Proactive Resource Guarding**.

---

## 2. Structural Sovereignty: The Identity Model

The bedrock of the system is a cryptographic tether between the user's intent and their hardware.

### 2.1 Root Identity Fingerprinting

Unlike traditional applications that rely on mutable metadata, Badger generates a **Stable Identity Fingerprint** derived from the raw key bytes of the user's local encryption key stored in the Secure Enclave.

* **Idempotency:** The fingerprint remains constant across iCloud sync updates and keychain wrapping churn.
* **Security Gate:** Any change in the underlying key data (e.g., identity recovery or rotation) invalidates the onboarding state, forcing a re-audit of system permissions.

---

## 3. Concurrency Architecture: The Actor-Isolated Core

To prevent race conditions during multi-step reasoning, the runtime is strictly isolated using Swift Actors.

### 3.1 HybridExecutionManager (The Brain)

The `HybridExecutionManager` is implemented as an **Actor** to serialize inference requests.

* **Inference Guarding:** Only one model can occupy the NPU/GPU buffers at a time per manager instance.
* **Cross-Actor Hopping:** The manager performs asynchronous "Context Hops" to the `@MainActor` for environment checks (Memory Pressure, Reachability) before resuming isolated inference.

---

## 4. Intent Arbitration: Autonomy vs. Interruptibility

Badger uses **Semantic Delta Analysis (SDA)** to distinguish between a user trying to "Refine" the current plan and a user trying to "Pivot" to something entirely new.

### 4.1 Refinement vs. Preemption: The Rationale

The arbitration thresholds are tuned for **Conservative Preemption**, prioritizing the prevention of "contextual bleeding" over the convenience of a merged plan.

#### **Criteria for Contextual Merge (Refinement)**

* **Entity Persistence (70% Threshold):** Chosen to ensure that the agent remains locked onto the user's specific subject (e.g., a specific set of files or contacts). Empirical testing suggests that dropped entities below 30% usually signal a shift in target, making a merge risky for data integrity.
* **Action Modifiers:** The input contains linguistic modifiers (*"actually"*, *"instead"*, *"also"*).
* **Behavior:** Badger performs an **In-Situ Update**, modifying parameters or inserting a "Correction" step while preserving the overall mission state.

#### **Criteria for Preempt & Archive (New Intent)**

* **Semantic Similarity (0.4 Cosine Threshold):** This value represents the "Safety Margin" for divergent tasks. While 0.5–0.6 often indicates topical similarity, 0.4 allows the system to catch "Subtle Pivots"—where the user is still talking about the same *app* (e.g., Mail) but has moved to a completely different *intent* (e.g., moving from "drafting" to "searching").
* **Goal Discontinuity:** The input introduces a new primary verb and target.
* **Behavior:** Badger triggers an **Atomic Preemption**. The current NPU inference is aborted, the active plan is archived, and a fresh loop is initiated.

---

## 5. Intelligent Resource Management

Running local LLMs on 8GB M1/M2/M3 hardware requires active resource reclamation to prevent "Swap Death."

### 5.1 Proactive Memory Guarding (The Sentinel)

Quantum Badger moves beyond reactive memory management through three distinct layers:

1. **The Heavy App Sentinel:** A background observer monitors `NSWorkspace` for high-impact creative apps (Xcode, Final Cut Pro, Adobe Premiere). Detecting these triggers an immediate, proactive model eviction *before* the system reaches critical pressure.
2. **Idle-Unload Sentinel:** On baseline hardware, a 30-second timer monitors inactivity. Upon timeout, the actor invokes `MLX.GPU.clearCache()`, flushing Metal buffers back to the system pool.
3. **Pressure Monitoring:** Utilizing `DispatchSourceMemoryPressure`, the system listens for kernel-level alerts. `Warning` or `Critical` events trigger an immediate emergency purge.

### 5.2 Cloud-Only Safe Mode

For deterministic stability during intensive workloads, users can toggle **Safe Mode**.

* **Zero Footprint:** Safe Mode explicitly bars local runtime selection, routing all reasoning to **Private Cloud Compute (PCC)** or **ChatGPT**.
* **Privacy Persistence:** The local **Redaction Gate** remains active, ensuring sensitive data is filtered before transit, even in offloaded modes.

### 5.3 Preemptive Priority Scheduling (PPS)

To ensure the system remains responsive, Badger utilizes a **Deterministic Priority Queue** within the `HybridExecutionManager`. This allows the runtime to triage tasks based on their impact on system stability rather than simple arrival time.

#### **5.4 Thermal Safeguards and Emergency State Persistence**

When local GGUF inference pushes the SoC toward its thermal limit, the **NPUThermalWatcher** executes a tiered defensive strategy:

1. **Throttling (.serious):** Badger signals the NPU to reduce its power envelope, prioritizing system stability over inference speed.
2. **Emergency Shutdown (.critical):** The PPS triggers a **Tier 0 Cancellation**. To ensure no data is lost during a sudden shutdown, Badger performs an **Atomic Flush**—writing the current conversation buffer and audit logs to the SSD in a single non-blocking burst before yielding all resources to the OS.

#### **5.5 Dynamic Memory Budgeting**

To ensure Quantum Badger never causes a kernel-level hang on baseline hardware, the `ModelLoader` implements **Context-Aware Fit Checks**. Every load request is validated against the **OS Memory Availability Matrix**:

1. **Physical Floor:** A hard macOS reserve of 3.0 GB is maintained at all times.
2. **KV-Cache Scaling:** Memory estimates scale linearly with `contextTokens`, ensuring large context windows are rejected on 8GB machines if they would force system-wide swap.
3. **Pressure-Aware Admission:** Inference engines are denied entry to the NPU/GPU if the system reports `Warning` or `Critical` memory pressure, protecting the user's active workflow from interruption.

#### **The Priority Hierarchy**

Badger categorizes all runtime requests into three distinct tiers:

1. **Tier 0: Critical (System Sentinel):** High-priority interrupts triggered by the Heavy App Sentinel or Thermal Watcher. These tasks jump to the front of the queue and can pre-empt (cancel) active inference.
2. **Tier 1: User-Initiated (Real-time):** Direct user commands, manual stops, or prompt refinements.
3. **Tier 2: Background (Agentic):** Autonomous planning, pre-fetching, or long-term reasoning loops.

#### **Preemption & Resource Yielding**

Unlike standard LLM wrappers, Badger does not wait for an inference pass to complete if a Tier 0 event occurs.

* **Active Cancellation:** Upon receiving a `.critical` signal, the `HybridExecutionManager` issues an immediate cancellation to the NPU/GPU task.
* **The "Yield-on-Launch" Protocol:** When a resource-intensive app (e.g., Final Cut Pro) is launched, the PPS immediately triggers `MLX.GPU.clearCache()`. This ensures the base-model Mac’s Unified Memory is returned to the OS within milliseconds, preventing the "Compressed Memory Swap" that leads to system lag.

---

## 6. The Reasoning & Planning Loop

Badger utilizes a **Decomposed Reasoning** model to bridge user intent with local automation.

### 6.1 Plan Hydration & Validation

The `Orchestrator` generates plans in a side-effect-free "Architecture Mode."

1. **Tool Definition Injection:** The `AppIntentScanner` manifest is injected into the prompt as a schema.
2. **Heuristic Parsing:** A resilient parser uses balanced-segment extraction to isolate JSON plans from conversational noise, respecting nested structures and escaped characters.
3. **Hydration:** Raw JSON is validated against the **ToolRegistry**. Any step referencing an unknown tool or illegal parameter is discarded or coerced into a "Human Approval Required" state.

---

## 7. Secure Action & Forensics

### 7.1 The Verified Delegate

Outbound communication is handled via a **Verified Delegate Pattern**. The agent cannot invoke `message.send` or `filesystem.write` without generating a system-level verification event requiring biometric (Touch ID) authorization.

### 7.2 Forensic Integrity

* **Audit Logs:** Every event is recorded with a SHA-256 integrity hash to detect tampering.
* **Sovereignty Receipts:** The system generates cryptographically-checked PDF receipts of all interactions, providing proof of provenance for agent actions.

---

## 8. Conclusion

The Quantum Badger Runtime proves that autonomous agents can be local, performant, and secure on baseline Apple Silicon. By combining strict Swift concurrency, proactive hardware-aware resource management, and **Preemptive Priority Scheduling**, Badger provides a blueprint for the next generation of sovereign software.

---

**© 2026 Quantum Badger Project.**
*Built for the Silicon of Today. Hardened for the Threats of Tomorrow.*
