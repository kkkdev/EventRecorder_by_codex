import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var controller: CaptureSessionController
    @ObservedObject var eventManager: EventManager
    @ObservedObject var teamsAutomationController: TeamsAutomationController

    @State private var selectedTargetWindowID: UInt32 = 0
    @State private var includeOffscreenTargets = false
    @State private var intervalSecondsText = "1.0"
    @State private var jpegQualityText = "0.9"
    @State private var audioBitrateText = "128"
    @State private var outputDirectoryPath = CaptureSettings.defaultOutputDirectory().path

    @State private var eventTitleText = ""
    @State private var eventURLText = ""
    @State private var eventStartsAt = Date().addingTimeInterval(3600)
    @State private var eventEndsAt = Date().addingTimeInterval(7200)

    @State private var localMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Event Recorder")
                    .font(.title)
                    .bold()

                Text("手動録画 + Teams会議自動録画 + 汎用URLイベント")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GroupBox("ステータス") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("録画状態", value: controller.state.statusText)
                        LabeledContent("通知権限", value: reminderStatusText)
                        LabeledContent("Screen Recording権限", value: controller.hasScreenRecordingPermission() ? "許可済み" : "未許可")
                        LabeledContent(
                            "Accessibility権限",
                            value: teamsAutomationController.hasAccessibilityPermission() ? "許可済み" : "未許可"
                        )
                        LabeledContent("Teams自動録画", value: teamsAutomationController.statusText)
                        LabeledContent("ffmpeg", value: controller.hasFFmpeg() ? "検出済み" : "未検出")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Teams自動録画") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Teams会議への参加を検出して自動録画",
                            isOn: Binding(
                                get: { teamsAutomationController.isMonitoring },
                                set: { enabled in
                                    if enabled {
                                        startTeamsMonitoring()
                                    } else {
                                        Task {
                                            await teamsAutomationController.stopMonitoring()
                                        }
                                    }
                                }
                            )
                        )
                        .accessibilityIdentifier("teams.automationToggle")

                        Text("アプリ起動中だけ監視します。scheduled meeting、Meet Now、1対1・グループ通話が対象です。本人マイクは収録しません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Accessibility権限を確認") {
                                if !teamsAutomationController.requestAccessibilityPermission() {
                                    teamsAutomationController.openAccessibilitySettings()
                                }
                            }

                            Button("通知許可をリクエスト") {
                                Task {
                                    await eventManager.requestNotificationPermission()
                                }
                            }

                            if let seconds = teamsAutomationController.pendingStartSeconds {
                                Text("\(seconds)秒後に録画開始")
                                    .foregroundStyle(.orange)
                                Button("今回の自動録画を取消") {
                                    teamsAutomationController.cancelPendingStart()
                                }
                                .accessibilityIdentifier("teams.cancelPendingButton")
                            }
                        }

                        if let message = teamsAutomationController.message {
                            Text(message)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("録画設定") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("キャプチャ対象ウィンドウ", selection: $selectedTargetWindowID) {
                                if controller.availableTargets.isEmpty {
                                    Text("対象ウィンドウが見つかりません").tag(UInt32(0))
                                }
                                ForEach(controller.availableTargets) { target in
                                    Text(target.summary).tag(target.windowID)
                                }
                            }
                            Button("対象更新") {
                                Task {
                                    await controller.prepare(includeOffscreen: includeOffscreenTargets)
                                    syncTargetSelectionIfNeeded()
                                }
                            }
                        }

                        Toggle("全デスクトップを含める", isOn: $includeOffscreenTargets)
                        Text("他デスクトップのウィンドウも候補に表示します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("スクショ間隔(秒)")
                            TextField("1.0", text: $intervalSecondsText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }

                        HStack {
                            Text("JPEG品質")
                            TextField("0.9", text: $jpegQualityText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }

                        HStack {
                            Text("音声ビットレート(kbps)")
                            TextField("128", text: $audioBitrateText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }

                        HStack {
                            Text("保存先")
                            TextField("保存先ディレクトリ", text: $outputDirectoryPath)
                                .textFieldStyle(.roundedBorder)
                            Button("選択") {
                                chooseOutputDirectory()
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("権限確認") {
                        if !controller.requestScreenRecordingPermission() {
                            controller.openPermissionSettings()
                        }
                    }

                    Button("開始") {
                        startCapture()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.state.isRunning)
                    .accessibilityIdentifier("capture.startButton")

                    Button("停止") {
                        Task {
                            await teamsAutomationController.stopCaptureByUser()
                        }
                    }
                    .disabled(!controller.state.canStop)
                    .accessibilityIdentifier("capture.stopButton")
                }

                GroupBox("イベント") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button("通知許可をリクエスト") {
                                Task {
                                    await eventManager.requestNotificationPermission()
                                }
                            }

                            Button("ブラウザ全画面切替") {
                                eventManager.toggleBrowserFullScreen()
                            }
                        }

                        HStack {
                            Text("タイトル(任意)")
                            TextField("任意", text: $eventTitleText)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("URL")
                            TextField("https://...", text: $eventURLText)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("event.urlField")
                        }

                        HStack {
                            DatePicker("開始日時", selection: $eventStartsAt)
                            DatePicker("終了日時", selection: $eventEndsAt)
                        }

                        Button("イベント追加") {
                            Task {
                                await eventManager.addEvent(
                                    title: eventTitleText,
                                    urlText: eventURLText,
                                    startsAt: eventStartsAt,
                                    endsAt: eventEndsAt
                                )
                                eventURLText = ""
                                eventTitleText = ""
                            }
                        }
                        .accessibilityIdentifier("event.addButton")

                        if eventManager.events.isEmpty {
                            Text("登録済みイベントはありません")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(eventManager.events) { event in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.displayTitle)
                                                .font(.headline)
                                            Text(event.url.absoluteString)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                            Text("開始: \(Self.dateFormatter.string(from: event.startsAt))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("終了: \(Self.dateFormatter.string(from: event.endsAt))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack {
                                            Button("開く") {
                                                eventManager.open(event)
                                            }
                                            Button("全画面で開く") {
                                                eventManager.openFullScreen(event)
                                            }
                                            .accessibilityIdentifier("event.fullscreenButton")
                                            Button("削除") {
                                                Task {
                                                    await eventManager.deleteEvent(id: event.id)
                                                }
                                            }
                                            .accessibilityIdentifier("event.deleteButton")
                                        }
                                    }
                                    Divider()
                                }
                            }
                        }
                    }
                }

                if let localMessage {
                    Text(localMessage)
                        .foregroundStyle(.orange)
                }

                if let message = eventManager.message {
                    Text(message)
                        .accessibilityIdentifier("event.messageLabel")
                        .foregroundStyle(.orange)
                }

                if let lastErrorMessage = controller.lastErrorMessage {
                    Text(lastErrorMessage)
                        .foregroundStyle(.red)
                }

                if let lastWarningMessage = controller.lastWarningMessage {
                    Text(lastWarningMessage)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
        }
        .task {
            await eventManager.prepare()
            await controller.prepare(includeOffscreen: includeOffscreenTargets)
            syncTargetSelectionIfNeeded()
        }
        .onChange(of: includeOffscreenTargets) { _ in
            Task {
                await controller.prepare(includeOffscreen: includeOffscreenTargets)
                syncTargetSelectionIfNeeded()
            }
        }
        .onReceive(controller.$availableTargets) { _ in
            syncTargetSelectionIfNeeded()
        }
    }

    private var reminderStatusText: String {
        switch eventManager.reminderPermissionStatus {
        case .authorized:
            return "許可済み"
        case .denied:
            return "拒否"
        case .notDetermined:
            return "未決定"
        }
    }

    private func startCapture() {
        localMessage = nil
        guard let preferences = makeCapturePreferences() else { return }
        guard let target = controller.availableTargets.first(where: { $0.windowID == selectedTargetWindowID }) else {
            localMessage = "キャプチャ対象ウィンドウを選択してください。"
            return
        }

        let outputDirectoryURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        let settings = CaptureSettings(
            target: target,
            intervalSeconds: preferences.intervalSeconds,
            jpegQuality: preferences.jpegQuality,
            outputDirectory: outputDirectoryURL,
            audioBitrateKbps: preferences.audioBitrateKbps
        )

        Task {
            await controller.start(settings: settings)
        }
    }

    private func startTeamsMonitoring() {
        localMessage = nil
        guard let preferences = makeCapturePreferences() else { return }
        teamsAutomationController.startMonitoring(preferences: preferences)
    }

    private func makeCapturePreferences() -> TeamsAutomationCapturePreferences? {
        guard let intervalSeconds = Double(intervalSecondsText) else {
            localMessage = "スクショ間隔は数値で入力してください。"
            return nil
        }
        guard let jpegQuality = Double(jpegQualityText) else {
            localMessage = "JPEG品質は数値で入力してください。"
            return nil
        }
        guard let audioBitrate = Int(audioBitrateText) else {
            localMessage = "音声ビットレートは整数で入力してください。"
            return nil
        }
        guard CaptureSettings.intervalRange.contains(intervalSeconds) else {
            localMessage = "スクショ間隔は0.5〜120秒で入力してください。"
            return nil
        }
        guard CaptureSettings.jpegQualityRange.contains(jpegQuality) else {
            localMessage = "JPEG品質は0.1〜1.0で入力してください。"
            return nil
        }
        guard CaptureSettings.bitrateRange.contains(audioBitrate) else {
            localMessage = "音声ビットレートは64〜320kbpsで入力してください。"
            return nil
        }

        return TeamsAutomationCapturePreferences(
            intervalSeconds: intervalSeconds,
            jpegQuality: jpegQuality,
            outputDirectory: URL(fileURLWithPath: outputDirectoryPath, isDirectory: true),
            audioBitrateKbps: audioBitrate
        )
    }

    private func syncTargetSelectionIfNeeded() {
        if selectedTargetWindowID != 0 {
            if controller.availableTargets.contains(where: { $0.windowID == selectedTargetWindowID }) {
                return
            }
            selectedTargetWindowID = 0
        }

        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        if let ownAppTarget = controller.availableTargets.first(where: { $0.application.processID == currentPID }) {
            selectedTargetWindowID = ownAppTarget.windowID
            return
        }

        guard let first = controller.availableTargets.first else {
            return
        }
        selectedTargetWindowID = first.windowID
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.prompt = "選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let selectedURL = panel.urls.first {
            outputDirectoryPath = selectedURL.path
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}
