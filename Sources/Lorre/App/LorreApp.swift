import LorreCore
import SwiftUI

struct LorreApp: App {
    /// One set of speech services for the whole app, so models are loaded once.
    private static let dependencies = AppDependencies.live()

    @StateObject private var viewModel = AppViewModel(dependencies: LorreApp.dependencies)
    @State private var services = AppServices(dependencies: LorreApp.dependencies)

    var body: some Scene {
        WindowGroup("Lorre") {
            AppShellView(viewModel: viewModel)
                .frame(minWidth: 1120, minHeight: 760)
                .preferredColorScheme(nil)
                .environment(\.recorderModel, services.recorder)
                .task {
                    if let recorder = services.recorder {
                        // Calls detected by the call watcher are recorded through the new recorder.
                        viewModel.externalRecorderStart = { source in
                            Task { await recorder.start(source: CaptureSource(source)) }
                        }
                    }
                    await viewModel.start()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(viewModel: viewModel)
        }

        MenuBarExtra {
            if let recorder = services.recorder {
                MenuBarRecorderView(model: recorder)
            } else {
                Text(services.startupError ?? "Recording is unavailable.")
                    .padding()
            }
        } label: {
            Image(systemName: services.recorder?.isRecording == true ? "record.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}

extension EnvironmentValues {
    /// The menu-bar recorder, for the parts of the old window that point at it.
    @Entry var recorderModel: RecorderModel?
}

extension CaptureSource {
    init(_ source: RecordingSource) {
        switch source {
        case .microphone: self = .microphone
        case .systemAudio: self = .systemAudio
        case .microphoneAndSystemAudio: self = .microphoneAndSystemAudio
        }
    }
}
