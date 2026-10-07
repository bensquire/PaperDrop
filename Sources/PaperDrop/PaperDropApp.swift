import ScanKit
import SwiftUI

@main
struct PaperDropApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("PaperDrop") {
            ContentView(model: model)
        }
        // Hides the title and the title bar's backing
        // (/documentation/swiftui/windowstyle/hiddentitlebar); the window
        // keeps its name for the Window menu and Mission Control.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Replaces File > New Window, which took ⌘N from Scan Page and
            // opened a second window onto the same scanner and pages; one
            // window suits an app built on one hardware device
            // (/documentation/swiftui/window).
            CommandGroup(replacing: .newItem) {
                Button("Scan Page") { model.scanPage() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.busy || model.selectedScanner == nil)
                Button("Save PDF…") { model.savePDF() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.pages.isEmpty || model.busy)
                Button("Cancel Scan") { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.scanning)
                Divider()
                Button("Discard Pages") { model.discardAll() }
                    .disabled(model.pages.isEmpty || model.busy)
            }
            // Every action in the window is in the menu bar too.
            CommandMenu("Scanner") {
                Button("Search for Scanners") { model.discoverScanners() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.discovering)
                Divider()
                ScanSettingsItems(model: model)
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var choosingFolder = false

    /// The sizes a page can snap to, from the table that does the snapping.
    private let snapSizes = Pipeline.paperSizesMM.map(\.name).joined(separator: "/")

    var body: some View {
        // The grouped style is System Settings' own look
        // (/documentation/swiftui/formstyle/grouped).
        Form {
            Picker("Default resolution", selection: $model.defaultDpi) {
                ForEach(model.availableDPIs, id: \.self) { Text("\($0) dpi").tag($0) }
            }
            Toggle("Snap pages to standard paper sizes (\(snapSizes))", isOn: $model.paperSnap)
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
                    Button("Choose…") { choosingFolder = true }
                        .fileImporter(
                            isPresented: $choosingFolder, allowedContentTypes: [.folder]
                        ) { result in
                            if case let .success(url) = result {
                                model.archivePath = url.path
                            }
                        }
                        // /documentation/swiftui/view/filedialogdefaultdirectory(_:)
                        .fileDialogDefaultDirectory(URL(fileURLWithPath: model.archivePath))
                }
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls, so it doesn't size the window; at five
        // rows it needn't scroll, and the window fits the rows.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 480)
    }
}
