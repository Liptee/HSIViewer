import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryPanel: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded: Bool = true
    @State private var isTargeted: Bool = false
    @State private var selectedEntryIDs: Set<CubeLibraryEntry.ID> = []
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop(providers:))
        .focusable(true)
        .focusEffectDisabled(true)
        .focused($isFocused)
        .onDeleteCommand(perform: deleteSelectedEntries)
        .onChange(of: state.libraryEntries) { entries in
            let existingIDs = Set(entries.map(\.id))
            selectedEntryIDs = selectedEntryIDs.intersection(existingIDs)
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Библиотека")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            if isTargeted {
                Text("Отпустите, чтобы добавить")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.libraryEntries.isEmpty {
                Text("Перетащи файлы .mat, .tiff, .npy или .dat сюда, чтобы добавить их в библиотеку. Двойной клик по пути — открыть куб.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    )
            } else {
                ForEach(state.libraryEntries) { entry in
                    libraryRow(for: entry)
                }
            }
        }
        .padding(8)
    }
    
    @ViewBuilder
    private func libraryRow(for entry: CubeLibraryEntry) -> some View {
        let isActive = isEntryActive(entry)
        let isSelected = selectedEntryIDs.contains(entry.id) && !isActive
        let singleTap = TapGesture()
            .onEnded {
                handleSelection(for: entry, isCommandPressed: isCommandPressed())
                isFocused = true
            }
        
        let doubleTap = TapGesture(count: 2)
            .onEnded {
                selectSingleEntry(entry)
                state.open(url: entry.url)
            }
        
        let contextTargets = contextMenuTargets(for: entry)
        let canCopyFromSingle = contextTargets.count == 1 && contextTargets.first.map { state.canCopyProcessing(from: $0) } == true
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary)
            Text(entry.url.deletingLastPathComponent().path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(isActive: isActive, isSelected: isSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(isActive: isActive, isSelected: isSelected), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(doubleTap)
        .simultaneousGesture(singleTap)
        .contextMenu {
            Button("Копировать обработку") {
                if let target = contextTargets.first {
                    state.copyProcessing(from: target)
                }
            }
            .disabled(!canCopyFromSingle)
            
            if state.hasProcessingClipboard {
                Button("Вставить обработку") {
                    for target in contextTargets {
                        state.pasteProcessing(to: target)
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                removeEntries(contextTargets)
            } label: {
                Text("Удалить из библиотеки")
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL {
                    DispatchQueue.main.async {
                        state.addLibraryEntries(from: [url])
                    }
                }
            }
            handled = true
        }
        return handled
    }
    
    private func isEntryActive(_ entry: CubeLibraryEntry) -> Bool {
        guard let current = state.cubeURL?.standardizedFileURL.path else { return false }
        return current == entry.url.standardizedFileURL.path
    }
    
    private func backgroundColor(isActive: Bool, isSelected: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.2)
        } else if isSelected {
            return Color(NSColor.selectedControlColor).opacity(0.3)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(0.2)
        }
    }
    
    private func borderColor(isActive: Bool, isSelected: Bool) -> Color {
        if isActive {
            return Color.accentColor
        } else if isSelected {
            return Color(NSColor.selectedControlColor)
        } else {
            return Color(NSColor.separatorColor.withAlphaComponent(0.6))
        }
    }
    
    private func deleteSelectedEntries() {
        let entriesToDelete = state.libraryEntries.filter { selectedEntryIDs.contains($0.id) }
        removeEntries(entriesToDelete)
    }
    
    private func removeEntry(_ entry: CubeLibraryEntry) {
        removeEntries([entry])
    }
    
    private func removeEntries(_ entries: [CubeLibraryEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            state.removeLibraryEntry(entry)
            selectedEntryIDs.remove(entry.id)
        }
    }
    
    private func contextMenuTargets(for entry: CubeLibraryEntry) -> [CubeLibraryEntry] {
        if selectedEntryIDs.contains(entry.id) {
            let selected = state.libraryEntries.filter { selectedEntryIDs.contains($0.id) }
            return selected.isEmpty ? [entry] : selected
        } else {
            return [entry]
        }
    }
    
    private func selectSingleEntry(_ entry: CubeLibraryEntry) {
        selectedEntryIDs = [entry.id]
    }
    
    private func handleSelection(for entry: CubeLibraryEntry, isCommandPressed: Bool) {
        if isCommandPressed {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } else {
            selectSingleEntry(entry)
        }
    }
    
    private func isCommandPressed() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.modifierFlags.contains(.command)
    }
}
