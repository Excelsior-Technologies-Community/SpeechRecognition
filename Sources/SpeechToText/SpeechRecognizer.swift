//
//  SpeechRecognizer.swift
//  DeliveryTrackingSystem
//
//  Enhanced version with continuous recognition until manual stop
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
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) // Changed to en-US for broader availability/testing, can revert to en-IN
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // --- State for Continuous Transcription ---
    private var baseText: String = "" // Stores the accumulated, final text chunks
    private var currentRecognitionChunk: String = "" // Stores the in-progress, partial text
    
    // Published property that combines base text and current chunk
    @Published public private(set) var recognizedText: String = ""
    
    @Published public var isRecording: Bool = false
    @Published public var errorMessage: String?
    @Published public var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published public var isAvailable: Bool = true
    
    // Haptic feedback
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Manual stop flag
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
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status != .authorized {
                    self?.errorMessage = SpeechRecognitionError.notAuthorized.errorDescription
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.errorMessage = "Microphone access denied. Please enable in Settings."
                }
            }
        }
    }
    
    public func start() {
        // Stop if already running
        if audioEngine.isRunning {
            stop()
            return
        }
        
        // Check authorization
        guard authorizationStatus == .authorized else {
            errorMessage = SpeechRecognitionError.notAuthorized.errorDescription
            return
        }
        
        guard isAvailable else {
            errorMessage = SpeechRecognitionError.notAvailable.errorDescription
            return
        }
        
        shouldContinueRecording = true
        feedbackGenerator.impactOccurred()
        
        do {
            // Append a space if there's already text to ensure separation
            if !baseText.isEmpty {
                 baseText += " "
            }
            try startRecording()
        } catch {
            errorMessage = error.localizedDescription
            isRecording = false
            shouldContinueRecording = false
        }
    }
    
    private func startRecording() throws {
        // Cancel previous task if exists
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        // Set category to .record
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineFailure
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        let inputNode = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            var newText: String?
            
            if let result = result {
                newText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }
            
            // Handle recognition update
            DispatchQueue.main.async {
                if let newText = newText {
                    // Update the current chunk in real-time
                    self.currentRecognitionChunk = newText
                }
                // Update the combined recognizedText
                self.updateRecognizedText()
                
                // If final, move current chunk to base text and restart
                if isFinal && self.shouldContinueRecording {
                    self.finalizeAndRestart(finalResult: newText)
                }
            }
            
            // Only handle critical errors, not normal completion (which is handled by result.isFinal)
            if let error = error as NSError? {
                let isCriticalError = !(error.domain == "kAFAssistantErrorDomain" && error.code == 216)
                
                if isCriticalError && self.shouldContinueRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.shouldContinueRecording {
                            self.restartRecognition(appendSpace: true) // Restart after a non-final error
                        }
                    }
                }
            }
        }
        
        // Configure audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // Ensure tap is only installed if not already installed (safer on multiple starts)
        inputNode.removeTap(onBus: 0) // Remove existing tap before installing new one
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
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
        
        // 1. Move current chunk to base text, add space for next chunk
        if let finalResult = finalResult, !finalResult.isEmpty {
            self.baseText += finalResult
        } else if !self.currentRecognitionChunk.isEmpty {
            self.baseText += self.currentRecognitionChunk
        }
        self.currentRecognitionChunk = "" // Clear current chunk
        self.updateRecognizedText()
        
        // 2. Restart recognition task with a small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldContinueRecording && self.audioEngine.isRunning {
                self.restartRecognition(appendSpace: true) // Restart recognition
            }
        }
    }
    
    private func restartRecognition(appendSpace: Bool = false) {
        guard shouldContinueRecording, audioEngine.isRunning else { return }
        
        // 1. Cancel current task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 2. Append space if requested (handles appending a space before the next chunk starts)
        if appendSpace && !baseText.isEmpty && !baseText.hasSuffix(" ") {
            baseText += " "
            updateRecognizedText()
        }
        
        // 3. Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // 4. Start new recognition task
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
            
            // Error handling
            if let error = error as NSError? {
                let isCriticalError = !(error.domain == "kAFAssistantErrorDomain" && error.code == 216)
                
                if isCriticalError && self.shouldContinueRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.shouldContinueRecording {
                            self.restartRecognition(appendSpace: true)
                        }
                    }
                }
            }
        }
    }
    
    private func updateRecognizedText() {
        // Combines base text and current in-progress chunk
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
        
        // Finalize any pending chunk when stopping
        if !currentRecognitionChunk.isEmpty {
            baseText += currentRecognitionChunk
            currentRecognitionChunk = ""
        }
        updateRecognizedText()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // Custom function to clear everything and prepare for a fresh start while recording
    public func clearAndRestart() {
        // 1. Clear internal state
        baseText = ""
        currentRecognitionChunk = ""
        errorMessage = nil
        
        // 2. Update UI (which will be done via updateRecognizedText())
        updateRecognizedText()
        
        // 3. If currently recording, restart the underlying recognition process
        if isRecording && shouldContinueRecording && audioEngine.isRunning {
            restartRecognition()
        }
    }
    
    deinit {
        stop()
    }
}

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
    
    // SpeechRecognizer is now an ObservedObject provided from the ContentView via the initializer
    @ObservedObject private var speech: SpeechRecognizer
    @Binding var binding: String
    
    // Initialize with the SpeechRecognizer instance and the binding
    public init(speech: SpeechRecognizer, binding: Binding<String>) {
        self._binding = binding
        self.speech = speech
    }
    
    public func body(content: Content) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            content
            
            VStack(spacing: 8) {
                // MARK: Mic Button
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
                            .symbolEffect(.pulse, options: .repeating, isActive: speech.isRecording)
                    }
                }
                .disabled(!speech.isAvailable || speech.authorizationStatus != .authorized)
                
                // MARK: Clear/Delete Button
                if !binding.isEmpty {
                    Button(action: {
                        binding = "" // Clear the bound text (which is updated by speech.recognizedText)
                        speech.clearAndRestart() // Clear speech internal state and restart recognition if needed
                    }) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        // Update the bound text whenever the SpeechRecognizer's recognizedText changes
        .onReceive(speech.$recognizedText) { value in
            binding = value
        }
        .alert("Error", isPresented: .constant(speech.errorMessage != nil)) {
            Button("OK") {
                speech.errorMessage = nil
            }
        } message: {
            if let error = speech.errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - View Extension
public extension View {
    // Requires an @ObservedObject SpeechRecognizer instance to be passed in
    func speakToType(_ binding: Binding<String>, using speechRecognizer: SpeechRecognizer) -> some View {
        self.modifier(SpeakToTypeModifier(speech: speechRecognizer, binding: binding))
    }
}
