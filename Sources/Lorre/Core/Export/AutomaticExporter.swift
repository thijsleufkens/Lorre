import Foundation

/// Writes the finalized transcript as the `.md` + `.json` envelope into the
/// configured auto-export folder. Single source of truth for the envelope contract
/// consumed by `strongbad-lorre-ingest`; used by both the GUI auto-export and the CLI.
enum AutomaticExporter {
    enum ExportError: Error, Equatable {
        case noFolder
    }

    @discardableResult
    static func writeEnvelope(
        session: SessionManifest,
        transcript: TranscriptDocument,
        configuration: AutomaticMarkdownExportConfiguration,
        exporter: any ExportService
    ) async throws -> (markdown: URL, json: URL) {
        guard let folderURL = configuration.folderURL else { throw ExportError.noFolder }

        let renderedFileName = AutomaticExportFileNameBuilder.fileName(
            session: session,
            transcript: transcript,
            template: configuration.fileNameTemplate
        )
        let fileName = collisionSafeFileName(renderedFileName, session: session, folderURL: folderURL)
        let markdownURL = folderURL.appendingPathComponent(fileName)
        let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = try await exporter.export(session: session, transcript: transcript, format: .markdown, destinationURL: markdownURL)
        _ = try await exporter.export(session: session, transcript: transcript, format: .json, destinationURL: jsonURL)
        return (markdownURL, jsonURL)
    }

    /// Two sessions on the same day with the same (smart) title render the same
    /// template file name. Overwriting another session's envelope is silent data
    /// loss for downstream consumers, so when the target files belong to a
    /// different session the name is disambiguated with the short session id.
    /// Re-exports of the same session keep their original name and overwrite
    /// themselves, which is the update contract `strongbad-lorre-ingest` relies on.
    private static func collisionSafeFileName(
        _ fileName: String,
        session: SessionManifest,
        folderURL: URL
    ) -> String {
        let markdownURL = folderURL.appendingPathComponent(fileName)
        let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")
        let fileManager = FileManager.default

        let markdownExists = fileManager.fileExists(atPath: markdownURL.path(percentEncoded: false))
        let jsonExists = fileManager.fileExists(atPath: jsonURL.path(percentEncoded: false))
        guard markdownExists || jsonExists else { return fileName }
        if jsonExists, envelopeSessionID(at: jsonURL) == session.id { return fileName }

        let stem = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        let shortID = String(session.id.uuidString.prefix(8)).lowercased()
        return pathExtension.isEmpty ? "\(stem)-\(shortID)" : "\(stem)-\(shortID).\(pathExtension)"
    }

    private static func envelopeSessionID(at url: URL) -> UUID? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionObject = object["session"] as? [String: Any],
              let idString = sessionObject["id"] as? String else {
            return nil
        }
        return UUID(uuidString: idString)
    }
}
