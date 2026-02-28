import Foundation

/// Grouped recording entity containing audio/transcript files with a shared base name.
public struct RecordingLibraryEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let audioURL: URL?
    public let transcriptURL: URL?
    public let allFiles: [URL]
    public let lastModified: Date?

    public var representativeURL: URL? {
        audioURL ?? transcriptURL ?? allFiles.first
    }

    public init(
        id: String,
        title: String,
        audioURL: URL?,
        transcriptURL: URL?,
        allFiles: [URL],
        lastModified: Date?
    ) {
        self.id = id
        self.title = title
        self.audioURL = audioURL
        self.transcriptURL = transcriptURL
        self.allFiles = allFiles
        self.lastModified = lastModified
    }
}

/// Parser extracted from paginated recordings loading logic.
public struct RecordingLibraryParser {
    public let allowedExtensions: Set<String>
    public let audioExtensions: Set<String>

    public init(
        allowedExtensions: Set<String> = ["m4a", "wav", "mp3", "txt"],
        audioExtensions: Set<String> = ["m4a", "wav", "mp3"]
    ) {
        self.allowedExtensions = allowedExtensions
        self.audioExtensions = audioExtensions
    }

    public func parseDirectory(at directoryURL: URL) throws -> [RecordingLibraryEntry] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return parse(files: files)
    }

    public func parse(files: [URL]) -> [RecordingLibraryEntry] {
        let filteredFiles = files.filter { url in
            allowedExtensions.contains(url.pathExtension.lowercased())
        }

        let metadata = filteredFiles.map { CachedFileMetadata(url: $0) }
        let grouped = Dictionary(grouping: metadata) { $0.baseName }

        let entries = grouped.map { baseName, metadataList in
            let urls = metadataList.map(\.url)

            let audio = metadataList.first { item in
                audioExtensions.contains(item.fileExtension)
            }?.url

            let transcript = metadataList.first { item in
                item.fileExtension == "txt"
            }?.url

            let lastModified = metadataList.compactMap(\.modificationDate).max()

            return RecordingLibraryEntry(
                id: baseName,
                title: baseName,
                audioURL: audio,
                transcriptURL: transcript,
                allFiles: urls,
                lastModified: lastModified
            )
        }

        return entries.sorted { lhs, rhs in
            let leftDate = lhs.lastModified ?? .distantPast
            let rightDate = rhs.lastModified ?? .distantPast
            return leftDate > rightDate
        }
    }
}

private struct CachedFileMetadata: Sendable {
    let url: URL
    let modificationDate: Date?
    let fileExtension: String
    let baseName: String

    init(url: URL) {
        self.url = url
        self.fileExtension = url.pathExtension.lowercased()
        self.baseName = url.deletingPathExtension().lastPathComponent
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        self.modificationDate = resourceValues?.contentModificationDate
    }
}
