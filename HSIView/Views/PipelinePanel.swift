import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers

struct PipelinePanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedOperation: UUID?
    @State private var showingAddMenu: Bool = false
    @State private var showingCustomPythonManager: Bool = false
    @State private var editingOperation: PipelineOperation?
    @FocusState private var hasListFocus: Bool
    
    var body: some View {
        GlassPanel(cornerRadius: 12) {
        VStack(alignment: .leading, spacing: 0) {
            header
            
            Divider()
            
            if state.pipelineOperations.isEmpty {
                emptyState
            } else {
                operationsList
            }
            
            Divider()
            
            footer
        }
        }
        .frame(maxWidth: .infinity)
        .popover(isPresented: $showingAddMenu, arrowEdge: .trailing) {
            addOperationMenu
        }
        .sheet(item: $editingOperation) { operation in
            OperationEditorView(operation: $editingOperation)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingCustomPythonManager) {
            CustomPythonOperationsManagerView(layout: state.activeLayout) { template in
                state.addCustomPythonOperation(template: template)
                showingCustomPythonManager = false
            }
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 14))
            Text(state.localized("Пайплайн обработки"))
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text(state.localized("Пайплайн пуст"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showingAddMenu = true
        }
        .contextMenu {
            pipelineContextMenu
        }
    }
    
    private var operationsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(state.pipelineOperations) { operation in
                    OperationRow(
                        operation: operation,
                        accent: accentColor(for: operation.type),
                        isSelected: selectedOperation == operation.id,
                        isDragging: false,
                        onSelect: {
                            selectedOperation = operation.id
                            hasListFocus = true
                        },
                        onEdit: { editingOperation = operation },
                        onDelete: {
                            if let idx = state.pipelineOperations.firstIndex(where: { $0.id == operation.id }) {
                                state.removeOperation(at: idx)
                            }
                        }
                    )
                }
                
                Color.clear
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        showingAddMenu = true
                    }
            }
            .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showingAddMenu = true
        }
        .background(Color.clear)
        .contextMenu {
            pipelineContextMenu
        }
        .onDeleteCommand(perform: deleteSelectedOperation)
        .focusable()
        .focusEffectDisabled()
        .focused($hasListFocus)
        .onTapGesture {
            hasListFocus = true
        }
        .onAppear {
            hasListFocus = true
        }
        .background(
            DeleteKeyCatcher(
                isActive: Binding(
                    get: { hasListFocus },
                    set: { hasListFocus = $0 }
                ),
                onDelete: deleteSelectedOperation
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }

    private func deleteSelectedOperation() {
        guard let selected = selectedOperation,
              let index = state.pipelineOperations.firstIndex(where: { $0.id == selected }) else {
            return
        }
        state.removeOperation(at: index)
        selectedOperation = nil
    }
    
    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Toggle(isOn: $state.pipelineAutoApply) {
                    HStack(spacing: 4) {
                        Image(systemName: state.pipelineAutoApply ? "bolt.fill" : "hand.raised.fill")
                            .font(.system(size: 10))
                        Text(state.pipelineAutoApply ? state.localized("Автоматическое применение") : state.localized("Ручной"))
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                
                if !state.pipelineAutoApply {
                    Button(action: { state.applyPipeline() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text(state.localized("Применить"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.pipelineOperations.isEmpty)
                }
            }
        }
        .padding(8)
    }
    
    private var addOperationMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(operationGroups) { group in
                groupRow(group)
            }
        }
        .padding(12)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
    
    private struct OperationGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let iconName: String
        let accent: Color
        let types: [PipelineOperationType]
    }
    
    private var operationGroups: [OperationGroup] {
        [
            OperationGroup(
                id: "values",
                title: state.localized("Значения"),
                subtitle: state.localized("Нормализация, клиппинг, типы"),
                iconName: "slider.horizontal.3",
                accent: Color(NSColor.systemTeal),
                types: [
                    .normalization,
                    .channelwiseNormalization,
                    .clipping,
                    .dataTypeConversion
                ]
            ),
            OperationGroup(
                id: "spatial",
                title: state.localized("Геометрия"),
                subtitle: state.localized("Поворот, транспонирование, размер, обрезка"),
                iconName: "rectangle.compress.vertical",
                accent: Color(NSColor.systemOrange),
                types: [
                    .rotation,
                    .transpose,
                    .resize,
                    .spatialCrop
                ]
            ),
            OperationGroup(
                id: "spectral",
                title: state.localized("Спектр"),
                subtitle: state.localized("Калибровка и спектральные операции"),
                iconName: "waveform.path.ecg",
                accent: Color(NSColor.systemGreen),
                types: [
                    .spectralTrim,
                    .spectralInterpolation,
                    .spectralAlignment,
                    .calibration
                ]
            ),
            OperationGroup(
                id: "custom",
                title: state.localized("Кастомные"),
                subtitle: state.localized("Пользовательские Python-обработки"),
                iconName: "terminal",
                accent: Color(NSColor.systemBlue),
                types: [
                    .customPython
                ]
            )
        ]
    }

    @ViewBuilder
    private var pipelineContextMenu: some View {
        Button(state.localized("Добавить обработку…")) {
            showingAddMenu = true
        }
        
        Button(state.localized("Вставить")) {
            state.pastePipelineOperation()
        }
        .disabled(state.pipelineOperationClipboard == nil)
        
        if !state.pipelineOperations.isEmpty {
            Divider()
            Button(state.localized("Очистить")) {
                state.clearPipeline()
            }
        }
    }
    
    private func groupRow(_ group: OperationGroup) -> some View {
        HStack(spacing: 8) {
            ForEach(group.types) { type in
                operationChip(type, accent: group.accent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            group.accent.opacity(0.18),
                            Color(NSColor.controlBackgroundColor).opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(group.accent.opacity(0.45), lineWidth: 1)
        )
    }

    private func accentColor(for type: PipelineOperationType) -> Color {
        switch type {
        case .normalization, .channelwiseNormalization, .clipping, .dataTypeConversion:
            return Color(NSColor.systemTeal)
        case .rotation, .transpose, .resize, .spatialCrop:
            return Color(NSColor.systemOrange)
        case .spectralTrim, .spectralInterpolation, .spectralAlignment, .calibration:
            return Color(NSColor.systemGreen)
        case .customPython:
            return Color(NSColor.systemIndigo)
        }
    }
    
    private func operationChip(_ type: PipelineOperationType, accent: Color) -> some View {
        OperationChip(
            type: type,
            accent: accent,
            lineLimit: chipLineLimit(for: type)
        ) {
            if type == .customPython {
                showingAddMenu = false
                DispatchQueue.main.async {
                    showingCustomPythonManager = true
                }
            } else {
                state.addOperation(type: type)
                showingAddMenu = false
            }
        }
    }

    private func chipLineLimit(for type: PipelineOperationType) -> Int {
        type.localizedTitle.count <= 12 ? 1 : 2
    }
}

private struct OperationChip: View {
    let type: PipelineOperationType
    let accent: Color
    let lineLimit: Int
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                Text(type.localizedTitle)
                    .font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .frame(maxWidth: 80)
            }
            .frame(width: 88, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(NSColor.windowBackgroundColor),
                                accent.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(color: accent.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 8 : 4, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct OperationRow: View {
    @EnvironmentObject var state: AppState
    let operation: PipelineOperation
    let accent: Color
    let isSelected: Bool
    let isDragging: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(width: 16)
            
            HStack(spacing: 8) {
                Image(systemName: operation.type.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(accent)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Text(operation.detailsText)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isHovered || isSelected {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: isSelected
                        ? [accent.opacity(0.22), Color(NSColor.controlBackgroundColor)]
                        : [accent.opacity(0.12), Color(NSColor.controlBackgroundColor).opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(accent.opacity(isSelected ? 0.9 : 0.45), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onSelect()
            onEdit()
        }
        .onTapGesture {
            onSelect()
        }
        .onAppear {
            // ensure selection focus is set when rows render
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: accent.opacity(isHovered ? 0.35 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button(state.localized("Копировать")) {
                state.copyPipelineOperation(operation)
            }
        }
    }
}

private struct DeleteKeyCatcher: NSViewRepresentable {
    @Binding var isActive: Bool
    let onDelete: () -> Void
    
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onDelete = onDelete
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onDelete = onDelete
        guard isActive else { return }
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
    
    final class KeyView: NSView {
        var onDelete: (() -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51, 117:
                onDelete?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

