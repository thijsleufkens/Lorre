import Foundation

/// What the app needs to look for updates: where the feed lives and the public key its entries are
/// signed with. Both come from the Info.plist, written by the packaging script. Without both, the
/// app has no update feature at all.
struct UpdateConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicKey: String

    static func from(infoDictionary: [String: Any]?) -> UpdateConfiguration? {
        guard let info = infoDictionary,
              let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return UpdateConfiguration(feedURL: url, publicKey: key)
    }
}
