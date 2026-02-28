import XCTest
@testable import CaptureLiveKit

final class DocumentImportServiceTests: XCTestCase {
    func testSupportsCaseInsensitiveExtensions() {
        XCTAssertTrue(DocumentImportService.supports(utType: nil, fileExtension: "PDF"))
        XCTAssertTrue(DocumentImportService.supports(utType: nil, fileExtension: "Md"))
        XCTAssertTrue(DocumentImportService.supports(utType: nil, fileExtension: "JSONL"))
    }

    func testProcessDocumentNormalizesLineEndings() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("notes.txt")
        let destinationDir = tempDir.appendingPathComponent("library")
        try "hello\r\nworld  \r".write(to: sourceURL, atomically: true, encoding: .utf8)

        let result = try DocumentImportService.processDocument(at: sourceURL, destinationDirectory: destinationDir)
        let saved = try String(contentsOf: result.destinationURL, encoding: .utf8)

        XCTAssertFalse(saved.contains("\r"))
        XCTAssertEqual(result.wordCount, 2)
    }

    func testRejectsEmptyDocument() throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("empty.txt")
        let destinationDir = tempDir.appendingPathComponent("library")
        try "   \n\n   ".write(to: sourceURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try DocumentImportService.processDocument(at: sourceURL, destinationDirectory: destinationDir)
        ) { error in
            XCTAssertEqual(error as? DocumentImportError, .emptyContents)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentImportServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
