//
//  ContentView.swift
//  Panktira
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
                .background(.regularMaterial)

            Divider()

            // Active tab content
            TabContentView(appState: appState, tabState: appState.activeTab)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .background(WindowCloseInterceptor(appState: appState))
        .background(KeyboardEventHandler(appState: appState))
        .navigationTitle(appState.activeTab.document.displayName)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabBarItem(
                        tab: tab,
                        isActive: index == appState.activeTabIndex,
                        onSelect: {
                            appState.switchToTab(at: index)
                        },
                        onClose: {
                            appState.closeTab(at: index)
                        }
                    )
                }

                // New tab button
                Button(action: { appState.newTab() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab")
                .padding(.leading, 4)

                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 30)
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async {
                    appState.safeLoadFile(at: url)
                }
            }
        }
        return true
    }
}

// MARK: - Tab Bar Item

private struct TabBarItem: View {
    @Bindable var tab: TabState
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            // Modified indicator
            if tab.document.isModified {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
            }

            Text(tab.tabDisplayName)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            // Close button (visible on hover or when active)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isActive ? Color.gray.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Tab Content View

/// The content for a single tab — toolbar, formula bar, find panel, spreadsheet, status bar.
private struct TabContentView: View {
    @Bindable var appState: AppState
    @Bindable var tabState: TabState
    @State private var addressText = ""
    @State private var addressBeforeEditing = ""
    @State private var isEditingAddress = false
    @State private var navigationRequest: CellNavigationRequest?

    var body: some View {
        VStack(spacing: 0) {
            // Formula bar
            formulaBar
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.regularMaterial)

            Divider()

            // Find & Replace toolbar
            if tabState.showFindPanel {
                FindReplaceContentView(tabState: tabState)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Spreadsheet
            SpreadsheetView(
                document: tabState.document,
                highlightedCells: tabState.highlightedCells,
                highlightedRows: tabState.highlightedRows,
                focusedSearchCell: tabState.focusedSearchCell,
                navigationRequest: navigationRequest,
                selection: Binding(
                    get: { tabState.selection },
                    set: { tabState.selection = $0 }
                ),
                extraSelections: Binding(
                    get: { tabState.extraSelections },
                    set: { tabState.extraSelections = $0 }
                ),
                isEditing: Binding(
                    get: { tabState.isEditing },
                    set: { tabState.isEditing = $0 }
                ),
                editText: $tabState.editText,
                columnWidths: $tabState.columnWidths,
                cellHeight: tabState.scaledCellHeight,
                rowNumberWidth: tabState.scaledRowNumberWidth,
                bodyFontSize: tabState.scaledBodyFontSize,
                captionFontSize: tabState.scaledCaptionFontSize,
                zoomLevel: tabState.zoomLevel,
                onCommitEdit: { tabState.commitEdit() },
                onCancelEdit: { tabState.cancelEdit() },
                onBeginEditing: { tabState.beginEditing() },
                onToggleCellSelection: { row, col in tabState.toggleCellSelection(row: row, column: col) }
            )

            Divider()

            // Status bar
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.regularMaterial)
        }
        .animation(.easeInOut(duration: 0.2), value: tabState.showFindPanel)
    }

    // MARK: - Formula Bar

    @FocusState private var formulaBarFocused: Bool
    @FocusState private var addressFieldFocused: Bool

    private func navigateToEnteredAddress() {
        if let position = tabState.selectCell(atAddress: addressText) {
            addressText = tabState.selectedCellAddress ?? ""
            addressBeforeEditing = addressText
            navigationRequest = CellNavigationRequest(position: position)
        } else {
            addressText = addressBeforeEditing
        }
        addressFieldFocused = false
        isEditingAddress = false
    }

    private var formulaBar: some View {
        HStack(spacing: 8) {
            if isEditingAddress {
                TextField("Cell", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: tabState.scaledBodyFontSize, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(width: 64)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.background, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentColor, lineWidth: 1)
                    )
                    .focused($addressFieldFocused)
                    .onSubmit { navigateToEnteredAddress() }
                    .onExitCommand {
                        addressText = addressBeforeEditing
                        addressFieldFocused = false
                        isEditingAddress = false
                    }
            } else {
                Text(addressText.isEmpty ? "—" : addressText)
                    .font(.system(size: tabState.scaledBodyFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(addressText.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(width: 64)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.background, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.gray.opacity(0.25), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabState.commitEditIfNeeded()
                        isEditingAddress = true
                        DispatchQueue.main.async {
                            addressFieldFocused = true
                        }
                    }
            }

            Divider()
                .frame(height: 18)

            if tabState.isEditing {
                TextField("", text: $tabState.editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: tabState.scaledBodyFontSize))
                    .focused($formulaBarFocused)
                    .onSubmit {
                        tabState.commitEdit()
                    }
                    .onExitCommand {
                        tabState.cancelEdit()
                    }
            } else if tabState.selection != nil {
                Text(tabState.selectedCellValue)
                    .font(.system(size: tabState.scaledBodyFontSize))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabState.beginEditing()
                    }
            } else {
                Text("No cell selected")
                    .font(.system(size: tabState.scaledBodyFontSize))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .onAppear {
            addressText = tabState.selectedCellAddress ?? ""
            addressBeforeEditing = addressText
        }
        .onChange(of: tabState.selectedCellAddress) { _, address in
            // A selection change always wins over an unfinished address edit.
            addressFieldFocused = false
            isEditingAddress = false
            addressText = address ?? ""
            addressBeforeEditing = addressText
        }
        .onChange(of: addressFieldFocused) { _, focused in
            if focused {
                addressBeforeEditing = tabState.selectedCellAddress ?? ""
                addressText = addressBeforeEditing
            } else {
                isEditingAddress = false
            }
        }
        .onChange(of: tabState.isEditing) { _, editing in
            if editing {
                formulaBarFocused = true
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Image(systemName: "tablecells")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(tabState.document.rowCount) rows × \(tabState.document.columnCount) columns")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                tabState.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!tabState.canZoomOut)
            .help("Zoom Out (⌘-)")

            Text(tabState.zoomPercentageText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .center)

            Button {
                tabState.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!tabState.canZoomIn)
            .help("Zoom In (⌘+)")
        }
    }
}

// MARK: - Window Close Interceptor

private struct WindowCloseInterceptor: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        let appState: AppState
        private weak var originalDelegate: NSWindowDelegate?

        init(appState: AppState) {
            self.appState = appState
        }

        func install(on window: NSWindow) {
            originalDelegate = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // Check all tabs for unsaved changes
            for tab in appState.tabs {
                tab.commitEditIfNeeded()
                guard tab.document.isModified else { continue }

                let alert = NSAlert()
                alert.messageText = "Do you want to save changes to \"\(tab.tabDisplayName)\"?"
                alert.informativeText = "Your changes will be lost if you don't save them."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Save")
                alert.addButton(withTitle: "Don't Save")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                switch response {
                case .alertFirstButtonReturn:
                    guard tab.document.save() else { return false }
                case .alertSecondButtonReturn:
                    continue
                default:
                    return false
                }
            }
            return true
        }

        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }
    }
}

// MARK: - Keyboard Event Handler

private struct KeyboardEventHandler: NSViewRepresentable {
    let appState: AppState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(appState: appState)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var monitor: Any?

        func start(appState: AppState) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let tabState = appState.activeTab

                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    if event.keyCode == 53 && tabState.isEditing {
                        tabState.cancelEdit()
                        event.window?.makeFirstResponder(event.window?.contentView)
                        return nil
                    }
                    return event
                }

                let modifiers = event.modifierFlags
                let shiftHeld = modifiers.contains(.shift)
                let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

                // Let command-modified arrows reach SwiftUI's menu key equivalents.
                // This includes the Control-Option shortcuts for moving rows and columns.
                if !modifiers.intersection(commandModifiers).isEmpty {
                    return event
                }

                switch event.keyCode {
                case 126: // Up arrow
                    guard !tabState.isEditing else { return event }
                    if shiftHeld {
                        tabState.extendSelectionUp()
                    } else {
                        tabState.moveSelectionUp()
                    }
                    return nil
                case 125: // Down arrow
                    guard !tabState.isEditing else { return event }
                    if shiftHeld {
                        tabState.extendSelectionDown()
                    } else {
                        tabState.moveSelectionDown()
                    }
                    return nil
                case 123: // Left arrow
                    guard !tabState.isEditing else { return event }
                    if shiftHeld {
                        tabState.extendSelectionLeft()
                    } else {
                        tabState.moveSelectionLeft()
                    }
                    return nil
                case 124: // Right arrow
                    guard !tabState.isEditing else { return event }
                    if shiftHeld {
                        tabState.extendSelectionRight()
                    } else {
                        tabState.moveSelectionRight()
                    }
                    return nil
                case 36: // Return
                    if tabState.isEditing {
                        tabState.commitEdit()
                    } else {
                        tabState.beginEditing()
                    }
                    return nil
                case 53: // Escape
                    if tabState.isEditing {
                        tabState.cancelEdit()
                        return nil
                    }
                    // Collapse multi-cell selection to anchor
                    if let sel = tabState.selection, !sel.isSingleCell {
                        tabState.extraSelections.removeAll()
                        tabState.selection = .single(row: sel.anchorRow, column: sel.anchorColumn)
                        return nil
                    }
                    // Clear extra selections if any
                    if !tabState.extraSelections.isEmpty {
                        tabState.extraSelections.removeAll()
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
