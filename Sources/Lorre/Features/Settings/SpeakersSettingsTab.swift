import SwiftUI

struct SpeakersSettingsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Known Speakers") {
                if viewModel.knownSpeakers.isEmpty {
                    Text("No speakers enrolled yet. To enroll a speaker, type a name below and click Add Sample to import a clean single-voice clip. Lorre extracts an embedding locally and uses it for offline relabeling and live speaker hints.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(viewModel.knownSpeakers) { speaker in
                        speakerRow(for: speaker)
                    }
                }
            }

            Section {
                HStack(spacing: DS.Space.x2) {
                    TextField("Speaker name", text: $viewModel.knownSpeakerDraftName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add Sample") {
                        viewModel.importKnownSpeaker()
                    }
                    .disabled(viewModel.isKnownSpeakerOperationInFlight || viewModel.knownSpeakerDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let operation = viewModel.knownSpeakerOperationDescription {
                    Text(operation)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text(viewModel.knownSpeakerLibraryStatusLine)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Enroll New Speaker")
            } footer: {
                Text("Import a clean clip from a single voice. The clip is stored locally; Lorre extracts a speaker embedding used for offline relabeling and live speaker hints.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Speakers")
    }

    @ViewBuilder
    private func speakerRow(for speaker: KnownSpeaker) -> some View {
        HStack(alignment: .top, spacing: DS.Space.x2) {
            SpeakerBadgeView(speakerID: speaker.id, variant: speaker.styleVariant)

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.safeDisplayName)
                    .font(.body.weight(.semibold))

                if let clip = speaker.referenceClip {
                    Text("\(clip.sourceFileName) • \(Formatters.duration(clip.durationSeconds)) • \(clip.sampleRate) Hz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(speaker.enrollmentCount) enrollment\(speaker.enrollmentCount == 1 ? "" : "s") • updated \(speaker.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: DS.Space.x2)

            HStack(spacing: DS.Space.x2) {
                Button("Re-enroll") {
                    viewModel.reenrollKnownSpeaker(speaker.id)
                }
                .disabled(viewModel.isKnownSpeakerOperationInFlight)

                Button("Remove", role: .destructive) {
                    viewModel.deleteKnownSpeaker(speaker.id)
                }
                .disabled(viewModel.isKnownSpeakerOperationInFlight)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, DS.Space.x1)
    }
}
