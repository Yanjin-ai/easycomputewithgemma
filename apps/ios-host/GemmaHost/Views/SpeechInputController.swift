import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInputController: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var authorizationError: String?

    #if os(iOS)
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    func toggle(onResult: @escaping (String) -> Void) {
        #if os(iOS)
        if isListening {
            stop()
        } else {
            requestAuthorizationAndStart(onResult: onResult)
        }
        #else
        authorizationError = "Voice input is available on iOS devices."
        #endif
    }

    func stop() {
        #if os(iOS)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil
        #endif
        isListening = false
    }

    #if os(iOS)
    private func requestAuthorizationAndStart(onResult: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioApplication.requestRecordPermission(completionHandler: { micAllowed in
                DispatchQueue.main.async {
                    guard speechStatus == .authorized, micAllowed else {
                        self?.authorizationError = "Speech recognition and microphone permission are required."
                        return
                    }
                    self?.start(onResult: onResult)
                }
            })
        }
    }

    private func start(onResult: @escaping (String) -> Void) {
        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    DispatchQueue.main.async {
                        onResult(text)
                    }
                }
                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.async {
                        self?.stop()
                    }
                }
            }
        } catch {
            authorizationError = error.localizedDescription
            stop()
        }
    }
    #endif
}
