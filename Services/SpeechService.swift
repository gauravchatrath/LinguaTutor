import Foundation
import Speech
import AVFoundation

// MARK: - Speech Recognition Service
// Wraps Apple's SFSpeechRecognizer for real-time transcription.
// Supports mr-IN (Marathi), sv-SE (Swedish), pa-IN (Punjabi).
// Also drives AVSpeechSynthesizer for listening exercises.

@MainActor
final class SpeechService: ObservableObject {
    static let shared = SpeechService()

    @Published var transcribedText = ""
    @Published var isRecording = false
    @Published var isSpeaking = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func isLanguageSupported(_ language: Language) -> Bool {
        let locale = Locale(identifier: language.localeID)
        return SFSpeechRecognizer(locale: locale) != nil
    }

    // MARK: - Recording

    func startRecording(language: Language) throws {
        stopRecording()
        transcribedText = ""
        errorMessage = nil

        let locale = Locale(identifier: language.localeID)
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            throw SpeechError.recognizerUnavailable(language)
        }
        recognizer = rec

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { throw SpeechError.requestFailed }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            if let error {
                Task { @MainActor in
                    if (error as NSError).code != 216 {  // 216 = cancelled, not a real error
                        self.errorMessage = error.localizedDescription
                    }
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    // MARK: - Text-to-Speech (for listening exercises)

    func speak(_ text: String, language: Language, rate: Float = 0.45) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.localeID)
            ?? AVSpeechSynthesisVoice(language: language.code)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        isSpeaking = true
        synthesizer.speak(utterance)

        // Poll for completion
        Task {
            while synthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await MainActor.run { self.isSpeaking = false }
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Available voices check

    func availableVoice(for language: Language) -> String? {
        AVSpeechSynthesisVoice.speechVoices()
            .first(where: { $0.language.hasPrefix(language.code) })?.name
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case recognizerUnavailable(Language)
    case requestFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let lang):
            return "\(lang.rawValue) speech recognition is not available on this device."
        case .requestFailed:
            return "Could not start speech recognition."
        case .notAuthorized:
            return "Microphone access is required. Enable it in System Settings > Privacy."
        }
    }
}
