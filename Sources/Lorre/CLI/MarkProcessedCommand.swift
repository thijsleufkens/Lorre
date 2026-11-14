import ArgumentParser
import Foundation
import LorreCore

struct MarkProcessedCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark-processed",
        abstract: "Mark a record version as processed by a consumer."
    )

    @Argument(help: "Record id, or the first characters of it (see `records`).")
    var id: String

    @OptionGroup var store: StoreOptions

    @Option(help: "Your name as a consumer.")
    var consumer: String

    @Option(help: "The record version; default is the latest.")
    var version: Int?

    func run() throws {
        let database = try store.openDatabase()
        let listing = try RecordCatalog.resolve(id, in: RecordCatalog(database: database).list())
        let cursor = try ConsumerStore(database: database)
            .markProcessed(recordId: listing.recordId, version: version, consumer: consumer)
        print(Self.render(cursor, title: listing.title))
    }

    static func render(_ cursor: ConsumerCursor, title: String) -> String {
        "Marked \"\(title)\" (\(cursor.conversationId.uuidString.prefix(8))) version \(cursor.recordVersion) as processed by \(cursor.consumerName)."
    }
}
