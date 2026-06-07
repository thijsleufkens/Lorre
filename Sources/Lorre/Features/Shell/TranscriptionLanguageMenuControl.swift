import SwiftUI

/// Compact toolbar control for picking the batch transcription language hint,
/// sitting next to the source segmented control. Defaults to Automatic; a
/// concrete language is only needed when you want to force one.
struct TranscriptionLanguageMenuControl: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Picker("Language", selection: languageBinding) {
            ForEach(BatchTranscriptionLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .help("Transcription language — Automatic detects it for you")
        .disabled(!isEnabled)
    }

    private var languageBinding: Binding<BatchTranscriptionLanguage> {
        Binding(
            get: { viewModel.batchTranscriptionLanguage },
            set: { viewModel.setBatchTranscriptionLanguage($0) }
        )
    }

    private var isEnabled: Bool {
        viewModel.workStageRoute == .recorder
            && !viewModel.isStartingRecording
            && !viewModel.isRecording
            && !viewModel.isStoppingRecording
    }
}
