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
        }
        .formStyle(.grouped)
        .navigationTitle("General")
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
