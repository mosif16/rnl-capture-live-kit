import Foundation

public protocol RecordingSessionStore: Sendable {
    func save(_ session: RecordingSession) throws
    func load(id: UUID) throws -> RecordingSession
    func list() throws -> [RecordingSession]
    func delete(id: UUID) throws
}

public struct JSONFileRecordingSessionStore: RecordingSessionStore {
    public let directory: URL

    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documentsPath.appendingPathComponent("CaptureLiveSessions", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func save(_ session: RecordingSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to: fileURL(for: session.id), options: .atomic)
    }

    public func load(id: UUID) throws -> RecordingSession {
        let data = try Data(contentsOf: fileURL(for: id))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingSession.self, from: data)
    }

    public func list() throws -> [RecordingSession] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                let data = try Data(contentsOf: file)
                return try decoder.decode(RecordingSession.self, from: data)
            }
            .sorted(by: { $0.startedAt > $1.startedAt })
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
