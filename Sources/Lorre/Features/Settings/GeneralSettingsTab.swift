import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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

            Section("Automatic export") {
                Toggle("Save a Markdown copy when a transcript is ready", isOn: autoExportBinding)
                    .disabled(!viewModel.automaticMarkdownExport.hasFolder)
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(viewModel.automaticMarkdownExport.folderDisplayName)
                        .foregroundStyle(.secondary)
                    Button("Choose…") { chooseAutoExportFolder() }
                }
                TextField("Filename template", text: fileNameTemplateBinding)
                Text("Tokens: {date}, {time}, {datetime}, {smart_title}, {keywords}, {duration}, {speaker_count}. Preview: \(viewModel.automaticMarkdownExportFileNamePreview)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private var autoExportBinding: Binding<Bool> {
        Binding(
            get: { viewModel.automaticMarkdownExport.isEnabled },
            set: { viewModel.setAutomaticMarkdownExportEnabled($0) }
        )
    }

    private var fileNameTemplateBinding: Binding<String> {
        Binding(
            get: { viewModel.automaticMarkdownExport.fileNameTemplate },
            set: { viewModel.setAutomaticMarkdownExportFileNameTemplate($0) }
        )
    }

    private func chooseAutoExportFolder() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setAutomaticMarkdownExportFolderPath(url.path(percentEncoded: false))
        }
        #endif
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
