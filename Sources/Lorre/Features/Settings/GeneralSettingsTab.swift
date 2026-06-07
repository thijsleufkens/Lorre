import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Audio") {
                Picker("Source audio after transcript", selection: retentionBinding) {
                    Text("Keep audio").tag(false)
                    Text("Delete after transcript").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Keep the audio file alongside the transcript, or auto-delete it once transcription completes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Live transcription") {
                Toggle("Show live preview while recording", isOn: liveTranscriptionBinding)
                Text("Streams partial transcript text as you speak. Uses a faster, lower-accuracy model.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Call watcher") {
                Toggle("Prompt to record when a call starts", isOn: callWatcherBinding)
                Text("Watches for calls in Teams, Zoom, Meet and similar apps, then sends a notification asking if you want to record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if viewModel.isCallWatcherEnabled {
                    Picker("Record with", selection: callWatcherSourceBinding) {
                        ForEach(RecordingSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    Text("Status: \(viewModel.callWatcherSummary)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var callWatcherBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isCallWatcherEnabled },
            set: { viewModel.setCallWatcherEnabled($0) }
        )
    }

    private var callWatcherSourceBinding: Binding<RecordingSource> {
        Binding(
            get: { viewModel.callWatcherConfiguration.defaultRecordingSource },
            set: { viewModel.setCallWatcherDefaultRecordingSource($0) }
        )
    }

    private var retentionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDeleteAudioAfterTranscriptionEnabled },
            set: { viewModel.setDeleteAudioAfterTranscriptionEnabled($0) }
        )
    }

    private var liveTranscriptionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLiveTranscriptionEnabled },
            set: { viewModel.setLiveTranscriptionEnabled($0) }
        )
    }
}
