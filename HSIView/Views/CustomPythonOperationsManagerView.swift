import SwiftUI

struct CustomPythonOperationsManagerView: View {
    let layout: CubeLayout
    let onInsert: (CustomPythonOperationTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CustomPythonOperationStore.shared

    @State private var selectedTemplateID: UUID?
    @State private var showingCreateEditor = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("custom.python.manager.title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(L("common.done")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)

            Divider()

            if store.templates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(L("custom.python.manager.empty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Button(L("custom.python.manager.create")) {
                        showingCreateEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List(selection: $selectedTemplateID) {
                    ForEach(store.templates) { template in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text(LF("custom.python.manager.updated", formattedDate(template.updatedAt)))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .tag(template.id)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 10) {
                    Button(L("custom.python.manager.create")) {
                        showingCreateEditor = true
                    }
                    .buttonStyle(.bordered)

                    Button(L("custom.python.manager.delete")) {
                        guard let selectedTemplateID else { return }
                        store.deleteTemplate(id: selectedTemplateID)
                        self.selectedTemplateID = store.templates.first?.id
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedTemplateID == nil)

                    Spacer()

                    Button(L("custom.python.manager.add_to_pipeline")) {
                        guard let template = selectedTemplate else { return }
                        onInsert(template)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTemplate == nil)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .onAppear {
            if selectedTemplateID == nil {
                selectedTemplateID = store.templates.first?.id
            }
        }
        .sheet(isPresented: $showingCreateEditor) {
            CustomPythonOperationEditorSheet(layout: layout) { created in
                selectedTemplateID = created.id
            }
        }
    }

    private var selectedTemplate: CustomPythonOperationTemplate? {
        guard let selectedTemplateID else { return nil }
        return store.template(for: selectedTemplateID)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = AppLocalizer.locale
        return formatter.string(from: date)
    }
}

private struct CustomPythonOperationEditorSheet: View {
    let layout: CubeLayout
    let onSave: (CustomPythonOperationTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var script: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("custom.python.editor.create_title"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(L("common.cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(L("custom.python.editor.name"))
                    .font(.system(size: 11, weight: .medium))
                TextField(L("custom.python.operation.default_name"), text: $name)
                    .textFieldStyle(.roundedBorder)

                Text(
                    LF(
                        "custom.python.editor.layout",
                        layout == .auto ? CubeLayout.hwc.rawValue : layout.rawValue
                    )
                )
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                Text(L("custom.python.editor.code"))
                    .font(.system(size: 11, weight: .medium))
                TextEditor(text: $script)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 320)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button(L("common.save")) {
                    let created = CustomPythonOperationStore.shared.createTemplate(
                        name: name,
                        script: script
                    )
                    onSave(created)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if script.isEmpty {
                script = CustomPythonOperationTemplate.defaultScript(layout: layout)
            }
        }
    }
}
