import LorreCore
import SwiftUI

/// "What was said when?": every conversation, newest first, and a search across all transcripts.
struct ConversationsView: View {
    @Bindable var workspace: WorkspaceModel

    private let strings = Strings.current

    private var query: String { workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.x4) {
                    if query.isEmpty {
                        list
                    } else {
                        hits
                    }
                }
                .frame(maxWidth: DS.Layout.contentMaxWidth, alignment: .leading)
                .padding(DS.Space.x6)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.x2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .accessibilityHidden(true)
            TextField(strings.searchPlaceholder, text: $workspace.searchText)
                .textFieldStyle(.plain)
                .font(DS.FontStyle.body)
                .accessibilityLabel(strings.searchPlaceholder)
                .help(strings.searchHelp)
        }
        .padding(.horizontal, DS.Space.x3)
        .padding(.vertical, DS.Space.x2)
        .frame(maxWidth: DS.Layout.searchFieldMaxWidth)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.ColorToken.fieldBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.ColorToken.fieldBorder, lineWidth: 1)
        )
        .padding(.horizontal, DS.Space.x6)
        .padding(.top, DS.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var list: some View {
        if workspace.all.isEmpty {
            Text(strings.conversationsEmpty)
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Space.x8)
        } else {
            ForEach(ViewFormat.monthGroups(workspace.all, strings)) { group in
                VStack(alignment: .leading, spacing: DS.Space.x2) {
                    Text(group.title)
                        .font(DS.FontStyle.sectionLabel)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items, id: \.conversation.id) { summary in
                        ConversationRow(summary: summary) { workspace.open(summary.conversation.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var hits: some View {
        if workspace.searchHits.isEmpty {
            Text(strings.noHits(for: query))
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Space.x8)
        } else {
            ForEach(workspace.searchHits, id: \.segmentId) { hit in
                SearchHitRow(hit: hit) { workspace.open(hit.conversationId) }
            }
        }
    }
}

private struct ConversationRow: View {
    let summary: ConversationSummary
    let onOpen: () -> Void

    private let strings = Strings.current

    var body: some View {
        let conversation = summary.conversation
        let reviewable = ViewFormat.isReviewable(conversation)
        Button(action: onOpen) {
            HStack(spacing: DS.Space.x4) {
                VStack(alignment: .leading, spacing: DS.Space.x1) {
                    Text(conversation.title.isEmpty ? strings.untitledConversation : conversation.title)
                        .font(DS.FontStyle.bodyStrong)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                    Text(
                        [ViewFormat.dayAndTime(conversation.startedAt, strings),
                         ViewFormat.duration(conversation.durationSeconds, strings)]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                }
                Spacer()
                Text(ViewFormat.stateLabel(conversation, strings))
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .padding(.horizontal, DS.Space.x2_5)
                    .padding(.vertical, DS.Space.x1)
                    .background(Capsule().fill(DS.ColorToken.chipBg))
                    .overlay(Capsule().stroke(DS.ColorToken.chipBorder, lineWidth: 1))
            }
            .padding(DS.Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPanelSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!reviewable)
        .help(reviewable ? "" : strings.notReadyHelp)
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit
    let onOpen: () -> Void

    private let strings = Strings.current

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Space.x1_5) {
                Text(hit.conversationTitle.isEmpty ? strings.untitledConversation : hit.conversationTitle)
                    .font(DS.FontStyle.bodyStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                Text(emphasised)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(DS.Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPanelSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The snippet with the matched words in bold and highlighted.
    private var emphasised: AttributedString {
        var result = AttributedString()
        for piece in ViewFormat.snippetPieces(hit.snippet) {
            var part = AttributedString(piece.text)
            if piece.isMatch {
                part.font = DS.FontStyle.bodyStrong
                part.foregroundColor = DS.ColorToken.fgPrimary
                part.backgroundColor = DS.ColorToken.matchFill
            }
            result += part
        }
        return result
    }
}
