import LorreCore
import SwiftUI

/// The page of one person: who they are, what to prepare for the next conversation, and their conversations.
struct PersonBriefView: View {
    let workspace: WorkspaceModel
    let brief: PersonBrief

    @State private var mergeTarget: PersonSummary?

    private let strings = Strings.current

    private var people: PeopleModel { workspace.people }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.x6) {
                PersonHeaderView(people: people, person: brief.person)
                if let message = people.errorMessage {
                    Text(message)
                        .font(DS.FontStyle.body)
                        .foregroundStyle(DS.ColorToken.statusError)
                }
                nextConversation
                aboutAndDecisions
                conversations
                mergeMenu
            }
            .frame(maxWidth: DS.Layout.contentMaxWidth, alignment: .leading)
            .padding(DS.Space.x6)
            .frame(maxWidth: .infinity)
        }
        .alert(
            mergeTarget.map { strings.mergeConfirmTitle(from: brief.person.name, into: $0.person.name) } ?? "",
            isPresented: Binding(get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }),
            presenting: mergeTarget
        ) { target in
            Button(strings.mergeConfirmButton, role: .destructive) {
                people.merge(brief.person.id, into: target.id)
                mergeTarget = nil
            }
            Button(strings.cancel, role: .cancel) { mergeTarget = nil }
        } message: { target in
            Text(strings.mergeConfirmMessage(from: brief.person.name, into: target.person.name))
        }
    }

    // MARK: Preparation

    @ViewBuilder private var nextConversation: some View {
        let groups = people.visibleGroups
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            Text(strings.nextConversationHeader)
                .font(DS.FontStyle.cardTitle)
                .foregroundStyle(DS.ColorToken.fgPrimary)
                .accessibilityAddTraits(.isHeader)
            if groups.isEmpty {
                Text(strings.briefEmpty)
                    .font(DS.FontStyle.sectionLabel)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            } else {
                ForEach(groups.filter(\.isForNextConversation), id: \.self) { group in
                    itemGroup(group)
                }
            }
        }
    }

    @ViewBuilder private var aboutAndDecisions: some View {
        ForEach(people.visibleGroups.filter { !$0.isForNextConversation }, id: \.self) { group in
            itemGroup(group)
        }
    }

    private func itemGroup(_ group: BriefGroup) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            Text(title(of: group))
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(people.items(group)) { item in
                BriefItemRow(item: item) { workspace.open(item.conversation.id) }
            }
        }
    }

    private func title(of group: BriefGroup) -> String {
        switch group {
        case .myActions: strings.groupMyActions
        case .theirCommitments: strings.groupTheirCommitments
        case .openPoints: strings.groupOpenPoints
        case .hooks: strings.groupHooks
        case .notes: strings.groupAboutPerson
        case .lastDecisions: strings.groupLastDecisions
        }
    }

    // MARK: Conversations and merging

    private var conversations: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            Text(strings.personConversationsHeader)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityAddTraits(.isHeader)
            if brief.conversations.isEmpty {
                Text(strings.personNoConversations)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            ForEach(brief.conversations, id: \.id) { conversation in
                Button { workspace.open(conversation.id) } label: {
                    HStack(spacing: DS.Space.x4) {
                        Text(conversation.title.isEmpty ? strings.untitledConversation : conversation.title)
                            .font(DS.FontStyle.bodyStrong)
                            .foregroundStyle(DS.ColorToken.fgPrimary)
                        Spacer()
                        Text(ViewFormat.dayAndTime(conversation.startedAt, strings))
                            .font(DS.FontStyle.helper)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }
                    .padding(DS.Space.x3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsPanelSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!ViewFormat.isReviewable(conversation))
                .help(ViewFormat.isReviewable(conversation) ? strings.personConversationHelp : strings.notReadyHelp)
            }
        }
    }

    @ViewBuilder private var mergeMenu: some View {
        let targets = people.mergeTargets
        if !targets.isEmpty {
            Menu(strings.mergePerson) {
                ForEach(targets) { target in
                    Button(target.person.name) { mergeTarget = target }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .help(strings.mergePersonHelp)
        }
    }
}

// MARK: Items

private struct BriefItemRow: View {
    let item: PersonBrief.Item
    let onOpen: () -> Void

    private let strings = Strings.current

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.x4) {
                Text(item.outcome.text)
                    .font(DS.FontStyle.outcomeText)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Space.x2)
                Text(ViewFormat.day(item.conversation.startedAt, strings))
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            .padding(DS.Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPanelSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(strings.briefItemHelp)
    }
}

// MARK: Header

/// Name, organisation, role and notes, edited in place. Each field saves when you press Return
/// or leave it; an empty name is put back as it was.
private struct PersonHeaderView: View {
    let people: PeopleModel
    let person: Person

    @State private var name = ""
    @State private var organisation = ""
    @State private var role = ""
    @State private var notes = ""
    @FocusState private var focused: Field?

    private enum Field { case name, organisation, role, notes }

    private let strings = Strings.current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            TextField(strings.personNameHelp, text: $name)
                .textFieldStyle(.plain)
                .font(DS.FontStyle.appTitle)
                .foregroundStyle(DS.ColorToken.fgPrimary)
                .focused($focused, equals: .name)
                .onSubmit(commitName)
                .help(strings.personNameHelp)
                .accessibilityLabel(strings.personNameHelp)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: DS.Space.x4) {
                field(strings.personOrganisationPlaceholder, help: strings.personOrganisationHelp, text: $organisation, field: .organisation) {
                    people.setOrganisation(person.id, organisation)
                }
                field(strings.personRolePlaceholder, help: strings.personRoleHelp, text: $role, field: .role) {
                    people.setRole(person.id, role)
                }
            }
            Text(strings.personNotesHeader)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .padding(.top, DS.Space.x2)
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: $notes)
                .font(DS.FontStyle.body)
                .scrollContentBackground(.hidden)
                .focused($focused, equals: .notes)
                .padding(DS.Space.x2)
                .frame(minHeight: DS.Layout.notesFieldMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ColorToken.fieldBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.ColorToken.fieldBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(strings.personNotesPlaceholder)
                            .font(DS.FontStyle.body)
                            .foregroundStyle(DS.ColorToken.fieldPlaceholder)
                            .padding(DS.Space.x3)
                            .allowsHitTesting(false)
                    }
                }
                .help(strings.personNotesHelp)
                .accessibilityLabel(strings.personNotesHelp)
        }
        .onAppear(perform: reset)
        .onChange(of: person) { reset() }
        .onChange(of: focused) { old, _ in
            switch old {
            case .name: commitName()
            case .organisation: people.setOrganisation(person.id, organisation)
            case .role: people.setRole(person.id, role)
            case .notes: people.setNotes(person.id, notes)
            case nil: break
            }
        }
    }

    private func field(
        _ placeholder: String, help: String, text: Binding<String>, field: Field, commit: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(DS.FontStyle.body)
            .foregroundStyle(DS.ColorToken.fgSecondary)
            .focused($focused, equals: field)
            .onSubmit(commit)
            .help(help)
            .accessibilityLabel(help)
    }

    private func reset() {
        name = person.name
        organisation = person.organisation ?? ""
        role = person.role ?? ""
        notes = person.notes ?? ""
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == person.name {
            name = person.name
        } else {
            people.rename(person.id, to: trimmed)
        }
    }
}
