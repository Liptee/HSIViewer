import SwiftUI
import UniformTypeIdentifiers

struct LibraryPanel: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded: Bool = true
    @State private var isTargeted: Bool = false
    
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
        VStack(alignment: .leading, spacing: 4) {
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
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color(NSColor.separatorColor.withAlphaComponent(0.6)), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            state.open(url: entry.url)
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
}
