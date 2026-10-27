import AppKit
import SwiftUI
import AVFoundation
import UserNotifications

struct GeneralSettings: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.detectMeetings) private var detectMeetings = true
    @AppStorage(SettingsKey.autoRecord) private var autoRecord = false
    @AppStorage(SettingsKey.autoStopRecording) private var autoStopRecording = true
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKey.fillerRemoval) private var fillerRemoval = false
    @AppStorage(SettingsKey.showLiveRecordingCard) private var showLiveRecordingCard = true
    @AppStorage(SettingsKey.defaultTemplate) private var defaultTemplate = "Meeting Notes"
    @AppStorage(SettingsKey.systemAudioConfirmed) private var systemAudioConfirmed = false

    @State private var micStatus = MicRecorder.permissionGranted
    @AppStorage(SettingsKey.openMainWindowAtLaunch) private var openMainWindowAtLaunch = true
    @AppStorage(SettingsKey.developerMode) private var developerMode = false
    @AppStorage(SettingsKey.crashDiagnostics) private var crashDiagnostics = false
    @State private var launchAtLogin = LaunchAtLogin.isOn
    @State private var requestingSystemAudio = false
    @State private var systemAudioError: String?
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Setup") {
                Toggle("Launch Ayrvo at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLaunchAtLogin() }
                Text(LaunchAtLogin.requiresApproval
                     ? "Approve Ayrvo under System Settings → General → Login Items to finish enabling this."
                     : "Starts Ayrvo in the menu bar automatically when you log in.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Toggle("Open Ayrvo window at launch", isOn: $openMainWindowAtLaunch)
                Text("Shows the main window when Ayrvo starts. Turn off to stay in the menu bar until you open it.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Button("Run setup walkthrough again") { openWindow(id: "onboarding") }
                    .buttonStyle(.plain)
                    .font(.ayrvo(12))
                    .foregroundStyle(Theme.blueberry)
            }

            Section("Meetings") {
                Toggle("Detect meetings automatically", isOn: $detectMeetings)
                    .onChange(of: detectMeetings) {
                        detectMeetings ? app.startDetection() : app.stopDetection()
                    }
                Toggle("Start recording without asking", isOn: $autoRecord)
                    .disabled(!detectMeetings)
                Text("Ayrvo notices when another app starts using your microphone — Zoom, Meet, Teams, anything — and offers to record. Nothing is captured until recording starts.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Toggle("Stop recording automatically when the meeting ends", isOn: $autoStopRecording)
                    .disabled(!detectMeetings)
                Text("Waits ~8s after the meeting app releases the microphone, in case it reconnects.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Toggle("Show floating transcript while recording", isOn: $showLiveRecordingCard)
                    .onAppear { app.showLiveRecordingCard = showLiveRecordingCard }
                    .onChange(of: showLiveRecordingCard) { app.showLiveRecordingCard = showLiveRecordingCard }
                Text("The draggable live transcript card. Turn off to record from the menu bar only.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                if detectMeetings {
                    HStack(alignment: .top) {
                        StatusDot(ok: app.activeMicAppNames.isEmpty ? nil : true)
                        Text(app.activeMicAppNames.isEmpty
                             ? "No other app is using the microphone right now."
                             : "Currently hearing: \(app.activeMicAppNames.joined(separator: ", "))")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Understanding") {
                Toggle("Identify individual speakers", isOn: $identifySpeakers)
                Text("Separates different voices on the call using a small on-device model (~22 MB, downloaded once).")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Toggle("Remove filler words", isOn: $fillerRemoval)
                Text("Strips \"uh\", \"um\", \"er\", \"hmm\" and other disfluencies from the text used to generate notes. The saved transcript stays verbatim.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
                Picker("Default template", selection: $defaultTemplate) {
                    ForEach(app.templates.list()) { Text($0.name).tag($0.name) }
                }
            }

            Section("Permissions") {
                permissionRow(
                    ok: micStatus,
                    title: "Microphone",
                    detail: "Records your side of the call.") {
                    Task { micStatus = await MicRecorder.requestPermission() }
                }
                HStack(alignment: .firstTextBaseline) {
                    StatusDot(ok: systemAudioOK)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Audio Recording").font(.ayrvo(12, .medium))
                        Text(systemAudioSettingsDetail)
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Request access", action: requestSystemAudio)
                        .controlSize(.small)
                        .disabled(requestingSystemAudio)
                    Button("Open Settings") {
                        NSWorkspace.shared.open(SystemAudioPermission.privacySettingsURL)
                    }
                    .controlSize(.small)
                }
                HStack(alignment: .firstTextBaseline) {
                    StatusDot(ok: accessibilityTrusted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility").font(.ayrvo(12, .medium))
                        Text(accessibilitySettingsDetail)
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Grant…") { AccessibilityPermission.request() }
                            .controlSize(.small)
                        Button("Open Settings") {
                            NSWorkspace.shared.open(AccessibilityPermission.privacySettingsURL)
                        }
                        .controlSize(.small)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    StatusDot(ok: app.notificationAuthStatus == .authorized
                               ? true : (app.notificationAuthStatus == .denied ? false : nil))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.ayrvo(12, .medium))
                        Text("Lets Ayrvo notify you when a recording finishes processing and your notes are ready.")
                            .font(.ayrvo(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.notificationAuthStatus == .notDetermined {
                        Button("Grant…") { Task { await app.requestNotificationAuthorization() } }
                            .controlSize(.small)
                    } else {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(
                                string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                        .controlSize(.small)
                    }
                }
                .task { await app.refreshNotificationStatus() }
            }

            Section {
                Toggle("Developer mode", isOn: $developerMode)
                    .onChange(of: developerMode) {
                        AyrvoConsoleLog.app("developer mode \(developerMode ? "enabled" : "disabled")")
                        if developerMode {
                            AyrvoConsoleLog.app("debug logging active — stderr + Debug tab")
                        }
                    }
                Text("Shows a Debug tab with diagnostics and experimental options.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Save a crash diagnostic on crash", isOn: $crashDiagnostics)
                Text("When Ayrvo crashes, writes a small scrubbed record (version, OS, signal, and the in-flight meeting's title and state — never audio, transcript, or notes) to its local diagnostics archive so you can attach it to a bug report. Off by default.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Ayrvo")
                        .font(.ayrvo(14, .semibold))
                    Spacer()
                    if let v = AppVersion.displayVersion {
                        Text(v)
                            .font(.ayrvo(12))
                            .foregroundStyle(.secondary)
                            .help("Version \(v) (build \(AppVersion.buildNumber))")
                    }
                }
                Link("Changelog",
                     destination: AppVersion.changelogURL)
                    .font(.ayrvo(11))
            }

            Section("Reset") {
                Button("Reset to Defaults", role: .destructive) {
                    showResetConfirm = true
                }
                Text("Restores detection, recording, transcription, and appearance settings to their defaults. Meetings and notes are not affected.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { resetToDefaults() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restores detection, recording, transcription, and appearance preferences to their defaults. Your meetings and notes are not affected.")
        }
        .formStyle(.grouped)
        .onAppear {
            micStatus = MicRecorder.permissionGranted
            launchAtLogin = LaunchAtLogin.isOn
            accessibilityTrusted = AccessibilityPermission.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = MicRecorder.permissionGranted
            accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private var accessibilitySettingsDetail: String {
        accessibilityTrusted
            ? "Allowed — reads Zoom speakers and Google Meet captions in Chrome to label who said what in the transcript."
            : "Optional — labels Zoom speakers and Google Meet captions in Chrome. Click Grant, then enable Ayrvo under Accessibility."
    }

    private var systemAudioOK: Bool? { nil }

    private var systemAudioSettingsDetail: String {
        systemAudioError ?? SystemAudioPermission.guidance(previouslyCaptured: systemAudioConfirmed)
    }

    private func requestSystemAudio() {
        requestingSystemAudio = true
        systemAudioError = nil
        Task {
            defer { requestingSystemAudio = false }
            do { try await SystemAudioPermission.request() }
            catch { systemAudioError = error.localizedDescription }
        }
    }

    private func applyLaunchAtLogin() {
        try? LaunchAtLogin.set(launchAtLogin)
        launchAtLogin = LaunchAtLogin.isOn // reflect what actually took effect
    }

    private func resetToDefaults() {
        detectMeetings = true
        autoRecord = false
        autoStopRecording = true
        identifySpeakers = true
        showLiveRecordingCard = true
        defaultTemplate = "Meeting Notes"
        openMainWindowAtLaunch = true
        developerMode = false
        crashDiagnostics = false
        UserDefaults.standard.set(
            AppearanceMode.system.rawValue, forKey: SettingsKey.appearanceMode)
        UserDefaults.standard.set(
            Theme.defaultActionColorHex, forKey: SettingsKey.actionColorHex)
        AyrvoConsoleLog.app("settings reset to defaults")
    }

    private func permissionRow(
        ok: Bool, title: String, detail: String, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            StatusDot(ok: ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ayrvo(12, .medium))
                Text(detail).font(.ayrvo(11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Grant…", action: action).controlSize(.small)
            }
        }
    }
}
