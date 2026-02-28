import XCTest
@testable import CaptureLiveKit

final class RecordingLibraryParserTests: XCTestCase {
    func testParserGroupsFilesByBaseNameAndSortsByLastModified() throws {
        let parser = RecordingLibraryParser()
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()

        let algebraAudio = tempDir.appendingPathComponent("Algebra.m4a")
        let algebraTranscript = tempDir.appendingPathComponent("Algebra.txt")
        let biologyTranscript = tempDir.appendingPathComponent("Biology.txt")
        let ignoredArchive = tempDir.appendingPathComponent("ignored.zip")

        try Data("audio".utf8).write(to: algebraAudio)
        try "algebra transcript".write(to: algebraTranscript, atomically: true, encoding: .utf8)
        try "biology transcript".write(to: biologyTranscript, atomically: true, encoding: .utf8)
        try Data("archive".utf8).write(to: ignoredArchive)

        try setModificationDate(now.addingTimeInterval(-120), for: algebraAudio)
        try setModificationDate(now.addingTimeInterval(-90), for: algebraTranscript)
        try setModificationDate(now.addingTimeInterval(-10), for: biologyTranscript)

        let entries = try parser.parseDirectory(at: tempDir)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.id, "Biology")

        guard let algebra = entries.first(where: { $0.id == "Algebra" }) else {
            XCTFail("Expected Algebra group")
            return
        }

        XCTAssertNotNil(algebra.audioURL)
        XCTAssertNotNil(algebra.transcriptURL)
        XCTAssertEqual(algebra.allFiles.count, 2)
    }

    func testParserCanParseInMemoryFileList() {
        let parser = RecordingLibraryParser()

        let urls = [
            URL(fileURLWithPath: "/tmp/LectureA.m4a"),
            URL(fileURLWithPath: "/tmp/LectureA.txt"),
            URL(fileURLWithPath: "/tmp/LectureB.txt"),
            URL(fileURLWithPath: "/tmp/LectureB.mp3")
        ]

        let entries = parser.parse(files: urls)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains(where: { $0.id == "LectureA" && $0.transcriptURL != nil }))
        XCTAssertTrue(entries.contains(where: { $0.id == "LectureB" && $0.audioURL != nil }))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingLibraryParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
