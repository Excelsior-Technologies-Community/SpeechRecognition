

# SpeechRecognition

A lightweight, production-ready SwiftUI speech-to-text package that supports continuous voice recognition, real-time text updates, restartable recognition, deletion handling, and background interruption control.

This package exposes two main components:

1. `SpeechRecognizer` – the core engine handling continuous speech recognition
2. `.speakToType(_:using:)` – a SwiftUI modifier that attaches voice input to any TextEditor or TextField

The system supports continuous transcription by combining finalized and partial segments, restarting recognition seamlessly, and updating a bound text value in real time.
Implementation reference: SpeechRecognizer.swift 

---

# Installation

## Swift Package Manager

In Xcode:

1. Open File → Add Packages
2. Enter repository URL:

   ```
	https://github.com/Excelsior-Technologies-Community/SpeechRecognition
   ```
3. Select the package and add it to your project.

Inside your Swift files:

```swift
import SpeechToText
```

---

# Usage Guide

Below are two complete examples demonstrating how to use the SpeechRecognizer and the SpeakToType modifier.

---


# Required Permissions

Add these to Info.plist:

```
NSSpeechRecognitionUsageDescription
NSMicrophoneUsageDescription
```

Example:

```
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition is required to convert your voice into text.</string>
<key>NSMicrophoneUsageDescription</key>
<string>The app requires microphone access for speech recognition.</string>
```
---

# Example 1: Basic Usage (Simple Speak-To-Type)

This example demonstrates:

* Creating a StateObject instance of SpeechRecognizer
* Using `.speakToType(_:using:)` inside a TextEditor
* Automatic binding to recognized text
* Listening, stopping, and deleting text

```swift
import SwiftUI
import SpeechToText

struct ContentView: View {
    
    @State private var message = ""
    @StateObject private var speechRecognizer = SpeechRecognizer() // Must own the SpeechRecognizer instance

    var body: some View {
        VStack {
            // Display current state (optional)
            Text(speechRecognizer.isRecording ? "Status: Listening..." : "Status: Idle")
                .foregroundColor(speechRecognizer.isRecording ? .green : .gray)
            
            TextEditor(text: $message)
                .speakToType($message, using: speechRecognizer)
                .frame(minHeight: 120, maxHeight: 500)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
        }
        .padding()
    }
}
```

This is the simplest way to integrate your package.
Any developer can drop this into their project and immediately get working speech-to-text.

---

# Background Behavior Support

Stopping speech recognition when the app goes to the background is essential to:

* Comply with iOS microphone rules
* Avoid unexpected recognition when the app is not visible
* Ensure the user explicitly resumes recording

You must observe `scenePhase`:

```swift
@Environment(\.scenePhase) private var scenePhase
```

Then detect transitions:

```
if newPhase == .inactive || newPhase == .background {
    if speechRecognizer.isRecording {
        userInitiatedRecording = true
        speechRecognizer.stop()
        print("Speech recognition stopped due to app backgrounding.")
    }
} else if newPhase == .active {
    if userInitiatedRecording {
        print("App returned to foreground. User must tap mic to resume listening.")
        userInitiatedRecording = false
    }
}
```

Explanation:

* The package never automatically restarts microphone input because restarting silently is not allowed and breaks expected UX.
* Developers must decide whether to show a prompt or allow the user to tap the mic again.

---

# Example 2: Full Implementation with Background Handling

```swift
import SwiftUI
import SpeechToText

struct ContentView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var message = ""
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    @State private var userInitiatedRecording = false

    var body: some View {
        VStack {
            // Display current state
            HStack {
                Text(speechRecognizer.isRecording ? "Status: Listening (Active)" : "Status: Idle (Tap Mic to Start)")
                    .font(.caption)
                    .foregroundColor(speechRecognizer.isRecording ? .green : .gray)
                
                Spacer()
            if speechRecognizer.isRecording {
  		  Image(systemName: "waveform")
		        .foregroundColor(.red)
		        .scaleEffect(speechRecognizer.isRecording ? 1.1 : 1.0)
		        .animation(
		            speechRecognizer.isRecording ?
		                Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
		                : .default,
		            value: speechRecognizer.isRecording
        		)
		}

            }
            .padding(.horizontal)
            
            TextEditor(text: $message)
                .speakToType($message, using: speechRecognizer)
                .frame(minHeight: 120, maxHeight: 500)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
        }
        .padding()
        
        // MARK: - ScenePhase Observation
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .inactive || newPhase == .background {
                
                if speechRecognizer.isRecording {
                    userInitiatedRecording = true
                    speechRecognizer.stop()
                    print("Speech recognition stopped due to app backgrounding.")
                }
                
            } else if newPhase == .active {
                
                if userInitiatedRecording {
                    print("App returned to foreground. User must tap mic to resume listening.")
                    userInitiatedRecording = false
                }
            }
        }
        
        // Store whether the user manually initiated recording
        .onReceive(speechRecognizer.$isRecording) { isRecording in
            userInitiatedRecording = isRecording
        }
    }
}
```

---

# Required Permissions

Add these to Info.plist:

```
NSSpeechRecognitionUsageDescription
NSMicrophoneUsageDescription
```

Example:

```
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition is required to convert your voice into text.</string>
<key>NSMicrophoneUsageDescription</key>
<string>The app requires microphone access for speech recognition.</string>
```

---
 
