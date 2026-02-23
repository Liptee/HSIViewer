import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GridLibraryWindowView: View {
    @EnvironmentObject var state: AppState

    @State private var isLibraryDropTargeted: Bool = false
    @State private var selectedEntryIDs: Set<CubeLibraryEntry.ID> = []
    @State private var hoveredEntryID: CubeLibraryEntry.ID?
    @State private var targetedCell: GridLibraryCellPosition?
    @State private var hoveredCell: GridLibraryCellPosition?
    @State private var selectedRowID: UUID?
    @State private var selectedColumnID: UUID?

    @State private var isEntryRenaming: Bool = false
    @State private var entryRenameText: String = ""
    @State private var entryRenameTargetID: CubeLibraryEntry.ID?

    @State private var isRowRenaming: Bool = false
    @State private var rowRenameText: String = ""
    @State private var rowRenameTargetID: UUID?

    @State private var isColumnRenaming: Bool = false
    @State private var columnRenameText: String = ""
    @State private var columnRenameTargetID: UUID?

    @FocusState private var isLibraryListFocused: Bool

    private let rowHeaderWidth: CGFloat = 170
    private let columnWidth: CGFloat = 180
    private let cellHeight: CGFloat = 72
    private let addButtonWidth: CGFloat = 44

    private var freeLibraryEntries: [CubeLibraryEntry] {
        state.libraryEntries.filter { state.gridLibraryCellPosition(for: $0.id) == nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
                .frame(width: 260)
            Divider()
            workspace
        }
        .frame(minWidth: 980, minHeight: 560)
        .onChange(of: state.libraryEntries) { _, entries in
            let existingIDs = Set(entries.map(\.id))
            selectedEntryIDs = selectedEntryIDs.intersection(existingIDs)
        }
        .onChange(of: state.gridLibraryAssignments) { _, _ in
            let freeIDs = Set(freeLibraryEntries.map(\.id))
            selectedEntryIDs = selectedEntryIDs.intersection(freeIDs)
        }
        .alert(state.localized("library.rename_cube.title"), isPresented: $isEntryRenaming) {
            TextField(state.localized("library.rename_cube.field_name"), text: $entryRenameText)
            Button(state.localized("common.save")) { commitEntryRename() }
            Button(state.localized("common.cancel"), role: .cancel) { cancelEntryRename() }
        } message: {
            Text(state.localized("library.rename_cube.message"))
        }
        .alert(state.localized("grid.rename_row.title"), isPresented: $isRowRenaming) {
            TextField(state.localized("grid.rename_row.field_name"), text: $rowRenameText)
            Button(state.localized("common.save")) { commitRowRename() }
            Button(state.localized("common.cancel"), role: .cancel) { cancelRowRename() }
        } message: {
            Text(state.localized("grid.rename_row.message"))
        }
        .alert(state.localized("grid.rename_column.title"), isPresented: $isColumnRenaming) {
            TextField(state.localized("grid.rename_column.field_name"), text: $columnRenameText)
            Button(state.localized("common.save")) { commitColumnRename() }
            Button(state.localized("common.cancel"), role: .cancel) { cancelColumnRename() }
        } message: {
            Text(state.localized("grid.rename_column.message"))
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(state.localized("grid.sidebar.hsi"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if isLibraryDropTargeted {
                    Text(state.localized("grid.sidebar.release_to_import"))
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isLibraryDropTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if state.libraryEntries.isEmpty {
                        Text(state.localized("grid.sidebar.empty_library"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                    } else if freeLibraryEntries.isEmpty {
                        Text(state.localized("grid.sidebar.all_assigned"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                    } else {
                        ForEach(freeLibraryEntries) { entry in
                            libraryEntryRow(entry)
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [UTType.fileURL], isTargeted: $isLibraryDropTargeted, perform: handleLibraryDrop(providers:))
        .focusable(true)
        .focusEffectDisabled(true)
        .focused($isLibraryListFocused)
        .onDeleteCommand(perform: deleteSelectedEntries)
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if state.gridLibraryRows.isEmpty || state.gridLibraryColumns.isEmpty {
                emptyGridState
            } else {
                gridTable
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(state.localized("grid.title"))
                .font(.system(size: 14, weight: .semibold))

            Text(state.localizedFormat("grid.header.counts", state.gridLibraryRows.count, state.gridLibraryColumns.count))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var emptyGridState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.localized("grid.empty_state.title"))
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                if state.gridLibraryRows.isEmpty {
                    Button(state.localized("grid.create_row")) { state.addGridLibraryRow() }
                }
                if state.gridLibraryColumns.isEmpty {
                    Button(state.localized("grid.create_column")) { state.addGridLibraryColumn() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var gridTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: rowHeaderWidth, height: 52)
                    ForEach(state.gridLibraryColumns) { column in
                        columnHeader(for: column)
                    }
                    addColumnButton
                }

                ForEach(state.gridLibraryRows) { row in
                    HStack(spacing: 6) {
                        rowHeader(for: row)
                        ForEach(state.gridLibraryColumns) { column in
                            gridCell(row: row, column: column)
                        }
                        Color.clear
                            .frame(width: addButtonWidth, height: cellHeight)
                    }
                }

                HStack(spacing: 6) {
                    addRowButton
                    ForEach(state.gridLibraryColumns) { _ in
                        Color.clear
                            .frame(width: columnWidth, height: 34)
                    }
                    Color.clear
                        .frame(width: addButtonWidth, height: 34)
                }
            }
            .padding(4)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var addColumnButton: some View {
        Button {
            state.addGridLibraryColumn()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: addButtonWidth, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .help(state.localized("grid.help.add_column"))
    }

    private var addRowButton: some View {
        Button {
            state.addGridLibraryRow()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(state.localized("grid.add_row"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: rowHeaderWidth, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .help(state.localized("grid.help.add_row"))
    }

    private func columnHeader(for column: GridLibraryAxisItem) -> some View {
        let index = state.gridLibraryColumns.firstIndex(where: { $0.id == column.id }) ?? 0
        let groupEntries = columnEntries(columnID: column.id)
        let isSelected = selectedColumnID == column.id
        let singleTap = TapGesture().onEnded {
            if selectedColumnID == column.id {
                selectedColumnID = nil
            } else {
                selectedColumnID = column.id
                selectedRowID = nil
            }
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            startColumnRename(column)
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(column.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: columnWidth, height: 52, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(doubleTap)
        .simultaneousGesture(singleTap)
        .contextMenu {
            groupContextMenu(for: groupEntries, scope: .column(column.id))
            Divider()
            Button(state.localized("grid.context.rename")) { startColumnRename(column) }
            Button(state.localized("grid.context.move_left")) { state.moveGridLibraryColumn(id: column.id, by: -1) }
                .disabled(index == 0)
            Button(state.localized("grid.context.move_right")) { state.moveGridLibraryColumn(id: column.id, by: 1) }
                .disabled(index >= state.gridLibraryColumns.count - 1)
            Divider()
            Button(role: .destructive) { state.removeGridLibraryColumn(id: column.id) } label: {
                Text(state.localized("grid.context.delete_column"))
            }
        }
    }

    private func rowHeader(for row: GridLibraryAxisItem) -> some View {
        let index = state.gridLibraryRows.firstIndex(where: { $0.id == row.id }) ?? 0
        let groupEntries = rowEntries(rowID: row.id)
        let isSelected = selectedRowID == row.id
        let singleTap = TapGesture().onEnded {
            if selectedRowID == row.id {
                selectedRowID = nil
            } else {
                selectedRowID = row.id
                selectedColumnID = nil
            }
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            startRowRename(row)
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: rowHeaderWidth, height: cellHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(doubleTap)
        .simultaneousGesture(singleTap)
        .contextMenu {
            groupContextMenu(for: groupEntries, scope: .row(row.id))
            Divider()
            Button(state.localized("grid.context.rename")) { startRowRename(row) }
            Button(state.localized("grid.context.move_up")) { state.moveGridLibraryRow(id: row.id, by: -1) }
                .disabled(index == 0)
            Button(state.localized("grid.context.move_down")) { state.moveGridLibraryRow(id: row.id, by: 1) }
                .disabled(index >= state.gridLibraryRows.count - 1)
            Divider()
            Button(role: .destructive) { state.removeGridLibraryRow(id: row.id) } label: {
                Text(state.localized("grid.context.delete_row"))
            }
        }
    }

    @ViewBuilder
    private func gridCell(row: GridLibraryAxisItem, column: GridLibraryAxisItem) -> some View {
        let position = GridLibraryCellPosition(rowID: row.id, columnID: column.id)
        let isTargeted = targetedCell == position
        let entryID = state.gridLibraryEntryID(rowID: row.id, columnID: column.id)
        let entry = entryID.flatMap { state.libraryEntry(for: $0) }
        let isRowSelected = selectedRowID == row.id
        let isColumnSelected = selectedColumnID == column.id
        let isAxisSelected = isRowSelected || isColumnSelected
        let isHovered = hoveredCell == position && entry != nil

        VStack(alignment: .leading, spacing: 2) {
            if let entry {
                Text(entry.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                libraryEntryStatsRow(for: entry, compact: true)
                wavelengthRangeLabel(for: entry, compact: true)
            } else {
                Text(state.localized("grid.cell.empty"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(width: columnWidth, height: cellHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    cellBackgroundColor(
                        isTargeted: isTargeted,
                        isAxisSelected: isAxisSelected,
                        hasEntry: entry != nil
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : (isAxisSelected ? Color.accentColor.opacity(0.7) : Color(NSColor.separatorColor)), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredCell = position
            } else if hoveredCell == position {
                hoveredCell = nil
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: Binding(
                get: { targetedCell == position },
                set: { value in
                    if value {
                        targetedCell = position
                    } else if targetedCell == position {
                        targetedCell = nil
                    }
                }
            ),
            perform: { providers in
                handleDropToCell(providers: providers, rowID: row.id, columnID: column.id)
            }
        )
        .onTapGesture(count: 2) {
            if let entry {
                selectedEntryIDs = [entry.id]
                state.open(url: entry.url)
            }
        }
        .onDrag {
            guard let entry else { return NSItemProvider() }
            return NSItemProvider(object: entry.url as NSURL)
        }
        .contextMenu {
            if let entry {
                entryContextMenu(for: [entry])
                Divider()
                Button(state.localized("grid.context.return_to_library")) {
                    state.clearGridLibraryCell(rowID: row.id, columnID: column.id)
                }
            } else {
                Button(state.localized("grid.context.return_to_library")) {
                    state.clearGridLibraryCell(rowID: row.id, columnID: column.id)
                }
                .disabled(true)
            }
        }
    }

    private func cellBackgroundColor(isTargeted: Bool, isAxisSelected: Bool, hasEntry: Bool) -> Color {
        if isTargeted {
            return Color.accentColor.opacity(0.18)
        }
        if hasEntry {
            return Color.accentColor.opacity(0.14)
        }
        if isAxisSelected {
            return Color.accentColor.opacity(0.1)
        }
        return Color(NSColor.windowBackgroundColor)
    }

    private func libraryEntryRow(_ entry: CubeLibraryEntry) -> some View {
        let isActive = isEntryActive(entry)
        let isSelected = selectedEntryIDs.contains(entry.id) && !isActive
        let isHovered = hoveredEntryID == entry.id
        let singleTap = TapGesture().onEnded {
            handleSelection(for: entry, isCommandPressed: isCommandPressed())
            isLibraryListFocused = true
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            selectedEntryIDs = [entry.id]
            state.open(url: entry.url)
        }
        let contextTargets = contextMenuTargets(for: entry)

        return VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary)
                .lineLimit(1)
            libraryEntryStatsRow(for: entry, compact: true)
            wavelengthRangeLabel(for: entry, compact: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(isActive: isActive, isSelected: isSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(isActive: isActive, isSelected: isSelected), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .highPriorityGesture(doubleTap)
        .simultaneousGesture(singleTap)
        .onHover { hovering in
            if hovering {
                hoveredEntryID = entry.id
            } else if hoveredEntryID == entry.id {
                hoveredEntryID = nil
            }
        }
        .onDrag {
            NSItemProvider(object: entry.url as NSURL)
        }
        .contextMenu {
            entryContextMenu(for: contextTargets)
        }
    }

    @ViewBuilder
    private func entryContextMenu(for targets: [CubeLibraryEntry]) -> some View {
        let canCopyFromSingle = targets.count == 1 && targets.first.map { state.canCopyProcessing(from: $0) } == true
        let canCopyWavelengths = targets.count == 1 && targets.first.map { state.canCopyWavelengths(from: $0) } == true
        let canCopySelections = targets.count == 1 && targets.first.map { state.canCopySpectrumSelections(from: $0) } == true
        let canPastePoint = state.canPasteSpectrumPoint
        let canPasteROI = state.canPasteSpectrumROI
        let canPasteSelections = state.canPasteSpectrumSelections
        let canRename = targets.count == 1

        Button(state.localized("library.context.copy_processing")) {
            if let target = targets.first { state.copyProcessing(from: target) }
        }
        .disabled(!canCopyFromSingle)

        if state.hasProcessingClipboard {
            Button(state.localized("library.context.paste_processing")) {
                for target in targets { state.pasteProcessing(to: target) }
            }
        }

        Divider()

        Button(state.localized("library.context.copy_wavelengths")) {
            if let target = targets.first { state.copyWavelengths(from: target) }
        }
        .disabled(!canCopyWavelengths)

        if state.hasWavelengthClipboard {
            Button(state.localized("library.context.paste_wavelengths")) {
                for target in targets { state.pasteWavelengths(to: target) }
            }
        }

        Divider()

        Button(state.localized("library.context.paste_point")) {
            for target in targets { state.pasteSpectrumPoint(to: target) }
        }
        .disabled(!canPastePoint)

        Button(state.localized("library.context.paste_area")) {
            for target in targets { state.pasteSpectrumROI(to: target) }
        }
        .disabled(!canPasteROI)

        Button(state.localized("library.context.copy_points_areas")) {
            if let target = targets.first { state.copySpectrumSelections(from: target) }
        }
        .disabled(!canCopySelections)

        Button(state.localized("library.context.paste_points_areas")) {
            for target in targets { state.pasteSpectrumSelections(to: target) }
        }
        .disabled(!canPasteSelections)

        Divider()

        Button(state.localized("library.context.rename")) {
            if let target = targets.first { startEntryRename(for: target) }
        }
        .disabled(!canRename)

        Divider()

        Button(role: .destructive) {
            removeEntries(targets)
        } label: {
            Text(state.localized("library.context.remove_from_library"))
        }
    }

    private func startEntryRename(for entry: CubeLibraryEntry) {
        entryRenameTargetID = entry.id
        entryRenameText = entry.displayName
        isEntryRenaming = true
    }

    private func commitEntryRename() {
        guard let targetID = entryRenameTargetID else { return }
        state.renameLibraryEntry(id: targetID, to: entryRenameText)
        cancelEntryRename()
    }

    private func cancelEntryRename() {
        isEntryRenaming = false
        entryRenameTargetID = nil
        entryRenameText = ""
    }

    private func startRowRename(_ row: GridLibraryAxisItem) {
        rowRenameTargetID = row.id
        rowRenameText = row.name
        isRowRenaming = true
    }

    private func commitRowRename() {
        guard let targetID = rowRenameTargetID else { return }
        state.renameGridLibraryRow(id: targetID, to: rowRenameText)
        cancelRowRename()
    }

    private func cancelRowRename() {
        isRowRenaming = false
        rowRenameTargetID = nil
        rowRenameText = ""
    }

    private func startColumnRename(_ column: GridLibraryAxisItem) {
        columnRenameTargetID = column.id
        columnRenameText = column.name
        isColumnRenaming = true
    }

    private func commitColumnRename() {
        guard let targetID = columnRenameTargetID else { return }
        state.renameGridLibraryColumn(id: targetID, to: columnRenameText)
        cancelColumnRename()
    }

    private func cancelColumnRename() {
        isColumnRenaming = false
        columnRenameTargetID = nil
        columnRenameText = ""
    }

    private func handleLibraryDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    state.addLibraryEntries(from: [url])
                }
            }
            handled = true
        }
        return handled
    }

    private func handleDropToCell(providers: [NSItemProvider], rowID: UUID, columnID: UUID) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    if let entry = state.libraryEntry(for: url) ?? state.addLibraryEntryIfPossible(from: url) {
                        state.assignLibraryEntryToGrid(entryID: entry.id, rowID: rowID, columnID: columnID)
                    }
                }
            }
            handled = true
        }
        return handled
    }

    private func contextMenuTargets(for entry: CubeLibraryEntry) -> [CubeLibraryEntry] {
        if selectedEntryIDs.contains(entry.id) {
            let selected = freeLibraryEntries.filter { selectedEntryIDs.contains($0.id) }
            return selected.isEmpty ? [entry] : selected
        }
        return [entry]
    }

    @ViewBuilder
    private func groupContextMenu(for targets: [CubeLibraryEntry], scope: GroupScope) -> some View {
        let hasTargets = !targets.isEmpty
        let canPastePoint = state.canPasteSpectrumPoint && hasTargets
        let canPasteROI = state.canPasteSpectrumROI && hasTargets
        let canPasteSelections = state.canPasteSpectrumSelections && hasTargets

        if hasTargets {
            Text(state.localizedFormat("grid.context.group.items_count", targets.count))
        } else {
            Text(state.localized("grid.context.group.empty"))
        }

        Button(state.localized("library.context.paste_processing")) {
            for target in targets { state.pasteProcessing(to: target) }
        }
        .disabled(!state.hasProcessingClipboard || !hasTargets)

        Button(state.localized("library.context.paste_wavelengths")) {
            for target in targets { state.pasteWavelengths(to: target) }
        }
        .disabled(!state.hasWavelengthClipboard || !hasTargets)

        Button(state.localized("library.context.paste_point")) {
            for target in targets { state.pasteSpectrumPoint(to: target) }
        }
        .disabled(!canPastePoint)

        Button(state.localized("library.context.paste_area")) {
            for target in targets { state.pasteSpectrumROI(to: target) }
        }
        .disabled(!canPasteROI)

        Button(state.localized("library.context.paste_points_areas")) {
            for target in targets { state.pasteSpectrumSelections(to: target) }
        }
        .disabled(!canPasteSelections)

        Divider()

        Button(state.localized("grid.context.group.return_to_library")) {
            clearGroupAssignments(scope: scope)
        }
        .disabled(!hasTargets)
    }

    private func rowEntries(rowID: UUID) -> [CubeLibraryEntry] {
        state.gridLibraryColumns.compactMap { column in
            guard let entryID = state.gridLibraryEntryID(rowID: rowID, columnID: column.id) else { return nil }
            return state.libraryEntry(for: entryID)
        }
    }

    private func columnEntries(columnID: UUID) -> [CubeLibraryEntry] {
        state.gridLibraryRows.compactMap { row in
            guard let entryID = state.gridLibraryEntryID(rowID: row.id, columnID: columnID) else { return nil }
            return state.libraryEntry(for: entryID)
        }
    }

    private func clearGroupAssignments(scope: GroupScope) {
        switch scope {
        case .row(let rowID):
            for column in state.gridLibraryColumns {
                state.clearGridLibraryCell(rowID: rowID, columnID: column.id)
            }
        case .column(let columnID):
            for row in state.gridLibraryRows {
                state.clearGridLibraryCell(rowID: row.id, columnID: columnID)
            }
        }
    }

    private func handleSelection(for entry: CubeLibraryEntry, isCommandPressed: Bool) {
        if isCommandPressed {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } else {
            selectedEntryIDs = [entry.id]
        }
    }

    private func deleteSelectedEntries() {
        let entriesToDelete = state.libraryEntries.filter { selectedEntryIDs.contains($0.id) }
        removeEntries(entriesToDelete)
    }

    private func removeEntries(_ entries: [CubeLibraryEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            state.removeLibraryEntry(entry)
            selectedEntryIDs.remove(entry.id)
        }
    }

    private func isEntryActive(_ entry: CubeLibraryEntry) -> Bool {
        guard let current = state.cubeURL?.standardizedFileURL.path else { return false }
        return current == entry.url.standardizedFileURL.path
    }

    private func backgroundColor(isActive: Bool, isSelected: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.2)
        }
        if isSelected {
            return Color(NSColor.selectedControlColor).opacity(0.3)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.2)
    }

    private func borderColor(isActive: Bool, isSelected: Bool) -> Color {
        if isActive {
            return Color.accentColor
        }
        if isSelected {
            return Color(NSColor.selectedControlColor)
        }
        return Color(NSColor.separatorColor.withAlphaComponent(0.6))
    }
    
    private func libraryEntryStatsRow(for entry: CubeLibraryEntry, compact: Bool) -> some View {
        let stats = state.libraryEntryStats(for: entry)
        let fontSize: CGFloat = compact ? 8 : 9
        let spacing: CGFloat = compact ? 8 : 10
        
        return HStack(spacing: spacing) {
            statsBadge(systemImage: "point.topleft.down.to.point.bottomright.curvepath", count: stats.points, fontSize: fontSize)
            statsBadge(systemImage: "rectangle.dashed", count: stats.roi, fontSize: fontSize)
            statsBadge(systemImage: "line.3.horizontal.decrease.circle", count: stats.pipelineOperations, fontSize: fontSize)
        }
    }
    
    private func statsBadge(systemImage: String, count: Int, fontSize: CGFloat) -> some View {
        Label("\(count)", systemImage: systemImage)
            .font(.system(size: fontSize))
            .foregroundColor(.secondary)
    }

    private func wavelengthRangeLabel(for entry: CubeLibraryEntry, compact: Bool) -> some View {
        let fontSize: CGFloat = compact ? 8 : 9
        return Label(state.libraryEntryWavelengthRangeText(for: entry), systemImage: "waveform.path")
            .font(.system(size: fontSize))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }

    private func isCommandPressed() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.modifierFlags.contains(.command)
    }

    private enum GroupScope {
        case row(UUID)
        case column(UUID)
    }
}
