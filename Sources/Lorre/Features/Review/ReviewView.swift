import AppKit
import LorreCore
import SwiftUI

/// The review of one conversation: judge the proposed outcomes, fix who is who, add what was missed,
/// and finish. Keyboard first; see `handle(_:)`.
struct ReviewView: View {
    let review: ReviewModel
    let onClose: () -> Void

    @State private var draft = ReviewDraft()
    @FocusState private var focus: ReviewField?

    private let strings = Strings.current

    var body: some View {
        VStack(spacing: 0) {
            ReviewHeaderView(review: review, onBack: onClose, focus: $focus)
            Divider()
            HStack(spacing: 0) {
                OutcomeListView(review: review, draft: draft, focus: $focus)
                    .frame(width: DS.Layout.reviewListWidth)
                Divider()
                EvidenceColumnView(review: review, draft: draft, focus: $focus)
            }
            if let error = review.errorMessage {
                Text(error)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.x6)
                    .padding(.vertical, DS.Space.x2)
            }
            Divider()
            footer
        }
        .focusable()
        .focused($focus, equals: .list)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handle($0) }
        .onAppear {
            focus = .list
            if review.selectedOutcomeID == nil { review.selectNext() }
        }
        .onChange(of: focus) { old, _ in
            if old == .edit, draft.editingID != nil { draft.commitEdit(in: review) }
        }
        .background(DS.ColorToken.bgApp)
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if review.isFinished, let export = review.lastExport {
            HStack(spacing: DS.Space.x4) {
                VStack(alignment: .leading, spacing: DS.Space.x1) {
                    Text(strings.savedTitle)
                        .font(DS.FontStyle.bodyStrong)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                    Text(strings.savedAt(folderText(for: export)))
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(strings.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([export.markdown, export.json])
                }
                .buttonStyle(SecondaryControlButtonStyle())
                Button(strings.done, action: onClose)
                    .buttonStyle(PrimaryControlButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.x4)
        } else {
            HStack(spacing: DS.Space.x4) {
                Text(strings.keyboardHints)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                Spacer()
                Text(strings.pendingCount(review.pendingCount))
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                Button(strings.finish) { review.finish() }
                    .buttonStyle(PrimaryControlButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(strings.finishHelp)
            }
            .padding(DS.Space.x4)
        }
    }

    private func folderText(for export: RecordExporter.Exported) -> String {
        let folder = export.markdown.deletingLastPathComponent().path(percentEncoded: false)
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Keyboard

    /// Single-key shortcuts work only while no text field has focus.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard focus == nil || focus == .list, draft.editingID == nil else { return .ignored }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .upArrow:
            review.selectPrevious()
            return .handled
        case .downArrow:
            review.selectNext()
            return .handled
        case .space:
            if review.isPlaying { review.stopPlayback() } else { review.playEvidence() }
            return .handled
        case .escape:
            onClose()
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case "a":
            review.approveSelected()
        case "x":
            review.rejectSelected()
        case "e":
            guard let outcome = review.selectedOutcome else { return .ignored }
            draft.beginEdit(outcome)
            focus = .edit
        case "n":
            focus = .add
        default:
            return .ignored
        }
        return .handled
    }
}
