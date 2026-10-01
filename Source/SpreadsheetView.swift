//
//  SpreadsheetView.swift
//  Panktira
//

import SwiftUI

/// A cell address used to track selection and highlight state across the spreadsheet.
struct CellPosition: Equatable, Hashable {
    let row: Int      // -1 means header row
    let column: Int
}

/// A uniquely identified request to reveal a cell in the spreadsheet.
struct CellNavigationRequest: Equatable {
    let id = UUID()
    let position: CellPosition
}

// MARK: - SpreadsheetView

struct SpreadsheetView: View {
    @Bindable var document: CSVDocument
    var highlightedCells: Set<CellPosition>
    var highlightedRows: Set<Int>
    var focusedSearchCell: CellPosition?
    var navigationRequest: CellNavigationRequest?
    @Binding var selection: CellRange?
    @Binding var extraSelections: Set<CellPosition>
    @Binding var isEditing: Bool
    @Binding var editText: String
    @Binding var columnWidths: [CGFloat]
    var cellHeight: CGFloat
    var rowNumberWidth: CGFloat
    var bodyFontSize: CGFloat
    var captionFontSize: CGFloat
    var zoomLevel: CGFloat
    var onCommitEdit: () -> Void
    var onCancelEdit: () -> Void
    var onBeginEditing: () -> Void
    var onToggleCellSelection: (Int, Int) -> Void

    /// Tracks in-progress resize for the vertical indicator line.
    @State private var resizingColumn: Int? = nil
    @State private var resizingPreviewWidth: CGFloat = 0

    /// Columns that have been auto-fitted; double-clicking again resets to default.
    @State private var autoFittedColumns: Set<Int> = []

    private func widthForColumn(_ index: Int) -> CGFloat {
        guard index >= 0, index < columnWidths.count else { return TabState.defaultColumnWidth * zoomLevel }
        return columnWidths[index] * zoomLevel
    }

    /// X position of the resize indicator line (leading edge of scroll content).
    private var resizeIndicatorX: CGFloat? {
        guard let col = resizingColumn else { return nil }
        var x = rowNumberWidth
        for i in 0..<col {
            x += widthForColumn(i)
        }
        x += resizingPreviewWidth
        return x
    }

    /// Whether a cell is selected (in range or extras).
    private func isCellSelected(row: Int, column: Int) -> Bool {
        if selection?.contains(row: row, column: column) == true { return true }
        return extraSelections.contains(CellPosition(row: row, column: column))
    }

    /// The cell currently being edited (derived from selection + isEditing).
    private var editingCell: CellPosition? {
        guard isEditing, let sel = selection else { return nil }
        return CellPosition(row: sel.anchorRow, column: sel.anchorColumn)
    }

    /// Compute the optimal base width (unscaled) for a column by measuring its content.
    private func autoFitWidth(for colIndex: Int) -> CGFloat {
        let padding: CGFloat = 16 // horizontal padding inside cells
        let headerFont = NSFont.systemFont(ofSize: TabState.baseBodyFontSize, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: TabState.baseBodyFontSize)
        let attrs = [NSAttributedString.Key.font: bodyFont]
        let headerAttrs = [NSAttributedString.Key.font: headerFont]

        // Measure header
        let headerText = document.headerValue(column: colIndex) as NSString
        var maxWidth = headerText.size(withAttributes: headerAttrs).width

        // Measure all data rows
        for row in 0..<document.rowCount {
            let cellText = document.cellValue(row: row, column: colIndex) as NSString
            let w = cellText.size(withAttributes: attrs).width
            if w > maxWidth { maxWidth = w }
        }

        return max(TabState.minimumColumnWidth, ceil(maxWidth + padding))
    }

    /// Handle double-click on the column resize handle: toggle auto-fit / default.
    private func handleAutoFit(for colIndex: Int) {
        while columnWidths.count <= colIndex {
            columnWidths.append(TabState.defaultColumnWidth)
        }

        if autoFittedColumns.contains(colIndex) {
            // Reset to default
            columnWidths[colIndex] = TabState.defaultColumnWidth
            autoFittedColumns.remove(colIndex)
        } else {
            // Auto-fit to content
            columnWidths[colIndex] = autoFitWidth(for: colIndex)
            autoFittedColumns.insert(colIndex)
        }
    }

    private func scroll(to cell: CellPosition, using proxy: ScrollViewProxy) {
        // Materialize the lazy row first, then reveal the exact cell on the next layout pass.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(cell.row)
        }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(cell, anchor: .center)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(0..<document.rowCount), id: \.self) { rowIndex in
                                dataRow(rowIndex)
                                    .id(rowIndex)
                            }
                        } header: {
                            headerSection
                        }
                    }
                    .padding(.bottom, 20)
                    .padding(.trailing, 20)

                    // Vertical resize indicator line
                    if let indicatorX = resizeIndicatorX {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 1.5)
                            .offset(x: indicatorX)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onChange(of: focusedSearchCell) { _, newValue in
                guard let cell = newValue else { return }
                scroll(to: cell, using: proxy)
            }
            .onChange(of: navigationRequest) { _, request in
                guard let request else { return }
                scroll(to: request.position, using: proxy)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CornerCell(width: rowNumberWidth, height: cellHeight)

                ForEach(Array(0..<document.columnCount), id: \.self) { colIndex in
                    ColumnLetterCell(
                        index: colIndex,
                        isSelected: (selection?.containsColumn(colIndex) ?? false) || extraSelections.contains(where: { $0.column == colIndex }),
                        width: widthForColumn(colIndex),
                        height: cellHeight,
                        fontSize: captionFontSize,
                        sortOrder: document.sortOrder(for: colIndex),
                        onCycleSort: {
                            if isEditing { onCommitEdit() }
                            document.cycleSort(for: colIndex)
                        }
                    )
                    .overlay(alignment: .trailing) {
                        ColumnResizeHandle(
                            height: cellHeight,
                            currentWidth: widthForColumn(colIndex),
                            minimumWidth: TabState.minimumColumnWidth * zoomLevel,
                            onResizeChanged: { previewWidth in
                                resizingColumn = colIndex
                                resizingPreviewWidth = previewWidth
                            },
                            onResizeEnded: { finalWidth in
                                // Ensure the array is large enough
                                while columnWidths.count <= colIndex {
                                    columnWidths.append(TabState.defaultColumnWidth)
                                }
                                // Store as base width (divide out zoom)
                                columnWidths[colIndex] = finalWidth / zoomLevel
                                resizingColumn = nil
                                // Manual drag clears auto-fit state
                                autoFittedColumns.remove(colIndex)
                            },
                            onDoubleClick: {
                                handleAutoFit(for: colIndex)
                            }
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                        if shiftHeld, let sel = selection {
                            extraSelections.removeAll()
                            selection = CellRange(
                                anchorRow: sel.anchorRow,
                                anchorColumn: sel.anchorColumn,
                                extentRow: document.rowCount - 1,
                                extentColumn: colIndex
                            )
                        } else {
                            // Select entire column
                            extraSelections.removeAll()
                            selection = CellRange(
                                anchorRow: -1,
                                anchorColumn: colIndex,
                                extentRow: document.rowCount - 1,
                                extentColumn: colIndex
                            )
                        }
                    }
                }
            }

            HStack(spacing: 0) {
                RowNumberCell(number: nil, isSelected: false, width: rowNumberWidth, height: cellHeight, fontSize: captionFontSize)

                ForEach(Array(0..<document.columnCount), id: \.self) { colIndex in
                    let pos = CellPosition(row: -1, column: colIndex)
                    headerCellView(column: colIndex, position: pos)
                        .id(pos)
                }
            }
        }
    }

    // MARK: - Data Row

    private func dataRow(_ rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            RowNumberCell(
                number: rowIndex + 1,
                isSelected: (selection?.containsRow(rowIndex) ?? false) || extraSelections.contains(where: { $0.row == rowIndex }),
                isInMatchedRow: highlightedRows.contains(rowIndex),
                width: rowNumberWidth,
                height: cellHeight,
                fontSize: captionFontSize
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditing { onCommitEdit() }
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                if shiftHeld, let sel = selection {
                    extraSelections.removeAll()
                    selection = CellRange(
                        anchorRow: sel.anchorRow,
                        anchorColumn: 0,
                        extentRow: rowIndex,
                        extentColumn: document.columnCount - 1
                    )
                } else {
                    // Select entire row
                    extraSelections.removeAll()
                    selection = CellRange(
                        anchorRow: rowIndex,
                        anchorColumn: 0,
                        extentRow: rowIndex,
                        extentColumn: document.columnCount - 1
                    )
                }
            }

            ForEach(Array(0..<document.columnCount), id: \.self) { colIndex in
                let pos = CellPosition(row: rowIndex, column: colIndex)
                dataCellView(row: rowIndex, column: colIndex, position: pos)
                    .id(pos)
            }
        }
    }

    // MARK: - Header Cell

    private func headerCellView(column: Int, position: CellPosition) -> some View {
        let isHighlighted = highlightedCells.contains(position)
        let isFocused = focusedSearchCell == position
        let isCellEditing = editingCell == position
        let value = document.headerValue(column: column)
        let isSelected = isCellSelected(row: -1, column: column)
        let isAnchor = selection.map { $0.anchorRow == -1 && $0.anchorColumn == column } ?? false

        return ZStack {
            Rectangle()
                .fill(CellBackgroundResolver.color(
                    isHighlighted: isHighlighted,
                    isFocused: isFocused,
                    isInSelection: isSelected,
                    isAnchor: isAnchor
                ))
                .background(.bar)

            if isCellEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: bodyFontSize, weight: .semibold))
                    .padding(.horizontal, 4)
                    .onSubmit { onCommitEdit() }
                    .onExitCommand { onCancelEdit() }
            } else {
                Text(value)
                    .font(.system(size: bodyFontSize, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: widthForColumn(column), height: cellHeight)
        .border(isFocused ? Color.accentColor : (isAnchor ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2)), width: isFocused ? 2 : (isAnchor ? 1.5 : 0.5))
        .overlay {
            if isFocused {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .foregroundStyle(Color.yellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            let shiftHeld = modifiers.contains(.shift)
            let cmdHeld = modifiers.contains(.command)

            if isEditing { onCommitEdit() }

            if cmdHeld {
                onToggleCellSelection(-1, column)
            } else if shiftHeld, selection != nil {
                extraSelections.removeAll()
                selection = CellRange(
                    anchorRow: selection!.anchorRow,
                    anchorColumn: selection!.anchorColumn,
                    extentRow: -1,
                    extentColumn: column
                )
            } else {
                let wasSelected = selection.map { $0.anchorRow == -1 && $0.anchorColumn == column && $0.isSingleCell } ?? false
                    && extraSelections.isEmpty
                extraSelections.removeAll()
                selection = .single(row: -1, column: column)
                if wasSelected && !isEditing {
                    onBeginEditing()
                }
            }
        }
    }

    // MARK: - Data Cell

    private func dataCellView(row: Int, column: Int, position: CellPosition) -> some View {
        let isCellEditing = editingCell == position
        let value = document.cellValue(row: row, column: column)
        let colWidth = widthForColumn(column)

        let isSelected = isCellSelected(row: row, column: column)
        let isAnchor = selection.map { $0.anchorRow == row && $0.anchorColumn == column } ?? false

        let visualState = DataCellView.VisualState(
            isHighlighted: highlightedCells.contains(position),
            isFocused: focusedSearchCell == position,
            isInMatchedRow: highlightedRows.contains(row),
            isInSelection: isSelected,
            isAnchor: isAnchor
        )

        return ZStack {
            DataCellView(
                value: value,
                state: visualState,
                width: colWidth,
                height: cellHeight,
                fontSize: bodyFontSize
            )

            if isCellEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: bodyFontSize))
                    .padding(.horizontal, 4)
                    .frame(width: colWidth, height: cellHeight)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .onSubmit { onCommitEdit() }
                    .onExitCommand { onCancelEdit() }
            }
        }
        .frame(width: colWidth, height: cellHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            let shiftHeld = modifiers.contains(.shift)
            let cmdHeld = modifiers.contains(.command)

            if isEditing { onCommitEdit() }

            if cmdHeld {
                onToggleCellSelection(row, column)
            } else if shiftHeld, selection != nil {
                extraSelections.removeAll()
                selection = CellRange(
                    anchorRow: selection!.anchorRow,
                    anchorColumn: selection!.anchorColumn,
                    extentRow: row,
                    extentColumn: column
                )
            } else {
                let wasAnchor = selection.map { $0.anchorRow == row && $0.anchorColumn == column && $0.isSingleCell } ?? false
                    && extraSelections.isEmpty
                extraSelections.removeAll()
                selection = .single(row: row, column: column)
                if wasAnchor && !isEditing {
                    onBeginEditing()
                }
            }
        }
    }
}

// MARK: - DataCellView (Equatable — SwiftUI skips body when inputs unchanged)

struct DataCellView: View, Equatable {
    let value: String
    let state: VisualState
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat

    struct VisualState: Equatable {
        let isHighlighted: Bool
        let isFocused: Bool
        let isInMatchedRow: Bool
        let isInSelection: Bool
        let isAnchor: Bool
    }

    static func == (lhs: DataCellView, rhs: DataCellView) -> Bool {
        lhs.value == rhs.value && lhs.state == rhs.state && lhs.width == rhs.width && lhs.height == rhs.height && lhs.fontSize == rhs.fontSize
    }

    private var borderColor: Color {
        if state.isFocused { return Color.accentColor }
        if state.isAnchor { return Color.accentColor.opacity(0.6) }
        if state.isInSelection { return Color.accentColor.opacity(0.3) }
        return Color.gray.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        if state.isFocused { return 2 }
        if state.isAnchor { return 1.5 }
        return 0.5
    }

    var body: some View {
        let bgColor = CellBackgroundResolver.color(
            isHighlighted: state.isHighlighted,
            isFocused: state.isFocused,
            isInMatchedRow: state.isInMatchedRow,
            isInSelection: state.isInSelection,
            isAnchor: state.isAnchor
        )

        Rectangle()
            .fill(bgColor)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Text(value)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .border(borderColor, width: borderWidth)
            .overlay {
                if state.isFocused {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .foregroundStyle(Color.yellow)
                }
            }
    }
}

// MARK: - CornerCell

struct CornerCell: View, Equatable {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.bar)
            Rectangle().fill(.quaternary.opacity(0.3))
        }
        .frame(width: width, height: height)
        .border(Color.gray.opacity(0.2), width: 0.5)
    }
}

// MARK: - ColumnLetterCell

struct ColumnLetterCell: View, Equatable {
    let index: Int
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let sortOrder: ColumnSortState.Order?
    let onCycleSort: () -> Void

    static func == (lhs: ColumnLetterCell, rhs: ColumnLetterCell) -> Bool {
        lhs.index == rhs.index
            && lhs.isSelected == rhs.isSelected
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.fontSize == rhs.fontSize
            && lhs.sortOrder == rhs.sortOrder
    }

    private var sortSymbol: String {
        switch sortOrder {
        case .ascending:
            "arrow.up"
        case .descending:
            "arrow.down"
        case nil:
            "arrow.up.arrow.down"
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .background(.bar)
            HStack(spacing: 3) {
                Text(CSVDocument.columnLetter(for: index))
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: onCycleSort) {
                    Label("Sort", systemImage: sortSymbol)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(sortOrder == nil ? .secondary : Color.accentColor)
                .help("Sort")
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
        }
        .frame(width: width, height: height)
        .border(Color.gray.opacity(0.2), width: 0.5)
    }
}

// MARK: - RowNumberCell

struct RowNumberCell: View, Equatable {
    let number: Int?
    let isSelected: Bool
    let isInMatchedRow: Bool
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat

    init(number: Int?, isSelected: Bool, isInMatchedRow: Bool = false, width: CGFloat, height: CGFloat, fontSize: CGFloat) {
        self.number = number
        self.isSelected = isSelected
        self.isInMatchedRow = isInMatchedRow
        self.width = width
        self.height = height
        self.fontSize = fontSize
    }

    var body: some View {
        let bgColor: Color = isSelected
            ? Color.accentColor.opacity(0.15)
            : (isInMatchedRow ? Color.yellow.opacity(0.06) : Color.clear)

        ZStack {
            Rectangle()
                .fill(bgColor)
                .background(.bar)
            if let number {
                Text("\(number)")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .border(Color.gray.opacity(0.2), width: 0.5)
    }
}

// MARK: - Column Resize Handle

struct ColumnResizeHandle: View {
    let height: CGFloat
    let currentWidth: CGFloat
    let minimumWidth: CGFloat
    let onResizeChanged: (_ previewWidth: CGFloat) -> Void
    let onResizeEnded: (_ finalWidth: CGFloat) -> Void
    var onDoubleClick: (() -> Void)? = nil

    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in
                if !isDragging {
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startWidth = currentWidth
                            NSCursor.resizeLeftRight.set()
                        }
                        let newWidth = max(minimumWidth, startWidth + value.translation.width)
                        onResizeChanged(newWidth)
                    }
                    .onEnded { value in
                        let finalWidth = max(minimumWidth, startWidth + value.translation.width)
                        onResizeEnded(finalWidth)
                        isDragging = false
                        NSCursor.arrow.set()
                    }
            )
            .onTapGesture(count: 2) {
                onDoubleClick?()
            }
    }
}

// MARK: - Background Color Resolver

enum CellBackgroundResolver {
    static func color(
        isHighlighted: Bool = false,
        isFocused: Bool = false,
        isInMatchedRow: Bool = false,
        isInSelection: Bool = false,
        isAnchor: Bool = false
    ) -> Color {
        if isFocused { return Color.accentColor.opacity(0.25) }
        if isHighlighted { return Color.yellow.opacity(0.25) }
        if isAnchor { return Color.accentColor.opacity(0.12) }
        if isInSelection { return Color.accentColor.opacity(0.08) }
        if isInMatchedRow { return Color.yellow.opacity(0.06) }
        return Color.clear
    }
}


