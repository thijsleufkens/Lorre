import SwiftUI
import UniformTypeIdentifiers

struct SessionShelfView: View {
    private static let compactViewFilters: [ShelfFilter] = [.processing, .errors]

    @ObservedObject var viewModel: AppViewModel
    @State private var isPresentingImportPicker = false
    @State private var isShowingCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var contextRenameSession: SessionManifest?
    @State private var contextRenameDraft = ""
    @State private var contextDeleteSession: SessionManifest?
    @State private var contextRenameFolder: SessionFolder?
    @State private var contextRenameFolderDraft = ""
    @State private var contextDeleteFolder: SessionFolder?
    @State private var isShowingModelSettings = false

    private var hasVisibleViewFilters: Bool {
        viewModel.sessions.contains { $0.status == .processing || $0.status == .error }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: DS.Space.x4) {
                    SearchFieldView(label: "Sessions", text: $viewModel.searchQuery)

                    HStack(spacing: DS.Space.x2) {
                        Button {
                            isPresentingImportPicker = true
                        } label: {
                            Text("Import Audio")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(SecondaryControlButtonStyle())
                        .disabled(viewModel.isStartingRecording || viewModel.hasActiveRecording)

                        Button {
                            viewModel.showRecorderScreenTapped()
                        } label: {
                            Text(viewModel.recorderShelfActionLabel)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(PrimaryControlButtonStyle())
                        .disabled(viewModel.isStartingRecording || (viewModel.hasActiveRecording && viewModel.selectedSession == nil))
                    }
                    .frame(maxWidth: .infinity)

                    if viewModel.hasActiveRecording {
                        ActiveRecordingShelfCard(viewModel: viewModel)
                    }

                    if hasVisibleViewFilters {
                        VStack(alignment: .leading, spacing: DS.Space.x2) {
                            CapsLabel(text: "Views")
                            ForEach(Self.compactViewFilters) { filter in
                                Button {
                                    viewModel.selectedFilter = filter
                                    viewModel.toggleSidebarViewExpansion(filter)
                                } label: {
                                    FolderFilterRowView(
                                        title: filter.title,
                                        iconName: filter.iconName,
                                        count: viewModel.count(for: filter),
                                        isSelected: viewModel.selectedFilter == filter,
                                        isExpanded: viewModel.expandedViewFilters.contains(filter)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())

                                if viewModel.expandedViewFilters.contains(filter) {
                                    FolderContentsListView(
                                        sessions: viewModel.sessionsForViewBrowser(filter),
                                        selectedSessionID: viewModel.selectedSessionID,
                                        folders: viewModel.folders,
                                        onSelectSession: { session in
                                            viewModel.selectSession(session)
                                        },
                                        onRevealSession: { session in
                                            viewModel.revealFiles(for: session.id)
                                        },
                                        onRenameSession: { session in
                                            contextRenameSession = session
                                            contextRenameDraft = session.displayTitle
                                        },
                                        onDeleteSession: { session in
                                            contextDeleteSession = session
                                        },
                                        onMoveSession: { sessionID, folderID in
                                            viewModel.moveSession(sessionID, to: folderID)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if !viewModel.folders.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.x2) {
                            CapsLabel(text: "Folders")

                            Button {
                                viewModel.selectFolderFilter(nil)
                            } label: {
                                FolderFilterRowView(
                                    title: "All Folders",
                                    iconName: "tray.full",
                                    count: viewModel.sessions.count,
                                    isSelected: viewModel.selectedFolderID == nil
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())

                            Button {
                                viewModel.selectFolderFilter(AppViewModel.unfiledFolderSelectionID)
                                viewModel.toggleSidebarFolderExpansion(AppViewModel.unfiledFolderSelectionID)
                            } label: {
                                FolderFilterRowView(
                                    title: "Unfiled",
                                    iconName: "folder",
                                    count: viewModel.countForFolder(AppViewModel.unfiledFolderSelectionID),
                                    isSelected: viewModel.selectedFolderID == AppViewModel.unfiledFolderSelectionID,
                                    isExpanded: viewModel.expandedFolderIDs.contains(AppViewModel.unfiledFolderSelectionID)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())

                            if viewModel.expandedFolderIDs.contains(AppViewModel.unfiledFolderSelectionID) {
                                FolderContentsListView(
                                    sessions: viewModel.sessionsForFolderBrowser(AppViewModel.unfiledFolderSelectionID),
                                    selectedSessionID: viewModel.selectedSessionID,
                                    folders: viewModel.folders,
                                    onSelectSession: { session in
                                        viewModel.selectSession(session)
                                    },
                                    onRevealSession: { session in
                                        viewModel.revealFiles(for: session.id)
                                    },
                                    onRenameSession: { session in
                                        contextRenameSession = session
                                        contextRenameDraft = session.displayTitle
                                    },
                                    onDeleteSession: { session in
                                        contextDeleteSession = session
                                    },
                                    onMoveSession: { sessionID, folderID in
                                        viewModel.moveSession(sessionID, to: folderID)
                                    }
                                )
                            }

                            ForEach(viewModel.folders) { folder in
                                Button {
                                    viewModel.selectFolderFilter(folder.id)
                                    viewModel.toggleSidebarFolderExpansion(folder.id)
                                } label: {
                                    FolderFilterRowView(
                                        title: folder.name,
                                        iconName: "folder",
                                        count: viewModel.countForFolder(folder.id),
                                        isSelected: viewModel.selectedFolderID == folder.id,
                                        isExpanded: viewModel.expandedFolderIDs.contains(folder.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Rename Folder…") {
                                        contextRenameFolder = folder
                                        contextRenameFolderDraft = folder.name
                                    }
                                    Button("Delete Folder…", role: .destructive) {
                                        contextDeleteFolder = folder
                                    }
                                }

                                if viewModel.expandedFolderIDs.contains(folder.id) {
                                    FolderContentsListView(
                                        sessions: viewModel.sessionsForFolderBrowser(folder.id),
                                        selectedSessionID: viewModel.selectedSessionID,
                                        folders: viewModel.folders,
                                        onSelectSession: { session in
                                            viewModel.selectSession(session)
                                        },
                                        onRevealSession: { session in
                                            viewModel.revealFiles(for: session.id)
                                        },
                                        onRenameSession: { session in
                                            contextRenameSession = session
                                            contextRenameDraft = session.displayTitle
                                        },
                                        onDeleteSession: { session in
                                            contextDeleteSession = session
                                        },
                                        onMoveSession: { sessionID, folderID in
                                            viewModel.moveSession(sessionID, to: folderID)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(DS.Space.x4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            // Footer: always-visible "+ New folder" affordance
            HStack {
                Button {
                    newFolderName = ""
                    isShowingCreateFolderAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                        Text("New folder")
                    }
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, DS.Space.x4)
            .padding(.vertical, DS.Space.x2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dsPanelSurface(cornerRadius: DS.Radius.lg)
        .fileImporter(
            isPresented: $isPresentingImportPicker,
            allowedContentTypes: [.audio]
        ) { result in
            viewModel.importAudioPickerCompleted(result)
        }
        .alert("New Folder", isPresented: $isShowingCreateFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                viewModel.createFolder(named: newFolderName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a local session folder for organizing recordings.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { contextRenameFolder != nil },
            set: { if !$0 { contextRenameFolder = nil } }
        )) {
            TextField("Folder name", text: $contextRenameFolderDraft)
            Button("Save") {
                if let folder = contextRenameFolder {
                    viewModel.renameFolder(folder.id, to: contextRenameFolderDraft)
                }
                contextRenameFolder = nil
            }
            Button("Cancel", role: .cancel) {
                contextRenameFolder = nil
            }
        } message: {
            Text("Rename this folder for session organization.")
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { contextRenameSession != nil },
            set: { if !$0 { contextRenameSession = nil } }
        )) {
            TextField("Recording name", text: $contextRenameDraft)
            Button("Save") {
                if let session = contextRenameSession {
                    viewModel.renameSession(session.id, to: contextRenameDraft)
                }
                contextRenameSession = nil
            }
            Button("Cancel", role: .cancel) {
                contextRenameSession = nil
            }
        } message: {
            Text("Rename this recording in the session shelf and exports.")
        }
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { contextDeleteFolder != nil },
                set: { if !$0 { contextDeleteFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = contextDeleteFolder {
                    viewModel.deleteFolder(folder.id)
                }
                contextDeleteFolder = nil
            }
            Button("Cancel", role: .cancel) {
                contextDeleteFolder = nil
            }
        } message: {
            if let folder = contextDeleteFolder {
                Text("Delete folder \"\(folder.name)\" and move its recordings to Unfiled.")
            } else {
                Text("Delete this folder and move its recordings to Unfiled.")
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(
                get: { contextDeleteSession != nil },
                set: { if !$0 { contextDeleteSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Session", role: .destructive) {
                if let session = contextDeleteSession {
                    viewModel.deleteSession(session.id)
                }
                contextDeleteSession = nil
            }
            Button("Cancel", role: .cancel) {
                contextDeleteSession = nil
            }
        } message: {
            Text("This removes the session audio, transcript, and local exports from Lorre storage.")
        }
    }
}

private struct ActiveRecordingShelfCard: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            HStack(spacing: DS.Space.x2) {
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(DS.ColorToken.white.opacity(0.92))
                        .frame(width: 6, height: 6)

                    Text(viewModel.isStoppingRecording ? "FINALIZING" : "LIVE")
                        .font(DS.FontStyle.control)
                        .foregroundStyle(DS.ColorToken.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, DS.Space.x2)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(DS.ColorToken.black)
                )
                Spacer(minLength: 0)
                Text(Formatters.duration(viewModel.recordingElapsedSeconds))
                    .font(DS.FontStyle.monoStrong)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
            }

            Text(viewModel.activeRecordingHeadline)
                .font(DS.FontStyle.bodyStrong)
                .foregroundStyle(DS.ColorToken.fgPrimary)

            Text(viewModel.activeRecordingDetail)
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Space.x2) {
                CapsLabel(text: viewModel.activeRecordingSourceBadge)
                Spacer(minLength: 0)
                if viewModel.selectedSession != nil {
                    Button("Open Recorder") {
                        viewModel.showRecorderScreenTapped()
                    }
                    .buttonStyle(SecondaryControlButtonStyle())
                    .disabled(viewModel.isStoppingRecording)
                }
            }

            IndexRailView(mode: .live(viewModel.liveMeterSamples), height: 10)
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(alt: true, cornerRadius: DS.Radius.md)
    }
}

private struct FolderFilterRowView: View {
    let title: String
    let iconName: String
    let count: Int
    let isSelected: Bool
    var isExpanded: Bool? = nil

    var body: some View {
        HStack(spacing: DS.Space.x2) {
            if let isExpanded {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .frame(width: 10)
            }
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .frame(width: 16)

            Text(title)
                .font(DS.FontStyle.body)
                .foregroundStyle(DS.ColorToken.fgPrimary)

            Spacer()

            Text("\(count)")
                .font(DS.FontStyle.mono)
                .foregroundStyle(DS.ColorToken.fgSecondary)
        }
        .padding(.horizontal, DS.Space.x3)
        .padding(.vertical, DS.Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanelSurface(selected: isSelected, alt: !isSelected, cornerRadius: DS.Radius.sm)
    }
}

private struct FolderContentsListView: View {
    let sessions: [SessionManifest]
    let selectedSessionID: UUID?
    let folders: [SessionFolder]
    let onSelectSession: (SessionManifest) -> Void
    let onRevealSession: (SessionManifest) -> Void
    let onRenameSession: (SessionManifest) -> Void
    let onDeleteSession: (SessionManifest) -> Void
    let onMoveSession: (UUID, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x1) {
            if sessions.isEmpty {
                Text("No recordings")
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
                    .padding(.leading, DS.Space.x6)
                    .padding(.vertical, DS.Space.x1)
            } else {
                let grouper = SessionDateGrouper(calendar: .current, now: Date())
                ForEach(grouper.group(sessions), id: \.group) { bucket in
                    SessionDateGroupHeader(group: bucket.group)
                        .padding(.leading, DS.Space.x4)
                    ForEach(bucket.sessions) { session in
                        sessionRow(for: session)
                            .padding(.leading, DS.Space.x4)
                    }
                }
            }
        }
    }

    private func sessionRow(for session: SessionManifest) -> some View {
        let isSelected = selectedSessionID == session.id
        return Button {
            onSelectSession(session)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.x2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryShelfTitle(for: session))
                        .font(DS.FontStyle.bodyStrong)
                        .foregroundStyle(DS.ColorToken.fgPrimary)
                        .lineLimit(1)
                    Text(secondaryShelfMetadata(for: session))
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(DS.ColorToken.fgSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let badgeColor = statusBadgeColor(for: session.status) {
                    Text(session.status.label.uppercased())
                        .font(DS.FontStyle.helper)
                        .foregroundStyle(badgeColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, DS.Space.x3)
            .padding(.vertical, DS.Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(isSelected ? DS.ColorToken.bgPanelAlt : Color.clear)
            )
            .dsActiveAccentBar(isActive: isSelected)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal Files") {
                onRevealSession(session)
            }

            Button("Rename…") {
                onRenameSession(session)
            }

            Button("Delete…", role: .destructive) {
                onDeleteSession(session)
            }

            Divider()

            Menu("Move to Folder") {
                Button("Unfiled") {
                    onMoveSession(session.id, nil)
                }
                Divider()
                ForEach(folders) { folder in
                    Button(folder.name) {
                        onMoveSession(session.id, folder.id)
                    }
                }
            }
        }
    }

    private func primaryShelfTitle(for session: SessionManifest) -> String {
        guard isDefaultGeneratedSessionTitle(session.displayTitle) else {
            return session.displayTitle
        }
        let date = session.recordedAt ?? session.createdAt
        let timeString = date.formatted(date: .omitted, time: .shortened)
        if let duration = session.durationSeconds {
            return "\(timeString) • \(Formatters.duration(duration))"
        }
        return timeString
    }

    private func secondaryShelfMetadata(for session: SessionManifest) -> String {
        let date = session.recordedAt ?? session.createdAt
        if isDefaultGeneratedSessionTitle(session.displayTitle) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return Formatters.sessionMetadata(date: date, durationSeconds: session.durationSeconds)
    }

    private func isDefaultGeneratedSessionTitle(_ title: String) -> Bool {
        title.hasPrefix("Session ")
    }

    /// Returns a color for the status badge, or nil to suppress the badge entirely.
    /// `.idle` and `.ready` are suppressed — they are the default/boring states and
    /// would clutter every row. Only actionable states get a badge.
    private func statusBadgeColor(for status: SessionStatus) -> Color? {
        switch status {
        case .recording:
            return DS.ColorToken.accentLive
        case .error:
            return DS.ColorToken.statusError
        case .processing:
            return DS.ColorToken.statusPreparing
        case .idle, .ready:
            return nil
        }
    }
}
