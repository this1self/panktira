# Panktira Code Review Findings

Date: 2026-04-23
Scope: current repository state; `.csv` and `.png` contents skipped by request.
Build: not evaluated; user stated the latest code builds fine.
Latest pass: includes the Cmd-click disjoint-selection update.

## Executive Summary

Code quality is around 53/100. The code is still compact and readable, but the newest selection model adds more mutable UI state without integrating it into table mutations, undo, or performance strategy.

Remote security risk remains low, probably under 2%, because there is no network, subprocess, scripting, plugin, or web surface. The practical security issue is still local untrusted-file denial-of-service through large CSVs. Performance risk is now moderately higher because disjoint selection can materialize huge `Set<CellPosition>` values and render-time membership checks scan them repeatedly.


## P0 Findings

### 1. Save can discard data

References: `Source/AppState.swift:655-667`, `Source/AppState.swift:724-742`, `Source/ContentView.swift:328-344`, `Source/CSVDocument.swift:436-451`, `Source/CSVDocument.swift:454-463`

`tab.document.save()` is treated as synchronous, but untitled documents use `NSSavePanel.begin`, which returns immediately. Close/new/open/window-close can proceed while Save As is still pending. If the user cancels Save As, the tab/window may already have closed or the document may already have been replaced.

Existing-file writes are synchronous, but failures are swallowed, then close/new/open paths still proceed.

Impact: user data loss.

Suggested direction: make save APIs completion/result-based, e.g. `save(completion: (Bool) -> Void)`, and only continue destructive actions after `true`.

- [x] Fixed — `save()`/`saveAs()` now use synchronous `runModal()` and return `Bool`. All callers check the result before proceeding with destructive actions.

### 2. Active cell edits are not committed before save or close

References: `Source/PanktiraApp.swift:77-85`, `Source/AppState.swift:651-667`, `Source/ContentView.swift:328-344`, `Source/AppState.swift:724-742`

Save, Save As, close tab, close window, new, and open rely on `CSVDocument` state. If a user is currently editing a cell, the new text lives in `TabState.editText`, not `CSVDocument.rows/headerRow`.

If the document was otherwise unmodified, close can skip the dirty prompt entirely. If it was modified, save can write stale data.

Impact: visible user input can be omitted from saved output or lost on close.

Suggested direction: centralize document actions through `TabState.commitEditIfNeeded()` before dirty checks and writes.

- [x] Fixed — Added `TabState.commitEditIfNeeded()`. Called before dirty checks in `closeTab`, `confirmDiscardingChanges`, `windowShouldClose`, and before `save()`/`saveAs()` in menu commands.

## P1 Findings

### 3. Main-thread CSV load/parsing can freeze or exhaust memory

References: `Source/CSVDocument.swift:424-430`, `Source/CSVDocument.swift:260-294`, `Source/CSVDocument.swift:302-376`

`loadFile(at:)` reads the entire file as one UTF-8 `String` on the main actor, then `parseCSV` duplicates it into `Array(text.unicodeScalars)`, then builds full parsed rows, then copies again into document rows.

Performance impact: large files can stall the UI and allocate several multiples of file size.
Security impact: untrusted local files can be used as a denial-of-service input.

Suggested direction: enforce file-size limits, parse off-main, stream scalars/bytes, and return user-visible errors.

- [ ] Fixed?

### 4. Undo/redo stores unbounded full-document snapshots

References: `Source/CSVDocument.swift:71-80`, `Source/CSVDocument.swift:96-105`

Every edit appends a complete `CSVState(rows:headerRow:)`. For large tables, even small edits duplicate the entire document. There is no cap, coalescing, diff-based history, or memory-pressure response.

Performance impact: memory can grow roughly as `documentSize * editCount`.

Suggested direction: cap history, coalesce continuous edits, or store operations/diffs instead of whole-table snapshots.

- [ ] Fixed?

### 5. Cmd-click can flatten huge ranges into `extraSelections`

References: `Source/AppState.swift:202-230`

When Cmd-clicking after a non-single range, the current range is flattened into `extraSelections` by nested loops over every selected row and column. Cmd-click after Select All on a large sheet tries to allocate one `CellPosition` per selected cell.

Performance impact: high memory growth and UI freeze.
Correctness impact: a visual range selection becomes a very large explicit set, changing the cost model unexpectedly.

Suggested direction: represent selections as a collection of ranges plus sparse cells, not by expanding ranges into per-cell positions.

- [ ] Fixed?

### 6. Multi-row/multi-column delete creates many undo snapshots

References: `Source/AppState.swift:518-527`, `Source/AppState.swift:548-560`, `Source/CSVDocument.swift:168-171`, `Source/CSVDocument.swift:231-238`

Range delete loops one row/column at a time, and each `document.deleteRow` / `document.deleteColumn` pushes its own full snapshot. Deleting 1,000 selected rows requires 1,000 undo operations and may allocate 1,000 full document copies.

Correctness impact: one logical delete is not one undo step.
Performance impact: bulk deletes are disproportionately expensive.

Suggested direction: add batch document mutations that push one undo snapshot per logical command.

- [ ] Fixed?

### 7. Column-width state still diverges from document undo/redo

References: `Source/AppState.swift:534-560`, `Source/AppState.swift:581-598`, `Source/CSVDocument.swift:96-105`

Column widths live in `TabState`, while undo/redo only restores `CSVDocument`. Column insert/delete/move mutates both, but undo/redo only changes the document columns. After undo, widths can attach to the wrong columns or have the wrong count.

Suggested direction: include view metadata in undo state or make column-width mutations separately undoable/synchronized after document undo/redo.

- [ ] Fixed?

## P2 Findings

### 8. Disjoint selection becomes stale after table mutations

References: `Source/AppState.swift:140-157`, `Source/AppState.swift:518-560`, `Source/AppState.swift:567-598`

`extraSelections` stores absolute row/column positions. Insert/delete/move row/column operations adjust `selection`, but they do not remap or clear `extraSelections`. After deleting or moving rows/columns, extra selections can point at different cells than the user selected.

Suggested direction: clear all selections on structural table changes.

- [ ] Fixed?

### 9. Cmd-clicking the anchor in a disjoint selection cannot visually deselect it

References: `Source/AppState.swift:202-230`, `Source/SpreadsheetView.swift:388-397`

After a Cmd-click multi-selection, `selection` is moved to the clicked cell and the same cell can also be present in `extraSelections`. Cmd-clicking that anchor again removes it from `extraSelections`, but it remains selected through `selection`, so the visible state does not toggle as expected.

Suggested direction: if the toggled position is also the current single-cell anchor, choose another selected cell as anchor or clear `selection` when appropriate.

- [ ] Fixed?

### 10. Search does expensive whole-document work on every keystroke

References: `Source/FindReplaceContentView.swift:144-151`, `Source/CSVDocument.swift:473-507`, `Source/CSVDocument.swift:576-581`

Every search text/options change scans every cell. `matches` lowercases the query inside every cell comparison, and whole-word search compiles a regex per cell.

Performance impact: search will degrade quickly on large CSVs.

Suggested direction: debounce typing, precompute normalized query once per search, compile regex once, and consider background search.

- [ ] Fixed?

### 11. Selection membership checks scan `extraSelections` during rendering

References: `Source/SpreadsheetView.swift:160-164`, `Source/SpreadsheetView.swift:232-237`, `Source/AppState.swift:148-157`

Column and row headers call `extraSelections.contains(where:)`, which is O(number of extra selections). With many disjoint selections, each render can scan the same set repeatedly.

Suggested direction: maintain derived row/column index sets or use a range/sparse selection model with cheap membership queries.

- [ ] Fixed?

### 12. Highlight sets are recomputed from all search results during view updates

References: `Source/AppState.swift:397-403`, `Source/ContentView.swift:159-163`

`highlightedCells` and `highlightedRows` allocate new sets from all search results whenever SwiftUI reads them. With many matches, this adds repeated allocation and hashing during normal rendering.

Suggested direction: cache derived highlight sets when `searchResults` changes.

- [ ] Fixed?

### 13. Spreadsheet view has vertical laziness but no horizontal virtualization

References: `Source/SpreadsheetView.swift:110-123`, `Source/SpreadsheetView.swift:232-270`

`LazyVStack` virtualizes rows, but each visible row builds an `HStack` containing every column. Wide CSVs therefore render poorly even when only a subset of columns is visible.

Suggested direction: use a grid/table component with two-axis virtualization or a custom tiling strategy.

- [ ] Fixed?

### 14. `ForEach(Array(range))` allocates large index arrays during rendering

References: `Source/SpreadsheetView.swift:116`, `Source/SpreadsheetView.swift:160`, `Source/SpreadsheetView.swift:221`, `Source/SpreadsheetView.swift:266`, `Source/ContentView.swift:37`

The code repeatedly wraps ranges/enumerations in `Array(...)` for SwiftUI iteration. For large row/column counts, this creates avoidable allocations during body recomputation.

Suggested direction: prefer `ForEach(0..<count, id: \.self)` where possible; for tabs, consider stable indexed iteration without allocating an enumerated array.

- [ ] Fixed?

### 15. Range selection can edit an unintended anchor cell

References: `Source/SpreadsheetView.swift:194-213`, `Source/SpreadsheetView.swift:243-263`, `Source/ContentView.swift:431-436`, `Source/AppState.swift:285-302`

Whole-row and whole-column selections are represented as a rectangular `CellRange` with an anchor cell. Pressing Return starts editing the anchor, not the range. For a whole column, that means the header; for a whole row, that means the first cell.

This may be acceptable if intentional, but it is risky because the UI communicates a range selection while edit mode targets one cell.

Suggested direction: only allow editing when `selection.isSingleCell` and `extraSelections.isEmpty`, or make the anchor visually unambiguous.

- [ ] Fixed?

### 16. Drag/drop still has an active-tab race and weak file validation

References: `Source/ContentView.swift:71-77`, `Source/CSVDocument.swift:424-432`

The async provider callback loads into `appState.safeLoadFile`, which uses whatever tab is active when the callback fires, not necessarily the tab active at drop time. It also accepts any file URL and leaves binary/huge-file rejection to UTF-8 loading.

Suggested direction: capture the target tab at drop time and validate file type/size before load.

- [ ] Fixed?

### 17. Recent documents likely bypass app state

References: `Source/PanktiraApp.swift:308-314`

`RecentDocumentsMenu` calls `NSDocumentController.shared.openDocument`, but this is not an `NSDocument`-based app and the result is not routed through `AppState.safeLoadFile`.

Likely behavior: recent documents do nothing useful or bypass the tab/dirty-state flow.

Suggested direction: pass an `AppState` action into `RecentDocumentsMenu` and call `safeLoadFile(at:)`.

- [x] Fixed — `RecentDocumentsMenu` now takes `appState` and calls `safeLoadFile(at:)` instead of `NSDocumentController.shared.openDocument`.

### 18. CSV formula injection is not mitigated on export

References: `Source/CSVDocument.swift:381-395`

Cells beginning with `=`, `+`, `-`, or `@` are exported unchanged. If the generated CSV is opened in Excel, Numbers, or Google Sheets, those values may be interpreted as formulas.

Security impact: moderate when users edit/export untrusted CSV values and open them in formula-capable spreadsheet tools.

Counter-argument: many CSV editors intentionally preserve exact cell contents. Neutralizing formulas by default can corrupt legitimate data. A pragmatic compromise is an export option or warning. Do this!

- [ ] Fixed?

### 19. README platform requirements still mismatch project settings

References: `README.md:18-21`, `Panktira.xcodeproj/project.pbxproj:189`, `Panktira.xcodeproj/project.pbxproj:247`

README says macOS 14+ and Xcode 16+, but the project deployment target is macOS 26.1. This is probably the biggest packaging/documentation mismatch.

Suggested direction: either lower the deployment target or update README honestly.

- [ ] Fixed?

## P3 Findings

### 20. Load/save failures are invisible

References: `Source/CSVDocument.swift:424-432`, `Source/CSVDocument.swift:454-463`

Both load and save catch errors and do nothing. This is user-hostile and complicates debugging. It also compounds the P0 data-loss paths.

Suggested direction: return `Result` or expose an app-level alert/error state.

- [ ] Fixed?

### 21. UTF-8-only loading rejects common CSV encodings

References: `Source/CSVDocument.swift:424-427`

Many CSV files are UTF-8 with BOM, Windows-1252, ISO-8859-1, or UTF-16. Current loading accepts only strict UTF-8 and silently fails otherwise.

Suggested direction: detect BOMs, use `String.Encoding` fallback, or show a recoverable import dialog.

- [ ] Fixed?

### 22. CSV parser has incomplete RFC/error semantics

References: `Source/CSVDocument.swift:302-376`

The parser supports common quoted fields, embedded commas/newlines, and escaped quotes, but it does not report malformed CSV. Unclosed quotes, quotes appearing after unquoted characters, and trailing empty lines are accepted or normalized silently.

Counter-argument: permissive parsing is often desirable for messy CSVs. The issue is not permissiveness; it is the lack of diagnostics or strict mode.

- [ ] Fixed?

### 23. Selected-cell label ignores disjoint selection count

References: `Source/AppState.swift:257-269`, `Source/ContentView.swift:204-212`

`selectedCellAddress` only describes the primary range/anchor. If extra cells are selected via Cmd-click, the formula bar can still show a single address, which under-communicates the current selection state.

Suggested direction: show a count such as `5 cells` or include a separate status-bar selection summary.

- [ ] Fixed?

### 24. Tracked user-specific Xcode files remain in the repository

References: `Panktira.xcodeproj/project.xcworkspace/xcuserdata/grp.xcuserdatad/UserInterfaceState.xcuserstate`, `Panktira.xcodeproj/xcuserdata/grp.xcuserdatad/xcschemes/xcschememanagement.plist`, `.gitignore:5-7`

`.gitignore` excludes `xcuserdata/`, but user-specific files are already tracked. This creates noisy diffs and local state churn.

Suggested direction: remove tracked `xcuserdata` files from the index in a deliberate cleanup commit.

- [ ] Fixed?

### 25. Supporting assets may be packaged more broadly than needed

References: `Panktira.xcodeproj/project.pbxproj:69-72`, `Supporting Files/Logo/Logo.ai`

The `Supporting Files` folder is a synchronized root group. That can package source/design assets such as `Logo.ai` alongside app resources. This is not a major security issue, but it increases bundle size and may leak source design metadata.

Suggested direction: keep source artwork outside app resources or exclude it from the target.

- [ ] Fixed?

## Security Posture

Good:

- App sandbox is enabled: `Supporting Files/Panktira.entitlements:5-6`
- User-selected read/write is the only file entitlement: `Supporting Files/Panktira.entitlements:7-8`
- Hardened runtime is enabled in project settings: `Panktira.xcodeproj/project.pbxproj:266`, `Panktira.xcodeproj/project.pbxproj:299`
- No network, subprocess, dynamic code execution, shell invocation, or web rendering surface found.

Risks:

- Local file denial-of-service through large CSVs: high-likelihood if users open large exports.
- Selection denial-of-service through range flattening into `extraSelections`.
- CSV formula injection on export: context-dependent.
- Silent failures can mislead users about whether data was saved.

## Performance Priorities

1. Move file load/parse/search off the main actor.
2. Replace full-document snapshot undo or cap it.
3. Keep selection as ranges plus sparse cells; do not flatten large ranges.
4. Make bulk row/column mutations push one undo state.
5. Add file size/row/column limits with user-visible errors.
6. Avoid repeated render-time allocation: `Array(range)`, highlight-set recomputation, per-cell regex/query normalization, and `contains(where:)` selection scans.
7. Plan for horizontal virtualization before supporting wide CSVs.

## Suggested Fix Order

1. Save lifecycle and active-edit commit.
2. Main-thread CSV loading/parsing/search limits.
3. Selection data model and stale-selection remapping.
4. Undo batching and undo limits.
5. Column-width state synchronization.
6. Error reporting for load/save.
7. Recent documents and drag/drop target routing.
8. README/deployment target mismatch.
