import AVFoundation
import Foundation
import Observation

@MainActor
protocol EvidencePlaying: AnyObject {
    var isPlaying: Bool { get }
    /// Plays the stretch [startMs, endMs] of the file; endMs nil plays to the end.
    func play(url: URL, startMs: Int, endMs: Int?)
    func stop()
}

/// Plays the stretch of a recording that backs an outcome.
@MainActor
@Observable
final class EvidencePlayer: EvidencePlaying {
    private(set) var isPlaying = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func play(url: URL, startMs: Int, endMs: Int?) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        let start = max(0, Double(startMs) / 1000)
        guard start < player.duration else { return }
        player.currentTime = start
        guard player.play() else { return }
        self.player = player
        isPlaying = true

        let end = min(endMs.map { Double($0) / 1000 } ?? player.duration, player.duration)
        let remaining = max(0.05, end - start)
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        isPlaying = false
    }
}
