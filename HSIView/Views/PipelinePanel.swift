import SwiftUI

struct PipelinePanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedOperation: UUID?
    @State private var showingAddMenu: Bool = false
    @State private var editingOperation: PipelineOperation?
    @State private var draggingItem: PipelineOperation?
    
    var body: some View {
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
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 2, y: 2)
        .frame(width: 280)
        .sheet(item: $editingOperation) { operation in
            OperationEditorView(operation: $editingOperation)
                .environmentObject(state)
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 14))
            Text("Пайплайн обработки")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Пайплайн пуст")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Нажмите + чтобы добавить обработку")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    private var operationsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(state.pipelineOperations) { operation in
                    OperationRow(
                        operation: operation,
                        isSelected: selectedOperation == operation.id,
                        isDragging: draggingItem?.id == operation.id,
                        onSelect: { selectedOperation = operation.id },
                        onEdit: { editingOperation = operation },
                        onDelete: {
                            if let index = state.pipelineOperations.firstIndex(where: { $0.id == operation.id }) {
                                state.removeOperation(at: index)
                            }
                        }
                    )
                    .onDrag {
                        draggingItem = operation
                        return NSItemProvider(object: operation.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: OperationDropDelegate(
                        item: operation,
                        operations: $state.pipelineOperations,
                        draggingItem: $draggingItem,
                        autoApply: state.pipelineAutoApply,
                        onApply: { state.applyPipeline() }
                    ))
                }
            }
            .padding(8)
        }
        .onDeleteCommand {
            if let selected = selectedOperation,
               let index = state.pipelineOperations.firstIndex(where: { $0.id == selected }) {
                state.removeOperation(at: index)
                selectedOperation = nil
            }
        }
    }
    
    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Toggle(isOn: $state.pipelineAutoApply) {
                    HStack(spacing: 4) {
                        Image(systemName: state.pipelineAutoApply ? "bolt.fill" : "hand.raised.fill")
                            .font(.system(size: 10))
                        Text(state.pipelineAutoApply ? "Авто" : "Ручной")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                
                if !state.pipelineAutoApply {
                    Button(action: { state.applyPipeline() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Применить")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.pipelineOperations.isEmpty)
                }
            }
            
            HStack(spacing: 8) {
                Button(action: { showingAddMenu.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Добавить")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showingAddMenu, arrowEdge: .bottom) {
                    addOperationMenu
                }
                
                Button(action: { state.clearPipeline() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Очистить")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.pipelineOperations.isEmpty)
            }
        }
        .padding(8)
    }
    
    private var addOperationMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PipelineOperationType.allCases) { type in
                Button(action: {
                    state.addOperation(type: type)
                    showingAddMenu = false
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: type.iconName)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            Text(type.description)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.01))
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                if type != PipelineOperationType.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 240)
        .padding(.vertical, 4)
    }
}

struct OperationRow: View {
    let operation: PipelineOperation
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
                    .foregroundColor(isSelected ? .accentColor : .primary)
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
                    HStack(spacing: 4) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(isDragging ? 0.5 : 1.0)
    }
}

struct OperationDropDelegate: SwiftUI.DropDelegate {
    let item: PipelineOperation
    @Binding var operations: [PipelineOperation]
    @Binding var draggingItem: PipelineOperation?
    let autoApply: Bool
    let onApply: () -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        if autoApply {
            DispatchQueue.main.async {
                onApply()
            }
        }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem else { return }
        guard draggingItem.id != item.id else { return }
        
        guard let fromIndex = operations.firstIndex(where: { $0.id == draggingItem.id }),
              let toIndex = operations.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        withAnimation(.default) {
            let fromItem = operations[fromIndex]
            operations.remove(at: fromIndex)
            operations.insert(fromItem, at: toIndex)
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return draggingItem != nil
    }
    
    func dropExited(info: DropInfo) {
    }
}

struct OperationEditorView: View {
    @Binding var operation: PipelineOperation?
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            if let op = operation {
                headerView(for: op)
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 16) {
                        editorContent(for: op)
                    }
                    .padding(16)
                }
                
                Divider()
                
                footerView
            }
        }
        .frame(width: 400, height: 500)
    }
    
    private func headerView(for op: PipelineOperation) -> some View {
        HStack {
            Image(systemName: op.type.iconName)
                .font(.system(size: 16))
            Text("Настройка: \(op.type.rawValue)")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private func editorContent(for op: PipelineOperation) -> some View {
        switch op.type {
        case .normalization:
            normalizationEditor(for: op)
        case .dataTypeConversion:
            dataTypeEditor(for: op)
        }
    }
    
    private func normalizationEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Тип нормализации:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: Binding(
                get: { op.normalizationType ?? .none },
                set: { newValue in
                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                        state.pipelineOperations[index].normalizationType = newValue
                    }
                }
            )) {
                ForEach(CubeNormalizationType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            
            if op.normalizationType?.hasParameters == true {
                Divider()
                
                if op.normalizationType == .minMaxCustom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Диапазон:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: Binding(
                                get: { op.normalizationParams?.minValue ?? 0.0 },
                                set: { newValue in
                                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                                        state.pipelineOperations[index].normalizationParams?.minValue = newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            
                            Text("→")
                            
                            TextField("Max", value: Binding(
                                get: { op.normalizationParams?.maxValue ?? 1.0 },
                                set: { newValue in
                                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                                        state.pipelineOperations[index].normalizationParams?.maxValue = newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                } else if op.normalizationType == .percentile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Процентили:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Lower", value: Binding(
                                get: { op.normalizationParams?.lowerPercentile ?? 2.0 },
                                set: { newValue in
                                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                                        state.pipelineOperations[index].normalizationParams?.lowerPercentile = newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                            Text("→")
                            
                            TextField("Upper", value: Binding(
                                get: { op.normalizationParams?.upperPercentile ?? 98.0 },
                                set: { newValue in
                                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                                        state.pipelineOperations[index].normalizationParams?.upperPercentile = newValue
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                        }
                    }
                }
            }
            
            Text(op.normalizationType?.description ?? "")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func dataTypeEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Целевой тип данных:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: Binding(
                get: { op.targetDataType ?? .float64 },
                set: { newValue in
                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                        state.pipelineOperations[index].targetDataType = newValue
                    }
                }
            )) {
                Text("Float64 (Double)").tag(DataType.float64)
                Text("Float32").tag(DataType.float32)
                Divider()
                Text("UInt8 (0-255)").tag(DataType.uint8)
                Text("UInt16 (0-65535)").tag(DataType.uint16)
                Divider()
                Text("Int8 (-128...127)").tag(DataType.int8)
                Text("Int16 (-32768...32767)").tag(DataType.int16)
                Text("Int32").tag(DataType.int32)
            }
            .pickerStyle(.menu)
            
            Divider()
            
            Toggle("Автоматическое масштабирование", isOn: Binding(
                get: { op.autoScale ?? true },
                set: { newValue in
                    if let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) {
                        state.pipelineOperations[index].autoScale = newValue
                    }
                }
            ))
            .font(.system(size: 11))
            
            Text(op.autoScale == true 
                 ? "Данные будут масштабированы в диапазон целевого типа"
                 : "Значения будут обрезаны (clamped)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var footerView: some View {
        HStack {
            if !state.pipelineAutoApply {
                Button(action: {
                    state.applyPipeline()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Применить изменения")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer()
            
            Button("Готово") {
                if state.pipelineAutoApply {
                    state.applyPipeline()
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
    }
}

