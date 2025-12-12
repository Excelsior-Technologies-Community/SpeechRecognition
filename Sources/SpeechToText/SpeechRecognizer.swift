//
//  SpeechRecognizer.swift
//   
//
//   Develope By noman Belim
//
//
import Foundation
import Speech
import AVFoundation
import SwiftUI

// MARK: - Speech Recognition Error Types
public enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case notAvailable
    case audioEngineFailure
    case recognitionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .audioEngineFailure:
            return "Failed to start audio recording."
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        }
    }
}

// MARK: - Speech Recognizer
public class SpeechRecognizer: NSObject, ObservableObject {
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var baseText: String = ""
    private var currentRecognitionChunk: String = ""
    
    @Published public private(set) var recognizedText: String = ""
    @Published public var isRecording: Bool = false
    @Published public var errorMessage: String?
    @Published public var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published public var isAvailable: Bool = true
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var shouldContinueRecording = false
    
    public override init() {
        super.init()
        setupSpeechRecognizer()
        requestPermissions()
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer?.delegate = self
        isAvailable = speechRecognizer?.isAvailable ?? false
    }
    
    private func requestPermissions() {
        
        // STEP 1 — Check Info.plist keys exist
        guard validatePermissionsKeys() else {
            print("Missing keys in Info.plist")
            return
        }
        
        // STEP 2 — Request speech authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                
                if status != .authorized {
                    self?.errorMessage = "Speech recognition permission denied."
                }
            }
        }
        
        // STEP 3 — Request microphone authorization
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.errorMessage = "Microphone permission denied."
                }
            }
        }
    }

    public func start() {
        
        // If missing keys → do not proceed
        guard validatePermissionsKeys() else {
            return
        }
        
        if audioEngine.isRunning {
            stop()
            return
        }
        
        guard authorizationStatus == .authorized else {
            errorMessage = "Speech permission not granted."
            return
        }
        
        guard isAvailable else {
            errorMessage = "Speech recognizer is not available."
            return
        }
        
        shouldContinueRecording = true
        feedbackGenerator.impactOccurred()
        
        do {
            if !baseText.isEmpty { baseText += " " }
            try startRecording()
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
            shouldContinueRecording = false
        }
    }

    
    private func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineFailure
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            var newText: String?
            
            if let result = result {
                newText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }
            
            DispatchQueue.main.async {
                if let newText = newText {
                    self.currentRecognitionChunk = newText
                }
                self.updateRecognizedText()
                
                if isFinal && self.shouldContinueRecording {
                    self.finalizeAndRestart(finalResult: newText)
                }
            }
            
            if let error = error as NSError? {
                let isCritical = !(error.domain == "kAFAssistantErrorDomain" && error.code == 216)
                if isCritical && self.shouldContinueRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restartRecognition(appendSpace: true)
                    }
                }
            }
        }
        
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.errorMessage = nil
        }
    }
    
    private func finalizeAndRestart(finalResult: String?) {
        guard shouldContinueRecording else { return }
        
        if let finalResult = finalResult, !finalResult.isEmpty {
            baseText += finalResult
        } else if !currentRecognitionChunk.isEmpty {
            baseText += currentRecognitionChunk
        }
        
        currentRecognitionChunk = ""
        updateRecognizedText()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldContinueRecording && self.audioEngine.isRunning {
                self.restartRecognition(appendSpace: true)
            }
        }
    }
    
    private func restartRecognition(appendSpace: Bool = false) {
        guard shouldContinueRecording, audioEngine.isRunning else { return }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        if appendSpace, !baseText.isEmpty, !baseText.hasSuffix(" ") {
            baseText += " "
            updateRecognizedText()
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        
        request.shouldReportPartialResults = true
        
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            var newText: String?
            
            if let result = result {
                newText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }
            
            DispatchQueue.main.async {
                if let newText = newText { self.currentRecognitionChunk = newText }
                self.updateRecognizedText()
                
                if isFinal && self.shouldContinueRecording {
                    self.finalizeAndRestart(finalResult: newText)
                }
            }
            
            if let error = error as NSError? {
                let isCritical = !(error.domain == "kAFAssistantErrorDomain" && error.code == 216)
                
                if isCritical && self.shouldContinueRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restartRecognition(appendSpace: true)
                    }
                }
            }
        }
    }
    
    private func updateRecognizedText() {
        recognizedText = baseText + currentRecognitionChunk
    }
    
    public func stop() {
        feedbackGenerator.impactOccurred()
        shouldContinueRecording = false
        stopAudioEngine()
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        if !currentRecognitionChunk.isEmpty {
            baseText += currentRecognitionChunk
            currentRecognitionChunk = ""
        }
        
        updateRecognizedText()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    public func clearAndRestart() {
        baseText = ""
        currentRecognitionChunk = ""
        errorMessage = nil
        updateRecognizedText()
        
        if isRecording && shouldContinueRecording && audioEngine.isRunning {
            restartRecognition()
        }
    }
    deinit {
        stop()
    }
    public func checkPermissionKeys() -> String? {
        let micKeyExists = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        let speechKeyExists = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
        
        if !micKeyExists {
            return "Missing NSMicrophoneUsageDescription in Info.plist (Permission)"
        }
        
        if !speechKeyExists {
            return "Missing NSSpeechRecognitionUsageDescription in Info.plist (Permission)"
        }
        
        return nil // All good
    }

    
      func validatePermissionsKeys() -> Bool {
        let micKeyExists = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        let speechKeyExists = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
        
        if !micKeyExists {
            self.errorMessage = "Missing NSMicrophoneUsageDescription in Info.plist (Permision)"
            return false
        }
        
        if !speechKeyExists {
            self.errorMessage = "Missing NSSpeechRecognitionUsageDescription in Info.plist (Permision)"
            return false
        }
        
        return true
    }
    } // ← CLOSE CLASS HERE



// MARK: - SFSpeechRecognizerDelegate
extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            self.isAvailable = available
            if !available {
                self.errorMessage = SpeechRecognitionError.notAvailable.errorDescription
                self.stop()
            }
        }
    }
}

// MARK: - View Modifier
public struct SpeakToTypeModifier: ViewModifier {
    
    @ObservedObject private var speech: SpeechRecognizer
    @Binding var binding: String
    
    public init(speech: SpeechRecognizer, binding: Binding<String>) {
        self._binding = binding
        self.speech = speech
    }
    
    public func body(content: Content) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            content
            
            VStack(spacing: 8) {
                Button(action: {
                    speech.isRecording ? speech.stop() : speech.start()
                }) {
                    ZStack {
                        Circle()
                            .fill(speech.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.1))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(speech.isRecording ? .red : .blue)
                    }
                }
                .disabled(!speech.isAvailable || speech.authorizationStatus != .authorized)
                
                if !binding.isEmpty {
                    Button(action: {
                        binding = ""
                        speech.clearAndRestart()
                    }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onReceive(speech.$recognizedText) { value in
            binding = value
        }
        .alert("Error", isPresented: .constant(speech.errorMessage != nil)) {
            Button("OK") { speech.errorMessage = nil }
        } message: {
            if let error = speech.errorMessage { Text(error) }
        }
    }
}

// MARK: - View Extension
public extension View {
    func speakToType(_ binding: Binding<String>, using speechRecognizer: SpeechRecognizer) -> some View {
        self.modifier(SpeakToTypeModifier(speech: speechRecognizer, binding: binding))
    }
}
 
