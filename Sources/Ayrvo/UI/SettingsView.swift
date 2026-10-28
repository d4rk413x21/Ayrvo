import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.developerMode) private var developerMode = false
    @State private var selection: SettingsSection = .general

    private enum SettingsSection: Hashable {
        case general, intelligence, transcription, templates, integrations, calendar, appearance, debug
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("General", systemImage: "gearshape", value: SettingsSection.general) {
                GeneralSettings()
            }
            Tab("Intelligence", systemImage: "sparkles", value: SettingsSection.intelligence) {
                IntelligenceSettings()
            }
            Tab("Transcription", systemImage: "waveform", value: SettingsSection.transcription) {
                TranscriptionSettings()
            }
            Tab("Templates", systemImage: "doc.text", value: SettingsSection.templates) {
                TemplateSettings()
            }
            Tab("Integrations", systemImage: "link", value: SettingsSection.integrations) {
                LinearSettings()
            }
            Tab("Calendar", systemImage: "calendar", value: SettingsSection.calendar) {
                CalendarSettings()
            }
            Tab("Appearance", systemImage: "paintbrush", value: SettingsSection.appearance) {
                AppearanceSettings()
            }
            if developerMode {
                Tab("Debug", systemImage: "ladybug", value: SettingsSection.debug) {
                    DebugSettings()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 720, idealWidth: 800, minHeight: 500, idealHeight: 620)
        .onChange(of: developerMode) { selection = .general }
    }
}

struct StatusDot: View {
    /// true = green, false = orange, nil = neutral (informational).
    let ok: Bool?

    init(ok: Bool?) { self.ok = ok }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .padding(.top, 3)
            .accessibilityLabel("Status")
            .accessibilityValue(ok.map { $0 ? "Available" : "Unavailable" } ?? "Not verified")
    }

    private var color: Color {
        switch ok {
        case .some(true): Theme.mint
        case .some(false): Color.orange
        case .none: Color.secondary.opacity(0.4)
        }
    }
}
