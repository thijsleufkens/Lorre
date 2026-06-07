import SwiftUI

struct SpeechModelsSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Speaker recognition") {
                Toggle("Label speakers in transcript", isOn: diarizationBinding)
                Text("Identifies different speakers and labels each line with who is talking.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Engine", selection: diarizationEngineBinding) {
                    ForEach(DiarizationEngine.allCases, id: \.self) { engine in
                        Text(engine.detailLabel).tag(engine)
                    }
                }
                Text(viewModel.diarizationEngine.settingsSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Expected speakers", selection: expectedSpeakersBinding) {
                    ForEach(DiarizationSpeakerCountHint.tuningPresets, id: \.self) { hint in
                        Text(hint.detailLabel).tag(hint)
                    }
                }
                Text("Hint for how many speakers to expect. Auto works well in most cases.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Transcript display") {
                Toggle("Show confidence scores", isOn: confidenceBinding)
                Text("Shows how sure Lorre is about each transcript line. Helpful when checking for mistakes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Vocabulary") {
                Toggle("Vocabulary boosting", isOn: vocabBoostingBinding)
                    .disabled(!viewModel.isVocabularyBoostingAvailable)
                Text(viewModel.vocabularyBoostingSupportSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Custom terms") {
                    Text("\(viewModel.customVocabularyTermLineCount) lines")
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $viewModel.customVocabularySimpleFormatTerms)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 120)
                HStack {
                    Button(viewModel.isVocabularyBoostingAvailable ? "Save Terms" : "Save Terms for Later") {
                        viewModel.saveCustomVocabularyTerms()
                    }
                    Text(
                        viewModel.isVocabularyBoostingAvailable
                            ? "One per line. Aliases format: Canonical: alias1, alias2"
                            : "You can still curate the list now. It stays stored until the vocabulary path is wired back in."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Model registry") {
                modelRegistryRows
            }

            Section("Advanced") {
                Toggle("Diarization debug export", isOn: diarizationDebugBinding)
                Text("Saves an extra debug file in each session folder. Usually not needed unless you are troubleshooting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speech & Models")
    }

    // MARK: - Bindings

    private var diarizationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isSpeakerDiarizationEnabled },
            set: { viewModel.setSpeakerDiarizationEnabled($0) }
        )
    }

    private var diarizationEngineBinding: Binding<DiarizationEngine> {
        Binding(
            get: { viewModel.diarizationEngine },
            set: { viewModel.setDiarizationEngine($0) }
        )
    }

    private var expectedSpeakersBinding: Binding<DiarizationSpeakerCountHint> {
        Binding(
            get: { viewModel.diarizationExpectedSpeakerCountHint.normalized() },
            set: { viewModel.setDiarizationExpectedSpeakerCountHint($0) }
        )
    }

    private var confidenceBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isTranscriptConfidenceVisible },
            set: { viewModel.setTranscriptConfidenceVisible($0) }
        )
    }

    private var vocabBoostingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isVocabularyBoostingAvailable && viewModel.isVocabularyBoostingEnabled },
            set: { viewModel.setVocabularyBoostingEnabled($0) }
        )
    }

    private var diarizationDebugBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDiarizationDebugExportEnabled },
            set: { viewModel.setDiarizationDebugExportEnabled($0) }
        )
    }

    // MARK: - Model registry

    @ViewBuilder
    private var modelRegistryRows: some View {
        LabeledContent("Registry") {
            Text(viewModel.modelRegistrySummaryLabel)
                .foregroundStyle(.secondary)
        }

        TextField("https://huggingface.co", text: $viewModel.modelRegistryCustomBaseURL)

        HStack {
            Button("Save Registry") {
                viewModel.saveModelRegistryConfiguration()
            }
            Button("Use Default") {
                viewModel.resetModelRegistryConfiguration()
            }
            .disabled(!viewModel.isCustomModelRegistryConfigured)
        }

        Text("Set a mirror or private registry base URL before downloading models. Leave blank to use the default Hugging Face registry.")
            .font(.callout)
            .foregroundStyle(.secondary)

        LabeledContent("Status") {
            Text(viewModel.modelPreparationStatusLine)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Processing") {
            Text(viewModel.runtimeCapabilities.processingModeDescription)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Capabilities") {
            Text(modelCapabilitiesText)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Technical") {
            Text(viewModel.modelPreparationDetailLine)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }

        if !viewModel.fluidAudioStatus.isEmpty {
            LabeledContent("FluidAudio") {
                Text(viewModel.fluidAudioStatus)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        Button(buttonLabel) {
            viewModel.prepareModelsTapped()
        }
        .disabled(viewModel.modelPreparationState == .preparing)
    }

    // MARK: - Helpers

    private var modelCapabilitiesText: String {
        let labels = viewModel.runtimeCapabilities.featureLabels
        return labels.isEmpty ? "Speech transcription" : labels.joined(separator: " • ")
    }

    private var buttonLabel: String {
        switch viewModel.modelPreparationState {
        case .ready:
            return "Re-prepare Models"
        case .preparing:
            return "Preparing…"
        default:
            return "Prepare Models"
        }
    }
}
