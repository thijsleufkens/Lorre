import ArgumentParser
import Foundation

struct TranscribeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio or video file locally."
    )

    @Argument(help: "Path to an audio or video file.")
    var input: String

    mutating func run() async throws {
        throw ValidationError("transcribe is not implemented yet")
    }
}
