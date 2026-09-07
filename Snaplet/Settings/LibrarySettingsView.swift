import SwiftUI

struct LibrarySettingsView: View {
    let environment: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Keep a local history of captures"),
                       isOn: $settings.preferences.historyEnabled)
            } header: {
                Text(String(localized: "History"))
            } footer: {
                Text(String(localized: "History stores file paths, sizes and recognised text on this Mac. The media itself stays in your output folder — Snaplet never copies it into a database."))
                    .font(.caption)
            }

            Section {
                Button(String(localized: "Open History…")) { environment.showHistory() }
                Button(String(localized: "Clear history and text index…"), role: .destructive) {
                    isConfirmingClear = true
                }
            } footer: {
                Text(String(localized: "Clearing the history removes Snaplet's records only. Your image and video files are left untouched."))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(String(localized: "Clear the history and recognised-text index?"),
                            isPresented: $isConfirmingClear) {
            Button(String(localized: "Clear"), role: .destructive) {
                environment.clearLibrary()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your capture files stay where they are."))
        }
    }
}
