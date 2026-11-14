import SwiftUI

/// The main window: a top bar with the two sections and the record control, and the open section
/// or the review of one conversation underneath.
struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceModel
    let recorder: RecorderModel?

    @State private var onboarding: OnboardingModel?

    private let strings = Strings.current

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let message = ViewFormat.friendlyError(recorder?.message, strings: strings) {
                MessageBar(text: message) { recorder?.message = nil }
            }
            if let error = ViewFormat.friendlyError(workspace.errorMessage, strings: strings) {
                MessageBar(text: error, onDismiss: nil)
            }
            content
        }
        .background(DS.ColorToken.bgApp)
        .sheet(isPresented: Binding(
            get: { onboarding != nil },
            set: { if !$0 { onboarding = nil } }
        )) {
            if let onboarding {
                OnboardingView(model: onboarding)
                    .onChange(of: onboarding.isCompleted) { _, done in
                        if done { self.onboarding = nil }
                    }
            }
        }
        .task {
            if OnboardingModel.isNeeded(settings: workspace.settings) {
                onboarding = OnboardingModel(settings: workspace.settings)
            }
        }
        .task { workspace.refresh() }
        .task { await pollWhileBusy() }
        .onChange(of: recorder?.phase) { workspace.refresh() }
        .onChange(of: recorder?.rows) { workspace.refresh() }
        .onChange(of: workspace.section) {
            if workspace.review != nil { workspace.closeReview() }
        }
    }

    private var topBar: some View {
        HStack(spacing: DS.Space.x6) {
            Text("Lorre")
                .font(DS.FontStyle.wordmark)
                .foregroundStyle(DS.ColorToken.serifInk)
                .accessibilityAddTraits(.isHeader)
            Picker("", selection: $workspace.section) {
                Text(strings.sectionToday).tag(WorkspaceSection.today)
                Text(strings.sectionConversations).tag(WorkspaceSection.conversations)
                Text(strings.sectionPeople).tag(WorkspaceSection.people)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(strings.sectionPickerLabel)
            .frame(width: DS.Layout.sectionPickerWidth)
            Spacer()
            RecordControl(recorder: recorder)
        }
        .padding(.horizontal, DS.Space.x6)
        .padding(.vertical, DS.Space.x3)
    }

    @ViewBuilder private var content: some View {
        if let review = workspace.review {
            ReviewView(review: review) {
                // After finishing you go to what is next; otherwise back to where you came from.
                if review.isFinished { workspace.section = .today }
                workspace.closeReview()
            }
            .id(review.conversationID)
        } else {
            switch workspace.section {
            case .today: TodayView(workspace: workspace, recorder: recorder)
            case .conversations: ConversationsView(workspace: workspace)
            case .people: PeopleView(workspace: workspace)
            }
        }
    }

    /// Keeps the lists current while anything is recording or being transcribed.
    private func pollWhileBusy() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            if !workspace.inProgress.isEmpty || recorder?.isBusy == true {
                workspace.refresh()
            }
        }
    }
}

/// A one-line notice under the top bar, dismissible when a dismiss action is given.
private struct MessageBar: View {
    let text: String
    let onDismiss: (() -> Void)?

    private let strings = Strings.current

    var body: some View {
        HStack(spacing: DS.Space.x3) {
            Text(text)
                .font(DS.FontStyle.body)
                .foregroundStyle(DS.ColorToken.fgPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(strings.dismiss, action: onDismiss)
                    .buttonStyle(.borderless)
                    .font(DS.FontStyle.control)
                    .help(strings.dismissHelp)
            }
        }
        .padding(.horizontal, DS.Space.x6)
        .padding(.vertical, DS.Space.x2_5)
        .background(DS.ColorToken.selectionFill)
    }
}

/// "● Opnemen" when idle; the elapsed time and "Stop" while recording.
struct RecordControl: View {
    let recorder: RecorderModel?

    private let strings = Strings.current

    var body: some View {
        if let recorder {
            switch recorder.phase {
            case .idle:
                startButton(recorder, enabled: true, title: strings.record)
            case .starting:
                startButton(recorder, enabled: false, title: strings.starting)
            case let .recording(since):
                HStack(spacing: DS.Space.x3) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(ViewFormat.clock(seconds: Int(context.date.timeIntervalSince(since))))
                            .font(DS.FontStyle.timerCompact)
                            .foregroundStyle(DS.ColorToken.accentLive)
                    }
                    Button(strings.stop) { Task { await recorder.stop() } }
                        .buttonStyle(PrimaryControlButtonStyle())
                        .help(strings.stopHelp)
                }
            case .stopping:
                Button(strings.stopping) {}
                    .buttonStyle(SecondaryControlButtonStyle())
                    .disabled(true)
            }
        } else {
            startButton(nil, enabled: false, title: strings.record)
                .help(strings.recorderUnavailable)
        }
    }

    private func startButton(_ recorder: RecorderModel?, enabled: Bool, title: String) -> some View {
        Button {
            guard let recorder else { return }
            Task { await recorder.start() }
        } label: {
            HStack(spacing: DS.Space.x2) {
                Circle()
                    .fill(enabled ? DS.ColorToken.accentLive : DS.ColorToken.fgTertiary)
                    .frame(width: DS.Layout.recordDot, height: DS.Layout.recordDot)
                    .accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(SecondaryControlButtonStyle())
        .disabled(!enabled)
        .help(strings.recordHelp)
    }
}
