import SwiftUI
import AppKit

struct AccessManagerView: View {
    @ObservedObject private var store = SecurityScopedBookmarkStore.shared
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddError = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(state.localized("access.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(state.localized("common.done")) {
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
                    Text(state.localized("access.empty.saved_none"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(state.localized("access.empty.add_hint"))
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
                                Text(isActive ? state.localized("access.status.active") : state.localized("access.status.lost"))
                                    .font(.system(size: 9))
                                    .foregroundColor(isActive ? .secondary : .orange)
                            }
                            Spacer()
                            Button(state.localized("common.remove")) {
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
                Button(state.localized("access.add_folder")) {
                    addFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
        .alert(state.localized("access.alert.save_failed.title"), isPresented: $showAddError) {
            Button(state.localized("common.ok"), role: .cancel) {}
        } message: {
            Text(state.localized("access.alert.save_failed.message"))
        }
    }
    
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.message = state.localized("access.panel.select_folder.message")
        panel.prompt = state.localized("access.panel.select_folder.prompt_add")
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
