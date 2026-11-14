import LorreCore
import SwiftUI

/// Back button, editable title, conversation type, the people in the conversation, date and length.
struct ReviewHeaderView: View {
    let review: ReviewModel
    let onBack: () -> Void
    var focus: FocusState<ReviewField?>.Binding

    @State private var titleDraft = ""
    @State private var renaming: Participant?
    @State private var renameText = ""

    private let strings = Strings.current

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.x4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(DS.FontStyle.icon)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(strings.back)
            .help(strings.backHelp)

            VStack(alignment: .leading, spacing: DS.Space.x2) {
                TextField(strings.untitledConversation, text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(DS.FontStyle.appTitle)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .focused(focus, equals: .title)
                    .onSubmit { commitTitle(); focus.wrappedValue = .list }
                    .onExitCommand { resetTitle(); focus.wrappedValue = .list }
                    .help(strings.titleHelp)
                    .accessibilityLabel(strings.titleHelp)
                participantChips
            }

            Spacer(minLength: DS.Space.x4)

            VStack(alignment: .trailing, spacing: DS.Space.x2) {
                typePicker
                if let conversation = review.conversation {
                    Text(details(of: conversation))
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                }
            }
        }
        .padding(.horizontal, DS.Space.x6)
        .padding(.vertical, DS.Space.x4)
        .onAppear(perform: resetTitle)
        .onChange(of: review.conversation?.title) { resetTitle() }
        .onChange(of: focus.wrappedValue) { old, _ in
            if old == .title { commitTitle() }
        }
        .alert(strings.renamePrompt, isPresented: renameBinding) {
            TextField(strings.renamePrompt, text: $renameText)
            Button(strings.renameConfirm) {
                if let renaming { review.rename(renaming.id, to: renameText) }
                renaming = nil
            }
            Button(strings.cancel, role: .cancel) { renaming = nil }
        }
    }

    // MARK: People

    private var participantChips: some View {
        HStack(spacing: DS.Space.x2) {
            ForEach(review.participants) { participant in
                Menu {
                    Button(strings.renameParticipant) {
                        renameText = participant.name
                        renaming = participant
                    }
                    Button(strings.thisIsMe) { review.setUser(participant.id) }
                        .disabled(participant.isUser)
                    let others = review.participants.filter { $0.id != participant.id }
                    if !others.isEmpty {
                        Menu(strings.mergeInto) {
                            ForEach(others) { other in
                                Button(other.name) { review.merge(participant.id, into: other.id) }
                            }
                        }
                    }
                    personItems(for: participant)
                } label: {
                    HStack(spacing: DS.Space.x1) {
                        if participant.isUser {
                            Image(systemName: "person.fill").accessibilityHidden(true)
                        } else if review.person(of: participant) != nil {
                            Image(systemName: "person.crop.circle")
                                .accessibilityLabel(strings.linkedToPerson)
                                .help(strings.linkedToPerson)
                        }
                        Text(participant.name)
                    }
                    .font(DS.FontStyle.control)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .padding(.horizontal, DS.Space.x2_5)
                    .padding(.vertical, DS.Space.x1)
                    .background(Capsule().fill(DS.ColorToken.chipBg))
                    .overlay(Capsule().stroke(DS.ColorToken.chipBorder, lineWidth: 1))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(strings.participantMenuHelp)
            }
        }
    }

    /// Menu items that tie a participant to a person in the list of people. Never for the user.
    @ViewBuilder private func personItems(for participant: Participant) -> some View {
        if !participant.isUser {
            let linked = review.person(of: participant)
            let suggestions = review.personSuggestions(for: participant.id)
            if linked != nil || review.canSaveAsPerson(participant) || !suggestions.isEmpty {
                Divider()
            }
            if let linked {
                Button(strings.viewPerson(linked.name)) { review.showPerson(of: participant.id) }
                Button(strings.unlinkPerson) { review.unlink(participant.id) }
            } else if review.canSaveAsPerson(participant) {
                Button(strings.saveAsPerson) { review.saveAsPerson(participant.id) }
            }
            ForEach(suggestions) { person in
                Button(strings.thisIsPerson(person.name)) { review.link(participant.id, to: person.id) }
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: Type, title, details

    private var typePicker: some View {
        Picker(strings.conversationType, selection: typeBinding) {
            ForEach(ConversationType.allCases, id: \.self) { type in
                Text(type.title(strings.language)).tag(type)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(strings.conversationType)
        .help(strings.conversationTypeHelp)
    }

    private var typeBinding: Binding<ConversationType> {
        Binding(
            get: { review.conversation?.type ?? .other },
            set: { review.setType($0) }
        )
    }

    private func details(of conversation: Conversation) -> String {
        [ViewFormat.dayAndTime(conversation.startedAt, strings),
         ViewFormat.duration(conversation.durationSeconds, strings)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func resetTitle() {
        titleDraft = review.conversation?.title ?? ""
    }

    private func commitTitle() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != review.conversation?.title {
            review.setTitle(title)
        } else {
            resetTitle()
        }
    }
}
