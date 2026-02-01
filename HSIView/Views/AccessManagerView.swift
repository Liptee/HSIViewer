import SwiftUI
import AppKit

struct AccessManagerView: View {
    @ObservedObject private var store = SecurityScopedBookmarkStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddError = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Управление доступами")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Готово") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("Нет сохранённых доступов")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Добавьте папку, чтобы избежать повторных запросов доступа")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.entries) { entry in
                        let isActive = store.resolvedURL(for: entry) != nil
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.path)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Text(isActive ? "Доступ активен" : "Доступ утрачён")
                                    .font(.system(size: 9))
                                    .foregroundColor(isActive ? .secondary : .orange)
                            }
                            Spacer()
                            Button("Удалить") {
                                store.remove(entry)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
            
            HStack {
                Button("Добавить папку…") {
                    addFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
        .alert("Не удалось сохранить доступ", isPresented: $showAddError) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text("Попробуйте выбрать другую папку или проверьте права доступа.")
        }
    }
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.message = "Выберите папку, к которой нужно сохранить постоянный доступ"
        panel.prompt = "Добавить"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            if !store.addFolder(url: url) {
                showAddError = true
            }
        }
    }
}
