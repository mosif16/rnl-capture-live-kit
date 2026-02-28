import Foundation
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum DocumentImportError: Error, Equatable {
    case unsupportedType
    case fileTooLarge(actualBytes: Int, limitBytes: Int)
    case emptyContents
    case decodingFailed
    case pdfReadFailed
}

public struct DocumentImportResult: Sendable, Equatable {
    public let destinationURL: URL
    public let displayName: String
    public let wordCount: Int

    public init(destinationURL: URL, displayName: String, wordCount: Int) {
        self.destinationURL = destinationURL
        self.displayName = displayName
        self.wordCount = wordCount
    }
}

public enum DocumentImportService {
    private static let maxTextFileSizeBytes = 25 * 1024 * 1024
    private static let fallbackEncodings: [String.Encoding] = [
        .utf8,
        .utf16,
        .utf16LittleEndian,
        .utf16BigEndian,
        .utf32,
        .utf32LittleEndian,
        .utf32BigEndian,
        .windowsCP1252,
        .isoLatin1,
        .ascii
    ]

    public static var supportedContentTypes: [UTType] {
        var types: Set<UTType> = [
            .text,
            .plainText,
            .utf8PlainText,
            .utf16PlainText,
            .rtf,
            .rtfd,
            .pdf,
            .html,
            .xml,
            .json,
            .sourceCode,
            .commaSeparatedText
        ]

        ["md", "markdown", "txt", "log", "csv", "tsv", "jsonl", "yaml", "yml"].forEach { ext in
            if let customType = UTType(filenameExtension: ext) {
                types.insert(customType)
            }
        }

        return Array(types)
    }

    public static func supports(utType: UTType?, fileExtension: String) -> Bool {
        let sanitizedExtension = fileExtension.lowercased()
        if let utType {
            if supportedContentTypes.contains(where: { utType.conforms(to: $0) }) {
                return true
            }
        }
        return ["txt", "md", "markdown", "rtf", "rtfd", "pdf", "csv", "tsv", "log", "json", "jsonl", "yaml", "yml", "html", "htm", "xml"].contains(sanitizedExtension)
    }

    public static func processDocumentAsync(at sourceURL: URL, destinationDirectory: URL) async throws -> DocumentImportResult {
        try await Task.detached(priority: .userInitiated) {
            try processDocument(at: sourceURL, destinationDirectory: destinationDirectory)
        }.value
    }

    public static func processDocument(at sourceURL: URL, destinationDirectory: URL) throws -> DocumentImportResult {
        let fileManager = FileManager.default
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        if let fileSize = resourceValues.fileSize, fileSize > maxTextFileSizeBytes {
            throw DocumentImportError.fileTooLarge(actualBytes: fileSize, limitBytes: maxTextFileSizeBytes)
        }

        let originalName = resourceValues.name ?? sourceURL.deletingPathExtension().lastPathComponent
        let baseName = sanitizedBaseName(from: originalName)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(forBaseName: baseName, in: destinationDirectory)
        let utType = UTType(filenameExtension: sourceURL.pathExtension.lowercased())
        let extractedText: String

        if utType?.conforms(to: .pdf) == true {
            extractedText = try extractPDFText(from: sourceURL)
        } else if utType?.conforms(to: .rtf) == true {
            extractedText = try extractAttributedText(from: sourceURL, documentType: .rtf)
        } else if utType?.conforms(to: .rtfd) == true {
            extractedText = try extractAttributedText(from: sourceURL, documentType: .rtfd)
        } else if utType?.conforms(to: .html) == true {
            extractedText = try extractAttributedText(from: sourceURL, documentType: .html)
        } else if utType?.conforms(to: .xml) == true
                    || utType?.conforms(to: .json) == true
                    || utType?.conforms(to: .sourceCode) == true
                    || utType?.conforms(to: .text) == true {
            extractedText = try loadPlainText(from: sourceURL)
        } else if supports(utType: utType, fileExtension: sourceURL.pathExtension) {
            extractedText = try loadPlainText(from: sourceURL)
        } else {
            throw DocumentImportError.unsupportedType
        }

        let normalized = normalize(text: extractedText)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.emptyContents
        }

        try normalized.write(to: destinationURL, atomically: true, encoding: .utf8)
        let wordCount = countWords(in: normalized)

        return DocumentImportResult(
            destinationURL: destinationURL,
            displayName: baseName,
            wordCount: wordCount
        )
    }

    public static func userFacingMessage(for error: Error, fileName: String) -> (title: String, message: String) {
        switch error {
        case DocumentImportError.fileTooLarge(let actualBytes, let limitBytes):
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB]
            formatter.countStyle = .file
            let actual = formatter.string(fromByteCount: Int64(actualBytes))
            let limit = formatter.string(fromByteCount: Int64(limitBytes))
            return (
                title: "File Too Large",
                message: "\"\(fileName)\" is \(actual). The maximum supported text upload is \(limit). Please compress or shorten it before importing."
            )
        case DocumentImportError.emptyContents:
            return (
                title: "No Text Detected",
                message: "We couldn’t find readable text in \"\(fileName)\". If it’s a scanned document, run OCR before importing."
            )
        case DocumentImportError.decodingFailed:
            return (
                title: "Unsupported Encoding",
                message: "We couldn’t decode the text in \"\(fileName)\". Convert it to UTF-8 or plain text and try again."
            )
        case DocumentImportError.pdfReadFailed:
            return (
                title: "PDF Extraction Failed",
                message: "Something went wrong while reading \"\(fileName)\". Ensure the PDF isn’t password-protected or corrupted."
            )
        case DocumentImportError.unsupportedType:
            return (
                title: "Unsupported Document",
                message: "\"\(fileName)\" isn’t a supported text document. Save it as PDF, RTF, or plain text before importing."
            )
        default:
            return (
                title: "Import Failed",
                message: error.localizedDescription.isEmpty
                    ? "An unknown error occurred while importing \"\(fileName)\"."
                    : error.localizedDescription
            )
        }
    }

    private static func loadPlainText(from url: URL) throws -> String {
        var usedEncoding = String.Encoding.utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &usedEncoding) {
            return detected
        }

        let data = try Data(contentsOf: url)
        for encoding in fallbackEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }
        throw DocumentImportError.decodingFailed
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentImportError.pdfReadFailed
        }

        var segments: [String] = []
        for index in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: index) else { continue }
            if let text = page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(text)
            } else if let attributed = page.attributedString?.string,
                      !attributed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(attributed)
            }
        }

        guard !segments.isEmpty else {
            throw DocumentImportError.emptyContents
        }
        return segments.joined(separator: "\n\n")
    }

    private static func extractAttributedText(
        from url: URL,
        documentType: NSAttributedString.DocumentType
    ) throws -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]
        let attributed = try NSAttributedString(
            url: url,
            options: options,
            documentAttributes: nil
        )
        return attributed.string
    }

    private static func uniqueDestinationURL(forBaseName baseName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).txt")
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).txt")
            index += 1
        }
        return candidate
    }

    private static func sanitizedBaseName(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let components = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(components).replacingOccurrences(of: "--", with: "-")
        if cleaned.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).isEmpty {
            return "Document-\(Int(Date().timeIntervalSince1970))"
        }
        return cleaned
    }

    private static func normalize(text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmedTrailing = lines.map { line -> String in
            var mutable = String(line)
            while let last = mutable.unicodeScalars.last,
                  CharacterSet.whitespaces.contains(last) {
                mutable.unicodeScalars.removeLast()
            }
            return mutable
        }

        return trimmedTrailing.joined(separator: "\n")
    }

    private static func countWords(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}
