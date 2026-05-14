import SwiftUI

struct RecorderConsoleView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingCancelRecordingConfirmation = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: DS.Space.x4) {
                if viewModel.isRecording || viewModel.isStoppingRecording {
                    recordingConsole
                } else {
                    setupConsole
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 940, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Cancel this recording?",
            isPresented: $isShowingCancelRecordingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete In-Progress Session", role: .destructive) {
                viewModel.cancelRecordingTapped()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("This will stop recording immediately. The in-progress session and audio will be deleted.")
        }
    }

    private var recordingConsole: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            // Pattern B — live indicator + hero timer panel
            VStack(alignment: .leading, spacing: DS.Space.x2) {
                HStack(spacing: DS.Space.x2) {
                    Circle()
                        .fill(DS.ColorToken.accentLive)
                        .frame(width: 12, height: 12)
                        .shadow(color: DS.ColorToken.accentLive.opacity(0.35), radius: 4, x: 0, y: 0)
                    Text(viewModel.isStoppingRecording ? "STOPPING" : "RECORDING")
                        .font(DS.FontStyle.kicker)
                        .tracking(1.5)
                        .foregroundStyle(DS.ColorToken.accentLive)
                    Spacer()
                    Button("Stop Recording") {
                        viewModel.stopRecordingTapped()
                    }
                    .buttonStyle(PrimaryControlButtonStyle())
                    .disabled(viewModel.isStoppingRecording)

                    Button("Cancel Recording") {
                        isShowingCancelRecordingConfirmation = true
                    }
                    .buttonStyle(SecondaryControlButtonStyle())
                    .disabled(viewModel.isStoppingRecording)
                }
                Text(Formatters.duration(viewModel.recordingElapsedSeconds))
                    .font(DS.FontStyle.timer)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .monospacedDigit()
            }
            .padding(DS.Space.x4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.ColorToken.bgPanelAlt)
            )
            .dsPanelShadow()

            // Pattern A — kicker + source label
            VStack(alignment: .leading, spacing: 4) {
                Text("— Recorder")
                    .font(DS.FontStyle.sectionLabel)
                    .foregroundStyle(DS.ColorToken.serifInk)
                Text("Recording \(viewModel.selectedRecordingSource.label)")
                    .font(DS.FontStyle.panelTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Text("Audio capture is stored locally. Stop to create a session and begin transcript processing.")
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }

            if viewModel.isDeleteAudioAfterTranscriptionEnabled {
                Text("Privacy mode is on. After the transcript is saved, Lorre will delete the source audio and keep the transcript and exports.")
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }

            IndexRailView(mode: .live(viewModel.liveMeterSamples), height: 24)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.x2)

            if viewModel.isLiveTranscriptionSupported && viewModel.isLiveTranscriptionEnabled {
                LiveTranscriptPreviewCard(viewModel: viewModel)
            }
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsPanelSurface(cornerRadius: DS.Radius.lg)
    }

    private var setupConsole: some View {
        RecorderSetupView(viewModel: viewModel)
    }
}

private struct RecorderSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("— Recorder")
                    .font(DS.FontStyle.sectionLabel)
                    .foregroundStyle(DS.ColorToken.serifInk)
                Text(heroTitle)
                    .font(DS.FontStyle.panelTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
            }

            Button {
                viewModel.startRecordingTapped()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(DS.ColorToken.accentLive)
                        .frame(width: 10, height: 10)
                    Text("Start recording")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.ColorToken.accentPrimary)
            .controlSize(.large)
            .disabled(!canStart)

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceLine)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                HStack(spacing: 4) {
                    Text(preferencesLine)
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.x6)
    }

    private var heroTitle: String {
        "New recording"
    }

    private var canStart: Bool {
        !viewModel.isStartingRecording && !viewModel.isRecording && !viewModel.isStoppingRecording
    }

    private var sourceLine: String {
        switch viewModel.selectedRecordingSource {
        case .microphone: return "Microphone · 48 kHz"
        case .microphoneAndSystemAudio: return "Microphone + system audio · 48 kHz"
        case .systemAudio: return "System audio · 48 kHz"
        }
    }

    private var preferencesLine: String {
        let live = viewModel.isLiveTranscriptionEnabled ? "Live preview on" : "Live preview off"
        let retention = viewModel.isDeleteAudioAfterTranscriptionEnabled ? "Delete after transcript" : "Keep audio"
        return "\(live) · \(retention)"
    }
}

private struct LiveTranscriptPreviewCard: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            HStack(spacing: DS.Space.x2) {
                CapsLabel(text: "Live Preview")
                if let preview = viewModel.liveTranscriptPreview, preview.isFinalizing {
                    Text("FINALIZING")
                        .font(DS.FontStyle.control)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                } else {
                    Text("BETA")
                        .font(DS.FontStyle.control)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                }
            }

            if let preview = viewModel.liveTranscriptPreview, let error = preview.errorMessage {
                Text(error)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let preview = viewModel.liveTranscriptPreview, preview.hasContent || preview.hasSpeakerHint {
                if preview.hasSpeakerHint {
                    HStack(spacing: DS.Space.x2) {
                        Image(systemName: "person.wave.2")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                        Text(preview.activeSpeakerDisplayName ?? "Known speaker")
                            .font(DS.FontStyle.bodyStrong)
                            .foregroundStyle(DS.ColorToken.fgPrimary)
                        if let confidence = preview.activeSpeakerConfidence {
                            Text("\(Int((confidence * 100).rounded()))%")
                                .font(DS.FontStyle.mono)
                                .foregroundStyle(DS.ColorToken.fgTertiary)
                        }
                    }
                }

                if !preview.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(preview.confirmedText)
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !preview.partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(preview.partialText)
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Listening for speech… partial transcript will appear here while recording.")
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Live preview is English-only. Final post-pass (Parakeet v3) usually performs better for Dutch + English.")
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(alt: true, cornerRadius: DS.Radius.md)
    }
}


struct ProcessingPipelineView: View {
    @ObservedObject var viewModel: AppViewModel
    let session: SessionManifest

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            StageHeaderCard(
                title: session.displayTitle,
                statusLine: session.processing.progressLabel ?? "Processing",
                rail: .progress(session.processing.progressFraction ?? 0.1),
                trailingActions: {
                    HStack(spacing: DS.Space.x2) {
                        Button("Export") {}
                            .buttonStyle(PrimaryControlButtonStyle())
                            .disabled(true)
                        Button("Reveal Files") {}
                            .buttonStyle(SecondaryControlButtonStyle())
                            .disabled(true)
                    }
                }
            )

            VStack(alignment: .leading, spacing: DS.Space.x3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("— Processing")
                        .font(DS.FontStyle.sectionLabel)
                        .foregroundStyle(DS.ColorToken.serifInk)
                    Text(session.processing.progressPhase?.label ?? "Processing")
                        .font(DS.FontStyle.panelTitle)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                    Text(session.processing.progressLabel ?? "Working on transcript…")
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                }

                IndexRailView(mode: .progress(session.processing.progressFraction ?? 0.1), height: 10)
                    .frame(maxWidth: .infinity)

                HStack(spacing: DS.Space.x4) {
                    pipelineMetadata(label: "STATUS", value: session.status.label)
                    pipelineMetadata(label: "PHASE", value: session.processing.progressPhase?.rawValue.uppercased() ?? "WAITING")
                    pipelineMetadata(label: "FLUIDAUDIO", value: "SEAM READY")
                }

                Text("Processing stays in the main work stage so the user keeps context while the transcript is prepared.")
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            .padding(DS.Space.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPanelSurface(cornerRadius: DS.Radius.lg)

            SpeakerRecognitionQuickAccessView(
                viewModel: viewModel,
                scopeNote: "This changes future processing runs. The current session keeps the settings it started with."
            )

            if let transcript = viewModel.activeTranscript, transcript.sessionId == session.id {
                VStack(alignment: .leading, spacing: DS.Space.x2) {
                    HStack(spacing: DS.Space.x2) {
                        CapsLabel(text: "Transcript Preview")
                        Text("Draft transcript while diarization runs (showing first \(min(4, transcript.segments.count)) segments)")
                            .font(DS.FontStyle.helper)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }

                    ForEach(Array(transcript.segments.prefix(4))) { segment in
                        HStack(alignment: .top, spacing: DS.Space.x2) {
                            Text(Formatters.timestamp(ms: segment.startMs))
                                .font(DS.FontStyle.mono)
                                .foregroundStyle(DS.ColorToken.fgSecondary)
                                .frame(width: 54, alignment: .leading)
                            Text(segment.text)
                                .font(DS.FontStyle.body)
                                .foregroundStyle(DS.ColorToken.fgPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                        }
                        .padding(.vertical, DS.Space.x1)
                    }
                }
                .padding(DS.Space.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPanelSurface(cornerRadius: DS.Radius.lg)
            }

            Spacer(minLength: 0)
        }
    }

    private func pipelineMetadata(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.x1) {
            CapsLabel(text: label)
            Text(value)
                .font(DS.FontStyle.mono)
                .foregroundStyle(DS.ColorToken.fgPrimary)
        }
    }
}

struct StageHeaderCard<TrailingActions: View>: View {
    let title: String
    let statusLine: String
    let rail: IndexRailMode
    @ViewBuilder var trailingActions: () -> TrailingActions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.x4) {
            VStack(alignment: .leading, spacing: DS.Space.x2) {
                Text(title)
                    .font(DS.FontStyle.appTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .lineLimit(2)

                Text(statusLine)
                    .font(DS.FontStyle.stageStatus)
                    .foregroundStyle(DS.ColorToken.fgSecondary)

                IndexRailView(mode: rail, height: railHeight)
                    .frame(width: 220)
            }

            Spacer()

            trailingActions()
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(cornerRadius: DS.Radius.lg)
    }

    private var railHeight: CGFloat {
        switch rail {
        case .live:
            return 10
        default:
            return 8
        }
    }
}
