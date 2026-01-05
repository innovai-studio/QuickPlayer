# QuickPlayer iOS Implementation Guide

This document outlines the tasks required to support iOS platform.

## Current Status

- **Android**: Fully implemented and working
- **iOS**: Requires native implementation for audio analysis

---

## Tasks for iOS Implementation

### 1. Audio Analysis Platform Channel (Required)

**File to create:** `ios/Runner/AppDelegate.swift`

**Current Android implementation:** `android/app/src/main/kotlin/com/quickplayer/quickplayer/MainActivity.kt`

**Dart interface (already cross-platform):** `lib/core/audio/audio_analyzer_service.dart`

#### Platform Channel Details

- **Channel Name:** `com.quickplayer/audio_analyzer`
- **Method:** `analyzeBpmAndKey`
- **Input:** `filePath` (String) - path to audio file
- **Output:** `Map<String, Any?>` with keys:
  - `bpm` (Int?) - detected BPM
  - `key` (String?) - detected musical key (e.g., "C Major", "A Minor")

#### iOS Implementation Steps

1. **Audio Decoding**
   - Use `AVAudioFile` or `AVAssetReader` to decode audio to PCM samples
   - Convert to mono Float32 array
   - Sample first 30 seconds for analysis

2. **BPM Detection Algorithm**
   - Calculate energy envelope with 10ms windows
   - Apply low-pass filter for smoothing
   - Calculate onset strength (positive derivative)
   - Autocorrelation to find dominant periodicity
   - Convert lag to BPM (range: 50-220)

3. **Key Detection Algorithm**
   - Apply Hann window to frames (4096 samples, 2048 hop)
   - Use Goertzel algorithm to calculate energy at each pitch class frequency
   - Sum energy across octaves 2-6 for each pitch class
   - Normalize chromagram
   - Correlate with Krumhansl-Schmuckler major/minor profiles
   - Return best matching key

#### Reference Frequencies for Chroma (C4 to B4)
```swift
let referenceFreqs = [261.63, 277.18, 293.66, 311.13, 329.63, 349.23,
                      369.99, 392.00, 415.30, 440.00, 466.16, 493.88]
```

#### Krumhansl-Schmuckler Key Profiles
```swift
// Major profile
let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]

// Minor profile
let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
```

---

### 2. iOS Permissions (Required)

**File to modify:** `ios/Runner/Info.plist`

Add the following keys:
```xml
<key>NSAppleMusicUsageDescription</key>
<string>QuickPlayer needs access to your music library to import audio files.</string>

<key>UISupportsDocumentBrowser</key>
<true/>
```

---

### 3. Podfile Configuration (Required)

**File to check:** `ios/Podfile`

Ensure minimum iOS version is set (recommended iOS 12.0+):
```ruby
platform :ios, '12.0'
```

---

### 4. Dependencies Check

All Flutter packages used are cross-platform compatible:

| Package | iOS Support |
|---------|-------------|
| just_audio | Yes |
| file_picker | Yes |
| hive / hive_flutter | Yes |
| path_provider | Yes |
| go_router | Yes |
| flutter_riverpod | Yes |
| uuid | Yes |
| audio_session | Yes |

---

## Swift Code Template

Below is a starting template for the iOS implementation:

```swift
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private let channelName = "com.quickplayer/audio_analyzer"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler { [weak self] (call, result) in
            if call.method == "analyzeBpmAndKey" {
                guard let args = call.arguments as? [String: Any],
                      let filePath = args["filePath"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "File path is required", details: nil))
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    let analysisResult = self?.analyzeAudio(filePath: filePath)
                    DispatchQueue.main.async {
                        result(analysisResult)
                    }
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func analyzeAudio(filePath: String) -> [String: Any?] {
        // TODO: Implement audio decoding and analysis
        // 1. Decode audio to PCM samples using AVAudioFile
        // 2. Call detectBpm()
        // 3. Call detectKey()
        // 4. Return ["bpm": bpm, "key": key]

        return ["bpm": nil, "key": nil]
    }

    private func detectBpm(samples: [Float], sampleRate: Int) -> Int? {
        // TODO: Implement BPM detection using autocorrelation
        return nil
    }

    private func detectKey(samples: [Float], sampleRate: Int) -> String? {
        // TODO: Implement key detection using chroma features
        return nil
    }
}
```

---

## Testing Checklist

After iOS implementation, test the following:

- [ ] App launches without crash
- [ ] Can import audio files from Files app
- [ ] Audio playback works
- [ ] BPM detection returns reasonable values
- [ ] Key detection returns correct format (e.g., "C Major")
- [ ] Speed control adjusts BPM display
- [ ] Pitch control adjusts Key display
- [ ] Mini player bar works
- [ ] A-B loop works
- [ ] Markers work
- [ ] Waveform display works

---

## Estimated Work

- Platform Channel implementation: 2-4 hours
- Testing and debugging: 1-2 hours
- App Store preparation: 1-2 hours

Total: ~4-8 hours

---

## Notes

- The audio analysis algorithms (BPM/Key detection) are the same on both platforms
- Only the audio decoding method differs (MediaCodec on Android, AVAudioFile on iOS)
- Consider using a shared algorithm library in the future (e.g., C++ with FFI) for easier maintenance
