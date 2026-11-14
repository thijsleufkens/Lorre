import LorreCore
import SwiftUI

/// "Who am I talking to?": the people you know on the left, and on the right what to remember
/// for the next conversation with the selected person.
struct PeopleView: View {
    let workspace: WorkspaceModel

    private let strings = Strings.current

    private var people: PeopleModel { workspace.people }

    var body: some View {
        if people.allPeople.isEmpty {
            Text(strings.peopleEmpty)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: DS.Layout.searchFieldMaxWidth)
                .padding(DS.Space.x8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                PeopleListView(people: people)
                    .frame(width: DS.Layout.peopleListWidth)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let brief = people.brief {
            PersonBriefView(workspace: workspace, brief: brief)
                .id(brief.person.id)
        } else {
            Text(strings.personNoSelection)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .multilineTextAlignment(.center)
                .padding(DS.Space.x8)
        }
    }
}

// MARK: List

private struct PeopleListView: View {
    @Bindable var people: PeopleModel

    private let strings = Strings.current

    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.x2) {
                    if people.people.isEmpty {
                        Text(strings.peopleNoMatches)
                            .font(DS.FontStyle.sectionLabel)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, DS.Space.x6)
                    }
                    ForEach(people.people) { summary in
                        PersonRow(summary: summary, isSelected: summary.id == people.selectedPersonID) {
                            people.select(summary.id)
                        }
                    }
                }
                .padding(DS.Space.x4)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.x2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityHidden(true)
            TextField(strings.peopleSearchPlaceholder, text: $people.searchText)
                .textFieldStyle(.plain)
                .font(DS.FontStyle.body)
                .accessibilityLabel(strings.peopleSearchPlaceholder)
                .help(strings.peopleSearchHelp)
        }
        .padding(.horizontal, DS.Space.x3)
        .padding(.vertical, DS.Space.x2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ColorToken.fieldBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.ColorToken.fieldBorder, lineWidth: 1)
        )
        .padding(.horizontal, DS.Space.x4)
        .padding(.top, DS.Space.x4)
    }
}

private struct PersonRow: View {
    let summary: PersonSummary
    let isSelected: Bool
    let onSelect: () -> Void

    private let strings = Strings.current

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: DS.Space.x2) {
                VStack(alignment: .leading, spacing: DS.Space.x1) {
                    Text(summary.person.name)
                        .font(DS.FontStyle.bodyStrong)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                    if let organisation = summary.person.organisation {
                        Text(organisation)
                            .font(DS.FontStyle.helper)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }
                    Text(detail)
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                }
                Spacer(minLength: DS.Space.x2)
                if summary.openCount > 0 {
                    Text(strings.openItemCount(summary.openCount))
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .padding(.horizontal, DS.Space.x2_5)
                        .padding(.vertical, DS.Space.x1)
                        .background(Capsule().fill(DS.ColorToken.chipBg))
                        .overlay(Capsule().stroke(DS.ColorToken.chipBorder, lineWidth: 1))
                }
            }
            .padding(DS.Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPanelSurface(selected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "3 gesprekken · Laatst gesproken op 8 okt", or "Nog geen gesprek".
    private var detail: String {
        guard let last = summary.lastConversationAt else { return strings.noConversationYet }
        return "\(strings.conversationCount(summary.conversationCount)) · \(strings.lastConversationOn(ViewFormat.day(last, strings)))"
    }
}
