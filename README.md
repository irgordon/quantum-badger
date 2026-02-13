# 🦡 Quantum Badger

<p align="center">
<img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-macOS_14.0+-lightgrey?logo=apple)
![MLX](https://img.shields.io/badge/AI-MLX_Swift-blue)
![License](https://img.shields.io/badge/License-MIT-green)

**Quantum Badger** is a local‑first, privacy‑obsessed assistant for macOS that works quietly in the background and keeps your data where it belongs—on your Mac. It handles the busywork, remembers what matters, and helps you stay organized without ever trading away your privacy or control.

---

## ✨ Key Features

### 🧠 Hybrid Intelligence Engine

* **Local First:** Runs optimized models (Phi-4, Mistral 7B, Llama 3) directly on your device using Apple Silicon (Metal/MLX).
* **Cloud Fallback:** Seamlessly switches to top-tier cloud models (Anthropic Claude, OpenAI GPT-4, Google Gemini) for complex reasoning tasks.
* **Smart Routing:** The **Shadow Router** analyzes prompt complexity and system load (VRAM/Thermals) to automatically choose the best execution path.

### 🛡️ Privacy & Security

* **PII Redaction:** Automatically detects and redacts sensitive data (SSNs, API Keys, Emails) before it leaves the app.
* **Input Sanitization:** Blocks malicious prompt injection attempts (SQLi, Shell Injection) before execution.
* **Audit Logging:** An immutable local ledger tracks every decision and inference request for full transparency.
* **Lockdown Mode:** A global kill-switch instantly cuts network access and unloads models in emergencies.

### ⚡ System Health Dashboard

* **Live Monitoring:** Real-time visualization of VRAM usage and Thermal pressure.
* **Resource Guard:** Prevents system slowdowns by throttling or suspending local inference if the device overheats or runs low on memory.
* **Traffic Light Status:** Quick-glance indicators for Local (Green) vs. Cloud (Blue) execution.

### 🔌 Deep Integration

* **Shortcuts & Siri:** Full support for App Intents (`Ask Quantum Badger...`).
* **Contextual History:** Searchable interaction history with smart categorization (Code, Creative, Analysis).
* **File Generation:** Automatically converts long responses or code blocks into downloadable files.

---

## 🛠️ Tech Stack

* **Language:** Swift 6 (Strict Concurrency)
* **UI Framework:** SwiftUI (NavigationSplitView, Charts)
* **Architecture:** Modular (BadgerCore, BadgerRuntime, App)
* **Local Inference:** Metal / MLX (Apple Silicon Optimized)
* **Search:** CoreSpotlight
* **Security:** Local Authentication & Keychain (Secure Enclave)

---

## 🚀 Getting Started

### Prerequisites

* **Xcode 16+** (Required for Swift 6)
* **macOS 15+** (Sequoia) or **iOS 18+**
* **Apple Silicon Mac** (M1/M2/M3) recommended for local inference.

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/quantum-badger.git
cd quantum-badger

```


2. **Open the Project**
Open `QuantumBadger.xcodeproj` in Xcode.
3. **Resolve Packages**
Xcode should automatically fetch dependencies (BadgerCore, BadgerRuntime, MLX-Swift).
4. **Build & Run**
Select your target (Mac or iPad) and hit **Run (Cmd+R)**.

---

## ⚙️ Configuration

### Setting up Cloud Providers

To use cloud fallback capabilities:

1. Go to **Settings** > **Cloud Accounts**.
2. Enter your API Keys for Anthropic, OpenAI, or Google.
3. Keys are stored encrypted in the **Secure Enclave** and never leave your device except for inference requests.

### Downloading Local Models

1. Go to **Settings** > **System Health**.
2. Check the **VRAM** card to see your available memory.
3. The app will recommend a model (e.g., "Phi-4" for 16GB Macs, "TinyLlama" for 8GB Macs).
4. Download the model weights to the app's document directory.

---

## 📂 Project Structure

* `BadgerApp`: The main UI layer, Views, and ViewModels.
* `BadgerRuntime`: The "Brain." Handles the Shadow Router, Inference Engines, and System Monitoring (VRAM/Thermal).
* `BadgerCore`: Shared data models, entities, and protocols.

---

## 🤝 Contributing

We welcome contributions! Please see `CONTRIBUTING.md` for details on how to submit pull requests, report issues, and request features.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

<p align="center">
Built with ❤️ using Swift 6 and MLX-LM.
</p>
