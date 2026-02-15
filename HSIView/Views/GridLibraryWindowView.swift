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
        .alert("Переименовать куб", isPresented: $isEntryRenaming) {
            TextField("Название", text: $entryRenameText)
            Button("Сохранить") { commitEntryRename() }
            Button("Отмена", role: .cancel) { cancelEntryRename() }
        } message: {
            Text("Введите новое имя для выбранного куба.")
        }
        .alert("Переименовать ряд", isPresented: $isRowRenaming) {
            TextField("Название ряда", text: $rowRenameText)
            Button("Сохранить") { commitRowRename() }
            Button("Отмена", role: .cancel) { cancelRowRename() }
        } message: {
            Text("Введите новое имя ряда.")
        }
        .alert("Переименовать столбец", isPresented: $isColumnRenaming) {
            TextField("Название столбца", text: $columnRenameText)
            Button("Сохранить") { commitColumnRename() }
            Button("Отмена", role: .cancel) { cancelColumnRename() }
        } message: {
            Text("Введите новое имя столбца.")
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ГСИ")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if isLibraryDropTargeted {
                    Text("Отпустите для импорта")
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
                        Text("Перетащите файлы .mat, .tiff, .npy или .dat, чтобы добавить ГСИ в библиотеку.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            )
                    } else if freeLibraryEntries.isEmpty {
                        Text("Все элементы размещены в Grid-таблице. Удалите элемент из ячейки или удалите ряд/столбец, чтобы вернуть его в список.")
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
            Text("Grid-библиотека")
                .font(.system(size: 14, weight: .semibold))

            Text("\(state.gridLibraryRows.count) ряд(ов) • \(state.gridLibraryColumns.count) столбец(ов)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var emptyGridState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Таблица пока не готова")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                if state.gridLibraryRows.isEmpty {
                    Button("Создать ряд") { state.addGridLibraryRow() }
                }
                if state.gridLibraryColumns.isEmpty {
                    Button("Создать столбец") { state.addGridLibraryColumn() }
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
        .help("Добавить столбец")
    }

    private var addRowButton: some View {
        Button {
            state.addGridLibraryRow()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Добавить ряд")
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
        .help("Добавить ряд")
    }

    private func columnHeader(for column: GridLibraryAxisItem) -> some View {
        let index = state.gridLibraryColumns.firstIndex(where: { $0.id == column.id }) ?? 0
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
            Button("Переименовать…") { startColumnRename(column) }
            Button("Сдвинуть влево") { state.moveGridLibraryColumn(id: column.id, by: -1) }
                .disabled(index == 0)
            Button("Сдвинуть вправо") { state.moveGridLibraryColumn(id: column.id, by: 1) }
                .disabled(index >= state.gridLibraryColumns.count - 1)
            Divider()
            Button(role: .destructive) { state.removeGridLibraryColumn(id: column.id) } label: {
                Text("Удалить столбец")
            }
        }
    }

    private func rowHeader(for row: GridLibraryAxisItem) -> some View {
        let index = state.gridLibraryRows.firstIndex(where: { $0.id == row.id }) ?? 0
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
            Button("Переименовать…") { startRowRename(row) }
            Button("Сдвинуть вверх") { state.moveGridLibraryRow(id: row.id, by: -1) }
                .disabled(index == 0)
            Button("Сдвинуть вниз") { state.moveGridLibraryRow(id: row.id, by: 1) }
                .disabled(index >= state.gridLibraryRows.count - 1)
            Divider()
            Button(role: .destructive) { state.removeGridLibraryRow(id: row.id) } label: {
                Text("Удалить ряд")
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
                Text("Пусто")
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
                Button("Вернуть в библиотеку") {
                    state.clearGridLibraryCell(rowID: row.id, columnID: column.id)
                }
            } else {
                Button("Вернуть в библиотеку") {
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
        let canPastePoint = state.canPasteSpectrumPoint
        let canPasteROI = state.canPasteSpectrumROI
        let canRename = targets.count == 1

        Button("Копировать обработку") {
            if let target = targets.first { state.copyProcessing(from: target) }
        }
        .disabled(!canCopyFromSingle)

        if state.hasProcessingClipboard {
            Button("Вставить обработку") {
                for target in targets { state.pasteProcessing(to: target) }
            }
        }

        Divider()

        Button("Копировать длины волн") {
            if let target = targets.first { state.copyWavelengths(from: target) }
        }
        .disabled(!canCopyWavelengths)

        if state.hasWavelengthClipboard {
            Button("Вставить длины волн") {
                for target in targets { state.pasteWavelengths(to: target) }
            }
        }

        Divider()

        Button("Вставить точку") {
            for target in targets { state.pasteSpectrumPoint(to: target) }
        }
        .disabled(!canPastePoint)

        Button("Вставить область") {
            for target in targets { state.pasteSpectrumROI(to: target) }
        }
        .disabled(!canPasteROI)

        Divider()

        Button("Переименовать…") {
            if let target = targets.first { startEntryRename(for: target) }
        }
        .disabled(!canRename)

        Divider()

        Button(role: .destructive) {
            removeEntries(targets)
        } label: {
            Text("Удалить из библиотеки")
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
}
