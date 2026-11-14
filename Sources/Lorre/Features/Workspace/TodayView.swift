import LorreCore
import SwiftUI

/// "What needs me?": conversations waiting for review, and the ones still being worked on.
struct TodayView: View {
    let workspace: WorkspaceModel
    let recorder: RecorderModel?

    private let strings = Strings.current

    var body: some View {
        if workspace.toReview.isEmpty && workspace.inProgress.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.x6) {
                    if !workspace.toReview.isEmpty {
                        section(strings.toReviewHeader) {
                            ForEach(workspace.toReview, id: \.conversation.id) { summary in
                                ReviewCard(summary: summary) { workspace.open(summary.conversation.id) }
                            }
                        }
                    }
                    if !workspace.inProgress.isEmpty {
                        section(strings.inProgressHeader) {
                            ForEach(workspace.inProgress, id: \.conversation.id) { summary in
                                InProgressRow(summary: summary)
                            }
                        }
                    }
                }
                .frame(maxWidth: DS.Layout.contentMaxWidth, alignment: .leading)
                .padding(DS.Space.x6)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.x4) {
            Text(strings.todayEmpty)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .multilineTextAlignment(.center)
            RecordControl(recorder: recorder)
        }
        .padding(DS.Space.x8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            Text(title.uppercased())
                .font(DS.FontStyle.kicker)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// One conversation that waits for review. The whole card opens it.
private struct ReviewCard: View {
    let summary: ConversationSummary
    let onOpen: () -> Void

    private let strings = Strings.current

    var body: some View {
        let conversation = summary.conversation
        HStack(alignment: .top, spacing: DS.Space.x4) {
            VStack(alignment: .leading, spacing: DS.Space.x1_5) {
                Text(conversation.title.isEmpty ? strings.untitledConversation : conversation.title)
                    .font(DS.FontStyle.cardTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Text(details)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                if !summary.participantNames.isEmpty {
                    Text(summary.participantNames.joined(separator: ", "))
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                }
                if summary.proposedOutcomes > 0 {
                    Text(strings.proposedOutcomesLine(summary.proposedOutcomes))
                        .font(DS.FontStyle.bodyStrong)
                        .foregroundStyle(DS.ColorToken.accentPrimary)
                }
            }
            Spacer(minLength: DS.Space.x4)
            Button(strings.reviewButton, action: onOpen)
                .buttonStyle(PrimaryControlButtonStyle())
                .help(strings.reviewButtonHelp)
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var details: String {
        let conversation = summary.conversation
        let parts = [
            ViewFormat.dayAndTime(conversation.startedAt, strings),
            ViewFormat.duration(conversation.durationSeconds, strings),
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// A conversation that is being recorded or transcribed, or that went wrong.
private struct InProgressRow: View {
    let summary: ConversationSummary

    private let strings = Strings.current

    var body: some View {
        let conversation = summary.conversation
        VStack(alignment: .leading, spacing: DS.Space.x1_5) {
            HStack(spacing: DS.Space.x3) {
                Text(conversation.title.isEmpty ? strings.untitledConversation : conversation.title)
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Spacer()
                Text(ViewFormat.stateLabel(conversation, strings))
                    .font(DS.FontStyle.control)
                    .foregroundStyle(isProblem ? DS.ColorToken.statusError : DS.ColorToken.fgSecondary)
            }
            Text(ViewFormat.dayAndTime(conversation.startedAt, strings))
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgTertiary)
            if isProblem, let error = conversation.lastError {
                Text(error)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(alt: true)
    }

    private var isProblem: Bool {
        let conversation = summary.conversation
        return conversation.state == .interrupted || conversation.lastError != nil
    }
}
