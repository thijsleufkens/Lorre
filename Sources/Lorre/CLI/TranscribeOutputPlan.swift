import ArgumentParser
import Foundation

enum TranscribeFormat: String, ExpressibleByArgument, CaseIterable {
    case md
    case json
    case both
}

/// Pure resolution of where rendered output goes, independent of ArgumentParser/FluidAudio.
enum TranscribeOutputPlan: Equatable {
    case stdout(ExportFormat)
    case file(URL, ExportFormat)
    case pair(markdown: URL, json: URL)

    static func resolve(format: TranscribeFormat, out: String?) throws -> TranscribeOutputPlan {
        switch format {
        case .md:
            guard let out else { return .stdout(.markdown) }
            return .file(URL(fileURLWithPath: out), .markdown)
        case .json:
            guard let out else { return .stdout(.json) }
            return .file(URL(fileURLWithPath: out), .json)
        case .both:
            guard let out else {
                throw ValidationError("--format both requires --out <stem> (writes <stem>.md and <stem>.json)")
            }
            let stem = URL(fileURLWithPath: out)
            return .pair(
                markdown: stem.deletingPathExtension().appendingPathExtension("md"),
                json: stem.deletingPathExtension().appendingPathExtension("json")
            )
        }
    }
}
