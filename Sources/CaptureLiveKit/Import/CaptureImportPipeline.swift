import Foundation
import UniformTypeIdentifiers

public enum CaptureImportClassification: String, Sendable {
    case audio
    case video
    case document
    case unsupported
}

public struct ImportedAudioAsset: Sendable, Equatable {
    public let sourceURL: URL
    public let audioURL: URL
    public let transcriptionReady: Bool

    public init(sourceURL: URL, audioURL: URL, transcriptionReady: Bool) {
        self.sourceURL = sourceURL
        self.audioURL = audioURL
        self.transcriptionReady = transcriptionReady
    }
}

public struct ImportedDocumentAsset: Sendable, Equatable {
    public let sourceURL: URL
    public let result: DocumentImportResult

    public init(sourceURL: URL, result: DocumentImportResult) {
        self.sourceURL = sourceURL
        self.result = result
    }
}

public enum CaptureImportOutcome: Sendable, Equatable {
    case audio(ImportedAudioAsset)
    case video(ImportedAudioAsset)
    case document(ImportedDocumentAsset)
}

public enum CaptureImportPipelineError: Error, Equatable {
    case unsupportedFileType(fileExtension: String)
    case missingVideoAudioExtractor
}

public protocol CaptureTranscriptionAvailabilityProviding: Sendable {
    func isTranscriptionReady() async -> Bool
}

public protocol CaptureVideoAudioExtracting: Sendable {
    func extractAudio(from videoURL: URL, to outputURL: URL) async throws
}

public protocol CaptureDocumentImporting: Sendable {
    func processDocument(at sourceURL: URL, destinationDirectory: URL) async throws -> DocumentImportResult
}

public struct DefaultDocumentImporter: CaptureDocumentImporting {
    public init() {}

    public func processDocument(at sourceURL: URL, destinationDirectory: URL) async throws -> DocumentImportResult {
        try await DocumentImportService.processDocumentAsync(at: sourceURL, destinationDirectory: destinationDirectory)
    }
}

/// Reusable file import pipeline extracted from the app-level coordinator.
public struct CaptureImportPipeline {
    public let supportedAudioExtensions: Set<String>
    public let supportedVideoExtensions: Set<String>

    public init(
        supportedAudioExtensions: Set<String> = ["m4a", "wav", "mp3"],
        supportedVideoExtensions: Set<String> = ["mp4", "mov", "mkv", "avi"]
    ) {
        self.supportedAudioExtensions = supportedAudioExtensions
        self.supportedVideoExtensions = supportedVideoExtensions
    }

    public func classify(url: URL) -> CaptureImportClassification {
        let ext = url.pathExtension.lowercased()

        if supportedAudioExtensions.contains(ext) {
            return .audio
        }
        if supportedVideoExtensions.contains(ext) {
            return .video
        }
        if DocumentImportService.supports(
            utType: UTType(filenameExtension: ext),
            fileExtension: ext
        ) {
            return .document
        }

        return .unsupported
    }

    public func importFile(
        at sourceURL: URL,
        destinationDirectory: URL,
        transcriptionAvailability: any CaptureTranscriptionAvailabilityProviding,
        videoAudioExtractor: (any CaptureVideoAudioExtracting)? = nil,
        documentImporter: any CaptureDocumentImporting = DefaultDocumentImporter()
    ) async throws -> CaptureImportOutcome {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension.lowercased()
        let baseName = sanitizedBaseName(sourceURL.deletingPathExtension().lastPathComponent)

        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        switch classify(url: sourceURL) {
        case .audio:
            let destinationURL = uniqueDestinationURL(baseName: baseName, extension: ext, in: destinationDirectory)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let ready = await transcriptionAvailability.isTranscriptionReady()
            return .audio(
                ImportedAudioAsset(
                    sourceURL: sourceURL,
                    audioURL: destinationURL,
                    transcriptionReady: ready
                )
            )

        case .video:
            guard let videoAudioExtractor else {
                throw CaptureImportPipelineError.missingVideoAudioExtractor
            }
            let destinationURL = uniqueDestinationURL(baseName: baseName, extension: "m4a", in: destinationDirectory)
            try await videoAudioExtractor.extractAudio(from: sourceURL, to: destinationURL)
            let ready = await transcriptionAvailability.isTranscriptionReady()
            return .video(
                ImportedAudioAsset(
                    sourceURL: sourceURL,
                    audioURL: destinationURL,
                    transcriptionReady: ready
                )
            )

        case .document:
            let result = try await documentImporter.processDocument(
                at: sourceURL,
                destinationDirectory: destinationDirectory
            )
            return .document(ImportedDocumentAsset(sourceURL: sourceURL, result: result))

        case .unsupported:
            throw CaptureImportPipelineError.unsupportedFileType(fileExtension: ext)
        }
    }

    private func uniqueDestinationURL(
        baseName: String,
        extension ext: String,
        in directory: URL
    ) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var index = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(index).\(ext)")
            index += 1
        }

        return candidate
    }

    private func sanitizedBaseName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Imported-\(Int(Date().timeIntervalSince1970))"
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let components = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(components).replacingOccurrences(of: "--", with: "-")

        if cleaned.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)).isEmpty {
            return "Imported-\(Int(Date().timeIntervalSince1970))"
        }

        return cleaned
    }
}
