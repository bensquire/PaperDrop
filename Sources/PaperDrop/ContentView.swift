import ScanKit
import SwiftUI

/// Gentle hover feedback — macOS button styles give little or none.
/// Inert while the control is disabled.
struct HoverHighlight: ViewModifier {
    var scale: CGFloat = 1.02
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let active = hovering && isEnabled
        content
            .brightness(active ? 0.07 : 0)
            .scaleEffect(active ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: active)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(scale: CGFloat = 1.02) -> some View {
        modifier(HoverHighlight(scale: scale))
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.pages.isEmpty {
                emptyState
            } else {
                pageGrid
                Divider()
                saveBar
            }
            statusBar
        }
        .frame(minWidth: 560, minHeight: 460)
        .toolbar { toolbarContent }
        .onAppear { model.discoverScanners() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            if model.discovering {
                ProgressView()
                Text("Looking for scanners…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if model.scanners.isEmpty {
                noScannerState
            } else {
                readyToScanState
            }
            Spacer()
            if !model.discovering {
                // Content states sit slightly above centre; the bare
                // spinner looks off unless truly centred.
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noScannerState: some View {
        VStack(spacing: 0) {
            Image(systemName: "scanner")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("No scanner found")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            Text("Check it's connected and powered on")
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.top, 6)
            Button {
                model.discoverScanners()
            } label: {
                Label("Search Again", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .hoverHighlight()
            .padding(.top, 24)
        }
    }

    private var readyToScanState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Place a document on the scanner")
                .font(.title3)
                .foregroundStyle(.secondary)
            if model.scanning {
                ProgressView()
                cancelScanButton("Cancel Scan", large: true)
            } else {
                Button(action: model.scanPage) {
                    Label("Scan First Page", systemImage: "scanner")
                        .font(.title3)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .hoverHighlight()
                .disabled(model.busy || model.selectedScanner == nil)
                .keyboardShortcut(.defaultAction)
            }
            if model.selectedScanner == nil {
                Text("Choose a scanner in the toolbar")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Page grid

    private let columns = [
        GridItem(
            .adaptive(minimum: 150, maximum: 190),
            spacing: 16
        )
    ]

    @State private var draggingID: UUID?

    private var pageGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { idx, page in
                    PageCell(page: page, number: idx + 1) {
                        model.deletePage(page.id)
                    }
                    .opacity(draggingID == page.id ? 0.4 : 1)
                    .onDrag {
                        draggingID = page.id
                        return NSItemProvider(object: page.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: PageReorderDelegate(
                            targetID: page.id,
                            draggingID: $draggingID,
                            model: model
                        )
                    )
                }
                scanNextCell
            }
            .padding(16)
        }
    }

    private var scanNextCell: some View {
        Button(action: model.scanPage) {
            VStack(spacing: 10) {
                if model.scanning {
                    ProgressView()
                    Text("Scanning…").font(.callout)
                    cancelScanButton("Cancel", large: false)
                } else {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 34, weight: .thin))
                    Text("Scan Next Page").font(.callout)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.tertiary)
            )
        }
        .buttonStyle(.plain)
        .hoverHighlight(scale: 1.01)
        .disabled(model.busy)
        .keyboardShortcut(.defaultAction)
    }

    private func cancelScanButton(_ title: String, large: Bool) -> some View {
        Button(role: .destructive) {
            model.cancelScan()
        } label: {
            Label(title, systemImage: "stop.circle")
                .padding(.horizontal, large ? 10 : 0)
                .padding(.vertical, large ? 4 : 0)
        }
        .buttonStyle(.bordered)
        .controlSize(large ? .large : .regular)
        .hoverHighlight()
    }

    // MARK: Save bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            TextField("Document name", text: $model.docName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.savePDF() }
            Toggle("OCR", isOn: $model.ocrEnabled)
                .toggleStyle(.checkbox)
                .help("Add an invisible, searchable text layer")
            Toggle("Uniform pages", isOn: $model.uniformPages)
                .toggleStyle(.checkbox)
                .help(
                    "Give every page the same size (the largest in the "
                        + "document), centring smaller scans"
                )
            Button {
                model.savePDF()
            } label: {
                Label(
                    model.saving ? "Saving…" : "Save PDF",
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.borderedProminent)
            .hoverHighlight()
            .disabled(model.busy)
            Button("Discard", role: .destructive) { model.discardAll() }
                .hoverHighlight()
                .disabled(model.busy)
        }
        .padding(12)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.scanning || model.saving {
                ProgressView().controlSize(.small)
            }
            if let err = model.errorText {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(err)
            } else {
                Text(model.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !model.pages.isEmpty {
                Text("\(model.pages.count) page\(model.pages.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Scanner", selection: $model.selectedScannerID) {
                if model.scanners.isEmpty {
                    Text(model.discovering ? "Searching…" : "No scanners")
                        .tag(String?.none)
                }
                ForEach(model.scanners) { s in
                    Text(s.name).tag(String?.some(s.id))
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .frame(minWidth: 170)

            Button {
                model.discoverScanners()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Look for scanners again")
            .disabled(model.discovering)

            Picker("Resolution", selection: $model.dpi) {
                ForEach(model.availableDPIs, id: \.self) { d in
                    Text("\(d) dpi").tag(d)
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .help("Scan resolution")

            Picker("Paper", selection: $model.paperChoice) {
                Text("Auto size").tag("auto")
                Divider()
                ForEach(AppModel.fixedPapers, id: \.key) { paper in
                    Text(paper.label).tag(paper.key)
                }
            }
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .help("Auto-detect the paper size, or force a specific one")

            // Only meaningful alongside a forced size — auto-detect derives
            // orientation from the page it found.
            Picker("Orientation", selection: $model.paperLandscape) {
                Image(systemName: "rectangle.portrait").tag(false)
                Image(systemName: "rectangle").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(model.fixedPaperMM == nil)
            .help("Portrait or landscape for the forced paper size")

            // Segmented control; per-segment .help doesn't work reliably on
            // macOS, so one combined tooltip describes both.
            Picker("Mode", selection: $model.photoMode) {
                Label("Document", systemImage: "doc.text").tag(false)
                Label("Photo", systemImage: "photo").tag(true)
            }
            .pickerStyle(.segmented)
            .help(
                "Document (left): pure black & white, tiny PDF. "
                    + "Photo (right): grayscale JPEG pages, keeps shading.")
        }
    }
}

// MARK: - Drag reorder

struct PageReorderDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let model: AppModel

    func dropEntered(info _: DropInfo) {
        if let dragging = draggingID {
            model.movePage(id: dragging, before: targetID)
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

// MARK: - Page cell

struct PageCell: View {
    let page: PageItem
    let number: Int
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = page.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 200)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Remove this page")
                    .hoverHighlight(scale: 1.15)
                }
            }
            Text("Page \(number) · \(page.mmSize) · \(page.sizeLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove Page", role: .destructive, action: onDelete)
        }
    }
}
