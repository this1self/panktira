//
//  CSVDocument.swift
//  Panktira
//

import SwiftUI
import UniformTypeIdentifiers

/// How to compare the search query against cell values.
enum MatchMode: String, CaseIterable, Identifiable {
    case contains = "Contains"
    case wholeWord = "Whole Word"
    case entireCell = "Entire Cell"
    case startsWith = "Starts With"
    case endsWith = "Ends With"

    var id: String { rawValue }
}

/// Options that control find behavior.
struct SearchOptions {
    var matchMode: MatchMode = .contains
    var caseSensitive: Bool = false
    var wrapAround: Bool = true
}

/// Represents the full state of a CSV spreadsheet for undo/redo snapshots.
struct CSVState: Equatable {
    var rows: [[String]]
    var headerRow: [String]
    var sortState: ColumnSortState?
    var rowsBeforeSorting: [[String]]?
}

/// The current sort state for a spreadsheet column.
struct ColumnSortState: Equatable {
    enum Order: Equatable {
        case ascending
        case descending
    }

    let column: Int
    let order: Order
}

/// Observable document model that manages CSV data, undo/redo, and file I/O.
@Observable
final class CSVDocument {
    // MARK: - Data

    /// The header row (column names). Not counted as a data row.
    var headerRow: [String] = ["A", "B", "C"]

    /// Data rows (excluding the header).
    var rows: [[String]] = [
        ["", "", ""],
        ["", "", ""],
        ["", "", ""]
    ]

    // MARK: - File State

    var fileURL: URL?
    var isModified: Bool = false

    // MARK: - Undo / Redo Stacks

    private var undoStack: [CSVState] = []
    private var redoStack: [CSVState] = []
    private var isRestoringState = false

    /// The unmodified row order captured before the current column sort.
    private var rowsBeforeSorting: [[String]]?
    private(set) var sortState: ColumnSortState?

    // MARK: - Column Count

    var columnCount: Int {
        headerRow.count
    }

    var rowCount: Int {
        rows.count
    }

    // MARK: - Snapshot Helpers

    private var currentState: CSVState {
        CSVState(
            rows: rows,
            headerRow: headerRow,
            sortState: sortState,
            rowsBeforeSorting: rowsBeforeSorting
        )
    }

    /// Push the current state onto the undo stack before mutating.
    private func pushUndo() {
        guard !isRestoringState else { return }
        undoStack.append(currentState)
        redoStack.removeAll()
        isModified = true
    }

    private func restore(_ state: CSVState) {
        isRestoringState = true
        headerRow = state.headerRow
        rows = state.rows
        sortState = state.sortState
        rowsBeforeSorting = state.rowsBeforeSorting
        isModified = true
        isRestoringState = false
    }

    // MARK: - Undo / Redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentState)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentState)
        restore(next)
    }

    // MARK: - Cell Editing

    func updateCell(row: Int, column: Int, value: String) {
        guard row >= 0, row < rows.count, column >= 0, column < columnCount else { return }
        // Pad the row if it's shorter than the column count (ragged CSV)
        while rows[row].count <= column {
            rows[row].append("")
        }
        let oldValue = rows[row][column]
        guard oldValue != value else { return }
        pushUndo()
        rows[row][column] = value
    }

    func updateHeader(column: Int, value: String) {
        guard column >= 0, column < columnCount else { return }
        let oldValue = headerRow[column]
        guard oldValue != value else { return }
        pushUndo()
        headerRow[column] = value
    }

    func cellValue(row: Int, column: Int) -> String {
        guard row >= 0, row < rows.count, column >= 0, column < rows[row].count else { return "" }
        return rows[row][column]
    }

    func headerValue(column: Int) -> String {
        guard column >= 0, column < headerRow.count else { return "" }
        return headerRow[column]
    }

    // MARK: - Sorting

    func sortOrder(for column: Int) -> ColumnSortState.Order? {
        guard sortState?.column == column else { return nil }
        return sortState?.order
    }

    /// Cycles a column through ascending, descending, and its original order.
    func cycleSort(for column: Int) {
        guard column >= 0, column < columnCount else { return }

        switch sortState {
        case let state? where state.column == column && state.order == .ascending:
            pushUndo()
            applySort(column: column, order: .descending)
        case let state? where state.column == column && state.order == .descending:
            pushUndo()
            rows = rowsBeforeSorting ?? rows
            rowsBeforeSorting = nil
            sortState = nil
        default:
            pushUndo()
            if rowsBeforeSorting == nil {
                rowsBeforeSorting = rows
            }
            applySort(column: column, order: .ascending)
        }
    }

    private func applySort(column: Int, order: ColumnSortState.Order) {
        let sourceRows = rowsBeforeSorting ?? rows
        rows = sourceRows
            .enumerated()
            .sorted { lhs, rhs in
                let comparison = value(at: column, in: lhs.element)
                    .localizedStandardCompare(value(at: column, in: rhs.element))

                if comparison == .orderedSame {
                    return lhs.offset < rhs.offset
                }

                switch order {
                case .ascending:
                    return comparison == .orderedAscending
                case .descending:
                    return comparison == .orderedDescending
                }
            }
            .map(\.element)
        sortState = ColumnSortState(column: column, order: order)
    }

    private func value(at column: Int, in row: [String]) -> String {
        guard column < row.count else { return "" }
        return row[column]
    }

    // MARK: - Row Operations

    func insertRowAbove(_ index: Int) {
        pushUndo()
        let newRow = Array(repeating: "", count: columnCount)
        let safeIndex = max(0, min(index, rows.count))
        rows.insert(newRow, at: safeIndex)
    }

    func insertRowBelow(_ index: Int) {
        pushUndo()
        let newRow = Array(repeating: "", count: columnCount)
        let safeIndex = max(0, min(index + 1, rows.count))
        rows.insert(newRow, at: safeIndex)
    }

    func moveRowUp(_ index: Int) {
        guard index > 0, index < rows.count else { return }
        pushUndo()
        rows.swapAt(index, index - 1)
    }

    func moveRowDown(_ index: Int) {
        guard index >= 0, index < rows.count - 1 else { return }
        pushUndo()
        rows.swapAt(index, index + 1)
    }

    func deleteRow(_ index: Int) {
        guard rows.count > 1, index >= 0, index < rows.count else { return }
        pushUndo()
        rows.remove(at: index)
    }

    // MARK: - Column Operations

    /// Ensure every data row has exactly `columnCount` elements (pad or trim).
    private func normalizeRows() {
        let cols = columnCount
        for i in 0..<rows.count {
            while rows[i].count < cols {
                rows[i].append("")
            }
            if rows[i].count > cols {
                rows[i] = Array(rows[i].prefix(cols))
            }
        }
    }

    func insertColumnBefore(_ index: Int) {
        pushUndo()
        normalizeRows()
        let safeIndex = max(0, min(index, columnCount))
        let letter = nextColumnLetter()
        headerRow.insert(letter, at: safeIndex)
        for i in 0..<rows.count {
            rows[i].insert("", at: safeIndex)
        }
    }

    func insertColumnAfter(_ index: Int) {
        pushUndo()
        normalizeRows()
        let safeIndex = max(0, min(index + 1, columnCount))
        let letter = nextColumnLetter()
        headerRow.insert(letter, at: safeIndex)
        for i in 0..<rows.count {
            rows[i].insert("", at: safeIndex)
        }
    }

    func moveColumnLeft(_ index: Int) {
        guard index > 0, index < columnCount else { return }
        pushUndo()
        normalizeRows()
        headerRow.swapAt(index, index - 1)
        for i in 0..<rows.count {
            rows[i].swapAt(index, index - 1)
        }
    }

    func moveColumnRight(_ index: Int) {
        guard index >= 0, index < columnCount - 1 else { return }
        pushUndo()
        normalizeRows()
        headerRow.swapAt(index, index + 1)
        for i in 0..<rows.count {
            rows[i].swapAt(index, index + 1)
        }
    }

    func deleteColumn(_ index: Int) {
        guard columnCount > 1, index >= 0, index < columnCount else { return }
        pushUndo()
        normalizeRows()
        headerRow.remove(at: index)
        for i in 0..<rows.count {
            rows[i].remove(at: index)
        }
    }

    // MARK: - Column Letter Helpers

    /// Generate a spreadsheet-style column letter (A, B, ..., Z, AA, AB, ...).
    static func columnLetter(for index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private func nextColumnLetter() -> String {
        CSVDocument.columnLetter(for: columnCount)
    }

    // MARK: - CSV Parsing

    func loadFromCSV(_ text: String) {
        undoStack.removeAll()
        redoStack.removeAll()
        sortState = nil
        rowsBeforeSorting = nil

        let parsed = CSVDocument.parseCSV(text)
        guard !parsed.isEmpty else {
            headerRow = ["A", "B", "C"]
            rows = [["", "", ""]]
            isModified = false
            return
        }

        // Determine column count from the widest row
        let maxCols = parsed.map(\.count).max() ?? 1

        // First row is the header
        var header = parsed[0]
        while header.count < maxCols { header.append("") }
        headerRow = header

        // Remaining rows are data
        if parsed.count > 1 {
            rows = parsed.dropFirst().map { row in
                var r = row
                while r.count < maxCols { r.append("") }
                return r
            }
        } else {
            rows = [Array(repeating: "", count: maxCols)]
        }

        // Final safety: ensure all rows match header column count
        normalizeRows()
        isModified = false
    }

    /// RFC 4180-aware CSV parser handling quoted fields, embedded commas,
    /// embedded newlines, and escaped quotes.
    ///
    /// Iterates over Unicode scalars (not Characters) so that CR+LF is always
    /// treated as two separate code points. Swift's `Character` type merges
    /// `\r\n` into a single grapheme cluster that doesn't match `"\r"` or `"\n"`.
    static func parseCSV(_ text: String) -> [[String]] {
        // Use integer-based Unicode.Scalar constants so Xcode preview thunks
        // don't rewrite them into __designTimeString() calls.
        let kQuote  = Unicode.Scalar(0x22)! // "
        let kComma  = Unicode.Scalar(0x2C)! // ,
        let kCR     = Unicode.Scalar(0x0D)! // \r
        let kLF     = Unicode.Scalar(0x0A)! // \n

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        let scalars = Array(text.unicodeScalars)
        var i = 0

        while i < scalars.count {
            let s = scalars[i]

            if insideQuotes {
                if s == kQuote {
                    // Check for escaped quote ""
                    if i + 1 < scalars.count && scalars[i + 1] == kQuote {
                        currentField.unicodeScalars.append(kQuote)
                        i += 2
                        continue
                    } else {
                        insideQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.unicodeScalars.append(s)
                    i += 1
                    continue
                }
            }

            // Not inside quotes
            if s == kQuote {
                insideQuotes = true
                i += 1
            } else if s == kComma {
                currentRow.append(currentField)
                currentField = ""
                i += 1
            } else if s == kCR {
                // Handle \r\n or lone \r
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
                if i + 1 < scalars.count && scalars[i + 1] == kLF {
                    i += 2
                } else {
                    i += 1
                }
            } else if s == kLF {
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
                i += 1
            } else {
                currentField.unicodeScalars.append(s)
                i += 1
            }
        }

        // Flush last field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    // MARK: - CSV Serialization

    func toCSV() -> String {
        var lines: [String] = []
        lines.append(headerRow.map { escapeCSVField($0) }.joined(separator: ","))
        for row in rows {
            lines.append(row.map { escapeCSVField($0) }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - File I/O

    func newDocument() {
        undoStack.removeAll()
        redoStack.removeAll()
        sortState = nil
        rowsBeforeSorting = nil
        headerRow = ["A", "B", "C"]
        rows = [
            ["", "", ""],
            ["", "", ""],
            ["", "", ""]
        ]
        fileURL = nil
        isModified = false
    }

    @discardableResult
    func openFile() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return false }
        loadFile(at: url)
        return true
    }

    func loadFile(at url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            loadFromCSV(text)
            fileURL = url
            isModified = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            // Silently fail – could show alert in future
        }
    }

    @discardableResult
    func save() -> Bool {
        if let url = fileURL {
            return writeToFile(url)
        } else {
            return saveAs()
        }
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Untitled.csv"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return false }
        return writeToFile(url)
    }

    @discardableResult
    private func writeToFile(_ url: URL) -> Bool {
        do {
            let text = toCSV()
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            isModified = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Search

    struct CellAddress: Equatable {
        let row: Int    // -1 = header row
        let column: Int
    }

    /// Find all cells matching the query with the given options.
    func findCells(matching query: String, options: SearchOptions = SearchOptions()) -> [CellAddress] {
        guard !query.isEmpty else { return [] }
        var results: [CellAddress] = []

        func matches(_ cellValue: String) -> Bool {
            let value = options.caseSensitive ? cellValue : cellValue.lowercased()
            let q = options.caseSensitive ? query : query.lowercased()
            switch options.matchMode {
            case .contains:   return value.contains(q)
            case .wholeWord:  return matchesWholeWord(value, query: q)
            case .entireCell: return value == q
            case .startsWith: return value.hasPrefix(q)
            case .endsWith:   return value.hasSuffix(q)
            }
        }

        // Search header
        for col in 0..<columnCount {
            if matches(headerRow[col]) {
                results.append(CellAddress(row: -1, column: col))
            }
        }

        // Search data rows
        for row in 0..<rows.count {
            for col in 0..<rows[row].count {
                if matches(rows[row][col]) {
                    results.append(CellAddress(row: row, column: col))
                }
            }
        }

        return results
    }

    // MARK: - Replace

    /// Replace the value at a specific cell address. Returns true if a replacement was made.
    func replaceCell(at address: CellAddress, query: String, replacement: String, options: SearchOptions) -> Bool {
        let currentValue: String
        if address.row == -1 {
            currentValue = headerValue(column: address.column)
        } else {
            currentValue = cellValue(row: address.row, column: address.column)
        }

        guard let newValue = applyReplacement(to: currentValue, query: query, replacement: replacement, options: options) else {
            return false
        }

        if address.row == -1 {
            updateHeader(column: address.column, value: newValue)
        } else {
            updateCell(row: address.row, column: address.column, value: newValue)
        }
        return true
    }

    /// Replace all occurrences across the entire document. Returns the count replaced.
    func replaceAll(query: String, replacement: String, options: SearchOptions) -> Int {
        let matches = findCells(matching: query, options: options)
        guard !matches.isEmpty else { return 0 }

        // Single undo snapshot for the entire batch
        pushUndo()

        var count = 0
        for address in matches {
            let currentValue: String
            if address.row == -1 {
                currentValue = headerValue(column: address.column)
            } else {
                currentValue = cellValue(row: address.row, column: address.column)
            }

            guard let newValue = applyReplacement(to: currentValue, query: query, replacement: replacement, options: options) else {
                continue
            }

            // Direct mutation — no per-cell pushUndo (we already pushed once)
            isRestoringState = true
            if address.row == -1 {
                if address.column >= 0 && address.column < headerRow.count {
                    headerRow[address.column] = newValue
                }
            } else {
                if address.row >= 0 && address.row < rows.count {
                    while rows[address.row].count <= address.column {
                        rows[address.row].append("")
                    }
                    rows[address.row][address.column] = newValue
                }
            }
            isRestoringState = false
            count += 1
        }

        isModified = true
        return count
    }

    /// Check if the value contains the query as a whole word (bounded by non-alphanumeric chars or string edges).
    private func matchesWholeWord(_ value: String, query: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    /// Apply the replacement to a cell value based on match mode.
    private func applyReplacement(to value: String, query: String, replacement: String, options: SearchOptions) -> String? {
        let compareValue = options.caseSensitive ? value : value.lowercased()
        let compareQuery = options.caseSensitive ? query : query.lowercased()

        switch options.matchMode {
        case .entireCell:
            guard compareValue == compareQuery else { return nil }
            return replacement
        case .wholeWord:
            guard matchesWholeWord(compareValue, query: compareQuery) else { return nil }
            // Use regex to replace only whole-word occurrences
            let escaped = NSRegularExpression.escapedPattern(for: query)
            let pattern = "\\b\(escaped)\\b"
            let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else { return nil }
            let range = NSRange(value.startIndex..., in: value)
            return regex.stringByReplacingMatches(in: value, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        case .contains:
            guard compareValue.contains(compareQuery) else { return nil }
            if options.caseSensitive {
                return value.replacingOccurrences(of: query, with: replacement)
            } else {
                return value.replacingOccurrences(of: query, with: replacement, options: .caseInsensitive)
            }
        case .startsWith:
            guard compareValue.hasPrefix(compareQuery) else { return nil }
            let prefixEnd = value.index(value.startIndex, offsetBy: query.count)
            var result = value
            result.replaceSubrange(value.startIndex..<prefixEnd, with: replacement)
            return result
        case .endsWith:
            guard compareValue.hasSuffix(compareQuery) else { return nil }
            let suffixStart = value.index(value.endIndex, offsetBy: -query.count)
            var result = value
            result.replaceSubrange(suffixStart..<value.endIndex, with: replacement)
            return result
        }
    }

    // MARK: - Window Title

    var displayName: String {
        if let url = fileURL {
            return url.lastPathComponent + (isModified ? " — Edited" : "")
        }
        return "Untitled" + (isModified ? " — Edited" : "")
    }
}
