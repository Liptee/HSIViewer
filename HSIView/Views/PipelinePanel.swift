import SwiftUI
import AppKit

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
    
    @State private var localNormalizationType: CubeNormalizationType = .none
    @State private var localNormalizationParams: CubeNormalizationParameters = .default
    @State private var localPreserveDataType: Bool = true
    @State private var localTargetDataType: DataType = .float64
    @State private var localAutoScale: Bool = true
    @State private var localRotationAngle: RotationAngle = .degree90
    @State private var localCropParameters: SpatialCropParameters = SpatialCropParameters(left: 0, right: 0, top: 0, bottom: 0)
    
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
        .frame(width: 960, height: 620)
        .onAppear {
            loadLocalState()
        }
        .onChange(of: operation?.id) { _ in
            loadLocalState()
        }
    }
    
    private func loadLocalState() {
        guard let op = operation else { return }
        
        switch op.type {
        case .normalization, .channelwiseNormalization:
            localNormalizationType = op.normalizationType ?? .none
            localNormalizationParams = op.normalizationParams ?? .default
            localPreserveDataType = op.preserveDataType ?? true
        case .dataTypeConversion:
            localTargetDataType = op.targetDataType ?? .float64
            localAutoScale = op.autoScale ?? true
        case .rotation:
            localRotationAngle = op.rotationAngle ?? .degree90
        case .spatialCrop:
            if let params = op.cropParameters {
                localCropParameters = params
            }
        }
    }
    
    private func saveLocalState() {
        guard let op = operation,
              let index = state.pipelineOperations.firstIndex(where: { $0.id == op.id }) else {
            return
        }
        
        switch op.type {
        case .normalization, .channelwiseNormalization:
            state.pipelineOperations[index].normalizationType = localNormalizationType
            state.pipelineOperations[index].normalizationParams = localNormalizationParams
            state.pipelineOperations[index].preserveDataType = localPreserveDataType
        case .dataTypeConversion:
            state.pipelineOperations[index].targetDataType = localTargetDataType
            state.pipelineOperations[index].autoScale = localAutoScale
        case .rotation:
            state.pipelineOperations[index].rotationAngle = localRotationAngle
        case .spatialCrop:
            state.pipelineOperations[index].cropParameters = localCropParameters
        }
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
        case .normalization, .channelwiseNormalization:
            normalizationEditor(for: op)
        case .dataTypeConversion:
            dataTypeEditor(for: op)
        case .rotation:
            rotationEditor(for: op)
        case .spatialCrop:
            cropEditor(for: op)
        }
    }
    
    private func normalizationEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Тип нормализации:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localNormalizationType) {
                ForEach(CubeNormalizationType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            
            if localNormalizationType.hasParameters {
                Divider()
                
                if localNormalizationType == .minMaxCustom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Диапазон:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.minValue, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("→")
                            
                            TextField("Max", value: $localNormalizationParams.maxValue, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else if localNormalizationType == .percentile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Процентили:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Lower", value: $localNormalizationParams.lowerPercentile, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                            Text("→")
                            
                            TextField("Upper", value: $localNormalizationParams.upperPercentile, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                        }
                    }
                }
            }
            
            Divider()
            
            Toggle("Сохранить тип данных", isOn: $localPreserveDataType)
                .font(.system(size: 11))
            
            Text(localPreserveDataType 
                 ? "При нормализации тип данных будет сохранён, если диапазон позволяет (например, UInt8 для [0, 255])"
                 : "Результат нормализации всегда будет Float64")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            Text(localNormalizationType.description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func dataTypeEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Целевой тип данных:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localTargetDataType) {
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
            
            Toggle("Автоматическое масштабирование", isOn: $localAutoScale)
                .font(.system(size: 11))
            
            Text(localAutoScale 
                 ? "Данные будут масштабированы в диапазон целевого типа"
                 : "Значения будут обрезаны (clamped)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func rotationEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Угол поворота:")
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 12) {
                ForEach(RotationAngle.allCases) { angle in
                    Button(action: {
                        localRotationAngle = angle
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(localRotationAngle == angle ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: rotationIcon(for: angle))
                                    .font(.system(size: 32))
                                    .foregroundColor(localRotationAngle == angle ? .accentColor : .secondary)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(localRotationAngle == angle ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            
                            Text(angle.rawValue)
                                .font(.system(size: 12, weight: localRotationAngle == angle ? .semibold : .regular))
                                .foregroundColor(localRotationAngle == angle ? .accentColor : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Поворот выполняется по часовой стрелке относительно центра изображения")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func cropEditor(for op: PipelineOperation) -> some View {
        let preview = currentPreviewImage()
        let currentSpatialSize = spatialSize(for: op)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Выбор области обрезки:")
                .font(.system(size: 11, weight: .medium))
            
            if let cropSize = currentSpatialSize, cropSize.width > 0, cropSize.height > 0 {
                HStack(alignment: .top, spacing: 20) {
                    SpatialCropPreview(
                        image: preview,
                        pixelWidth: cropSize.width,
                        pixelHeight: cropSize.height,
                        parameters: bindingForParameters(width: cropSize.width, height: cropSize.height)
                    )
                    .frame(height: 420)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                    .cornerRadius(14)
                    
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Размер области")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(cropSize.width) × \(cropSize.height) px")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                            Text("Layout: \(op.layout.rawValue)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Границы (px)")
                                .font(.system(size: 11, weight: .semibold))
                            
                            VStack(spacing: 10) {
                                cropValueField(
                                    label: "Левая граница",
                                    value: binding(for: \.left, width: cropSize.width, height: cropSize.height),
                                    range: 0...max(cropSize.width - 1, 0)
                                )
                                
                                cropValueField(
                                    label: "Правая граница",
                                    value: binding(for: \.right, width: cropSize.width, height: cropSize.height),
                                    range: 0...max(cropSize.width - 1, 0)
                                )
                                
                                cropValueField(
                                    label: "Верхняя граница",
                                    value: binding(for: \.top, width: cropSize.width, height: cropSize.height),
                                    range: 0...max(cropSize.height - 1, 0)
                                )
                                
                                cropValueField(
                                    label: "Нижняя граница",
                                    value: binding(for: \.bottom, width: cropSize.width, height: cropSize.height),
                                    range: 0...max(cropSize.height - 1, 0)
                                )
                            }
                        }
                    }
                    .frame(width: 280)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    )
                }
                .onAppear {
                    clampCropParametersIfNeeded(width: cropSize.width, height: cropSize.height)
                }
                .onChange(of: state.cube?.id) { _ in
                    if let freshSize = spatialSize(for: op) {
                        clampCropParametersIfNeeded(width: freshSize.width, height: freshSize.height)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("Предпросмотр недоступен")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
    }
    
    private func currentPreviewImage() -> NSImage? {
        guard let cube = state.cube else { return nil }
        let layout = state.layout
        let totalChannels = cube.channelCount(for: layout)
        let clampedChannel = max(0, min(Int(state.currentChannel), max(totalChannels - 1, 0)))
        
        switch state.viewMode {
        case .gray:
            return ImageRenderer.renderGrayscale(
                cube: cube,
                layout: layout,
                channelIndex: clampedChannel
            )
        case .rgb:
            if let wavelengths = state.wavelengths, wavelengths.count >= totalChannels {
                return ImageRenderer.renderRGB(
                    cube: cube,
                    layout: layout,
                    wavelengths: wavelengths
                )
            } else {
                return ImageRenderer.renderGrayscale(
                    cube: cube,
                    layout: layout,
                    channelIndex: clampedChannel
                )
            }
        }
    }
    
    private func spatialSize(for op: PipelineOperation) -> (width: Int, height: Int)? {
        guard let cube = state.cube else { return nil }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        guard let axes = cube.axes(for: op.layout) ?? cube.axes(for: state.layout) else {
            return nil
        }
        return (dims[axes.width], dims[axes.height])
    }
    
    private func clampCropParametersIfNeeded(width: Int, height: Int) {
        localCropParameters = localCropParameters.clamped(
            maxWidth: max(width, 1),
            maxHeight: max(height, 1)
        )
    }
    
    private func bindingForParameters(width: Int, height: Int) -> Binding<SpatialCropParameters> {
        Binding(
            get: { localCropParameters },
            set: { newValue in
                localCropParameters = newValue.clamped(maxWidth: width, maxHeight: height)
            }
        )
    }
    
    private func binding(for keyPath: WritableKeyPath<SpatialCropParameters, Int>, width: Int, height: Int) -> Binding<Int> {
        Binding(
            get: { localCropParameters[keyPath: keyPath] },
            set: { newValue in
                localCropParameters[keyPath: keyPath] = newValue
                localCropParameters = localCropParameters.clamped(maxWidth: width, maxHeight: height)
            }
        )
    }
    
    private func cropValueField(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
            HStack(spacing: 8) {
                TextField("0", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            Text("\(value.wrappedValue) px")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    private func rotationIcon(for angle: RotationAngle) -> String {
        switch angle {
        case .degree90:
            return "rotate.right"
        case .degree180:
            return "arrow.up.arrow.down"
        case .degree270:
            return "rotate.left"
        }
    }
    
    private var footerView: some View {
        HStack {
            if !state.pipelineAutoApply {
                Button(action: {
                    saveLocalState()
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
                saveLocalState()
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

struct SpatialCropPreview: View {
    let image: NSImage?
    let pixelWidth: Int
    let pixelHeight: Int
    @Binding var parameters: SpatialCropParameters
    
    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let fittedSize = fittedSize(for: image?.size ?? CGSize(width: 1, height: 1), in: containerSize)
            let offsetX = (containerSize.width - fittedSize.width) / 2
            let offsetY = (containerSize.height - fittedSize.height) / 2
            
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            Text("Нет предпросмотра")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        )
                        .frame(width: fittedSize.width, height: fittedSize.height)
                }
                
                if pixelWidth > 0 && pixelHeight > 0 {
                    CropOverlayView(
                        parameters: $parameters,
                        pixelWidth: pixelWidth,
                        pixelHeight: pixelHeight
                    )
                    .frame(width: fittedSize.width, height: fittedSize.height)
                }
            }
            .frame(width: fittedSize.width, height: fittedSize.height)
            .position(x: offsetX + fittedSize.width / 2, y: offsetY + fittedSize.height / 2)
        }
    }
    
    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            let minSide = min(container.width, container.height)
            return CGSize(width: minSide, height: minSide)
        }
        let widthScale = container.width / imageSize.width
        let heightScale = container.height / imageSize.height
        let scale = min(widthScale, heightScale)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}

private struct CropOverlayView: View {
    @Binding var parameters: SpatialCropParameters
    let pixelWidth: Int
    let pixelHeight: Int
    
    @State private var dragSnapshot: SpatialCropParameters?
    
    var body: some View {
        if pixelWidth <= 0 || pixelHeight <= 0 {
            Color.clear
        } else {
            GeometryReader { geo in
                let widthLimit = max(pixelWidth, 1)
                let heightLimit = max(pixelHeight, 1)
                let xScale = geo.size.width / CGFloat(widthLimit)
                let yScale = geo.size.height / CGFloat(heightLimit)
                let rect = cropRect(xScale: xScale, yScale: yScale)
                
                ZStack {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                    
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .contentShape(Rectangle())
                        .gesture(moveGesture(xScale: xScale, yScale: yScale))
                    
                    edgeHandle()
                        .frame(width: 3, height: rect.height + 24)
                        .position(x: rect.minX, y: rect.midY)
                        .gesture(edgeGesture(.left, xScale: xScale, yScale: yScale))
                    
                    edgeHandle()
                        .frame(width: 3, height: rect.height + 24)
                        .position(x: rect.maxX, y: rect.midY)
                        .gesture(edgeGesture(.right, xScale: xScale, yScale: yScale))
                    
                    horizontalHandle()
                        .frame(width: rect.width + 24, height: 3)
                        .position(x: rect.midX, y: rect.minY)
                        .gesture(edgeGesture(.top, xScale: xScale, yScale: yScale))
                    
                    horizontalHandle()
                        .frame(width: rect.width + 24, height: 3)
                        .position(x: rect.midX, y: rect.maxY)
                        .gesture(edgeGesture(.bottom, xScale: xScale, yScale: yScale))
                }
            }
        }
    }
    
    private func cropRect(xScale: CGFloat, yScale: CGFloat) -> CGRect {
        let left = CGFloat(parameters.left) * xScale
        let right = CGFloat(parameters.right + 1) * xScale
        let top = CGFloat(parameters.top) * yScale
        let bottom = CGFloat(parameters.bottom + 1) * yScale
        return CGRect(
            x: left,
            y: top,
            width: max(1, right - left),
            height: max(1, bottom - top)
        )
    }
    
    @ViewBuilder
    private func edgeHandle() -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(0.9))
    }
    
    @ViewBuilder
    private func horizontalHandle() -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(0.9))
    }
    
    private func edgeGesture(_ edge: CropEdge, xScale: CGFloat, yScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragSnapshot == nil { dragSnapshot = parameters }
                guard let start = dragSnapshot else { return }
                var updated = start
                switch edge {
                case .left:
                    updated.left = start.left + deltaPixels(value.translation.width, scale: xScale)
                case .right:
                    updated.right = start.right + deltaPixels(value.translation.width, scale: xScale)
                case .top:
                    updated.top = start.top + deltaPixels(value.translation.height, scale: yScale)
                case .bottom:
                    updated.bottom = start.bottom + deltaPixels(value.translation.height, scale: yScale)
                }
                parameters = updated.clamped(maxWidth: pixelWidth, maxHeight: pixelHeight)
            }
            .onEnded { _ in
                dragSnapshot = nil
            }
    }
    
    private func moveGesture(xScale: CGFloat, yScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragSnapshot == nil { dragSnapshot = parameters }
                guard let start = dragSnapshot else { return }
                let rawDeltaX = deltaPixels(value.translation.width, scale: xScale)
                let rawDeltaY = deltaPixels(value.translation.height, scale: yScale)
                
                let minDeltaX = -start.left
                let maxDeltaX = (pixelWidth - 1) - start.right
                let minDeltaY = -start.top
                let maxDeltaY = (pixelHeight - 1) - start.bottom
                
                let clampedDeltaX = min(max(rawDeltaX, minDeltaX), maxDeltaX)
                let clampedDeltaY = min(max(rawDeltaY, minDeltaY), maxDeltaY)
                
                var updated = start
                updated.left = start.left + clampedDeltaX
                updated.right = start.right + clampedDeltaX
                updated.top = start.top + clampedDeltaY
                updated.bottom = start.bottom + clampedDeltaY
                parameters = updated
            }
            .onEnded { _ in
                dragSnapshot = nil
            }
    }
    
    private func deltaPixels(_ translation: CGFloat, scale: CGFloat) -> Int {
        guard scale.isFinite, scale != 0 else { return 0 }
        return Int((translation / scale).rounded())
    }
    
    private enum CropEdge {
        case left, right, top, bottom
    }
}
