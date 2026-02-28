import Foundation

/// A timestamped chunk of transcribed text from a recording.
public struct TranscriptSegment: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public var generatedCardIDs: [UUID]

    public var duration: TimeInterval {
        endTime - startTime
    }

    public var wordCount: Int {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    public var isHighConfidence: Bool {
        confidence >= 0.8
    }

    public var timeRangeString: String {
        let startFormatted = formatTime(startTime)
        let endFormatted = formatTime(endTime)
        return "\(startFormatted) - \(endFormatted)"
    }

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0,
        generatedCardIDs: [UUID] = []
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = max(0, min(1, confidence))
        self.generatedCardIDs = generatedCardIDs
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

public extension TranscriptSegment {
    static func fromTranscription(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            startTime: startTime,
            endTime: endTime,
            confidence: confidence
        )
    }

    static func merge(_ segments: [TranscriptSegment]) -> TranscriptSegment? {
        guard let first = segments.first, let last = segments.last else { return nil }

        let combinedText = segments.map(\.text).joined(separator: " ")
        let avgConfidence = segments.map(\.confidence).reduce(0, +) / Float(segments.count)
        let allCardIDs = segments.flatMap(\.generatedCardIDs)

        return TranscriptSegment(
            text: combinedText,
            startTime: first.startTime,
            endTime: last.endTime,
            confidence: avgConfidence,
            generatedCardIDs: allCardIDs
        )
    }

    var sentences: [String] {
        var results: [String] = []
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var currentSentence = ""

        for char in text {
            currentSentence.append(char)
            if let scalar = char.unicodeScalars.first, sentenceEnders.contains(scalar) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    results.append(trimmed)
                }
                currentSentence = ""
            }
        }

        let remaining = currentSentence.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            results.append(remaining)
        }

        return results
    }

    var endsWithCompleteSentence: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last else { return false }
        return lastChar == "." || lastChar == "!" || lastChar == "?"
    }
}
