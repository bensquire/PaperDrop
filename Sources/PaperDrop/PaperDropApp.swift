import SwiftUI

@main
struct PaperDropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("PaperDrop") {
            ContentView()
                .environmentObject(model)
        }
        // Hides the title text; the window keeps its name for the Window
        // menu and Mission Control.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Page") { model.scanPage() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.busy || model.selectedScanner == nil)
                Button("Save PDF…") { model.savePDF() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.pages.isEmpty || model.busy)
                Button("Cancel Scan") { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.scanning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Picker("Default resolution", selection: $model.defaultDpi) {
                ForEach(model.availableDPIs, id: \.self) { Text("\($0) dpi").tag($0) }
            }
            Toggle(
                "Snap pages to standard paper sizes (A4/A5/A6/Letter)",
                isOn: $model.paperSnap
            )
            Toggle("Add searchable text layer (OCR)", isOn: $model.ocrEnabled)
            Toggle(
                "Uniform page size across a document",
                isOn: $model.uniformPages
            )
            LabeledContent("Archive folder") {
                HStack {
                    Text(model.archivePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = URL(fileURLWithPath: model.archivePath)
                        if panel.runModal() == .OK, let url = panel.url {
                            model.archivePath = url.path
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
