import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            SpeechModelsSettingsTab(viewModel: viewModel)
                .tabItem { Label("Speech & Models", systemImage: "waveform.and.mic") }
            SpeakersSettingsTab(viewModel: viewModel)
                .tabItem { Label("Speakers", systemImage: "person.2") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540)
        .frame(minHeight: 380)
    }
}

// Placeholder stubs — replaced by dedicated files in later tasks.
private struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("General — placeholder") }.formStyle(.grouped) }
}
private struct SpeechModelsSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("Speech & Models — placeholder") }.formStyle(.grouped) }
}
private struct SpeakersSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View { Form { Text("Speakers — placeholder") }.formStyle(.grouped) }
}
private struct AboutSettingsTab: View {
    var body: some View { Form { Text("About — placeholder") }.formStyle(.grouped) }
}
