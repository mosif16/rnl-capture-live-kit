import Foundation

/// A transcription update emitted during streaming.
public struct TranscriptionUpdate: Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public let isFinal: Bool

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float,
        isFinal: Bool
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isFinal = isFinal
    }
}
