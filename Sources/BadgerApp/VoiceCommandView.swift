import SwiftUI
import Speech

/// Voice command input UI with local speech‑to‑text transcription.
///
/// Recording is **UI‑initiated only** — no background listening.
/// Transcribed text passes through the same sanitization and
/// arbitration pipeline as typed commands.
///
/// ## HIG Error Compliance
/// - All error messages use calm, non‑technical language
/// - Errors are logged to ``AppLogger`` and the persistent ``ErrorLog``
/// - No raw `localizedDescription` strings are shown to the user
struct VoiceCommandView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var userNotice: UserNotice?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?

    var body: some View {
        VStack(spacing: 16) {
            Label("Voice Command", systemImage: "mic.fill")
                .font(.subheadline.weight(.semibold))

            // Transcription display.
            GroupBox {
                Text(coordinator.lastVoiceTranscription.isEmpty
                     ? "Tap the microphone to begin…"
                     : coordinator.lastVoiceTranscription)
                    .foregroundStyle(coordinator.lastVoiceTranscription.isEmpty
                                     ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 60)
                    .accessibilityLabel(coordinator.lastVoiceTranscription.isEmpty
                                        ? "No transcription yet"
                                        : "Transcription: \(coordinator.lastVoiceTranscription)")
            }

            // Record button.
            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: coordinator.isRecording
                          ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                    Text(coordinator.isRecording ? "Stop" : "Record")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(coordinator.isRecording ? .red : .accentColor)
            .controlSize(.large)
            .accessibilityLabel(coordinator.isRecording ? "Stop recording" : "Start recording")
            .accessibilityHint("Double-tap to \(coordinator.isRecording ? "stop" : "start") voice transcription")

            // Inline notice for voice-specific issues.
            if let notice = userNotice {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(notice.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.08))
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(notice.detail)
            }
        }
        .padding(20)
    }

    // MARK: - Recording

    private func toggleRecording() {
        if coordinator.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        userNotice = nil

        // Request authorization.
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    self.beginAudioSession()
                case .denied:
                    coordinator.logUI.warning("Speech recognition access denied by user")
                    self.userNotice = UserNotice.voiceUnavailable(
                        reason: "Voice recognition needs your permission. Open System Settings > Privacy & Security > Speech Recognition to enable access."
                    )
                case .restricted:
                    coordinator.logUI.warning("Speech recognition restricted on this device")
                    self.userNotice = UserNotice.voiceUnavailable(
                        reason: "Voice recognition is restricted on this device."
                    )
                case .notDetermined:
                    coordinator.logUI.info("Speech recognition authorization not yet determined")
                    self.userNotice = UserNotice.voiceUnavailable(
                        reason: "Voice recognition is not available yet. Please try again."
                    )
                @unknown default:
                    coordinator.logUI.warning("Speech recognition returned an unknown authorization status")
                    self.userNotice = UserNotice.voiceUnavailable(
                        reason: "Voice recognition is not available right now."
                    )
                }
            }
        }
    }

    private func beginAudioSession() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable else {
            coordinator.logUI.warning("Speech recognizer not available for locale \(Locale.current.identifier)")
            userNotice = UserNotice.voiceUnavailable(
                reason: "Voice recognition is not available for your current language."
            )
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            coordinator.logUI.warning("Audio engine could not start: \(error.localizedDescription)")
            userNotice = UserNotice.voiceUnavailable(
                reason: "The microphone could not be accessed. Check that no other app is using it."
            )
            return
        }

        let task = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    coordinator.lastVoiceTranscription = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    if let err = error {
                        coordinator.logUI.warning("Speech recognition ended: \(err.localizedDescription)")
                    }
                    self.stopRecording()
                    if let transcription = result?.bestTranscription.formattedString,
                       !transcription.isEmpty {
                        coordinator.submitVoiceCommand(transcription)
                    }
                }
            }
        }

        self.recognitionTask = task
        self.audioEngine = engine
        coordinator.isRecording = true
    }

    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        coordinator.isRecording = false
    }
}
