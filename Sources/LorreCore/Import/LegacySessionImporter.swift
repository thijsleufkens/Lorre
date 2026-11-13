import Foundation
import GRDB

public struct LegacyImportReport: Equatable, Sendable {
    public struct Skipped: Equatable, Sendable {
        public var folder: String
        public var reason: String
    }

    public var imported: [UUID] = []
    public var alreadyPresent: [UUID] = []
    public var skipped: [Skipped] = []
}

/// Copies the sessions of the pre-rebuild file store into the database.
///
/// The legacy folder is only read: audio stays where it is and is referenced by path. A session
/// that is already in the database is left untouched, so the import can be repeated safely.
public struct LegacySessionImporter: Sendable {
    private let paths: LorrePaths
    private let database: LorreDatabase
    private let now: @Sendable () -> Date

    public init(paths: LorrePaths, database: LorreDatabase, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.database = database
        self.now = now
    }

    public func run() throws -> LegacyImportReport {
        var report = LegacyImportReport()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.legacySessions.path(percentEncoded: false)) else {
            return report
        }
        let folders = try fileManager.contentsOfDirectory(
            at: paths.legacySessions,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for folder in folders {
            let name = folder.lastPathComponent
            do {
                let session = try loadSession(in: folder)
                let inserted = try database.queue.write { db in try insert(session, into: db) }
                if inserted {
                    report.imported.append(session.id)
                } else {
                    report.alreadyPresent.append(session.id)
                }
            } catch let error as ImportError {
                report.skipped.append(.init(folder: name, reason: error.reason))
            } catch {
                report.skipped.append(.init(folder: name, reason: "\(error)"))
            }
        }
        return report
    }

    // MARK: Reading the legacy files

    private struct ImportError: Error {
        var reason: String
    }

    private struct LegacyManifest: Decodable {
        var id: UUID?
        var title: String
        var status: String?
        var createdAt: Date?
        var updatedAt: Date?
        var recordedAt: Date?
        var durationSeconds: Double?
        var audioFileName: String?
        var microphoneStemFileName: String?
        var systemAudioStemFileName: String?
        var transcriptFileName: String?
    }

    private struct LegacyTranscript: Decodable {
        struct Speaker: Decodable {
            var id: String
            var displayName: String?
        }
        struct Segment: Decodable {
            var id: UUID?
            var startMs: Int
            var endMs: Int
            var text: String
            var speakerId: String?
            var confidence: Double?
            var isEdited: Bool?
        }
        var languageHint: String?
        var sourceEngine: String?
        var segments: [Segment]?
        var speakers: [Speaker]?
        var createdAt: Date?
    }

    private struct LoadedSession {
        var id: UUID
        var folderName: String
        var manifest: LegacyManifest
        var transcript: LegacyTranscript?
        var trackFiles: [(TrackKind, String)]
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func loadSession(in folder: URL) throws -> LoadedSession {
        let fileManager = FileManager.default
        let folderName = folder.lastPathComponent
        let manifestURL = folder.appendingPathComponent("session.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw ImportError(reason: "no session.json")
        }
        let manifest: LegacyManifest
        do {
            manifest = try Self.decoder().decode(LegacyManifest.self, from: manifestData)
        } catch {
            throw ImportError(reason: "session.json could not be read")
        }
        // The folder name is what the old app trusted when it differed from the id inside the file.
        guard let id = UUID(uuidString: folderName) ?? manifest.id else {
            throw ImportError(reason: "no usable session id")
        }

        var transcript: LegacyTranscript?
        let transcriptURL = folder.appendingPathComponent(manifest.transcriptFileName ?? "transcript.json")
        if let data = try? Data(contentsOf: transcriptURL) {
            do {
                transcript = try Self.decoder().decode(LegacyTranscript.self, from: data)
            } catch {
                throw ImportError(reason: "transcript.json could not be read")
            }
        }

        let candidates: [(TrackKind, String?)] = [
            (.mix, manifest.audioFileName),
            (.microphone, manifest.microphoneStemFileName),
            (.system, manifest.systemAudioStemFileName),
        ]
        let trackFiles = candidates.compactMap { kind, name -> (TrackKind, String)? in
            // A file name is all the legacy store ever wrote; anything with a path in it is not ours.
            guard let name, !name.isEmpty, !name.contains("/") else { return nil }
            let url = folder.appendingPathComponent(name)
            return fileManager.fileExists(atPath: url.path(percentEncoded: false)) ? (kind, name) : nil
        }
        return LoadedSession(
            id: id, folderName: folderName, manifest: manifest, transcript: transcript, trackFiles: trackFiles
        )
    }

    // MARK: Writing

    /// Returns false when the conversation was already in the database.
    private func insert(_ session: LoadedSession, into db: Database) throws -> Bool {
        if try Conversation.exists(db, key: session.id.uuidString) { return false }

        let importedAt = now()
        let manifest = session.manifest
        let segments = session.transcript?.segments ?? []
        let hasTranscript = manifest.status == "ready" && !segments.isEmpty
        let createdAt = manifest.createdAt ?? importedAt

        try Conversation(
            id: session.id,
            title: manifest.title,
            type: .other,
            state: hasTranscript ? .proposed : .interrupted,
            startedAt: manifest.recordedAt ?? createdAt,
            durationSeconds: manifest.durationSeconds,
            importedAt: importedAt,
            createdAt: createdAt,
            updatedAt: manifest.updatedAt ?? createdAt
        ).insert(db)

        for (kind, fileName) in session.trackFiles {
            try Track(
                conversationId: session.id,
                kind: kind,
                relativePath: "sessions/\(session.folderName)/\(fileName)"
            ).insert(db)
        }

        guard let transcript = session.transcript, !segments.isEmpty else { return true }

        var participantByLabel: [String: UUID] = [:]
        func participant(for label: String, name: String?) throws -> UUID {
            if let existing = participantByLabel[label] { return existing }
            let participant = Participant(
                conversationId: session.id,
                name: name ?? label,
                sourceLabel: label
            )
            try participant.insert(db)
            participantByLabel[label] = participant.id
            return participant.id
        }
        for speaker in transcript.speakers ?? [] {
            _ = try participant(for: speaker.id, name: speaker.displayName)
        }

        let version = TranscriptVersion(
            conversationId: session.id,
            engine: transcript.sourceEngine ?? "unknown",
            languageHint: transcript.languageHint,
            createdAt: transcript.createdAt ?? createdAt
        )
        var seenSegmentIds = Set<UUID>()
        let newSegments = try segments.map { legacy -> Segment in
            // Segment ids must be unique across the database; a duplicated legacy id gets a fresh one.
            var id = legacy.id ?? UUID()
            let isTaken = try seenSegmentIds.contains(id) || Segment.exists(db, key: id.uuidString)
            if isTaken { id = UUID() }
            seenSegmentIds.insert(id)
            return Segment(
                id: id,
                transcriptVersionId: version.id,
                participantId: try legacy.speakerId.map { try participant(for: $0, name: nil) },
                startMs: legacy.startMs,
                endMs: legacy.endMs,
                text: legacy.text,
                confidence: legacy.confidence,
                isEdited: legacy.isEdited ?? false
            )
        }
        try ConversationStore.insertTranscript(db, version: version, segments: newSegments)
        return true
    }
}
