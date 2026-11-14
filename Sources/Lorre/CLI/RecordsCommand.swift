import ArgumentParser
import Foundation
import LorreCore

extension RecordStatus: ExpressibleByArgument {}

struct RecordsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "records",
        abstract: "List the exported records (latest version of each), newest first."
    )

    @OptionGroup var store: StoreOptions

    @Flag(help: "Only records this consumer has not processed yet. Needs --consumer.")
    var new: Bool = false

    @Option(help: "Your name as a consumer, for --new.")
    var consumer: String?

    @Option(help: "Only draft or approved records.")
    var status: RecordStatus?

    @Flag(help: "Print JSON instead of a table.")
    var json: Bool = false

    func validate() throws {
        if new, (consumer ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("--new needs --consumer NAME.")
        }
    }

    func run() throws {
        let listings = try RecordCatalog(database: store.openDatabase())
            .list(status: status, newFor: new ? consumer : nil)
        print(try Self.render(listings, json: json))
    }

    static func render(_ listings: [RecordListing], json: Bool, timeZone: TimeZone = .current) throws -> String {
        if json {
            return String(decoding: try MeetingRecord.encoder().encode(listings), as: UTF8.self)
        }
        guard !listings.isEmpty else { return "No records." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return listings.map { listing in
            [
                String(listing.recordId.uuidString.prefix(8)),
                formatter.string(from: listing.startedAt),
                listing.status.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0),
                "v\(listing.recordVersion)".padding(toLength: 3, withPad: " ", startingAt: 0),
                listing.title,
            ].joined(separator: "  ")
        }.joined(separator: "\n")
    }
}

struct RecordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Print the latest exported record of a conversation."
    )

    @Argument(help: "Record id, or the first characters of it (see `records`).")
    var id: String

    @OptionGroup var store: StoreOptions

    @Flag(help: "Print the readable Markdown instead of the JSON.")
    var markdown: Bool = false

    func run() throws {
        let catalog = RecordCatalog(database: try store.openDatabase())
        let listing = try RecordCatalog.resolve(id, in: catalog.list())
        print(try Self.render(try catalog.record(listing.recordId), markdown: markdown), terminator: markdown ? "" : "\n")
    }

    static func render(_ record: MeetingRecord, markdown: Bool, language: LorreLanguage = .current) throws -> String {
        markdown
            ? RecordMarkdown.render(record, language: language)
            : String(decoding: try MeetingRecord.encoder().encode(record), as: UTF8.self)
    }
}
