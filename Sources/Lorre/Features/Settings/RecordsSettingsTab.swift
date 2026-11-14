import AppKit
import LorreCore
import SwiftUI

extension EnvironmentValues {
    /// The settings kept in the database; set by the app for the Settings window.
    @Entry var settingsStore: SettingsStore?
}

/// Where finished records are written, and how the user is called.
struct RecordsSettingsTab: View {
    @Environment(\.settingsStore) private var store

    @State private var folderPath = ""
    @State private var name = ""
    @State private var errorMessage: String?

    private let strings = Strings.current

    var body: some View {
        Form {
            Section {
                LabeledContent(strings.exportFolder) {
                    VStack(alignment: .trailing, spacing: DS.Space.x2) {
                        Text(folderPath)
                            .font(DS.FontStyle.body)
                            .foregroundStyle(DS.ColorToken.fgSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        HStack(spacing: DS.Space.x2) {
                            Button(strings.chooseFolder, action: chooseFolder)
                            Button(strings.useDefaultFolder, action: useDefault)
                        }
                    }
                }
                Text(strings.exportFolderHelp)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            Section {
                TextField(strings.yourName, text: $name)
                    .frame(maxWidth: DS.Layout.settingsFieldWidth)
                    .onSubmit(saveName)
                Text(strings.yourNameHelp)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.fgSecondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.statusError)
            }
        }
        .formStyle(.grouped)
        .task { load() }
        .onDisappear(perform: saveName)
    }

    private func load() {
        guard let store else { return }
        do {
            folderPath = try store.exportFolder().path(percentEncoded: false)
            name = try store.userName()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseFolder() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = strings.chooseFolderPrompt
        panel.directoryURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save { try store.set(url.path(percentEncoded: false), for: .exportFolder) }
    }

    private func useDefault() {
        guard let store else { return }
        save { try store.set(nil, for: .exportFolder) }
    }

    private func saveName() {
        guard let store else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save { try store.set(trimmed, for: .userName) }
    }

    private func save(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        load()
    }
}
