import LorreCore
import SwiftUI

struct LorreApp: App {
    /// One set of speech services for the whole app, so models are loaded once.
    private static let dependencies = AppDependencies.live()

    @StateObject private var viewModel = AppViewModel(dependencies: LorreApp.dependencies)
    @State private var services = AppServices(dependencies: LorreApp.dependencies)

    @ViewBuilder private var mainContent: some View {
        if let workspace = services.workspace {
            WorkspaceView(workspace: workspace, recorder: services.recorder)
        } else {
            Text(services.startupError ?? Strings.current.recorderUnavailable)
                .padding(DS.Space.x8)
        }
    }

    var body: some Scene {
        WindowGroup("Lorre") {
            mainContent
                .frame(minWidth: DS.Layout.workspaceMinWidth, minHeight: DS.Layout.workspaceMinHeight)
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
                .environment(\.settingsStore, services.settings)
        }

        MenuBarExtra {
            if let recorder = services.recorder {
                MenuBarRecorderView(model: recorder)
            } else {
                Text(services.startupError ?? Strings.current.menuUnavailable)
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
