import XCTest
@testable import CaptureLiveKit

final class CaptureImportPipelineTests: XCTestCase {
    private struct TranscriptionAvailabilityProvider: CaptureTranscriptionAvailabilityProviding {
        let ready: Bool

        func isTranscriptionReady() async -> Bool {
            ready
        }
    }

    private actor MockVideoExtractor: CaptureVideoAudioExtracting {
        private(set) var callCount = 0

        func extractAudio(from videoURL: URL, to outputURL: URL) async throws {
            callCount += 1
            let payload = "mock-audio-from-\(videoURL.lastPathComponent)"
            try Data(payload.utf8).write(to: outputURL)
        }

        func currentCallCount() -> Int {
            callCount
        }
    }

    func testClassificationCoversAudioVideoDocumentAndUnsupported() {
        let pipeline = CaptureImportPipeline()

        XCTAssertEqual(pipeline.classify(url: URL(fileURLWithPath: "/tmp/lecture.m4a")), .audio)
        XCTAssertEqual(pipeline.classify(url: URL(fileURLWithPath: "/tmp/lecture.mov")), .video)
        XCTAssertEqual(pipeline.classify(url: URL(fileURLWithPath: "/tmp/notes.pdf")), .document)
        XCTAssertEqual(pipeline.classify(url: URL(fileURLWithPath: "/tmp/archive.zip")), .unsupported)
    }

    func testAudioImportCopiesFileAndReturnsReadiness() async throws {
        let pipeline = CaptureImportPipeline()
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("capture.m4a")
        let destinationDir = tempDir.appendingPathComponent("library")

        let payload = Data([0, 1, 2, 3, 4])
        try payload.write(to: sourceURL)

        let outcome = try await pipeline.importFile(
            at: sourceURL,
            destinationDirectory: destinationDir,
            transcriptionAvailability: TranscriptionAvailabilityProvider(ready: false)
        )

        guard case .audio(let imported) = outcome else {
            XCTFail("Expected audio outcome")
            return
        }

        XCTAssertFalse(imported.transcriptionReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.audioURL.path))
        XCTAssertEqual(try Data(contentsOf: imported.audioURL), payload)
    }

    func testVideoImportRequiresExtractor() async throws {
        let pipeline = CaptureImportPipeline()
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("lecture.mov")
        let destinationDir = tempDir.appendingPathComponent("library")
        try Data("video".utf8).write(to: sourceURL)

        do {
            _ = try await pipeline.importFile(
                at: sourceURL,
                destinationDirectory: destinationDir,
                transcriptionAvailability: TranscriptionAvailabilityProvider(ready: true)
            )
            XCTFail("Expected missing video extractor error")
        } catch let error as CaptureImportPipelineError {
            XCTAssertEqual(error, .missingVideoAudioExtractor)
        }
    }

    func testVideoImportUsesExtractor() async throws {
        let pipeline = CaptureImportPipeline()
        let extractor = MockVideoExtractor()

        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("lecture.mov")
        let destinationDir = tempDir.appendingPathComponent("library")
        try Data("video".utf8).write(to: sourceURL)

        let outcome = try await pipeline.importFile(
            at: sourceURL,
            destinationDirectory: destinationDir,
            transcriptionAvailability: TranscriptionAvailabilityProvider(ready: true),
            videoAudioExtractor: extractor
        )

        guard case .video(let imported) = outcome else {
            XCTFail("Expected video outcome")
            return
        }

        XCTAssertTrue(imported.transcriptionReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.audioURL.path))
        let callCount = await extractor.currentCallCount()
        XCTAssertEqual(callCount, 1)
    }

    func testDocumentImportProcessesText() async throws {
        let pipeline = CaptureImportPipeline()
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("outline.txt")
        let destinationDir = tempDir.appendingPathComponent("library")
        try "Line one\nLine two".write(to: sourceURL, atomically: true, encoding: .utf8)

        let outcome = try await pipeline.importFile(
            at: sourceURL,
            destinationDirectory: destinationDir,
            transcriptionAvailability: TranscriptionAvailabilityProvider(ready: true)
        )

        guard case .document(let imported) = outcome else {
            XCTFail("Expected document outcome")
            return
        }

        XCTAssertGreaterThan(imported.result.wordCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.result.destinationURL.path))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureImportPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
