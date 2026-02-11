# 🦡 Quantum Badger

<p align="center">
<img src="logo.png" alt="Quantum Badger Logo" width="250" />
</p>

![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-macOS_14.0+-lightgrey?logo=apple)
![MLX](https://img.shields.io/badge/AI-MLX_Swift-blue)
![License](https://img.shields.io/badge/License-MIT-green)

**Quantum Badger** is a local‑first, privacy‑obsessed assistant for macOS that works quietly in the background and keeps your data where it belongs—on your Mac. It handles the busywork, remembers what matters, and helps you stay organized without ever trading away your privacy or control.

A high-performance, sandboxed macOS application built with **SwiftUI** and **MLX-Swift**. 

This project demonstrates how to run local inference (LLMs, Whisper, Stable Diffusion) securely within the App Sandbox, complying with Mac App Store security guidelines.

## 🚀 Features

* **Swift 6 Strict Concurrency:** Built with full actor isolation and `Sendable` correctness.
* **Local Intelligence:** Powered by [MLX Swift](https://github.com/ml-explore/mlx-swift) for Apple Silicon acceleration.
* **App Sandbox:** Fully secure environment with scoped resource access.
* **SwiftData:** Modern persistence for conversation history and settings.
* **Streaming UI:** Real-time token generation using Swift AsyncStreams.

## 🛠 Prerequisites

* **Xcode:** 16.0+
* **macOS:** Sonoma 14.0+ (Sequoia 15.0+ recommended for full Metal features)
* **Hardware:** Apple Silicon (M1/M2/M3/M4) required for MLX.
    * *Note: Intel Macs are not supported by the MLX framework.*

## 📦 Getting Started

### 1. Clone the Repository
```bash
git clone [https://github.com/irgordon/quantum-badger.git](https://github.com/irgordon/quantum-badger.git)
cd quantum-badger
