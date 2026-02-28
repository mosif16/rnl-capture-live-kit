import Foundation

public enum RecordingSessionStatus: String, Codable, Sendable, CaseIterable {
    case recording
    case paused
    case completed
}

/// Represents an active or completed recording session with transcript segments.
public struct RecordingSession: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var title: String
    public var transcriptSegments: [TranscriptSegment]
    public var audioFileURL: URL?
    public var status: RecordingSessionStatus

    public var duration: TimeInterval {
        guard let end = endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }

    public var wordCount: Int {
        transcriptSegments.reduce(0) { count, segment in
            count + segment.wordCount
        }
    }

    public var fullTranscript: String {
        transcriptSegments.map(\.text).joined(separator: " ")
    }

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        title: String = "",
        transcriptSegments: [TranscriptSegment] = [],
        audioFileURL: URL? = nil,
        status: RecordingSessionStatus = .recording
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.transcriptSegments = transcriptSegments
        self.audioFileURL = audioFileURL
        self.status = status
    }

    public mutating func pause() {
        guard status == .recording else { return }
        status = .paused
    }

    public mutating func resume() {
        guard status == .paused else { return }
        status = .recording
    }

    public mutating func complete() {
        status = .completed
        endedAt = Date()
    }

    public mutating func addSegment(_ segment: TranscriptSegment) {
        transcriptSegments.append(segment)
    }

    public mutating func ensureTitle() {
        if title.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            title = "Session \(formatter.string(from: startedAt))"
        }
    }
}
