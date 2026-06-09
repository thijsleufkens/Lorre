import Foundation

@main
struct LorreEntry {
    static func main() async {
        if CLIRouting.isCLIInvocation(CommandLine.arguments) {
            await LorreCLI.main()
        } else {
            LorreApp.main()
        }
    }
}
