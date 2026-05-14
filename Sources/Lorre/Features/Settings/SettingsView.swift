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
