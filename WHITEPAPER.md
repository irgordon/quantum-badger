# 📜 WHITEPAPER: The Quantum Badger Runtime
**Architecture, Concurrency, and Hardware-Aware Autonomy**

## 1. Executive Summary
Quantum Badger is a 2026-standard autonomous agent framework for macOS. It is designed to solve the "Agent's Dilemma": providing high-utility automation while maintaining absolute data sovereignty and system performance on baseline hardware (8GB Unified Memory). This paper details the technical implementation of our **Actor-Isolated Runtime**, **Heuristic Reasoning Loops**, and **Predictive Memory Eviction**.

---

## 2. Structural Sovereignty: The Identity Model
The bedrock of the system is a cryptographic tether between the user's intent and their hardware.

### 2.1 Root Identity Fingerprinting
Unlike traditional applications that rely on mutable metadata, Badger generates a **Stable Identity Fingerprint** derived from the raw key bytes of the user's local encryption key stored in the Secure Enclave.
* **Idempotency:** The fingerprint remains constant across iCloud sync updates and keychain wrapping churn.
* **Security Gate:** Any change in the underlying key data (e.g., identity recovery or rotation) invalidates the onboarding state, forcing a re-audit of system permissions (Full Disk Access, Accessibility).

---

## 3. Concurrency Architecture: The Actor-Isolated Core
To prevent race conditions during multi-step reasoning, the runtime is strictly isolated using Swift Actors.

### 3.1 HybridExecutionManager (The Brain)
The `HybridExecutionManager` is implemented as an **Actor** to serialize inference requests. 
* **Inference Guarding:** Only one model can occupy the NPU/GPU buffers at a time per manager instance.
* **Cross-Actor Hopping:** The manager performs asynchronous "Context Hops" to the `@MainActor` for environment checks (Memory Pressure, Reachability) before resuming isolated inference.



---

## 4. Intent Arbitration: Autonomy vs. Interruptibility
A cornerstone of the sovereignty model is the **User-In-Control (UIC)** arbitration logic. Badger uses **Semantic Delta Analysis (SDA)** to distinguish between a user trying to "Fix" the current plan and a user trying to "Pivot" to something entirely new.

### 4.1 Refinement vs. Preemption
This classification occurs in a sub-millisecond pre-processing phase before the execution manager commits to a state change.

#### **Criteria for Contextual Merge (Refinement)**
A new input is classified as a **Refinement** if it meets "High-Overlap" criteria:
* **Entity Persistence:** The input references at least 70% of the key entities (people, files, apps) present in the active plan.
* **Action Modifiers:** The input contains linguistic modifiers (*"actually"*, *"instead"*, *"also"*).
* **Behavior:** Badger performs an **In-Situ Update**, modifying parameters or inserting a "Correction" step while preserving the overall mission state.

#### **Criteria for Preempt & Archive (New Intent)**
An input triggers a full mission reset if:
* **Low Semantic Similarity:** The input’s embedding vector falls below a 0.4 cosine similarity threshold relative to the current goal.
* **Goal Discontinuity:** The input introduces a new primary verb and target (e.g., moving from "Email" to "Find a movie").
* **Behavior:** Badger triggers an **Atomic Preemption**. The current NPU inference is aborted, the active plan is archived, and a fresh "Reasoning Loop" is initiated.



---

## 5. Intelligent Resource Management
Running local LLMs on 8GB M1/M2/M3 hardware requires active resource reclamation.

### 5.1 Predictive Memory Eviction
The `ModelLoader` implements a **Yield-First** policy. On baseline hardware, a 30-second **Idle-Unload Sentinel** monitors the runtime. 
* **Purge Mechanism:** Upon timeout, the actor invokes `MLX.GPU.clearCache()`, explicitly flushing Metal buffers. 
* **Heavy App Sentinel:** A background observer monitors for "Heavy Apps" (e.g., Xcode, Final Cut Pro). Detecting these triggers an immediate, proactive memory purge to prevent system-wide swap-death.



### 5.2 Debounced Task Persistence
The `TaskPlanner` manages the agent's goal state using a **Debounced Write-Coalescing** strategy.
* **Revision Guarding:** Every save task is tagged with a revision ID. Stale, delayed tasks are prevented from overwriting newer in-memory states.
* **I/O Optimization:** Rapid-fire updates (e.g., progress bar increments) are batched into 500ms windows, reducing SSD wear on 256GB baseline drives.

---

## 6. The Reasoning & Planning Loop
Badger utilizes a **Decomposed Reasoning** model to bridge user intent with local automation.

### 6.1 Plan Hydration & Validation
The `Orchestrator` generates plans in a side-effect-free "Architecture Mode."
1. **Tool Definition Injection:** The `AppIntentScanner` manifest is injected into the prompt as a schema.
2. **Heuristic Parsing:** A resilient parser uses balanced-segment extraction to isolate JSON plans from conversational noise, respecting nested braces and escaped characters.
3. **Hydration:** Raw JSON is validated against the **ToolRegistry**. Any step referencing an unknown tool or illegal parameter is discarded or coerced into a safe "Approval Required" state.



---

## 7. Secure Communications: The Messaging Delegate
Outbound communication is handled via a **Verified Delegate Pattern**. 
* **Strict Provenance:** The agent cannot invoke the `message.send` tool without generating a system-level verification event.
* **Human-in-the-Loop:** All messaging intents are routed through a UI coordinator that requires biometrically authorized confirmation, preventing "Silent Exfiltration."

---

## 8. Forensic Integrity
Forensics are not an afterthought; they are baked into the write-path.
* **Audit Logs:** Every event is recorded with a SHA-256 integrity hash to detect tampering.
* **Sovereignty Receipts:** The `SovereigntyReportGenerator` generates PDF receipts. On baseline hardware, reports are capped at 300 pages to maintain a deterministic memory footprint.

---

## 9. Conclusion
The Quantum Badger Runtime proves that autonomous agents can be local, performant, and secure. By combining strict Swift concurrency with hardware-aware resource management and an interruptible intent model, Badger provides a blueprint for the next generation of sovereign software.

---
**© 2026 Quantum Badger Project.**
*Built for the Silicon of Today. Hardened for the Threats of Tomorrow.*
