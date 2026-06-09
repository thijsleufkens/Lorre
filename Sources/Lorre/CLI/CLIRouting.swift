import Foundation

/// Decides whether the process was launched as a CLI (a known subcommand was
/// passed) or as the normal GUI app. Only explicit subcommands count as CLI, so
/// LaunchServices-injected flags (e.g. `-psn_...`) still launch the GUI.
/// ArgumentParser meta-flags (--help, --version) are also routed to the CLI.
enum CLIRouting {
    static let subcommands: Set<String> = ["transcribe"]

    /// ArgumentParser global flags that should route to CLI even without a subcommand.
    private static let cliMetaFlags: Set<String> = ["--help", "-h", "--version"]

    static func isCLIInvocation(_ arguments: [String]) -> Bool {
        guard let first = arguments.dropFirst().first else { return false }
        return subcommands.contains(first) || cliMetaFlags.contains(first)
    }
}
