import Foundation
import LorreCore

enum AudioLocator {
    /// The file to play for a conversation: the mix when it exists, else the microphone track,
    /// else the system track. Only files that exist and are not empty count.
    static func playableURL(tracks: [Track], paths: LorrePaths) -> URL? {
        for kind in [TrackKind.mix, .microphone, .system] {
            for track in tracks where track.kind == kind {
                let url = paths.root.appendingPathComponent(track.relativePath)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { return url }
            }
        }
        return nil
    }
}
