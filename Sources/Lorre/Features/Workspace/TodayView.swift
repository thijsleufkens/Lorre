import LorreCore
import SwiftUI

/// "What needs me?": conversations waiting for review, and the ones still being worked on.
struct TodayView: View {
    let workspace: WorkspaceModel
    let recorder: RecorderModel?

    /// Conversations the user asked to retry, until the recorder's own list can tell their status.
    @State private var requested: Set<UUID> = []

    private let strings = Strings.current

    /// Whether a conversation is waiting in the queue or being written out right now.
    private func isQueuedOrRunning(_ id: UUID) -> Bool {
        if let status = recorder?.rows.first(where: { $0.id == id })?.status {
            return status == .waiting || status == .processing
        }
        return requested.contains(id)
    }

    /// Forgets requests that the recorder's list now answers, or that no longer apply.
    private func pruneRequests() {
        let known = Set(recorder?.rows.map(\.id) ?? [])
        let stillBusy = Set(workspace.inProgress.map(\.conversation.id))
        requested = requested.filter { stillBusy.contains($0) && !known.contains($0) }
    }

    var body: some View {
        if workspace.toReview.isEmpty && workspace.inProgress.isEmpty && !showsComingUp {
            emptyState
        } else {
            list
        }
    }

    /// Whether the "Coming up" section has anything to show: meetings, or the quiet offer.
    private var showsComingUp: Bool {
        switch workspace.comingUp.calendarAccess {
        case .notAsked: true
        case .granted: !workspace.comingUp.comingUp.isEmpty
        case .denied: false
        }
    }

    @ViewBuilder
    private var comingUpSection: some View {
        let model = workspace.comingUp
        if model.calendarAccess == .notAsked {
            section(strings.comingUpHeader) {
                HStack(spacing: DS.Space.x4) {
                    Text(strings.calendarPrompt)
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.x4)
                    Button(strings.calendarAllow) { Task { await model.allowCalendar() } }
                        .buttonStyle(SecondaryControlButtonStyle())
                        .help(strings.calendarAllowHelp)
                }
                .padding(DS.Space.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPanelSurface(alt: true)
            }
        } else if model.calendarAccess == .granted, !model.comingUp.isEmpty {
            section(strings.comingUpHeader) {
                ForEach(model.comingUp) { item in
                    ComingUpRow(item: item) { workspace.showPerson($0) }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.x6) {
                    comingUpSection
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
                                let id = summary.conversation.id
                                InProgressRow(
                                    summary: summary,
                                    isQueuedOrRunning: isQueuedOrRunning(id),
                                    onRetry: recorder.map { recorder in
                                        {
                                            requested.insert(id)
                                            Task { await recorder.process(id) }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: DS.Layout.contentMaxWidth, alignment: .leading)
                .padding(DS.Space.x6)
                .frame(maxWidth: .infinity)
        }
        .onChange(of: recorder?.rows) { pruneRequests() }
        .onChange(of: workspace.inProgress.map(\.conversation.state)) { pruneRequests() }
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
    /// Waiting in the queue or being written out right now.
    let isQueuedOrRunning: Bool
    /// Asks for processing again; nil when recording is unavailable.
    let onRetry: (() -> Void)?

    private let strings = Strings.current

    var body: some View {
        let conversation = summary.conversation
        VStack(alignment: .leading, spacing: DS.Space.x1_5) {
            HStack(spacing: DS.Space.x3) {
                Text(conversation.title.isEmpty ? strings.untitledConversation : conversation.title)
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Spacer()
                Text(ViewFormat.progressLabel(conversation, isQueuedOrRunning: isQueuedOrRunning, strings))
                    .font(DS.FontStyle.control)
                    .foregroundStyle(isProblem ? DS.ColorToken.statusError : DS.ColorToken.fgSecondary)
            }
            Text(ViewFormat.dayAndTime(conversation.startedAt, strings))
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgTertiary)
            if isProblem, let explanation {
                Text(explanation)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isProblem, ViewFormat.isRetryable(conversation), let onRetry {
                Button(strings.retry, action: onRetry)
                    .buttonStyle(SecondaryControlButtonStyle())
                    .help(strings.retryHelp)
                    .padding(.top, DS.Space.x1_5)
            }
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(alt: true)
    }

    /// Something went wrong and nothing is working on it right now.
    private var isProblem: Bool {
        let conversation = summary.conversation
        guard !isQueuedOrRunning else { return false }
        return conversation.state == .interrupted || conversation.lastError != nil
    }

    private var explanation: String? {
        let conversation = summary.conversation
        return ViewFormat.friendlyError(conversation.lastError, strings: strings)
            ?? (conversation.state == .interrupted ? strings.errorInterrupted : nil)
    }
}

/// One meeting that is coming up: when, what, with whom, and what is still open with them.
private struct ComingUpRow: View {
    let item: ComingUpItem
    let onShowPerson: (UUID) -> Void

    private let strings = Strings.current

    var body: some View {
        let meeting = item.meeting
        VStack(alignment: .leading, spacing: DS.Space.x1_5) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.x3) {
                Text(ViewFormat.dayAndTime(meeting.start, strings))
                    .font(DS.FontStyle.control)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                Text(meeting.title.isEmpty ? strings.untitledConversation : meeting.title)
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
            }
            if !meeting.attendeeNames.isEmpty {
                Text(meeting.attendeeNames.joined(separator: ", "))
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            if let match = item.mostOpen, let personId = match.personId {
                Button(strings.openItemsWith(match.openCount, match.name)) { onShowPerson(personId) }
                    .buttonStyle(.plain)
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.accentPrimary)
            }
        }
        .padding(DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(alt: true)
    }
}
