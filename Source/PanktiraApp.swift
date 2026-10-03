//
//  PanktiraApp.swift
//  Panktira
//

import SwiftUI

/// Intercepts Finder/"Open With"/cold-launch file-open requests so they land as a new tab in the
/// app's single window instead of letting AppKit spin up a second window for the same AppState.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let appState else { return }
        for url in urls {
            appState.openExternalFile(at: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PanktiraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    init() {
        // Disable the macOS native window tab bar — we use our own tab system.
        NSWindow.allowsAutomaticWindowTabbing = false
        appDelegate.appState = appState
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Panktira") {
                    showAboutPanel()
                }
            }

            // File menu
            CommandGroup(replacing: .newItem) {
                Button {
                    appState.safeNewDocument()
                } label: {
                    Label("New", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    appState.newTab()
                } label: {
                    Label("New Tab", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("t", modifiers: .command)

                Button {
                    appState.safeOpenFile()
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)

                RecentDocumentsMenu(appState: appState)

                Divider()

                Button {
                    appState.closeActiveTab()
                } label: {
                    Label("Close Tab", systemImage: "xmark.square")
                }
                .keyboardShortcut("w", modifiers: .command)

                Button {
                    appState.selectPreviousTab()
                } label: {
                    Label("Previous Tab", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    appState.selectNextTab()
                } label: {
                    Label("Next Tab", systemImage: "chevron.right")
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button {
                    appState.activeTab.commitEditIfNeeded()
                    appState.activeTab.document.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    appState.activeTab.commitEditIfNeeded()
                    appState.activeTab.document.saveAs()
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // Undo / Redo
            CommandGroup(replacing: .undoRedo) {
                Button {
                    appState.activeTab.document.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.activeTab.document.canUndo)

                Button {
                    appState.activeTab.document.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.activeTab.document.canRedo)
            }

            // Cut / Copy / Paste
            CommandGroup(replacing: .pasteboard) {
                Button {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("x", modifiers: .command)

                Button {
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    } else {
                        appState.activeTab.copySelection()
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)

                Button {
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    } else {
                        appState.activeTab.pasteFromPasteboard()
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)

                Button {
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    } else {
                        appState.activeTab.selectAll()
                    }
                } label: {
                    Label("Select All", systemImage: "selection.pin.in.out")
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            // Table
            CommandMenu("Table") {
                Section("Row") {
                    Button {
                        appState.activeTab.insertRowAbove()
                    } label: {
                        Label("Insert Row Above", systemImage: "arrow.up.to.line")
                    }
                    .keyboardShortcut(KeyEquivalent.upArrow, modifiers: [.command, .option])

                    Button {
                        appState.activeTab.insertRowBelow()
                    } label: {
                        Label("Insert Row Below", systemImage: "arrow.down.to.line")
                    }
                    .keyboardShortcut(KeyEquivalent.downArrow, modifiers: [.command, .option])

                    Button {
                        appState.activeTab.moveRowUp()
                    } label: {
                        Label("Move Row Up", systemImage: "arrow.up")
                    }
                    .keyboardShortcut(KeyEquivalent.upArrow, modifiers: [.control, .option])

                    Button {
                        appState.activeTab.moveRowDown()
                    } label: {
                        Label("Move Row Down", systemImage: "arrow.down")
                    }
                    .keyboardShortcut(KeyEquivalent.downArrow, modifiers: [.control, .option])
                }

                Divider()

                Section("Column") {
                    Button {
                        appState.activeTab.insertColumnBefore()
                    } label: {
                        Label("Insert Column Before", systemImage: "arrow.left.to.line")
                    }
                    .keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [.command, .option])

                    Button {
                        appState.activeTab.insertColumnAfter()
                    } label: {
                        Label("Insert Column After", systemImage: "arrow.right.to.line")
                    }
                    .keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [.command, .option])

                    Button {
                        appState.activeTab.moveColumnLeft()
                    } label: {
                        Label("Move Column Left", systemImage: "arrow.left")
                    }
                    .keyboardShortcut(KeyEquivalent.leftArrow, modifiers: [.control, .option])

                    Button {
                        appState.activeTab.moveColumnRight()
                    } label: {
                        Label("Move Column Right", systemImage: "arrow.right")
                    }
                    .keyboardShortcut(KeyEquivalent.rightArrow, modifiers: [.control, .option])
                }

                Divider()

                Section("Delete") {
                    Button {
                        appState.activeTab.deleteSelectedRows()
                    } label: {
                        Label("Delete Row(s)", systemImage: "minus.circle")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(appState.activeTab.selection == nil || appState.activeTab.selection?.minRow ?? -1 < 0)

                    Button {
                        appState.activeTab.deleteSelectedColumns()
                    } label: {
                        Label("Delete Column(s)", systemImage: "minus.circle")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(appState.activeTab.selection == nil)
                }
            }

            // Find & Replace
            CommandGroup(replacing: .textEditing) {
                Button {
                    appState.activeTab.showFind()
                } label: {
                    Label("Find & Replace…", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button {
                    appState.activeTab.findNext()
                } label: {
                    Label("Find Next", systemImage: "chevron.down")
                }
                .keyboardShortcut("g", modifiers: .command)

                Button {
                    appState.activeTab.findPrevious()
                } label: {
                    Label("Find Previous", systemImage: "chevron.up")
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button {
                    appState.activeTab.replaceCurrent()
                } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                }
                .disabled(appState.activeTab.searchResults.isEmpty || !appState.activeTab.showFindPanel)

                Button {
                    appState.activeTab.replaceAll()
                } label: {
                    Label("Replace All", systemImage: "arrow.left.arrow.right.square")
                }
                .disabled(appState.activeTab.searchResults.isEmpty || !appState.activeTab.showFindPanel)
            }

            // View — Zoom
            CommandGroup(replacing: .toolbar) {
                Button {
                    appState.activeTab.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!appState.activeTab.canZoomIn)

                Button {
                    appState.activeTab.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!appState.activeTab.canZoomOut)

                Button {
                    appState.activeTab.resetZoom()
                } label: {
                    Label("Actual Size", systemImage: "1.magnifyingglass")
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button {
                    appState.selectNextTab()
                } label: {
                    Label("Switch to Next Tab", systemImage: "arrow.right.square")
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button {
                    appState.selectPreviousTab()
                } label: {
                    Label("Switch to Previous Tab", systemImage: "arrow.left.square")
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()
            }

            // Remove system "Show All Tabs" / "Hide Tab Bar" from View menu
            CommandGroup(replacing: .windowArrangement) {}


        }
    }

    private func showAboutPanel() {
        let executableDate = Bundle.main.executableURL.flatMap { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let credits = NSAttributedString(
            string: "Date: \(formatter.string(from: executableDate ?? Date()))",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

// MARK: - Recent Documents Menu

struct RecentDocumentsMenu: View {
    var appState: AppState

    var body: some View {
        Menu {
            ForEach(recentURLs, id: \.self) { url in
                Button {
                    appState.safeLoadFile(at: url)
                } label: {
                    Label(url.lastPathComponent, systemImage: "doc")
                }
            }

            if !recentURLs.isEmpty {
                Divider()
            }

            Button {
                NSDocumentController.shared.clearRecentDocuments(nil)
            } label: {
                Label("Clear Menu", systemImage: "trash")
            }
        } label: {
            Label("Open Recent", systemImage: "clock")
        }
    }

    private var recentURLs: [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }
}
