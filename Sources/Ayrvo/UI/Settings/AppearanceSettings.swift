import AppKit
import SwiftUI

struct AppearanceSettings: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKey.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.actionColorHex) private var actionColorHex = Theme.defaultActionColorHex

    private var baseActionColor: Color {
        Color(hex: actionColorHex) ?? Theme.mediumGreen
    }

    private var actionColor: Color {
        Theme.prominentAction(baseActionColor, scheme: scheme)
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Choose light or dark mode, or follow your Mac's system setting.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }

            Section("Action color") {
                HStack {
                    Button("Record") {}
                        .buttonStyle(.borderedProminent)
                        .tint(actionColor)
                        .allowsHitTesting(false)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 10) {
                    ForEach(ActionColorPreset.allCases) { preset in
                        Button {
                            actionColorHex = preset.rawValue
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if actionColorHex.uppercased() == preset.rawValue {
                                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                        .accessibilityLabel("Action color: \(preset.name)")
                        .accessibilityValue(actionColorHex.uppercased() == preset.rawValue ? "Selected" : "Not selected")
                    }
                }

                ColorPicker("Custom color", selection: Binding(
                    get: { actionColor },
                    set: { newColor in
                        if let hex = newColor.hexString {
                            actionColorHex = hex
                        }
                    }
                ))
                if actionColorHex != Theme.defaultActionColorHex {
                    HStack {
                        Spacer()
                        Button("Reset to default") {
                            actionColorHex = Theme.defaultActionColorHex
                        }
                        .controlSize(.small)
                        .help("Reset the action color to the default Medium green")
                        .accessibilityLabel("Reset the action color to the default Medium green")
                    }
                }
                Text("Used for Record, Save, and other prominent buttons. Adjusted automatically for readable labels in each theme.")
                    .font(.ayrvo(11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
