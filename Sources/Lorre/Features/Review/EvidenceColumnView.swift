import AppKit
import LorreCore
import SwiftUI

/// The right column: where the selected outcome came from, and the whole conversation to pick from.
struct EvidenceColumnView: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding

    private let strings = Strings.current

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.x4) {
                    evidence
                    Divider()
                    transcript
                }
                .padding(DS.Space.x4)
            }
            .onChange(of: review.selectedOutcomeID) { scrollToEvidence(proxy) }
            .onChange(of: draft.transcriptExpanded) { scrollToEvidence(proxy) }
        }
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !review.selectedSegmentIDs.isEmpty {
                SelectionBar(review: review, draft: draft, focus: focus)
            }
        }
    }

    private func scrollToEvidence(_ proxy: ScrollViewProxy) {
        guard draft.transcriptExpanded, let first = review.selectedOutcome?.evidenceSegmentIds.first else { return }
        withAnimation { proxy.scrollTo(TranscriptRow.scrollID(first), anchor: .center) }
    }

    // MARK: Evidence

    private var evidence: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            HStack {
                Text(strings.evidenceHeader.uppercased())
                    .font(DS.FontStyle.kicker)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                playButton
            }
            if let outcome = review.selectedOutcome {
                if review.evidenceSegments.isEmpty {
                    Text(strings.evidenceNone)
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                } else {
                    ForEach(review.evidenceSegments) { segment in
                        EvidenceLine(
                            review: review,
                            segment: segment,
                            isEvidence: outcome.evidenceSegmentIds.contains(segment.id)
                        )
                    }
                }
            } else {
                Text(strings.evidenceSelectOne)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
        }
    }

    @ViewBuilder private var playButton: some View {
        if let start = review.selectedOutcome?.evidenceStartMs {
            Button {
                if review.isPlaying { review.stopPlayback() } else { review.playEvidence() }
            } label: {
                HStack(spacing: DS.Space.x1_5) {
                    Image(systemName: review.isPlaying ? "stop.fill" : "play.fill")
                    Text(ViewFormat.clock(milliseconds: start))
                        .font(DS.FontStyle.monoStrong)
                }
                .font(DS.FontStyle.control)
            }
            .buttonStyle(.borderless)
            .disabled(!review.canPlay)
            .accessibilityLabel(review.isPlaying ? strings.stopPlaying : strings.playEvidence)
            .help(review.canPlay
                  ? (review.isPlaying ? strings.stopPlaying : strings.playFrom(ViewFormat.clock(milliseconds: start)))
                  : strings.noAudio)
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        DisclosureGroup(isExpanded: Bindable(draft).transcriptExpanded) {
            if review.segments.isEmpty {
                Text(strings.transcriptEmpty)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            } else {
                LazyVStack(alignment: .leading, spacing: DS.Space.x1) {
                    ForEach(review.segments) { segment in
                        TranscriptRow(review: review, draft: draft, focus: focus, segment: segment)
                    }
                }
                .padding(.top, DS.Space.x2)
            }
        } label: {
            Text(strings.fullTranscript)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
        }
    }
}

/// One line of the evidence: the speaker and the words, bold when it is the evidence itself.
private struct EvidenceLine: View {
    let review: ReviewModel
    let segment: Segment
    let isEvidence: Bool

    private let strings = Strings.current

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.x3) {
            Text(speaker)
                .font(DS.FontStyle.control)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .frame(width: DS.Layout.speakerColumn, alignment: .leading)
            Text(segment.text)
                .font(isEvidence ? DS.FontStyle.outcomeTextStrong : DS.FontStyle.outcomeText)
                .foregroundStyle(isEvidence ? DS.ColorToken.fgPrimary : DS.ColorToken.fgSecondary)
                .padding(.horizontal, DS.Space.x1_5)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(isEvidence ? DS.ColorToken.evidenceFill : Color.clear)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var speaker: String {
        segment.participantId == nil ? strings.unknownSpeaker : review.name(of: segment.participantId)
    }
}

/// One segment of the full transcript: time, speaker menu, text, and a play button. Clicking selects it.
private struct TranscriptRow: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding
    let segment: Segment

    private let strings = Strings.current

    static func scrollID(_ id: UUID) -> String { "transcript-\(id.uuidString)" }

    private var isSelected: Bool { review.selectedSegmentIDs.contains(segment.id) }
    private var isEvidence: Bool { review.selectedOutcome?.evidenceSegmentIds.contains(segment.id) == true }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.x2) {
            Text(ViewFormat.clock(milliseconds: segment.startMs))
                .font(DS.FontStyle.mono)
                .foregroundStyle(DS.ColorToken.fgTertiary)
                .frame(width: DS.Layout.timeColumn, alignment: .leading)
            speakerMenu
            Text(segment.text)
                .font(DS.FontStyle.body)
                .foregroundStyle(DS.ColorToken.fgPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { review.play(segmentID: segment.id) } label: {
                Image(systemName: "play.circle").font(DS.FontStyle.icon)
            }
            .buttonStyle(.borderless)
            .disabled(!review.canPlay)
            .accessibilityLabel(strings.playFragment)
            .help(review.canPlay ? strings.playFragment : strings.noAudio)
        }
        .padding(.horizontal, DS.Space.x2)
        .padding(.vertical, DS.Space.x1)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isSelected ? DS.ColorToken.selectionFill : (isEvidence ? DS.ColorToken.evidenceFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { click() }
        .id(Self.scrollID(segment.id))
    }

    private var speakerMenu: some View {
        Menu {
            ForEach(review.participants) { participant in
                Button(participant.name) { review.assign(segmentID: segment.id, to: participant.id) }
            }
            Divider()
            Button(strings.unknownSpeaker) { review.assign(segmentID: segment.id, to: nil) }
        } label: {
            Text(segment.participantId == nil ? strings.unknownSpeaker : review.name(of: segment.participantId))
                .font(DS.FontStyle.control)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: DS.Layout.speakerColumn, alignment: .leading)
        .help(strings.speakerMenuHelp)
    }

    private func click() {
        let extend = NSEvent.modifierFlags.contains(.shift)
        review.selectedSegmentIDs = ViewFormat.selection(
            after: segment.id,
            order: review.segments.map(\.id),
            anchor: draft.anchorSegmentID,
            current: review.selectedSegmentIDs,
            extend: extend
        )
        draft.anchorSegmentID = segment.id
        focus.wrappedValue = .list
    }
}

/// Shown while part of the transcript is selected: turn it into an outcome.
private struct SelectionBar: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding

    private let strings = Strings.current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            HStack(spacing: DS.Space.x3) {
                Text(strings.selectedFragments(review.selectedSegmentIDs.count))
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Spacer()
                Menu(strings.selectionPrompt) {
                    ForEach(OutcomeKind.displayOrder, id: \.self) { kind in
                        Button(kind.title(strings.language, plural: false)) {
                            draft.startPending(kind: kind, from: review)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button(strings.clearSelection) {
                    review.selectedSegmentIDs = []
                    draft.cancelPending()
                }
                .buttonStyle(.borderless)
                .font(DS.FontStyle.control)
            }
            if let kind = draft.pendingKind {
                HStack(spacing: DS.Space.x2) {
                    Text(kind.title(strings.language, plural: false))
                        .font(DS.FontStyle.control)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                    TextField(strings.addPlaceholder, text: Bindable(draft).pendingText)
                        .textFieldStyle(.roundedBorder)
                        .focused(focus, equals: .pending)
                        .onSubmit { draft.confirmPending(in: review) }
                        .onExitCommand { draft.cancelPending() }
                    Button(strings.addConfirm) { draft.confirmPending(in: review) }
                        .buttonStyle(PrimaryControlButtonStyle())
                    Button(strings.cancel) { draft.cancelPending() }
                        .buttonStyle(SecondaryControlButtonStyle())
                }
            }
        }
        .padding(DS.Space.x4)
        .background(DS.ColorToken.bgPanel)
        .overlay(alignment: .top) { Divider() }
    }
}
