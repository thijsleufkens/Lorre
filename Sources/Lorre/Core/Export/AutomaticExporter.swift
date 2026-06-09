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

        let fileName = AutomaticExportFileNameBuilder.fileName(
            session: session,
            transcript: transcript,
            template: configuration.fileNameTemplate
        )
        let markdownURL = folderURL.appendingPathComponent(fileName)
        let jsonURL = markdownURL.deletingPathExtension().appendingPathExtension("json")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = try await exporter.export(session: session, transcript: transcript, format: .markdown, destinationURL: markdownURL)
        _ = try await exporter.export(session: session, transcript: transcript, format: .json, destinationURL: jsonURL)
        return (markdownURL, jsonURL)
    }
}
