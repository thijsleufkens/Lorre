import SwiftUI

struct SourceModeSegmentedControl: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Picker("Source", selection: sourceBinding) {
            Text("Mic").tag(RecordingSource.microphone)
            Text("Mic + System").tag(RecordingSource.microphoneAndSystemAudio)
            Text("System").tag(RecordingSource.systemAudio)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 280)
        .disabled(!isPickerEnabled)
    }

    private var sourceBinding: Binding<RecordingSource> {
        Binding(
            get: { viewModel.selectedRecordingSource },
            set: { viewModel.setRecordingSource($0) }
        )
    }

    private var isPickerEnabled: Bool {
        viewModel.workStageRoute == .recorder
            && !viewModel.isStartingRecording
            && !viewModel.isRecording
            && !viewModel.isStoppingRecording
    }
}
