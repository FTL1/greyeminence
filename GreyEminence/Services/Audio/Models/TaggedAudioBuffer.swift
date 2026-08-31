import AVFoundation

struct TaggedAudioBuffer: @unchecked Sendable {
    enum Source: Sendable {
        case microphone
        case system
    }

    let buffer: AVAudioPCMBuffer
    let source: Source
    let timestamp: TimeInterval

    var speaker: Speaker {
        switch source {
        case .microphone: Speaker.resolvedMe()
        case .system: .other("System")
        }
    }
}
