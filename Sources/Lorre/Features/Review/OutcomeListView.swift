import LorreCore
import SwiftUI

/// The left column: outcomes grouped by kind, and the form to add one that was missed.
struct OutcomeListView: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding

    private let strings = Strings.current

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.x4) {
                    if review.groups.isEmpty {
                        Text(strings.noOutcomes)
                            .font(DS.FontStyle.body)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                    }
                    ForEach(review.groups) { group in
                        OutcomeGroupView(review: review, draft: draft, focus: focus, group: group)
                    }
                    addForm
                }
                .padding(DS.Space.x4)
            }
            .onChange(of: review.selectedOutcomeID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
    }

    // MARK: Adding an outcome

    private var addForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            Text(strings.addOutcome)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
            HStack(spacing: DS.Space.x2) {
                Picker(strings.addKindHelp, selection: Bindable(draft).addKind) {
                    ForEach(OutcomeKind.displayOrder, id: \.self) { kind in
                        Text(kind.title(strings.language, plural: false)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help(strings.addKindHelp)
                Spacer(minLength: 0)
            }
            HStack(spacing: DS.Space.x2) {
                TextField(strings.addPlaceholder, text: Bindable(draft).addText)
                    .textFieldStyle(.roundedBorder)
                    .focused(focus, equals: .add)
                    .onSubmit { draft.confirmAdd(in: review) }
                    .onExitCommand { focus.wrappedValue = .list }
                Button(strings.addConfirm) { draft.confirmAdd(in: review) }
                    .buttonStyle(SecondaryControlButtonStyle())
                    .disabled(draft.addText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, DS.Space.x2)
    }
}

/// One kind of outcome with its items. Information starts collapsed: most items, least urgency.
private struct OutcomeGroupView: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding
    let group: ReviewModel.Group

    private let strings = Strings.current

    private var collapsible: Bool { group.kind == .information }

    private var isExpanded: Bool {
        guard collapsible else { return true }
        return draft.expandedKinds.contains(group.kind)
            || group.items.contains { $0.id == review.selectedOutcomeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x1) {
            header
            if isExpanded {
                ForEach(group.items) { outcome in
                    OutcomeRow(review: review, draft: draft, focus: focus, outcome: outcome)
                        .id(outcome.id)
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        let title = group.kind.title(strings.language).uppercased()
        if collapsible {
            Button {
                if draft.expandedKinds.contains(group.kind) {
                    draft.expandedKinds.remove(group.kind)
                } else {
                    draft.expandedKinds.insert(group.kind)
                }
            } label: {
                HStack(spacing: DS.Space.x1_5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DS.FontStyle.helper)
                        .accessibilityHidden(true)
                    Text("\(title) (\(group.items.count))")
                }
                .font(DS.FontStyle.kicker)
                .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? strings.hideGroup : strings.showGroup)
            .accessibilityLabel("\(isExpanded ? strings.hideGroup : strings.showGroup) \(title)")
        } else {
            Text(title)
                .font(DS.FontStyle.kicker)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// One outcome: status, text (editable in place), owner, and the approve and reject buttons.
private struct OutcomeRow: View {
    let review: ReviewModel
    let draft: ReviewDraft
    var focus: FocusState<ReviewField?>.Binding
    let outcome: Outcome

    private let strings = Strings.current

    private var isSelected: Bool { review.selectedOutcomeID == outcome.id }
    private var isEditing: Bool { draft.editingID == outcome.id }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.x2_5) {
            statusIcon
            VStack(alignment: .leading, spacing: DS.Space.x1_5) {
                textView
                if outcome.kind.hasOwner { ownerMenu }
            }
            Spacer(minLength: DS.Space.x2)
            if outcome.status == .proposed { judgeButtons }
        }
        .padding(.horizontal, DS.Space.x2_5)
        .padding(.vertical, DS.Space.x2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isSelected ? DS.ColorToken.selectionFill : Color.clear)
        )
        .dsActiveAccentBar(isActive: isSelected)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            review.select(outcome.id)
            draft.beginEdit(outcome)
            focus.wrappedValue = .edit
        }
        .onTapGesture {
            review.select(outcome.id)
            if !isEditing { focus.wrappedValue = .list }
        }
    }

    private var statusIcon: some View {
        Image(systemName: outcome.status == .approved ? "checkmark.circle.fill" : "circle")
            .font(DS.FontStyle.icon)
            .foregroundStyle(outcome.status == .approved ? DS.ColorToken.accentPrimary : DS.ColorToken.fgTertiary)
            .frame(width: DS.Layout.iconSlot)
            .accessibilityLabel(outcome.status == .approved ? strings.approvedLabel : strings.proposedLabel)
    }

    @ViewBuilder private var textView: some View {
        if isEditing {
            TextField(strings.edit, text: Bindable(draft).editText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(DS.FontStyle.outcomeText)
                .focused(focus, equals: .edit)
                .onSubmit {
                    draft.commitEdit(in: review)
                    focus.wrappedValue = .list
                }
                .onExitCommand {
                    draft.cancelEdit()
                    focus.wrappedValue = .list
                }
        } else {
            Text(outcome.text)
                .font(isSelected ? DS.FontStyle.outcomeTextStrong : DS.FontStyle.outcomeText)
                .foregroundStyle(DS.ColorToken.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ownerMenu: some View {
        Menu {
            ForEach(review.participants) { participant in
                Button(participant.name) { setOwner(participant.id) }
            }
            Divider()
            Button(strings.ownerNone) { setOwner(nil) }
        } label: {
            Text(review.name(of: outcome.ownerParticipantId) == "?" && outcome.ownerParticipantId == nil
                 ? strings.ownerNone : review.name(of: outcome.ownerParticipantId))
                .font(DS.FontStyle.control)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(strings.ownerMenuHelp)
        .accessibilityLabel("\(strings.owner): \(review.name(of: outcome.ownerParticipantId))")
    }

    private func setOwner(_ id: UUID?) {
        review.select(outcome.id)
        let owner: UUID?? = .some(id)
        review.updateSelected(owner: owner)
    }

    private var judgeButtons: some View {
        HStack(spacing: DS.Space.x1) {
            Button {
                review.select(outcome.id)
                review.approveSelected()
            } label: {
                Image(systemName: "checkmark").font(DS.FontStyle.icon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DS.ColorToken.accentPrimary)
            .accessibilityLabel(strings.approve)
            .help(strings.approve)
            Button {
                review.select(outcome.id)
                review.removeSelected()
            } label: {
                Image(systemName: "xmark").font(DS.FontStyle.icon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DS.ColorToken.statusError)
            .accessibilityLabel(strings.reject)
            .help(strings.reject)
        }
    }
}
