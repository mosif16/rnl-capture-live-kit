import Foundation

/// Emitted when enough content has accumulated for generation.
public struct CardGenerationTrigger: Sendable, Equatable {
    public let text: String
    public let segments: [TranscriptSegment]
    public let contextText: String

    public init(text: String, segments: [TranscriptSegment], contextText: String) {
        self.text = text
        self.segments = segments
        self.contextText = contextText
    }
}

public struct LiveTranscriptBufferConfiguration: Sendable {
    public let minGenerationIntervalSeconds: TimeInterval
    public let maxGenerationIntervalSeconds: TimeInterval
    public let contextWindowSentences: Int
    public let maxInMemorySegments: Int

    public init(
        minGenerationIntervalSeconds: TimeInterval = 30.0,
        maxGenerationIntervalSeconds: TimeInterval = 60.0,
        contextWindowSentences: Int = 3,
        maxInMemorySegments: Int = 100
    ) {
        self.minGenerationIntervalSeconds = minGenerationIntervalSeconds
        self.maxGenerationIntervalSeconds = maxGenerationIntervalSeconds
        self.contextWindowSentences = contextWindowSentences
        self.maxInMemorySegments = maxInMemorySegments
    }
}

/// Actor that accumulates transcript segments and triggers generation at configurable intervals.
public actor LiveTranscriptBuffer {
    private let configuration: LiveTranscriptBufferConfiguration

    private var allSegments: [TranscriptSegment] = []
    private var pendingSegments: [TranscriptSegment] = []
    private var pendingText: String = ""
    private var lastGenerationTime: Date?
    private var contextSentences: [String] = []
    private let archiveURL: URL?

    public init(
        configuration: LiveTranscriptBufferConfiguration = LiveTranscriptBufferConfiguration(),
        archiveURL: URL? = nil
    ) {
        self.configuration = configuration
        self.archiveURL = archiveURL
    }

    public func addTranscription(_ update: TranscriptionUpdate) -> CardGenerationTrigger? {
        let segment = TranscriptSegment(
            text: update.text,
            startTime: update.startTime,
            endTime: update.endTime,
            confidence: update.confidence
        )
        return addSegment(segment)
    }

    public func addSegment(_ segment: TranscriptSegment) -> CardGenerationTrigger? {
        allSegments.append(segment)
        pendingSegments.append(segment)
        pendingText += " " + segment.text
        pendingText = pendingText.trimmingCharacters(in: .whitespaces)

        let trigger = checkGenerationTrigger(now: Date())
        archiveOldSegmentsIfNeeded()
        return trigger
    }

    public func forceGeneration() -> CardGenerationTrigger? {
        guard !pendingSegments.isEmpty else { return nil }
        return triggerGeneration(now: Date())
    }

    public var segments: [TranscriptSegment] {
        allSegments
    }

    public func recentSegments(count: Int) -> [TranscriptSegment] {
        Array(allSegments.suffix(count))
    }

    public var fullTranscript: String {
        allSegments.map(\.text).joined(separator: " ")
    }

    public var segmentCount: Int {
        allSegments.count
    }

    public var pendingTextLength: Int {
        pendingText.count
    }

    public var contextWindow: String {
        contextSentences.joined(separator: " ")
    }

    public func clear() {
        allSegments.removeAll()
        pendingSegments.removeAll()
        pendingText = ""
        contextSentences.removeAll()
        lastGenerationTime = nil
    }

    private func checkGenerationTrigger(now: Date) -> CardGenerationTrigger? {
        let timeSinceLastGeneration: TimeInterval
        if let lastTime = lastGenerationTime {
            timeSinceLastGeneration = now.timeIntervalSince(lastTime)
        } else if let firstSegment = pendingSegments.first, let lastSegment = pendingSegments.last {
            timeSinceLastGeneration = lastSegment.endTime - firstSegment.startTime
        } else {
            timeSinceLastGeneration = 0
        }

        let hasMinContent = timeSinceLastGeneration >= configuration.minGenerationIntervalSeconds
        let shouldForce = timeSinceLastGeneration >= configuration.maxGenerationIntervalSeconds
        let endsWithSentence = pendingText.endsWithCompleteSentence

        if shouldForce || (hasMinContent && endsWithSentence) {
            return triggerGeneration(now: now)
        }

        return nil
    }

    private func triggerGeneration(now: Date) -> CardGenerationTrigger {
        let contextText = contextSentences.joined(separator: " ")
        let trigger = CardGenerationTrigger(
            text: pendingText,
            segments: pendingSegments,
            contextText: contextText
        )

        let newSentences = detectSentences(in: pendingText)
        contextSentences.append(contentsOf: newSentences)
        if contextSentences.count > configuration.contextWindowSentences {
            contextSentences = Array(contextSentences.suffix(configuration.contextWindowSentences))
        }

        pendingSegments.removeAll()
        pendingText = ""
        lastGenerationTime = now

        return trigger
    }

    private func detectSentences(in text: String) -> [String] {
        var sentences: [String] = []
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        var currentSentence = ""

        for char in text {
            currentSentence.append(char)
            if let scalar = char.unicodeScalars.first, sentenceEnders.contains(scalar) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                currentSentence = ""
            }
        }

        return sentences
    }

    private func archiveOldSegmentsIfNeeded() {
        guard allSegments.count > configuration.maxInMemorySegments else { return }
        guard let archiveURL else { return }

        let segmentsToArchive = Array(allSegments.prefix(configuration.maxInMemorySegments / 2))
        allSegments.removeFirst(segmentsToArchive.count)

        do {
            var archived: [TranscriptSegment] = []
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                let data = try Data(contentsOf: archiveURL)
                archived = try JSONDecoder().decode([TranscriptSegment].self, from: data)
            }
            archived.append(contentsOf: segmentsToArchive)
            let data = try JSONEncoder().encode(archived)
            try data.write(to: archiveURL)
        } catch {
            // Archive failures should not block live buffering.
        }
    }
}

private extension String {
    var endsWithCompleteSentence: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last else { return false }
        return lastChar == "." || lastChar == "!" || lastChar == "?"
    }
}
