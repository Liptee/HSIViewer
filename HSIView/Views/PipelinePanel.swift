import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PipelinePanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedOperation: UUID?
    @State private var showingAddMenu: Bool = false
    @State private var editingOperation: PipelineOperation?
    @State private var draggingItem: PipelineOperation?
    @State private var dropIndicator: DropIndicator?
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
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Пайплайн пуст")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Вставить") {
                state.pastePipelineOperation()
            }
            .disabled(state.pipelineOperationClipboard == nil)
        }
    }
    
    private var operationsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(state.pipelineOperations.enumerated()), id: \.element.id) { index, operation in
                    VStack(spacing: 0) {
                        if dropIndicator?.targetIndex == index && dropIndicator?.position == .above {
                            dropIndicatorView
                        }
                        
                        OperationRow(
                            operation: operation,
                            isSelected: selectedOperation == operation.id,
                            isDragging: draggingItem?.id == operation.id,
                            onSelect: { selectedOperation = operation.id },
                            onEdit: { editingOperation = operation },
                            onDelete: {
                                if let idx = state.pipelineOperations.firstIndex(where: { $0.id == operation.id }) {
                                    state.removeOperation(at: idx)
                                }
                            }
                        )
                        .draggable(operation.id.uuidString) {
                            OperationRow(
                                operation: operation,
                                isSelected: true,
                                isDragging: true,
                                onSelect: {},
                                onEdit: {},
                                onDelete: {}
                            )
                            .frame(width: 260)
                            .opacity(0.8)
                            .onAppear { draggingItem = operation }
                        }
                        .dropDestination(for: String.self) { items, location in
                            handleDrop(items: items, targetIndex: index, location: location)
                        } isTargeted: { isTargeted in
                            handleDropTargeting(isTargeted: isTargeted, targetIndex: index)
                        }
                        
                        if dropIndicator?.targetIndex == index && dropIndicator?.position == .below {
                            dropIndicatorView
                        }
                    }
                }
                
                if state.pipelineOperations.count > 0 {
                    Color.clear
                        .frame(height: 30)
                        .dropDestination(for: String.self) { items, location in
                            handleDrop(items: items, targetIndex: state.pipelineOperations.count, location: location)
                        } isTargeted: { isTargeted in
                            if isTargeted && draggingItem != nil {
                                dropIndicator = DropIndicator(targetIndex: state.pipelineOperations.count - 1, position: .below)
                            } else if !isTargeted && dropIndicator?.targetIndex == state.pipelineOperations.count - 1 {
                                dropIndicator = nil
                            }
                        }
                }
            }
            .padding(8)
        }
        .contextMenu {
            Button("Вставить") {
                state.pastePipelineOperation()
            }
            .disabled(state.pipelineOperationClipboard == nil)
        }
        .onDeleteCommand {
            if let selected = selectedOperation,
               let index = state.pipelineOperations.firstIndex(where: { $0.id == selected }) {
                state.removeOperation(at: index)
                selectedOperation = nil
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasListFocus)
        .onTapGesture {
            hasListFocus = true
        }
        .onAppear {
            hasListFocus = true
        }
        .onChange(of: draggingItem) { oldValue, newValue in
            if newValue == nil {
                dropIndicator = nil
            }
        }
    }
    
    private var dropIndicatorView: some View {
        Capsule()
            .fill(Color.yellow)
            .frame(height: 4)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .shadow(color: .yellow.opacity(0.6), radius: 4, x: 0, y: 0)
    }
    
    private func handleDrop(items: [String], targetIndex: Int, location: CGPoint) -> Bool {
        guard let draggedIDString = items.first,
              let draggedID = UUID(uuidString: draggedIDString),
              let fromIndex = state.pipelineOperations.firstIndex(where: { $0.id == draggedID }) else {
            dropIndicator = nil
            draggingItem = nil
            return false
        }
        
        let position = dropIndicator?.position ?? .below
        var toIndex = targetIndex
        if position == .below {
            toIndex += 1
        }
        
        state.moveOperation(from: fromIndex, to: toIndex)
        dropIndicator = nil
        draggingItem = nil
        return true
    }
    
    private func handleDropTargeting(isTargeted: Bool, targetIndex: Int) {
        guard draggingItem != nil else { return }
        
        if isTargeted {
            if let draggedIndex = state.pipelineOperations.firstIndex(where: { $0.id == draggingItem?.id }) {
                let position: DropPosition = targetIndex <= draggedIndex ? .above : .below
                dropIndicator = DropIndicator(targetIndex: targetIndex, position: position)
            }
        } else {
            if dropIndicator?.targetIndex == targetIndex {
                dropIndicator = nil
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
    @EnvironmentObject var state: AppState
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
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
        .contextMenu {
            Button("Копировать") {
                state.copyPipelineOperation(operation)
            }
        }
    }
}

fileprivate enum DropPosition: Equatable {
    case above
    case below
}

fileprivate struct DropIndicator: Equatable {
    let targetIndex: Int
    let position: DropPosition
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
    @State private var localClippingParams: ClippingParameters = .default
    @State private var localRotationAngle: RotationAngle = .degree90
    @State private var localCropParameters: SpatialCropParameters = SpatialCropParameters(left: 0, right: 0, top: 0, bottom: 0)
    @State private var localCalibrationParams: CalibrationParameters = .default
    @State private var localResizeParams: ResizeParameters = .default
    @State private var localSpectralTrimParams: SpectralTrimParameters = SpectralTrimParameters(startChannel: 0, endChannel: 0)
    @State private var localSpectralInterpolationParams: SpectralInterpolationParameters = .default
    @State private var localSpectralAlignmentParams: SpectralAlignmentParameters = .default
    @State private var resizeAspectRatio: Double = 1.0
    @State private var isAdjustingResize: Bool = false
    @State private var isComputingAlignment: Bool = false
    @State private var showAlignmentDetails: Bool = false
    @State private var calibrationRefError: String?
    
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
        .frame(width: editorSize.width, height: editorSize.height)
        .onAppear {
            loadLocalState()
        }
        .onChange(of: operation?.id) { _ in
            loadLocalState()
        }
    }

    private var editorSize: CGSize {
        guard let op = operation else {
            return CGSize(width: 420, height: 540)
        }
        switch op.type {
        case .spatialCrop:
        return CGSize(width: 960, height: 620)
        case .calibration:
            return CGSize(width: 500, height: 600)
        case .resize:
            return CGSize(width: 500, height: 520)
        case .spectralTrim:
            return CGSize(width: 460, height: 420)
        case .spectralInterpolation:
            return CGSize(width: 520, height: 520)
        case .spectralAlignment:
            return CGSize(width: 520, height: 720)
        default:
            return CGSize(width: 420, height: 540)
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
            localTargetDataType = op.targetDataType ?? state.cube?.originalDataType ?? .float64
            localAutoScale = op.autoScale ?? true
        case .clipping:
            localClippingParams = op.clippingParams ?? .default
        case .rotation:
            localRotationAngle = op.rotationAngle ?? .degree90
        case .spatialCrop:
            if let params = op.cropParameters {
                localCropParameters = params
            }
        case .calibration:
            localCalibrationParams = op.calibrationParams ?? .default
        case .resize:
            localResizeParams = op.resizeParameters ?? .default
            resizeAspectRatio = deriveAspectRatio(for: op, params: localResizeParams)
        case .spectralTrim:
            localSpectralTrimParams = op.spectralTrimParams ?? SpectralTrimParameters(startChannel: 0, endChannel: 0)
        case .spectralInterpolation:
            localSpectralInterpolationParams = op.spectralInterpolationParams ?? .default
        case .spectralAlignment:
            localSpectralAlignmentParams = op.spectralAlignmentParams ?? .default
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
        case .clipping:
            state.pipelineOperations[index].clippingParams = localClippingParams
        case .rotation:
            state.pipelineOperations[index].rotationAngle = localRotationAngle
        case .resize:
            state.pipelineOperations[index].resizeParameters = localResizeParams
        case .spatialCrop:
            state.pipelineOperations[index].cropParameters = localCropParameters
        case .spectralTrim:
            state.pipelineOperations[index].spectralTrimParams = localSpectralTrimParams
        case .calibration:
            state.pipelineOperations[index].calibrationParams = localCalibrationParams
        case .spectralInterpolation:
            state.pipelineOperations[index].spectralInterpolationParams = localSpectralInterpolationParams
        case .spectralAlignment:
            state.pipelineOperations[index].spectralAlignmentParams = localSpectralAlignmentParams
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
        case .clipping:
            clippingEditor(for: op)
        case .rotation:
            rotationEditor(for: op)
        case .resize:
            resizeEditor(for: op)
        case .spatialCrop:
            cropEditor(for: op)
        case .spectralTrim:
            spectralTrimEditor(for: op)
        case .calibration:
            calibrationEditor(for: op)
        case .spectralInterpolation:
            spectralInterpolationEditor(for: op)
        case .spectralAlignment:
            spectralAlignmentEditor(for: op)
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
                } else if localNormalizationType == .manualRange {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Исходный диапазон:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.sourceMin, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("→")
                            
                            TextField("Max", value: $localNormalizationParams.sourceMax, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text("Новый диапазон:")
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.targetMin, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("→")
                            
                            TextField("Max", value: $localNormalizationParams.targetMax, format: .number)
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
            
            Text("Точность вычислений:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localNormalizationParams.computePrecision) {
                ForEach(NormalizationComputationPrecision.allCases) { precision in
                    Text(precision.rawValue).tag(precision)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            Toggle("Сохранить тип данных", isOn: $localPreserveDataType)
                .font(.system(size: 11))
                .disabled(localNormalizationParams.computePrecision == .float32)
            
            Group {
                if localNormalizationParams.computePrecision == .float32 {
                    Text("При выборе Float32 результат всегда будет Float32, независимо от исходного типа")
                } else if localPreserveDataType {
                    Text("При нормализации тип данных будет сохранён, если диапазон позволяет (например, UInt8 для [0, 255])")
                } else {
                    Text("Результат нормализации всегда будет Float64")
                }
            }
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

    private func resizeEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Размер:")
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ширина")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Width", value: $localResizeParams.targetWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                VStack(spacing: 4) {
                    Button(action: {
                        localResizeParams.lockAspectRatio.toggle()
                        if localResizeParams.lockAspectRatio {
                            resizeAspectRatio = deriveAspectRatio(for: op, params: localResizeParams)
                        }
                    }) {
                        Image(systemName: localResizeParams.lockAspectRatio ? "link" : "link.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(localResizeParams.lockAspectRatio ? .accentColor : .secondary)
                            .frame(width: 34, height: 34)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(localResizeParams.lockAspectRatio ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .help("Фиксировать соотношение сторон")
                    }
                    
                    Text("Соотношение")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Высота")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Height", value: $localResizeParams.targetHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            if localResizeParams.lockAspectRatio {
                Text(String(format: "Будет сохранено соотношение: %.3f", resizeAspectRatio))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Text("Алгоритм интерполяции:")
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localResizeParams.algorithm) {
                ForEach(ResizeAlgorithm.allCases) { algo in
                    Text(algo.rawValue).tag(algo)
                }
            }
            .pickerStyle(.menu)
            
            switch localResizeParams.algorithm {
            case .bicubic:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Параметр a (Catmull-Rom = -0.5):")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("-0.5", value: $localResizeParams.bicubicA, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            case .lanczos:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Число лепестков (a):")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Stepper(value: $localResizeParams.lanczosA, in: 1...8) {
                        Text("\(localResizeParams.lanczosA)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(width: 160, alignment: .leading)
                }
            default:
                EmptyView()
            }
            
            if localResizeParams.algorithm != .nearest {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Точность вычислений")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localResizeParams.computePrecision) {
                        ForEach(ResizeComputationPrecision.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
            
            Divider()
            
            Text("Каждый канал будет ресайзнут отдельно в выбранном алгоритме.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .onChange(of: localResizeParams.targetWidth) { newWidth in
            adjustLinkedHeight(with: newWidth)
        }
        .onChange(of: localResizeParams.targetHeight) { newHeight in
            adjustLinkedWidth(with: newHeight)
        }
        .onChange(of: localResizeParams.lockAspectRatio) { isLocked in
            guard isLocked else { return }
            resizeAspectRatio = deriveAspectRatio(for: op, params: localResizeParams)
        }
    }

    private func spectralInterpolationEditor(for op: PipelineOperation) -> some View {
        let wavelengths = state.cube?.wavelengths ?? state.wavelengths
        let sourceMin = wavelengths?.min() ?? 0
        let sourceMax = wavelengths?.max() ?? 0
        let hasWavelengths = wavelengths != nil && !(wavelengths?.isEmpty ?? true)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Спектральная интерполяция")
                .font(.system(size: 11, weight: .medium))
            
            if hasWavelengths {
                Text(String(format: "Исходный диапазон: %.2f – %.2f нм", sourceMin, sourceMax))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Длины волн не заданы — интерполяция невозможна")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Целевое число каналов")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Channels", value: $localSpectralInterpolationParams.targetChannelCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Stepper("", value: $localSpectralInterpolationParams.targetChannelCount, in: 1...8192)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Диапазон λ")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Min", value: $localSpectralInterpolationParams.targetMinLambda, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("–")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("Max", value: $localSpectralInterpolationParams.targetMaxLambda, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Метод")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralInterpolationParams.method) {
                        ForEach(SpectralInterpolationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("За пределами")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralInterpolationParams.extrapolation) {
                        ForEach(SpectralExtrapolationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Тип данных")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralInterpolationParams.dataType) {
                        ForEach(SpectralInterpolationDataType.allCases) { dt in
                            Text(dt.rawValue).tag(dt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
            
            if localSpectralInterpolationParams.extrapolation == .extrapolate {
                Text("Экстраполяция может давать нефизические значения за пределами диапазона.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if hasWavelengths {
                if localSpectralInterpolationParams.targetChannelCount <= 0 {
                    let count = state.cube?.channelCount(for: op.layout) ?? 1
                    localSpectralInterpolationParams.targetChannelCount = max(1, count)
                }
                if localSpectralInterpolationParams.targetMinLambda == 0 && localSpectralInterpolationParams.targetMaxLambda == 0 {
                    localSpectralInterpolationParams.targetMinLambda = sourceMin
                    localSpectralInterpolationParams.targetMaxLambda = sourceMax
                }
            }
        }
    }
    
    private func spectralAlignmentEditor(for op: PipelineOperation) -> some View {
        let channels = state.cube?.channelCount(for: op.layout) ?? state.channelCount
        let maxIndex = max(channels - 1, 0)
        let wavelengths = state.cube?.wavelengths ?? state.wavelengths
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Спектральное выравнивание")
                .font(.system(size: 11, weight: .medium))
            
            Text("Выравнивает все каналы относительно эталонного канала, оптимизируя целевую метрику.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Эталонный канал")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Канал", value: $localSpectralAlignmentParams.referenceChannel, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $localSpectralAlignmentParams.referenceChannel, in: 0...maxIndex)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    if let wavelengths, localSpectralAlignmentParams.referenceChannel < wavelengths.count {
                        Text("λ = \(String(format: "%.1f", wavelengths[localSpectralAlignmentParams.referenceChannel])) нм")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Метод оптимизации")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralAlignmentParams.method) {
                        ForEach(SpectralAlignmentMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Диапазон смещений")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Min", value: $localSpectralAlignmentParams.offsetMin, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("до")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("Max", value: $localSpectralAlignmentParams.offsetMax, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("px")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Шаг поиска")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Шаг", value: $localSpectralAlignmentParams.step, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Stepper("", value: $localSpectralAlignmentParams.step, in: 1...10)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Итерации оптимизации")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Stepper(value: $localSpectralAlignmentParams.iterations, in: 1...5) {
                            Text("\(localSpectralAlignmentParams.iterations)")
                                .font(.system(size: 11))
                                .frame(minWidth: 20, alignment: .trailing)
                        }
                        .controlSize(.small)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Целевая метрика")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralAlignmentParams.metric) {
                        ForEach(SpectralAlignmentMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Дополнительные опции")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Toggle(isOn: $localSpectralAlignmentParams.enableMultiscale) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Многомасштабный поиск")
                                .font(.system(size: 10))
                            Text("Ускоряет вычисление")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    
                    Toggle(isOn: $localSpectralAlignmentParams.enableSubpixel) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Субпиксельное уточнение")
                                .font(.system(size: 10))
                            Text("Повышает точность")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
                    let isActuallyComputed = (currentParams?.isComputed ?? false) || localSpectralAlignmentParams.isComputed
                    let currentResult = currentParams?.alignmentResult ?? localSpectralAlignmentParams.alignmentResult
                    
                    if isActuallyComputed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Вычислено")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                        if let result = currentResult {
                            Text("Ср. \(result.metricName): \(String(format: "%.4f", result.averageScore))")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    } else if state.isAlignmentInProgress {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Вычисление…")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text("Не вычислено")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Ожидаемое время: \(localSpectralAlignmentParams.formattedEstimatedTime(channelCount: channels))")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
                    let hasResult = (currentParams?.alignmentResult != nil) || (localSpectralAlignmentParams.alignmentResult != nil)
                    let isComputed = (currentParams?.isComputed ?? false) || localSpectralAlignmentParams.isComputed
                    
                    Button(action: {
                        showAlignmentDetails = true
                    }) {
                        Text("Подробнее")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasResult)
                    
                    Button(action: {
                        localSpectralAlignmentParams.cachedHomographies = nil
                        localSpectralAlignmentParams.alignmentResult = nil
                        localSpectralAlignmentParams.isComputed = false
                        localSpectralAlignmentParams.shouldCompute = false
                        saveLocalState()
                    }) {
                        Text("Сбросить")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isComputed)
                }
            }
            
            if state.isAlignmentInProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(state.alignmentProgressMessage)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(state.alignmentProgress * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: state.alignmentProgress)
                        .progressViewStyle(.linear)
                    
                    HStack(spacing: 16) {
                        if state.alignmentTotalChannels > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 9))
                                Text("Канал \(state.alignmentCurrentChannel)/\(state.alignmentTotalChannels)")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if !state.alignmentElapsedTime.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text("Прошло: \(state.alignmentElapsedTime)")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if !state.alignmentEstimatedTimeRemaining.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 9))
                                Text("Осталось: \(state.alignmentEstimatedTimeRemaining)")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.cyan)
                        }
                        
                        Spacer()
                    }
                    
                    if !state.alignmentStage.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stageColor(for: state.alignmentStage))
                                .frame(width: 6, height: 6)
                            Text(stageName(for: state.alignmentStage))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            } else {
                let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
                let isActuallyComputed = (currentParams?.isComputed ?? false) || localSpectralAlignmentParams.isComputed
                
                if !isActuallyComputed {
                    Button(action: {
                        saveLocalState()
                        state.startAlignmentComputation(operationId: op.id)
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Вычислить выравнивание")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: $state.showAlignmentVisualization) {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                            Text("Показать точки на изображении")
                                .font(.system(size: 10))
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    
                    Spacer()
                }
                
                if state.showAlignmentVisualization {
                    HStack(spacing: 12) {
                        Toggle(isOn: $state.alignmentPointsEditable) {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.point.up.left")
                                Text("Редактировать точки")
                                    .font(.system(size: 10))
                            }
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        
                        Button(action: {
                            state.resetAlignmentPoints()
                            localSpectralAlignmentParams.referencePoints = AlignmentPoint.defaultCorners()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("По умолчанию")
                            }
                            .font(.system(size: 9))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Spacer()
                    }
                    
                    if state.alignmentPointsEditable {
                        Text("Перетащите точки на изображении для настройки области выравнивания")
                            .font(.system(size: 9))
                            .foregroundColor(.cyan)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
                let isActuallyComputed = (currentParams?.isComputed ?? false) || localSpectralAlignmentParams.isComputed
                let cachedCount = (currentParams?.cachedHomographies?.count ?? 0) > 0 
                    ? (currentParams?.cachedHomographies?.count ?? 0) 
                    : (localSpectralAlignmentParams.cachedHomographies?.count ?? 0)
                
                if isActuallyComputed {
                    if cachedCount == channels {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Кэшированные гомографии готовы к применению")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }
                        Text("При применении к изображению с \(channels) каналами будут использованы сохранённые параметры без пересчёта.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else if cachedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Несовпадение числа каналов")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        Text("Кэш содержит \(cachedCount) гомографий, а изображение имеет \(channels) каналов. При применении будет выполнен пересчёт.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("При копировании обработки в другое изображение будут применены сохранённые параметры гомографии без пересчёта.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
        .onAppear {
            if localSpectralAlignmentParams.referenceChannel > maxIndex {
                localSpectralAlignmentParams.referenceChannel = maxIndex / 2
            }
        }
        .onChange(of: localSpectralAlignmentParams.enableMultiscale) { _ in
            saveLocalState()
        }
        .onChange(of: localSpectralAlignmentParams.enableSubpixel) { _ in
            saveLocalState()
        }
        .onChange(of: localSpectralAlignmentParams.iterations) { _ in
            saveLocalState()
        }
        .onChange(of: state.isAlignmentInProgress) { inProgress in
            if !inProgress {
                if let opIndex = state.pipelineOperations.firstIndex(where: { $0.id == op.id }),
                   let updatedParams = state.pipelineOperations[opIndex].spectralAlignmentParams {
                    localSpectralAlignmentParams = updatedParams
                }
            }
        }
        .sheet(isPresented: $showAlignmentDetails) {
            let currentResult = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams?.alignmentResult ?? localSpectralAlignmentParams.alignmentResult
            SpectralAlignmentDetailsView(
                result: currentResult,
                wavelengths: wavelengths
            )
        }
    }
    
    private func stageColor(for stage: String) -> Color {
        switch stage {
        case "init", "extract_ref": return .orange
        case "extract": return .yellow
        case "homography": return .blue
        case "apply": return .purple
        case "done", "complete": return .green
        default: return .gray
        }
    }
    
    private func stageName(for stage: String) -> String {
        switch stage {
        case "init": return "Инициализация"
        case "extract_ref": return "Извлечение референса"
        case "extract": return "Извлечение канала"
        case "homography": return "Поиск гомографии"
        case "apply": return "Применение преобразования"
        case "done": return "Канал обработан"
        case "complete": return "Завершено"
        default: return stage
        }
    }

    private func spectralTrimEditor(for op: PipelineOperation) -> some View {
        let channels = state.cube?.channelCount(for: op.layout) ?? state.channelCount
        let maxIndex = max(channels - 1, 0)
        let wavelengths = state.cube?.wavelengths ?? state.wavelengths
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Обрезка спектра")
                .font(.system(size: 11, weight: .medium))
            
            if let wavelengths, !wavelengths.isEmpty,
               localSpectralTrimParams.startChannel < wavelengths.count,
               localSpectralTrimParams.endChannel < wavelengths.count {
                Text("λ: \(String(format: "%.1f", wavelengths[localSpectralTrimParams.startChannel])) – \(String(format: "%.1f", wavelengths[localSpectralTrimParams.endChannel])) нм")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Начальный канал")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Stepper(value: $localSpectralTrimParams.startChannel, in: 0...maxIndex) {
                        Text("\(localSpectralTrimParams.startChannel)")
                            .font(.system(size: 11))
                            .frame(minWidth: 36, alignment: .leading)
                    }
                    .controlSize(.small)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Конечный канал")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Stepper(value: $localSpectralTrimParams.endChannel, in: 0...maxIndex) {
                        Text("\(localSpectralTrimParams.endChannel)")
                            .font(.system(size: 11))
                            .frame(minWidth: 36, alignment: .leading)
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            if localSpectralTrimParams.endChannel == 0 && maxIndex > 0 {
                localSpectralTrimParams.endChannel = maxIndex
            }
            localSpectralTrimParams.startChannel = min(localSpectralTrimParams.startChannel, maxIndex)
            localSpectralTrimParams.endChannel = min(localSpectralTrimParams.endChannel, maxIndex)
            if localSpectralTrimParams.endChannel < localSpectralTrimParams.startChannel {
                localSpectralTrimParams.endChannel = localSpectralTrimParams.startChannel
            }
        }
        .onChange(of: localSpectralTrimParams.startChannel) { newValue in
            if localSpectralTrimParams.endChannel < newValue {
                localSpectralTrimParams.endChannel = newValue
            }
        }
        .onChange(of: localSpectralTrimParams.endChannel) { newValue in
            if newValue < localSpectralTrimParams.startChannel {
                localSpectralTrimParams.startChannel = newValue
            }
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

    private func clippingEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ограничение значений (clipping):")
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Нижний порог")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("0", value: $localClippingParams.lower, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Верхний порог")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("1", value: $localClippingParams.upper, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            
            if localClippingParams.upper < localClippingParams.lower {
                Text("Верхний порог меньше нижнего — значения будут поменяны местами при применении.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
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
    
    private func calibrationEditor(for op: PipelineOperation) -> some View {
        let pointSamples = state.spectrumSamples.map { sample in
            SpectrumSampleSnapshot(
                id: sample.id,
                pixelX: sample.pixelX,
                pixelY: sample.pixelY,
                values: sample.values,
                colorIndex: sample.colorIndex,
                displayName: sample.displayName
            )
        }
        let roiSamples = state.roiSamples.map { sample in
            SpectrumROISampleSnapshot(
                id: sample.id,
                minX: sample.rect.minX,
                minY: sample.rect.minY,
                width: sample.rect.width,
                height: sample.rect.height,
                values: sample.values,
                colorIndex: sample.colorIndex,
                displayName: sample.displayName
            )
        }
        let channelCount = state.cube?.channelCount(for: op.layout) ?? 0
        let spatial = spatialSize(for: op)
        let scanAxisSize = spatial?.width
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Калибровка изображения")
                .font(.system(size: 11, weight: .medium))
            
            Text("Выберите спектры или REF файлы для белой и/или чёрной точки калибровки.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("Белая точка (эталон белого)")
                        .font(.system(size: 11, weight: .semibold))
                }
                
                if let whiteRef = localCalibrationParams.whiteRef {
                    calibrationRefRow(
                        ref: whiteRef,
                        tint: .yellow,
                        onClear: { localCalibrationParams.whiteRef = nil }
                    )
                } else if let white = localCalibrationParams.whiteSpectrum {
                    HStack {
                        Text(white.sourceName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Убрать") {
                            localCalibrationParams.whiteSpectrum = nil
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 8) {
                        spectrumPickerMenu(
                            label: "Выбрать белую точку",
                            pointSamples: pointSamples,
                            roiSamples: roiSamples
                        ) { spectrum in
                            localCalibrationParams.whiteSpectrum = spectrum
                            localCalibrationParams.whiteRef = nil
                            calibrationRefError = nil
                        }
                        
                        Button("Выбрать файл REF") {
                            selectCalibrationRef(
                                forWhite: true,
                                expectedChannels: channelCount
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(channelCount == 0)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.gray)
                    Text("Чёрная точка (эталон чёрного)")
                        .font(.system(size: 11, weight: .semibold))
                }
                
                if let blackRef = localCalibrationParams.blackRef {
                    calibrationRefRow(
                        ref: blackRef,
                        tint: .gray,
                        onClear: { localCalibrationParams.blackRef = nil }
                    )
                } else if let black = localCalibrationParams.blackSpectrum {
                    HStack {
                        Text(black.sourceName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Убрать") {
                            localCalibrationParams.blackSpectrum = nil
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 8) {
                        spectrumPickerMenu(
                            label: "Выбрать чёрную точку",
                            pointSamples: pointSamples,
                            roiSamples: roiSamples
                        ) { spectrum in
                            localCalibrationParams.blackSpectrum = spectrum
                            localCalibrationParams.blackRef = nil
                            calibrationRefError = nil
                        }
                        
                        Button("Выбрать файл REF") {
                            selectCalibrationRef(
                                forWhite: false,
                                expectedChannels: channelCount
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(channelCount == 0)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Направление сканирования:")
                    .font(.system(size: 11, weight: .medium))

                Toggle("Использовать параметры сканирования", isOn: $localCalibrationParams.useScanDirection)
                    .font(.system(size: 10))
                
                if !localCalibrationParams.useScanDirection,
                   localCalibrationParams.whiteRef != nil || localCalibrationParams.blackRef != nil {
                    Text("REF файлы обнаружены — возможно, стоит включить параметры сканирования.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Picker("", selection: $localCalibrationParams.scanDirection) {
                    ForEach(CalibrationScanDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .disabled(!localCalibrationParams.useScanDirection)
                
                if let scanAxisSize,
                   (localCalibrationParams.whiteRef?.scanLength != nil || localCalibrationParams.blackRef?.scanLength != nil) {
                    if localCalibrationParams.whiteRef?.scanLength != nil && localCalibrationParams.whiteRef?.scanLength != scanAxisSize {
                        calibrationRefWarning(text: "REF белого не совпадает с размером скана (\(scanAxisSize) px).")
                    }
                    if localCalibrationParams.blackRef?.scanLength != nil && localCalibrationParams.blackRef?.scanLength != scanAxisSize {
                        calibrationRefWarning(text: "REF чёрного не совпадает с размером скана (\(scanAxisSize) px).")
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Целевой диапазон:")
                    .font(.system(size: 11, weight: .medium))
                
                HStack {
                    Text("Min:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("0", value: $localCalibrationParams.targetMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("Max:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("1", value: $localCalibrationParams.targetMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                Toggle("Ограничивать в диапазоне", isOn: $localCalibrationParams.clampOutput)
                    .font(.system(size: 10))
            }
            
            if !localCalibrationParams.isConfigured {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Выберите хотя бы одну точку или REF для калибровки")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            if let error = calibrationRefError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }
    
    @ViewBuilder
    private func spectrumPickerMenu(
        label: String,
        pointSamples: [SpectrumSampleSnapshot],
        roiSamples: [SpectrumROISampleSnapshot],
        onSelect: @escaping (CalibrationSpectrum) -> Void
    ) -> some View {
        Menu {
            if pointSamples.isEmpty && roiSamples.isEmpty {
                Text("Нет сохранённых спектров")
                    .foregroundColor(.secondary)
            }
            
            if !pointSamples.isEmpty {
                Section("Точки") {
                    ForEach(pointSamples) { sample in
                        Button(sample.effectiveName) {
                            onSelect(CalibrationSpectrum.from(sample: sample))
                        }
                    }
                }
            }
            
            if !roiSamples.isEmpty {
                Section("Области ROI") {
                    ForEach(roiSamples) { sample in
                        Button(sample.effectiveName) {
                            onSelect(CalibrationSpectrum.from(roiSample: sample))
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                Text(label)
            }
            .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .disabled(pointSamples.isEmpty && roiSamples.isEmpty)
    }

    private func calibrationRefRow(ref: CalibrationRefData, tint: Color, onClear: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.sourceName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("REF \(ref.channels)×\(ref.scanLength)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Убрать") {
                onClear()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(8)
        .background(tint.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func calibrationRefWarning(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }
    
    private func selectCalibrationRef(forWhite: Bool, expectedChannels: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Выберите REF файл (HDR/RAW)"
        
        let hdrType = UTType(filenameExtension: "hdr") ?? .data
        let rawType = UTType(filenameExtension: "raw") ?? .data
        let datType = UTType(filenameExtension: "dat") ?? .data
        let imgType = UTType(filenameExtension: "img") ?? .data
        let bsqType = UTType(filenameExtension: "bsq") ?? .data
        let bilType = UTType(filenameExtension: "bil") ?? .data
        let bipType = UTType(filenameExtension: "bip") ?? .data
        panel.allowedContentTypes = [hdrType, rawType, datType, imgType, bsqType, bilType, bipType]
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        calibrationRefError = nil
        let loadResult = EnviImageLoader.load(from: url)
        
        switch loadResult {
        case .failure(let error):
            calibrationRefError = error.localizedDescription
        case .success(let refCube):
            let sourceName = url.lastPathComponent
            let refResult = CalibrationRefData.from(
                refCube: refCube,
                expectedChannels: expectedChannels,
                sourceName: sourceName
            )
            
            switch refResult {
            case .failure(let error):
                calibrationRefError = error.localizedDescription
            case .success(let refData):
                if forWhite {
                    localCalibrationParams.whiteRef = refData
                    localCalibrationParams.whiteSpectrum = nil
                } else {
                    localCalibrationParams.blackRef = refData
                    localCalibrationParams.blackSpectrum = nil
                }
            }
        }
    }
    
    private func currentPreviewImage() -> NSImage? {
        guard let cube = state.cube else { return nil }
        let layout = state.activeLayout
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
            guard totalChannels > 0 else { return nil }
            switch state.colorSynthesisConfig.mode {
            case .trueColorRGB:
                return ImageRenderer.renderRGB(
                    cube: cube,
                    layout: layout,
                    wavelengths: state.wavelengths,
                    mapping: state.colorSynthesisConfig.mapping
                )
            case .pcaVisualization:
                return state.pcaRenderedImage
            }
        case .nd:
            guard let indices = state.ndChannelIndices() else { return nil }
            return ImageRenderer.renderND(
                cube: cube,
                layout: layout,
                positiveIndex: indices.positive,
                negativeIndex: indices.negative,
                palette: state.ndPalette,
                threshold: state.ndThreshold,
                preset: state.ndPreset,
                wdviSlope: Double(state.wdviSlope.replacingOccurrences(of: ",", with: ".")) ?? 1.0,
                wdviIntercept: Double(state.wdviIntercept.replacingOccurrences(of: ",", with: ".")) ?? 0.0
            )
        case .mask:
            return ImageRenderer.renderRGB(
                cube: cube,
                layout: layout,
                wavelengths: state.wavelengths,
                mapping: state.colorSynthesisConfig.mapping
            )
        }
    }
    
    private func spatialSize(for op: PipelineOperation) -> (width: Int, height: Int)? {
        guard let cube = state.cube else { return nil }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        guard let axes = cube.axes(for: op.layout) ?? cube.axes(for: state.activeLayout) else {
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
    
    private func deriveAspectRatio(for op: PipelineOperation, params: ResizeParameters) -> Double {
        if params.targetWidth > 0 && params.targetHeight > 0 {
            let safeHeight = max(params.targetHeight, 1)
            return max(Double(params.targetWidth) / Double(safeHeight), 0.01)
        }
        if let size = spatialSize(for: op), size.width > 0, size.height > 0 {
            return Double(size.width) / Double(size.height)
        }
        return resizeAspectRatio > 0 ? resizeAspectRatio : 1.0
    }
    
    private func adjustLinkedHeight(with newWidth: Int) {
        guard localResizeParams.lockAspectRatio,
              resizeAspectRatio > 0,
              !isAdjustingResize else { return }
        guard newWidth > 0 else { return }
        
        isAdjustingResize = true
        let newHeight = max(1, Int(round(Double(newWidth) / resizeAspectRatio)))
        if localResizeParams.targetHeight != newHeight {
            localResizeParams.targetHeight = newHeight
        }
        isAdjustingResize = false
    }
    
    private func adjustLinkedWidth(with newHeight: Int) {
        guard localResizeParams.lockAspectRatio,
              resizeAspectRatio > 0,
              !isAdjustingResize else { return }
        guard newHeight > 0 else { return }
        
        isAdjustingResize = true
        let newWidth = max(1, Int(round(Double(newHeight) * resizeAspectRatio)))
        if localResizeParams.targetWidth != newWidth {
            localResizeParams.targetWidth = newWidth
        }
        isAdjustingResize = false
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

struct SpectralAlignmentDetailsView: View {
    let result: SpectralAlignmentResult?
    let wavelengths: [Double]?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 16))
                Text("Результаты выравнивания")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if let result = result {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Метрика")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(result.metricName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Среднее значение")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.6f", result.averageScore))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Эталонный канал")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            if let wavelengths, result.referenceChannel < wavelengths.count {
                                Text("\(result.referenceChannel) (λ=\(String(format: "%.1f", wavelengths[result.referenceChannel])) нм)")
                                    .font(.system(size: 12, weight: .medium))
                            } else {
                                Text("\(result.referenceChannel)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    Text("Результаты по каналам")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 16)
                    
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            HStack {
                                Text("Канал")
                                    .frame(width: 50, alignment: .leading)
                                Text("λ (нм)")
                                    .frame(width: 70, alignment: .trailing)
                                Text("dx")
                                    .frame(width: 40, alignment: .trailing)
                                Text("dy")
                                    .frame(width: 40, alignment: .trailing)
                                Text(result.metricName)
                                    .frame(width: 80, alignment: .trailing)
                                Spacer()
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            
                            ForEach(0..<result.channelScores.count, id: \.self) { idx in
                                let isRef = idx == result.referenceChannel
                                let score = result.channelScores[idx]
                                let offset = idx < result.channelOffsets.count ? result.channelOffsets[idx] : (dx: 0, dy: 0)
                                
                                HStack {
                                    Text("\(idx)")
                                        .frame(width: 50, alignment: .leading)
                                    
                                    if let wavelengths, idx < wavelengths.count {
                                        Text(String(format: "%.1f", wavelengths[idx]))
                                            .frame(width: 70, alignment: .trailing)
                                    } else {
                                        Text("-")
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                    
                                    Text("\(offset.dx)")
                                        .frame(width: 40, alignment: .trailing)
                                        .foregroundColor(offset.dx != 0 ? .orange : .primary)
                                    
                                    Text("\(offset.dy)")
                                        .frame(width: 40, alignment: .trailing)
                                        .foregroundColor(offset.dy != 0 ? .orange : .primary)
                                    
                                    Text(String(format: "%.4f", score))
                                        .frame(width: 80, alignment: .trailing)
                                        .foregroundColor(scoreColor(score, isRef: isRef))
                                    
                                    if isRef {
                                        Text("(эталон)")
                                            .font(.system(size: 8))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Spacer()
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 3)
                                .background(isRef ? Color.blue.opacity(0.1) : Color.clear)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Нет данных о результатах")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Закрыть") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 450)
    }
    
    private func scoreColor(_ score: Double, isRef: Bool) -> Color {
        if isRef { return .blue }
        if score >= 0.95 { return .green }
        if score >= 0.85 { return .primary }
        if score >= 0.7 { return .orange }
        return .red
    }
}
