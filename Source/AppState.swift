//
//  AppState.swift
//  Panktira
//

import SwiftUI
import AppKit

// MARK: - CellRange

/// A rectangular cell selection defined by anchor and extent corners.
struct CellRange: Equatable {
    /// The cell where selection originated (the "active" cell for editing).
    var anchorRow: Int      // -1 = header
    var anchorColumn: Int

    /// The cell where selection was extended to.
    var extentRow: Int      // -1 = header
    var extentColumn: Int

    /// Normalized bounds (inclusive, always min...max).
    var minRow: Int { min(anchorRow, extentRow) }
    var maxRow: Int { max(anchorRow, extentRow) }
    var minColumn: Int { min(anchorColumn, extentColumn) }
    var maxColumn: Int { max(anchorColumn, extentColumn) }

    /// Whether this range covers exactly one cell.
    var isSingleCell: Bool {
        anchorRow == extentRow && anchorColumn == extentColumn
    }

    /// Whether a given cell position falls within this range.
    func contains(row: Int, column: Int) -> Bool {
        row >= minRow && row <= maxRow && column >= minColumn && column <= maxColumn
    }

    /// Whether a given row has any cells in the range.
    func containsRow(_ row: Int) -> Bool {
        row >= minRow && row <= maxRow
    }

    /// Whether a given column has any cells in the range.
    func containsColumn(_ column: Int) -> Bool {
        column >= minColumn && column <= maxColumn
    }

    /// Create a single-cell range.
    static func single(row: Int, column: Int) -> CellRange {
        CellRange(anchorRow: row, anchorColumn: column, extentRow: row, extentColumn: column)
    }
}

// MARK: - TabState

/// Holds all state that is unique to a single tab: its document, selection,
/// editing state, find/replace, zoom, and column widths.
@Observable
final class TabState: Identifiable {
    let id = UUID()

    // MARK: - Document

    var document = CSVDocument()

    // MARK: - Zoom

    var zoomLevel: CGFloat = 1.0

    private static let zoomStep: CGFloat = 0.1
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 2.0

    var zoomPercentageText: String {
        "\(Int(round(zoomLevel * 100)))%"
    }

    var canZoomIn: Bool { zoomLevel < Self.maxZoom - 0.001 }
    var canZoomOut: Bool { zoomLevel > Self.minZoom + 0.001 }

    func zoomIn() {
        zoomLevel = min(Self.maxZoom, ((zoomLevel + Self.zoomStep) * 10).rounded() / 10)
    }

    func zoomOut() {
        zoomLevel = max(Self.minZoom, ((zoomLevel - Self.zoomStep) * 10).rounded() / 10)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    // MARK: - Scaled Dimensions

    static let baseCellHeight: CGFloat = 30
    static let baseRowNumberWidth: CGFloat = 50
    static let baseBodyFontSize: CGFloat = 12
    static let baseCaptionFontSize: CGFloat = 10

    var scaledCellHeight: CGFloat { Self.baseCellHeight * zoomLevel }
    var scaledRowNumberWidth: CGFloat { Self.baseRowNumberWidth * zoomLevel }
    var scaledBodyFontSize: CGFloat { Self.baseBodyFontSize * zoomLevel }
    var scaledCaptionFontSize: CGFloat { Self.baseCaptionFontSize * zoomLevel }
    var scaledMinimumColumnWidth: CGFloat { Self.minimumColumnWidth * zoomLevel }
    var scaledDefaultColumnWidth: CGFloat { Self.defaultColumnWidth * zoomLevel }

    // MARK: - Column Widths

    static let defaultColumnWidth: CGFloat = 120
    static let minimumColumnWidth: CGFloat = 40

    var columnWidths: [CGFloat] = []

    func widthForColumn(_ index: Int) -> CGFloat {
        guard index >= 0, index < columnWidths.count else { return Self.defaultColumnWidth }
        return columnWidths[index]
    }

    /// Ensure columnWidths array matches the document's column count.
    func syncColumnWidths() {
        let count = document.columnCount
        while columnWidths.count < count {
            columnWidths.append(Self.defaultColumnWidth)
        }
        if columnWidths.count > count {
            columnWidths = Array(columnWidths.prefix(count))
        }
    }

    /// Reset all column widths to default for the current document.
    func resetColumnWidths() {
        columnWidths = Array(repeating: Self.defaultColumnWidth, count: document.columnCount)
    }

    // MARK: - Selection

    /// The current cell selection range, or nil if nothing is selected.
    var selection: CellRange? = nil

    /// Additional disjoint cells selected via Cmd+click.
    var extraSelections: Set<CellPosition> = []

    /// Whether a cell is selected (in the range or in extra selections).
    func isCellSelected(row: Int, column: Int) -> Bool {
        if selection?.contains(row: row, column: column) == true { return true }
        return extraSelections.contains(CellPosition(row: row, column: column))
    }

    /// Whether a row has any selected cells.
    func isRowSelected(_ row: Int) -> Bool {
        if selection?.containsRow(row) == true { return true }
        return extraSelections.contains(where: { $0.row == row })
    }

    /// Whether a column has any selected cells.
    func isColumnSelected(_ column: Int) -> Bool {
        if selection?.containsColumn(column) == true { return true }
        return extraSelections.contains(where: { $0.column == column })
    }

    /// The anchor row of the current selection (backward-compat shim).
    var selectedRow: Int? {
        get { selection?.anchorRow }
        set {
            if let newValue {
                if var sel = selection {
                    sel.anchorRow = newValue
                    sel.extentRow = newValue
                    selection = sel
                } else {
                    selection = .single(row: newValue, column: 0)
                }
            } else {
                selection = nil
            }
        }
    }

    /// The anchor column of the current selection (backward-compat shim).
    var selectedColumn: Int? {
        get { selection?.anchorColumn }
        set {
            if let newValue {
                if var sel = selection {
                    sel.anchorColumn = newValue
                    sel.extentColumn = newValue
                    selection = sel
                } else {
                    selection = .single(row: 0, column: newValue)
                }
            } else {
                selection = nil
            }
        }
    }

    /// Selects A1 when the document contains at least one data cell.
    func selectFirstCell() {
        if document.rowCount > 0, document.columnCount > 0 {
            selection = .single(row: 0, column: 0)
        } else {
            selection = nil
        }
        extraSelections.removeAll()
    }

    /// Select a single cell, clearing any range and extra selections.
    func selectCell(row: Int, column: Int) {
        selection = .single(row: row, column: column)
        extraSelections.removeAll()
    }

    /// Toggle a cell in/out of the extra selections (Cmd+click).
    func toggleCellSelection(row: Int, column: Int) {
        let pos = CellPosition(row: row, column: column)
        if extraSelections.contains(pos) {
            extraSelections.remove(pos)
            // If we removed the anchor cell, just leave the range as-is
        } else if selection?.contains(row: row, column: column) == true,
                  selection?.isSingleCell == true {
            // Cmd+clicking the only selected cell — deselect it
            selection = nil
            extraSelections.removeAll()
        } else {
            // If there's a current range, absorb it into extras first time
            if let sel = selection {
                // Flatten the current range into extras if not already done
                if extraSelections.isEmpty && !sel.isSingleCell {
                    for r in sel.minRow...sel.maxRow {
                        for c in sel.minColumn...sel.maxColumn {
                            extraSelections.insert(CellPosition(row: r, column: c))
                        }
                    }
                } else if extraSelections.isEmpty {
                    extraSelections.insert(CellPosition(row: sel.anchorRow, column: sel.anchorColumn))
                }
            }
            extraSelections.insert(pos)
            // Move anchor to the newly toggled cell
            selection = .single(row: row, column: column)
        }
    }

    /// Extend the current selection range to include the given cell.
    func extendSelection(toRow row: Int, toColumn column: Int) {
        extraSelections.removeAll()
        if var sel = selection {
            sel.extentRow = row
            sel.extentColumn = column
            selection = sel
        } else {
            selection = .single(row: row, column: column)
        }
    }

    /// Select all data cells.
    func selectAll() {
        guard document.rowCount > 0, document.columnCount > 0 else { return }
        selection = CellRange(
            anchorRow: 0,
            anchorColumn: 0,
            extentRow: document.rowCount - 1,
            extentColumn: document.columnCount - 1
        )
        extraSelections.removeAll()
    }

    /// Selects a data cell from an A1-style address and returns its position when valid.
    func selectCell(atAddress address: String) -> CellPosition? {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let letters = normalized.prefix { $0.isASCII && $0.isLetter }
        let digits = normalized.dropFirst(letters.count)

        guard !letters.isEmpty,
              !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let rowNumber = Int(digits),
              rowNumber > 0 else { return nil }

        var columnNumber = 0
        for scalar in letters.unicodeScalars {
            let value = Int(scalar.value) - Int(UnicodeScalar("A").value) + 1
            let (multiplied, multiplicationOverflow) = columnNumber.multipliedReportingOverflow(by: 26)
            let (next, additionOverflow) = multiplied.addingReportingOverflow(value)
            guard !multiplicationOverflow, !additionOverflow else { return nil }
            columnNumber = next
        }

        let position = CellPosition(row: rowNumber - 1, column: columnNumber - 1)
        guard position.row < document.rowCount,
              position.column < document.columnCount else { return nil }

        selectCell(row: position.row, column: position.column)
        return position
    }

    /// Display label for the currently selected cell, e.g. "A1", "B", or "A1:C3".
    var selectedCellAddress: String? {
        guard let sel = selection else { return nil }
        let anchorLetter = CSVDocument.columnLetter(for: sel.anchorColumn)
        if sel.anchorRow == -1 && sel.isSingleCell { return anchorLetter }
        let anchorAddr = sel.anchorRow == -1 ? anchorLetter : "\(anchorLetter)\(sel.anchorRow + 1)"

        if sel.isSingleCell { return anchorAddr }

        let extentLetter = CSVDocument.columnLetter(for: sel.extentColumn)
        let extentAddr = sel.extentRow == -1 ? extentLetter : "\(extentLetter)\(sel.extentRow + 1)"
        return "\(anchorAddr):\(extentAddr)"
    }

    /// The current text value of the anchor cell (read-only).
    var selectedCellValue: String {
        guard let sel = selection else { return "" }
        if sel.anchorRow == -1 {
            return document.headerValue(column: sel.anchorColumn)
        }
        return document.cellValue(row: sel.anchorRow, column: sel.anchorColumn)
    }

    /// Copies the active cell's value to the system pasteboard.
    func copySelectedCell() {
        guard selection != nil else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedCellValue, forType: .string)
    }

    // MARK: - Editing

    var isEditing: Bool = false
    var editText: String = ""

    func beginEditing() {
        guard selectedRow != nil, selectedColumn != nil else { return }
        editText = selectedCellValue
        isEditing = true
    }

    func commitEdit() {
        guard isEditing else { return }
        guard let col = selectedColumn, let row = selectedRow else {
            isEditing = false
            return
        }
        if row == -1 {
            document.updateHeader(column: col, value: editText)
        } else {
            document.updateCell(row: row, column: col, value: editText)
        }
        isEditing = false
    }

    func cancelEdit() {
        isEditing = false
        editText = ""
    }

    /// Flush any in-flight cell edit into the document model.
    /// Safe to call even when not editing (no-op).
    func commitEditIfNeeded() {
        guard isEditing else { return }
        commitEdit()
    }

    // MARK: - Arrow Key Navigation

    func moveSelectionUp() {
        guard let sel = selection else { return }
        extraSelections.removeAll()
        let row = sel.anchorRow
        if row == -1 { return }
        let col = sel.anchorColumn
        let newRow = row == 0 ? -1 : row - 1
        selection = .single(row: newRow, column: col)
    }

    func moveSelectionDown() {
        extraSelections.removeAll()
        guard let sel = selection else {
            selection = .single(row: 0, column: 0)
            return
        }
        let row = sel.anchorRow
        let col = sel.anchorColumn
        if row == -1 {
            selection = .single(row: 0, column: col)
        } else if row < document.rowCount - 1 {
            selection = .single(row: row + 1, column: col)
        }
    }

    func moveSelectionLeft() {
        guard let sel = selection else { return }
        extraSelections.removeAll()
        if sel.anchorColumn > 0 {
            selection = .single(row: sel.anchorRow, column: sel.anchorColumn - 1)
        }
    }

    func moveSelectionRight() {
        guard let sel = selection else { return }
        extraSelections.removeAll()
        if sel.anchorColumn < document.columnCount - 1 {
            selection = .single(row: sel.anchorRow, column: sel.anchorColumn + 1)
        }
    }

    // MARK: - Shift+Arrow Extend Selection

    func extendSelectionUp() {
        guard var sel = selection else { return }
        if sel.extentRow == -1 { return }
        sel.extentRow = sel.extentRow == 0 ? -1 : sel.extentRow - 1
        selection = sel
    }

    func extendSelectionDown() {
        guard var sel = selection else { return }
        if sel.extentRow == -1 {
            sel.extentRow = 0
        } else if sel.extentRow < document.rowCount - 1 {
            sel.extentRow += 1
        }
        selection = sel
    }

    func extendSelectionLeft() {
        guard var sel = selection else { return }
        if sel.extentColumn > 0 {
            sel.extentColumn -= 1
        }
        selection = sel
    }

    func extendSelectionRight() {
        guard var sel = selection else { return }
        if sel.extentColumn < document.columnCount - 1 {
            sel.extentColumn += 1
        }
        selection = sel
    }

    // MARK: - Find & Replace

    var showFindPanel = false
    var searchText = ""
    var replaceText = ""
    var searchOptions = SearchOptions()
    var searchResults: [CSVDocument.CellAddress] = []
    var currentSearchIndex = 0

    var highlightedCells: Set<CellPosition> {
        Set(searchResults.map { CellPosition(row: $0.row, column: $0.column) })
    }

    var highlightedRows: Set<Int> {
        Set(searchResults.map(\.row))
    }

    var focusedSearchCell: CellPosition? {
        guard !searchResults.isEmpty,
              currentSearchIndex >= 0,
              currentSearchIndex < searchResults.count else { return nil }
        let addr = searchResults[currentSearchIndex]
        return CellPosition(row: addr.row, column: addr.column)
    }

    func showFind() {
        showFindPanel = true
    }

    func dismissFind() {
        showFindPanel = false
        searchText = ""
        replaceText = ""
        searchResults = []
        currentSearchIndex = 0
    }

    func toggleFind() {
        if showFindPanel {
            dismissFind()
        } else {
            showFindPanel = true
        }
    }

    func performSearch() {
        searchResults = document.findCells(matching: searchText, options: searchOptions)
        if searchResults.isEmpty {
            currentSearchIndex = 0
        } else if currentSearchIndex >= searchResults.count {
            currentSearchIndex = 0
        }
    }

    func findNext() {
        guard !searchResults.isEmpty else { return }
        if currentSearchIndex + 1 < searchResults.count {
            currentSearchIndex += 1
        } else if searchOptions.wrapAround {
            currentSearchIndex = 0
        }
        selectFocusedCell()
    }

    func findPrevious() {
        guard !searchResults.isEmpty else { return }
        if currentSearchIndex - 1 >= 0 {
            currentSearchIndex -= 1
        } else if searchOptions.wrapAround {
            currentSearchIndex = searchResults.count - 1
        }
        selectFocusedCell()
    }

    private func selectFocusedCell() {
        guard let cell = focusedSearchCell else { return }
        selectCell(row: cell.row, column: cell.column)
    }

    // MARK: - Replace Actions

    func replaceCurrent() {
        guard !searchResults.isEmpty,
              currentSearchIndex >= 0,
              currentSearchIndex < searchResults.count else { return }

        let address = searchResults[currentSearchIndex]
        let didReplace = document.replaceCell(
            at: address,
            query: searchText,
            replacement: replaceText,
            options: searchOptions
        )

        if didReplace {
            performSearch()
            if currentSearchIndex >= searchResults.count && !searchResults.isEmpty {
                currentSearchIndex = searchOptions.wrapAround ? 0 : searchResults.count - 1
            }
            selectFocusedCell()
        }
    }

    func replaceAll() {
        let count = document.replaceAll(
            query: searchText,
            replacement: replaceText,
            options: searchOptions
        )
        if count > 0 {
            performSearch()
        }
    }

    // MARK: - Row Operations

    func insertRowAbove() {
        let index = selectedRow ?? 0
        if index >= 0 {
            document.insertRowAbove(index)
        }
    }

    func insertRowBelow() {
        let index = selectedRow ?? (document.rowCount - 1)
        if index >= 0 {
            document.insertRowBelow(index)
        }
    }

    func deleteSelectedRows() {
        guard let sel = selection else { return }
        let minRow = max(0, sel.minRow)
        let maxRow = min(sel.maxRow, document.rowCount - 1)
        guard minRow <= maxRow else { return }
        // Delete from bottom to top so indices stay valid
        for row in stride(from: maxRow, through: minRow, by: -1) {
            guard document.rowCount > 1 else { break }
            document.deleteRow(row)
        }
        let newRow = min(minRow, document.rowCount - 1)
        selection = .single(row: newRow, column: sel.anchorColumn)
    }

    // MARK: - Column Operations

    func insertColumnBefore() {
        let index = selectedColumn ?? 0
        let safeIndex = max(0, min(index, columnWidths.count))
        columnWidths.insert(Self.defaultColumnWidth, at: safeIndex)
        document.insertColumnBefore(index)
    }

    func insertColumnAfter() {
        let index = selectedColumn ?? (document.columnCount - 1)
        let safeIndex = max(0, min(index + 1, columnWidths.count))
        columnWidths.insert(Self.defaultColumnWidth, at: safeIndex)
        document.insertColumnAfter(index)
    }

    func deleteSelectedColumns() {
        guard let sel = selection else { return }
        let minCol = max(0, sel.minColumn)
        let maxCol = min(sel.maxColumn, document.columnCount - 1)
        guard minCol <= maxCol else { return }
        // Delete from right to left so indices stay valid
        for col in stride(from: maxCol, through: minCol, by: -1) {
            guard document.columnCount > 1 else { break }
            if col >= 0, col < columnWidths.count {
                columnWidths.remove(at: col)
            }
            document.deleteColumn(col)
        }
        let newCol = min(minCol, document.columnCount - 1)
        selection = .single(row: sel.anchorRow, column: newCol)
    }

    // MARK: - Move Operations

    func moveRowUp() {
        guard let sel = selection, sel.anchorRow >= 0 else { return }
        let row = sel.anchorRow
        document.moveRowUp(row)
        if row > 0 { selection = .single(row: row - 1, column: sel.anchorColumn) }
    }

    func moveRowDown() {
        guard let sel = selection, sel.anchorRow >= 0 else { return }
        let row = sel.anchorRow
        document.moveRowDown(row)
        if row < document.rowCount - 1 { selection = .single(row: row + 1, column: sel.anchorColumn) }
    }

    func moveColumnLeft() {
        guard let sel = selection else { return }
        let col = sel.anchorColumn
        if col > 0, col < columnWidths.count {
            columnWidths.swapAt(col, col - 1)
        }
        document.moveColumnLeft(col)
        if col > 0 { selection = .single(row: sel.anchorRow, column: col - 1) }
    }

    func moveColumnRight() {
        guard let sel = selection else { return }
        let col = sel.anchorColumn
        if col >= 0, col < columnWidths.count - 1 {
            columnWidths.swapAt(col, col + 1)
        }
        document.moveColumnRight(col)
        if col < document.columnCount - 1 { selection = .single(row: sel.anchorRow, column: col + 1) }
    }

    // MARK: - Tab Display Name

    var tabDisplayName: String {
        if let url = document.fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    // MARK: - Init

    init() {
        syncColumnWidths()
        selectFirstCell()
    }
}

// MARK: - AppState

/// Top-level app state managing a collection of tabs.
@Observable
final class AppState {
    // MARK: - Tabs

    var tabs: [TabState] = []
    var activeTabIndex: Int = 0

    /// The currently active tab. Always valid as long as tabs is non-empty.
    var activeTab: TabState {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else {
            return tabs[0]
        }
        return tabs[activeTabIndex]
    }

    init() {
        let initialTab = TabState()
        tabs = [initialTab]
        activeTabIndex = 0
    }

    // MARK: - Tab Management

    /// Create a new tab with a blank document and switch to it.
    func newTab() {
        let tab = TabState()
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    /// Close the tab at the given index. If it's the last tab, create a fresh one.
    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }

        let tab = tabs[index]
        tab.commitEditIfNeeded()

        if tab.document.isModified {
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
                guard tab.document.save() else { return }
            case .alertSecondButtonReturn:
                break // Don't save — proceed
            default:
                return // Cancel — abort close
            }
        }

        tabs.remove(at: index)

        if tabs.isEmpty {
            // Always keep at least one tab
            let freshTab = TabState()
            tabs.append(freshTab)
            activeTabIndex = 0
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
        // If activeTabIndex == index and index is still valid, we stay on same index
        // (which is now the next tab). This is standard tab-close behavior.
    }

    /// Close the currently active tab.
    func closeActiveTab() {
        closeTab(at: activeTabIndex)
    }

    /// Switch to the previous tab (wraps around).
    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        let newIndex = activeTabIndex > 0 ? activeTabIndex - 1 : tabs.count - 1
        switchToTab(at: newIndex)
    }

    /// Switch to the next tab (wraps around).
    func selectNextTab() {
        guard tabs.count > 1 else { return }
        let newIndex = activeTabIndex < tabs.count - 1 ? activeTabIndex + 1 : 0
        switchToTab(at: newIndex)
    }

    /// Switch to a specific tab index.
    func switchToTab(at index: Int) {
        guard index >= 0, index < tabs.count, index != activeTabIndex else { return }

        // Commit any in-progress edit on the old tab
        if activeTab.isEditing {
            activeTab.commitEdit()
        }

        activeTabIndex = index
    }

    // MARK: - Unsaved Changes Confirmation

    func confirmDiscardingChanges(on tab: TabState, action: @escaping () -> Void) {
        tab.commitEditIfNeeded()

        guard tab.document.isModified else {
            action()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to your document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if tab.document.save() {
                action()
            }
        case .alertSecondButtonReturn:
            action()
        default:
            break
        }
    }

    // MARK: - Safe Document Operations (operate on active tab)

    func safeNewDocument() {
        let tab = activeTab
        confirmDiscardingChanges(on: tab) {
            tab.document.newDocument()
            tab.selectFirstCell()
            tab.resetColumnWidths()
        }
    }

    func safeOpenFile() {
        let tab = activeTab
        confirmDiscardingChanges(on: tab) {
            if tab.document.openFile() {
                tab.selectFirstCell()
                tab.resetColumnWidths()
            }
        }
    }

    func safeLoadFile(at url: URL) {
        let tab = activeTab
        confirmDiscardingChanges(on: tab) {
            tab.document.loadFile(at: url)
            tab.selectFirstCell()
            tab.resetColumnWidths()
        }
    }
}



