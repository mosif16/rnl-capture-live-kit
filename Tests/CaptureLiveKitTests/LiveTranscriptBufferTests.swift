import XCTest
@testable import CaptureLiveKit

final class LiveTranscriptBufferTests: XCTestCase {
    func testMinIntervalRequiresSentenceBoundary() async {
        let buffer = LiveTranscriptBuffer()

        let first = await buffer.addSegment(
            TranscriptSegment(
                text: "First chunk without punctuation",
                startTime: 0,
                endTime: 20,
                confidence: 0.9
            )
        )
        XCTAssertNil(first)

        let second = await buffer.addSegment(
            TranscriptSegment(
                text: "Second chunk closes sentence.",
                startTime: 20,
                endTime: 35,
                confidence: 0.9
            )
        )

        XCTAssertNotNil(second)
        XCTAssertEqual(second?.segments.count, 2)
        XCTAssertEqual(second?.text, "First chunk without punctuation Second chunk closes sentence.")
    }

    func testMaxIntervalForcesGeneration() async {
        let buffer = LiveTranscriptBuffer()

        let trigger = await buffer.addSegment(
            TranscriptSegment(
                text: "Long chunk that does not end with punctuation",
                startTime: 0,
                endTime: 61,
                confidence: 0.8
            )
        )

        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.segments.count, 1)
        XCTAssertEqual(trigger?.segments.first?.startTime, 0)
        XCTAssertEqual(trigger?.segments.first?.endTime, 61)
    }

    func testContextWindowKeepsLastSentences() async {
        let configuration = LiveTranscriptBufferConfiguration(
            minGenerationIntervalSeconds: 30,
            maxGenerationIntervalSeconds: 60,
            contextWindowSentences: 3,
            maxInMemorySegments: 100
        )
        let buffer = LiveTranscriptBuffer(configuration: configuration)

        let firstTrigger = await buffer.addSegment(
            TranscriptSegment(
                text: "One. Two. Three. Four.",
                startTime: 0,
                endTime: 61,
                confidence: 0.95
            )
        )
        XCTAssertNotNil(firstTrigger)

        _ = await buffer.addSegment(
            TranscriptSegment(
                text: "Fresh sentence.",
                startTime: 61,
                endTime: 62,
                confidence: 0.95
            )
        )

        let secondTrigger = await buffer.forceGeneration()
        XCTAssertNotNil(secondTrigger)
        XCTAssertEqual(secondTrigger?.contextText, "Two. Three. Four.")
    }
}
