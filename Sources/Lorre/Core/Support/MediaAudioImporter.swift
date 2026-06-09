import AVFoundation
import Foundation

/// Prepares an arbitrary media file for the transcription pipeline by writing an
/// audio file into a session directory. Audio-only inputs are copied verbatim;
/// inputs that also contain video have their audio track extracted to `audio.m4a`.
enum MediaAudioImporter {
    enum ImportError: Error, Equatable {
        case noAudioTrack
        case exportFailed(String)
    }

    /// Returns the file name written into `directory` (store it as `audioFileName`).
    static func prepareAudio(from sourceURL: URL, intoDirectory directory: URL) async throws -> String {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ImportError.noAudioTrack }
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if videoTracks.isEmpty {
            let fileName = "audio.\(sanitizedExtension(sourceURL.pathExtension))"
            let dest = directory.appendingPathComponent(fileName)
            try removeIfExists(dest)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return fileName
        }

        let fileName = "audio.m4a"
        let dest = directory.appendingPathComponent(fileName)
        try removeIfExists(dest)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.exportFailed("Could not create AVAssetExportSession")
        }
        do {
            try await export.export(to: dest, as: .m4a)
        } catch {
            throw ImportError.exportFailed(error.localizedDescription)
        }
        return fileName
    }

    private static func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func sanitizedExtension(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sanitized = String(lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return sanitized.isEmpty ? "m4a" : sanitized
    }
}
