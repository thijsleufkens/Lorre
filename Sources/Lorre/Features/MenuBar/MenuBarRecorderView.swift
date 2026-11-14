import AppKit
import LorreCore
import SwiftUI

/// The recorder that lives in the menu bar: start, stop, and what happened to recent conversations.
struct MenuBarRecorderView: View {
    @Bindable var model: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            header
            if let message = ViewFormat.friendlyError(model.message, strings: Strings.current) {
                Text(message)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(DS.ColorToken.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
            if !model.rows.isEmpty {
                Divider()
                recent
            }
            Divider()
            footer
        }
        .padding(DS.Space.x4)
        .frame(width: DS.Layout.menuBarPanelWidth)
        .background(DS.ColorToken.bgApp)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Lorre")
                .font(DS.FontStyle.wordmark)
                .foregroundStyle(DS.ColorToken.serifInk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if case let .recording(since) = model.phase {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.elapsed(from: since, to: context.date))
                        .font(DS.FontStyle.timerCompact)
                        .foregroundStyle(DS.ColorToken.accentLive)
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle, .starting:
            Picker("Source", selection: $model.source) {
                Text("Microphone + system audio").tag(CaptureSource.microphoneAndSystemAudio)
                Text("Microphone only").tag(CaptureSource.microphone)
                Text("System audio only").tag(CaptureSource.systemAudio)
            }
            .labelsHidden()
            .disabled(model.phase == .starting)

            Button {
                Task { await model.start() }
            } label: {
                HStack(spacing: DS.Space.x2) {
                    Circle().fill(DS.ColorToken.accentLive).frame(width: DS.Space.x2_5, height: DS.Space.x2_5)
                    Text(model.phase == .starting ? "Starting…" : "Start recording")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.ColorToken.accentPrimary)
            .controlSize(.large)
            .disabled(model.phase == .starting)

            Text("Let the other person know the conversation is being recorded.")
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .recording, .stopping:
            VStack(alignment: .leading, spacing: DS.Space.x1_5) {
                ForEach(model.source.trackKinds, id: \.self) { kind in
                    LevelRow(label: kind == .microphone ? "You" : "Others", level: model.levels[kind] ?? 0)
                }
            }
            Button {
                Task { await model.stop() }
            } label: {
                Text(model.phase == .stopping ? "Stopping…" : "Stop recording")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.ColorToken.accentLive)
            .controlSize(.large)
            .disabled(model.phase == .stopping)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: DS.Space.x2) {
            Text("Recent")
                .font(DS.FontStyle.sectionLabel)
                .foregroundStyle(DS.ColorToken.serifInk)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.rows) { row in
                RecentRow(row: row) {
                    Task { await model.process(row.id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Lorre") {
                NSApp.activate()
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .disabled(model.isBusy)
                .help(model.isBusy ? "Stop the recording first." : "")
        }
        .buttonStyle(.link)
        .font(DS.FontStyle.helper)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LevelRow: View {
    let label: String
    let level: Double

    var body: some View {
        HStack(spacing: DS.Space.x2) {
            Text(label)
                .font(DS.FontStyle.helper)
                .foregroundStyle(DS.ColorToken.fgSecondary)
                .frame(width: DS.Layout.levelLabelWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.ColorToken.borderSoft)
                    Capsule()
                        .fill(DS.ColorToken.accentPrimary)
                        .frame(width: proxy.size.width * min(max(level, 0), 1))
                        .animation(.linear(duration: 0.2), value: level)
                }
            }
            .frame(height: DS.Space.x1_5)
        }
    }
}

private struct RecentRow: View {
    let row: RecorderModel.Row
    let process: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.x2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DS.FontStyle.body)
                    .foregroundStyle(DS.ColorToken.fgPrimary)
                    .lineLimit(1)
                Text(statusText)
                    .font(DS.FontStyle.helper)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.x2)
            switch row.status {
            case .ready:
                if let url = row.transcriptURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                }
            case .interrupted, .failed:
                Button(Strings.current.retry, action: process)
                    .help(Strings.current.retryHelp)
            case .recording, .waiting, .processing:
                EmptyView()
            }
        }
        .buttonStyle(.link)
        .font(DS.FontStyle.helper)
    }

    private var statusText: String {
        switch row.status {
        case .recording: "Recording…"
        case .waiting: "Waiting to be transcribed"
        case .processing: "Transcribing…"
        case .ready: row.durationSeconds.map { "Ready · \(Int(($0 / 60).rounded())) min" } ?? "Ready"
        case .interrupted: ViewFormat.friendlyError(row.error, strings: Strings.current) ?? Strings.current.errorInterrupted
        case .failed: ViewFormat.friendlyError(row.error, strings: Strings.current) ?? Strings.current.stateFailed
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .recording: DS.ColorToken.accentLive
        case .failed, .interrupted: DS.ColorToken.statusError
        case .waiting, .processing: DS.ColorToken.statusPreparing
        case .ready: DS.ColorToken.fgSecondary
        }
    }
}
