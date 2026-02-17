import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PipelinePanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedOperation: UUID?
    @State private var showingAddMenu: Bool = false
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
        .frame(width: 280)
        .popover(isPresented: $showingAddMenu, arrowEdge: .trailing) {
            addOperationMenu
        }
        .sheet(item: $editingOperation) { operation in
            OperationEditorView(operation: $editingOperation)
                .environmentObject(state)
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
        }
    }
    
    private func operationChip(_ type: PipelineOperationType, accent: Color) -> some View {
        OperationChip(
            type: type,
            accent: accent,
            lineLimit: chipLineLimit(for: type)
        ) {
            state.addOperation(type: type)
            showingAddMenu = false
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

private enum SpectralTrimInputMode: String, CaseIterable, Identifiable {
    case channels
    case wavelengths
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .channels:
            return L("Каналы")
        case .wavelengths:
            return L("Длины волн")
        }
    }
}

private enum SpectralInterpolationTargetMode: String, CaseIterable, Identifiable {
    case manual
    case fromFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return L("Ручной ввод")
        case .fromFile:
            return L("Из txt")
        }
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
    @State private var localClippingParams: ClippingParameters = .default
    @State private var localRotationAngle: RotationAngle = .degree90
    @State private var localTransposeParams: TransposeParameters = .default
    @State private var localCropParameters: SpatialCropParameters = SpatialCropParameters(left: 0, right: 0, top: 0, bottom: 0)
    @State private var autoCropEnabled: Bool = false
    @State private var autoCropReferenceEntryID: String?
    @State private var autoCropMetric: SpatialAutoCropMetric = .ssim
    @State private var autoCropSourceChannelsText: String = "0"
    @State private var autoCropReferenceChannelsText: String = "0"
    @State private var autoCropLimitWidth: Bool = false
    @State private var autoCropLimitHeight: Bool = false
    @State private var autoCropMinWidth: Int = 1
    @State private var autoCropMaxWidth: Int = 1
    @State private var autoCropMinHeight: Int = 1
    @State private var autoCropMaxHeight: Int = 1
    @State private var autoCropPositionStep: Int = 4
    @State private var autoCropSizeStep: Int = 4
    @State private var autoCropUseCoarseToFine: Bool = true
    @State private var autoCropKeepRefinementReserve: Bool = true
    @State private var autoCropDownsampleFactor: Int = 2
    @State private var autoCropProgress: Double = 0
    @State private var autoCropProgressMessage: String = ""
    @State private var autoCropInfoMessage: String?
    @State private var autoCropErrorMessage: String?
    @State private var isComputingAutoCrop: Bool = false
    @State private var localCalibrationParams: CalibrationParameters = .default
    @State private var localResizeParams: ResizeParameters = .default
    @State private var localSpectralTrimParams: SpectralTrimParameters = SpectralTrimParameters(startChannel: 0, endChannel: 0)
    @State private var localSpectralInterpolationParams: SpectralInterpolationParameters = .default
    @State private var localSpectralAlignmentParams: SpectralAlignmentParameters = .default
    @State private var spectralTrimInputMode: SpectralTrimInputMode = .channels
    @State private var spectralInterpolationTargetMode: SpectralInterpolationTargetMode = .manual
    @State private var spectralInterpolationImportError: String?
    @State private var spectralInterpolationImportInfo: String?
    @State private var spectralAlignmentIOError: String?
    @State private var spectralAlignmentIOInfo: String?
    @State private var trimStartWavelength: Double = 0
    @State private var trimEndWavelength: Double = 0
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

                if op.type == .spatialCrop {
                    VStack(spacing: 16) {
                        editorContent(for: op)
                    }
                    .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            editorContent(for: op)
                        }
                        .padding(16)
                    }
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
            return CGSize(width: 1120, height: 700)
        case .calibration:
            return CGSize(width: 500, height: 600)
        case .transpose:
            return CGSize(width: 460, height: 360)
        case .resize:
            return CGSize(width: 500, height: 520)
        case .spectralTrim:
            return CGSize(width: 460, height: 420)
        case .spectralInterpolation:
            return CGSize(width: 560, height: 590)
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
        case .transpose:
            localTransposeParams = op.transposeParameters ?? .default
        case .spatialCrop:
            if let params = op.cropParameters {
                localCropParameters = params
            }
            if let size = spatialSize(for: op) {
                syncAutoCropStateFromLocalParameters(size: size)
            } else {
                syncAutoCropStateFromLocalParameters(size: (width: 1, height: 1))
            }
            autoCropInfoMessage = nil
            autoCropErrorMessage = nil
            autoCropProgress = 0
            autoCropProgressMessage = ""
            isComputingAutoCrop = false
        case .calibration:
            localCalibrationParams = op.calibrationParams ?? .default
        case .resize:
            localResizeParams = op.resizeParameters ?? .default
            resizeAspectRatio = deriveAspectRatio(for: op, params: localResizeParams)
        case .spectralTrim:
            localSpectralTrimParams = op.spectralTrimParams ?? SpectralTrimParameters(startChannel: 0, endChannel: 0)
        case .spectralInterpolation:
            localSpectralInterpolationParams = op.spectralInterpolationParams ?? .default
            if let customTargets = localSpectralInterpolationParams.targetWavelengths, !customTargets.isEmpty {
                spectralInterpolationTargetMode = .fromFile
                localSpectralInterpolationParams.targetChannelCount = customTargets.count
                localSpectralInterpolationParams.targetMinLambda = customTargets.min() ?? 0
                localSpectralInterpolationParams.targetMaxLambda = customTargets.max() ?? 0
            } else {
                spectralInterpolationTargetMode = .manual
            }
            spectralInterpolationImportError = nil
            spectralInterpolationImportInfo = nil
        case .spectralAlignment:
            localSpectralAlignmentParams = op.spectralAlignmentParams ?? .default
            spectralAlignmentIOError = nil
            spectralAlignmentIOInfo = nil
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
        case .transpose:
            var normalized = localTransposeParams
            let cleaned = normalized.normalizedOrder
            normalized.order = cleaned.isEmpty ? localTransposeParams.order.uppercased() : cleaned
            localTransposeParams = normalized
            state.pipelineOperations[index].transposeParameters = normalized
        case .resize:
            state.pipelineOperations[index].resizeParameters = localResizeParams
        case .spatialCrop:
            var updated = localCropParameters
            if let size = spatialSize(for: op) {
                updated = updated.clamped(maxWidth: max(size.width, 1), maxHeight: max(size.height, 1))
            }
            let newSettings = buildAutoCropSettingsIfEnabled()
            if updated.autoCropSettings != newSettings {
                updated.autoCropResult = nil
            }
            updated.autoCropSettings = newSettings
            if newSettings == nil {
                updated.autoCropResult = nil
            }
            localCropParameters = updated
            state.pipelineOperations[index].cropParameters = updated
        case .spectralTrim:
            state.pipelineOperations[index].spectralTrimParams = localSpectralTrimParams
        case .calibration:
            state.pipelineOperations[index].calibrationParams = localCalibrationParams
        case .spectralInterpolation:
            if spectralInterpolationTargetMode == .manual {
                localSpectralInterpolationParams.targetWavelengths = nil
            }
            state.pipelineOperations[index].spectralInterpolationParams = localSpectralInterpolationParams
        case .spectralAlignment:
            state.pipelineOperations[index].spectralAlignmentParams = localSpectralAlignmentParams
        }
    }
    
    private func headerView(for op: PipelineOperation) -> some View {
        HStack {
            Image(systemName: op.type.iconName)
                .font(.system(size: 16))
            Text(LF("pipeline.setting.current", op.type.localizedTitle))
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
        case .transpose:
            transposeEditor(for: op)
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
            Text(state.localized("Тип нормализации:"))
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localNormalizationType) {
                ForEach(CubeNormalizationType.allCases) { type in
                    Text(type.localizedTitle).tag(type)
                }
            }
            .pickerStyle(.menu)
            
            if localNormalizationType.hasParameters {
                Divider()
                
                if localNormalizationType == .minMaxCustom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.localized("Диапазон:"))
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.minValue, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(state.localized("→"))
                            
                            TextField("Max", value: $localNormalizationParams.maxValue, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else if localNormalizationType == .manualRange {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.localized("Исходный диапазон:"))
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.sourceMin, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(state.localized("→"))
                            
                            TextField("Max", value: $localNormalizationParams.sourceMax, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text(state.localized("Новый диапазон:"))
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Min", value: $localNormalizationParams.targetMin, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text(state.localized("→"))
                            
                            TextField("Max", value: $localNormalizationParams.targetMax, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else if localNormalizationType == .percentile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.localized("Процентили:"))
                            .font(.system(size: 11, weight: .medium))
                        
                        HStack {
                            TextField("Lower", value: $localNormalizationParams.lowerPercentile, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                            Text(state.localized("→"))
                            
                            TextField("Upper", value: $localNormalizationParams.upperPercentile, format: .number)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("%")
                        }
                    }
                }
            }
            
            Divider()
            
            Text(state.localized("Точность вычислений:"))
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localNormalizationParams.computePrecision) {
                ForEach(NormalizationComputationPrecision.allCases) { precision in
                    Text(precision.rawValue).tag(precision)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            Toggle(state.localized("Сохранить тип данных"), isOn: $localPreserveDataType)
                .font(.system(size: 11))
                .disabled(localNormalizationParams.computePrecision == .float32)
            
            Group {
                if localNormalizationParams.computePrecision == .float32 {
                    Text(state.localized("При выборе Float32 результат всегда будет Float32, независимо от исходного типа"))
                } else if localPreserveDataType {
                    Text(state.localized("При нормализации тип данных будет сохранён, если диапазон позволяет (например, UInt8 для [0, 255])"))
                } else {
                    Text(state.localized("Результат нормализации всегда будет Float64"))
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
            Text(state.localized("Размер:"))
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Ширина"))
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
                            .help(state.localized("Фиксировать соотношение сторон"))
                    }
                    
                    Text(state.localized("Соотношение"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Высота"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("Height", value: $localResizeParams.targetHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            if localResizeParams.lockAspectRatio {
                Text(LF("pipeline.resize.aspect_ratio_preserved", resizeAspectRatio))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Text(state.localized("Алгоритм интерполяции:"))
                .font(.system(size: 11, weight: .medium))
            
            Picker("", selection: $localResizeParams.algorithm) {
                ForEach(ResizeAlgorithm.allCases) { algo in
                    Text(algo.localizedTitle).tag(algo)
                }
            }
            .pickerStyle(.menu)
            
            switch localResizeParams.algorithm {
            case .bicubic:
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.localized("Параметр a (Catmull-Rom = -0.5):"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("-0.5", value: $localResizeParams.bicubicA, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            case .lanczos:
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.localized("Число лепестков (a):"))
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
                    Text(state.localized("Точность вычислений"))
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
            
            Text(state.localized("Каждый канал будет ресайзнут отдельно в выбранном алгоритме."))
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
        let customTargets = localSpectralInterpolationParams.targetWavelengths ?? []
        let hasCustomTargets = !customTargets.isEmpty
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(state.localized("Спектральная интерполяция"))
                .font(.system(size: 11, weight: .medium))
            
            if hasWavelengths {
                Text(LF("pipeline.spectral_interp.source_range", sourceMin, sourceMax))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text(state.localized("Длины волн не заданы — интерполяция невозможна"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.localized("Целевая сетка"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Picker("", selection: $spectralInterpolationTargetMode) {
                    ForEach(SpectralInterpolationTargetMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
            
            if spectralInterpolationTargetMode == .manual {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Целевое число каналов"))
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
                        Text(state.localized("Диапазон λ"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("Min", value: $localSpectralInterpolationParams.targetMinLambda, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text(state.localized("–"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("Max", value: $localSpectralInterpolationParams.targetMaxLambda, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(state.localized("Загрузить λ из txt…")) {
                            importSpectralInterpolationTargetsFromFile()
                        }
                        .buttonStyle(.bordered)

                        Button(state.localized("Очистить")) {
                            localSpectralInterpolationParams.targetWavelengths = nil
                            spectralInterpolationImportError = nil
                            spectralInterpolationImportInfo = nil
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasCustomTargets)
                    }

                    if hasCustomTargets {
                        let minLambda = customTargets.min() ?? 0
                        let maxLambda = customTargets.max() ?? 0
                        Text(LF("pipeline.spectral_interp.file_channels_range", customTargets.count, minLambda, maxLambda))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(state.localized("Файл не загружен. Интерполяция будет использовать ручные параметры как fallback."))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if let spectralInterpolationImportInfo {
                        Text(spectralInterpolationImportInfo)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if let spectralInterpolationImportError {
                        Text(spectralInterpolationImportError)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Метод"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralInterpolationParams.method) {
                        ForEach(SpectralInterpolationMethod.allCases) { method in
                            Text(AppLocalizer.localized(method.rawValue)).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("За пределами"))
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
                    Text(state.localized("Тип данных"))
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
                Text(state.localized("Экстраполяция может давать нефизические значения за пределами диапазона."))
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
            if let customTargets = localSpectralInterpolationParams.targetWavelengths, !customTargets.isEmpty {
                spectralInterpolationTargetMode = .fromFile
            }
        }
    }
    
    private func spectralAlignmentEditor(for op: PipelineOperation) -> some View {
        let channels = state.cube?.channelCount(for: op.layout) ?? state.channelCount
        let maxIndex = max(channels - 1, 0)
        let wavelengths = state.cube?.wavelengths ?? state.wavelengths
        let isCurrentCubeAlignmentInProgress = state.isCurrentCubeAlignmentInProgress
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(state.localized("Спектральное выравнивание"))
                .font(.system(size: 11, weight: .medium))
            
            Text(state.localized("Выравнивает все каналы относительно эталонного канала, оптимизируя целевую метрику."))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Эталонный канал"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField(state.localized("Канал"), value: $localSpectralAlignmentParams.referenceChannel, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $localSpectralAlignmentParams.referenceChannel, in: 0...maxIndex)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    if let wavelengths, localSpectralAlignmentParams.referenceChannel < wavelengths.count {
                        Text(LF("pipeline.alignment.reference_lambda", wavelengths[localSpectralAlignmentParams.referenceChannel]))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Метод оптимизации"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralAlignmentParams.method) {
                        ForEach(SpectralAlignmentMethod.allCases) { method in
                            Text(AppLocalizer.localized(method.rawValue)).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Диапазон смещений"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField("Min", value: $localSpectralAlignmentParams.offsetMin, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text(state.localized("до"))
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
                    Text(state.localized("Шаг поиска"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        TextField(state.localized("Шаг"), value: $localSpectralAlignmentParams.step, format: .number)
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
                    Text(state.localized("Итерации оптимизации"))
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
                    Text(state.localized("Целевая метрика"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $localSpectralAlignmentParams.metric) {
                        ForEach(SpectralAlignmentMetric.allCases) { metric in
                            Text(AppLocalizer.localized(metric.rawValue)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text(state.localized("Дополнительные опции"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Toggle(isOn: $localSpectralAlignmentParams.enableMultiscale) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.localized("Многомасштабный поиск"))
                                .font(.system(size: 10))
                            Text(state.localized("Ускоряет вычисление"))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    
                    Toggle(isOn: $localSpectralAlignmentParams.enableSubpixel) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.localized("Субпиксельное уточнение"))
                                .font(.system(size: 10))
                            Text(state.localized("Повышает точность"))
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
                            Text(state.localized("Вычислено"))
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                        if let result = currentResult {
                            Text(LF("pipeline.alignment.average_metric", result.metricName, String(format: "%.4f", result.averageScore)))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    } else if isCurrentCubeAlignmentInProgress {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text(state.localized("Вычисление…"))
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text(state.localized("Не вычислено"))
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        
                        Text(LF("pipeline.alignment.estimated_time", localSpectralAlignmentParams.formattedEstimatedTime(channelCount: channels)))
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
                        Text(state.localized("Подробнее"))
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
                        Text(state.localized("Сбросить"))
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isComputed)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
                let canExport = (currentParams?.isComputed ?? false) || localSpectralAlignmentParams.isComputed
                
                HStack(spacing: 8) {
                    Button(state.localized("Экспорт гомографий в txt…")) {
                        exportSpectralAlignmentPreset(for: op)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canExport)
                    
                    Button(state.localized("Загрузить гомографии из txt…")) {
                        importSpectralAlignmentPreset(for: op)
                    }
                    .buttonStyle(.bordered)
                }
                
                Text(state.localized("Файл содержит layout, пространственные/спектральные характеристики и матрицы гомографии для быстрого повторного применения."))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                if let spectralAlignmentIOInfo {
                    Text(spectralAlignmentIOInfo)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if let spectralAlignmentIOError {
                    Text(spectralAlignmentIOError)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
            
            if isCurrentCubeAlignmentInProgress {
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
                                Text(LF("pipeline.alignment.channel_progress", state.alignmentCurrentChannel, state.alignmentTotalChannels))
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if !state.alignmentElapsedTime.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(LF("pipeline.alignment.elapsed", state.alignmentElapsedTime))
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        if !state.alignmentEstimatedTimeRemaining.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 9))
                                Text(LF("pipeline.alignment.remaining", state.alignmentEstimatedTimeRemaining))
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
                            Text(state.localized("Вычислить выравнивание"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(state.isAlignmentInProgress)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: $state.showAlignmentVisualization) {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                            Text(state.localized("Показать точки на изображении"))
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
                                Text(state.localized("Редактировать точки"))
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
                                Text(state.localized("По умолчанию"))
                            }
                            .font(.system(size: 9))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        Spacer()
                    }
                    
                    if state.alignmentPointsEditable {
                        Text(state.localized("Перетащите точки на изображении для настройки области выравнивания"))
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
                            Text(state.localized("Кэшированные гомографии готовы к применению"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }
                        Text(LF("pipeline.alignment.apply_cached_for_channels", channels))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    } else if cachedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(state.localized("Несовпадение числа каналов"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        Text(LF("pipeline.alignment.cache_mismatch", cachedCount, channels))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(state.localized("При копировании обработки в другое изображение будут применены сохранённые параметры гомографии без пересчёта."))
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
        case "init": return AppLocalizer.localized("Инициализация")
        case "extract_ref": return AppLocalizer.localized("Извлечение референса")
        case "extract": return AppLocalizer.localized("Извлечение канала")
        case "homography": return AppLocalizer.localized("Поиск гомографии")
        case "apply": return AppLocalizer.localized("Применение преобразования")
        case "done": return AppLocalizer.localized("Канал обработан")
        case "complete": return AppLocalizer.localized("Завершено")
        default: return stage
        }
    }

    private func spectralTrimEditor(for op: PipelineOperation) -> some View {
        let channels = state.cube?.channelCount(for: op.layout) ?? state.channelCount
        let maxIndex = max(channels - 1, 0)
        let wavelengths = state.cube?.wavelengths ?? state.wavelengths
        let hasWavelengths = (wavelengths?.isEmpty == false)
        let remainingChannels = max(0, localSpectralTrimParams.endChannel - localSpectralTrimParams.startChannel + 1)
        let startLambda = wavelengthValue(for: localSpectralTrimParams.startChannel, wavelengths: wavelengths)
        let endLambda = wavelengthValue(for: localSpectralTrimParams.endChannel, wavelengths: wavelengths)
        let wavelengthRange = wavelengthBounds(wavelengths)
        let startChannelBinding = Binding<Int>(
            get: { localSpectralTrimParams.startChannel },
            set: { newValue in
                localSpectralTrimParams.startChannel = clampChannel(newValue, maxIndex: maxIndex)
            }
        )
        let endChannelBinding = Binding<Int>(
            get: { localSpectralTrimParams.endChannel },
            set: { newValue in
                localSpectralTrimParams.endChannel = clampChannel(newValue, maxIndex: maxIndex)
            }
        )
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(state.localized("Обрезка спектра"))
                .font(.system(size: 11, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                Text(LF("pipeline.trim.channel_range_total", maxIndex, channels))
                if let range = wavelengthRange {
                    Text(LF("pipeline.trim.lambda_range", formatWavelength(range.min), formatWavelength(range.max)))
                } else {
                    Text(state.localized("Длины волн недоступны"))
                }
                Text(LF("pipeline.trim.remaining_channels", remainingChannels))
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("pipeline.trim.current_channels", localSpectralTrimParams.startChannel, localSpectralTrimParams.endChannel))
                    .font(.system(size: 10))
                if let startLambda, let endLambda {
                    Text(LF("pipeline.trim.will_clip_to_lambda", formatWavelength(startLambda), formatWavelength(endLambda)))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            if hasWavelengths {
                Picker(state.localized("Ввод"), selection: $spectralTrimInputMode) {
                    ForEach(SpectralTrimInputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if spectralTrimInputMode == .channels || !hasWavelengths {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Начальный канал"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            TextField("", value: startChannelBinding, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Stepper("", value: startChannelBinding, in: 0...maxIndex)
                                .labelsHidden()
                                .controlSize(.small)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Конечный канал"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            TextField("", value: endChannelBinding, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Stepper("", value: endChannelBinding, in: 0...maxIndex)
                                .labelsHidden()
                                .controlSize(.small)
                        }
                    }
                }
            }
            
            if hasWavelengths, spectralTrimInputMode == .wavelengths {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.localized("Начальная λ"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                TextField("", value: $trimStartWavelength, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Text(state.localized("нм"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.localized("Конечная λ"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                TextField("", value: $trimEndWavelength, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Text(state.localized("нм"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let startLambda, let endLambda {
                        Text(LF("pipeline.trim.nearest_channels", localSpectralTrimParams.startChannel, localSpectralTrimParams.endChannel, formatWavelength(startLambda), formatWavelength(endLambda)))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
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
            if hasWavelengths {
                syncTrimWavelengthInputs(wavelengths)
            } else {
                spectralTrimInputMode = .channels
            }
        }
        .onChange(of: localSpectralTrimParams.startChannel) { newValue in
            if localSpectralTrimParams.endChannel < newValue {
                localSpectralTrimParams.endChannel = newValue
            }
            if spectralTrimInputMode == .channels {
                syncTrimWavelengthInputs(wavelengths)
            }
        }
        .onChange(of: localSpectralTrimParams.endChannel) { newValue in
            if newValue < localSpectralTrimParams.startChannel {
                localSpectralTrimParams.startChannel = newValue
            }
            if spectralTrimInputMode == .channels {
                syncTrimWavelengthInputs(wavelengths)
            }
        }
        .onChange(of: spectralTrimInputMode) { newValue in
            guard newValue == .wavelengths else { return }
            syncTrimWavelengthInputs(wavelengths)
        }
        .onChange(of: trimStartWavelength) { _ in
            guard spectralTrimInputMode == .wavelengths else { return }
            updateTrimChannelsFromWavelengths(wavelengths, maxIndex: maxIndex)
        }
        .onChange(of: trimEndWavelength) { _ in
            guard spectralTrimInputMode == .wavelengths else { return }
            updateTrimChannelsFromWavelengths(wavelengths, maxIndex: maxIndex)
        }
    }

    private func clampChannel(_ value: Int, maxIndex: Int) -> Int {
        min(max(value, 0), maxIndex)
    }

    private func wavelengthValue(for channel: Int, wavelengths: [Double]?) -> Double? {
        guard let wavelengths, wavelengths.indices.contains(channel) else { return nil }
        return wavelengths[channel]
    }
    
    private func wavelengthBounds(_ wavelengths: [Double]?) -> (min: Double, max: Double)? {
        guard let wavelengths, let minValue = wavelengths.min(), let maxValue = wavelengths.max() else {
            return nil
        }
        return (min: minValue, max: maxValue)
    }
    
    private func formatWavelength(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
    
    private func nearestChannelIndex(to target: Double, wavelengths: [Double]) -> Int {
        guard !wavelengths.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDiff = abs(wavelengths[0] - target)
        for (index, wavelength) in wavelengths.enumerated() {
            let diff = abs(wavelength - target)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = index
            }
        }
        return bestIndex
    }
    
    private func syncTrimWavelengthInputs(_ wavelengths: [Double]?) {
        guard let wavelengths, !wavelengths.isEmpty else { return }
        let maxWaveIndex = max(wavelengths.count - 1, 0)
        let startIndex = min(localSpectralTrimParams.startChannel, maxWaveIndex)
        let endIndex = min(localSpectralTrimParams.endChannel, maxWaveIndex)
        trimStartWavelength = wavelengths[startIndex]
        trimEndWavelength = wavelengths[endIndex]
    }
    
    private func updateTrimChannelsFromWavelengths(_ wavelengths: [Double]?, maxIndex: Int) {
        guard let wavelengths, !wavelengths.isEmpty else { return }
        var startIndex = nearestChannelIndex(to: trimStartWavelength, wavelengths: wavelengths)
        var endIndex = nearestChannelIndex(to: trimEndWavelength, wavelengths: wavelengths)
        if endIndex < startIndex {
            swap(&startIndex, &endIndex)
        }
        localSpectralTrimParams.startChannel = clampChannel(startIndex, maxIndex: maxIndex)
        localSpectralTrimParams.endChannel = clampChannel(endIndex, maxIndex: maxIndex)
    }
    
    private func dataTypeEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.localized("Целевой тип данных:"))
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
            
            Toggle(state.localized("Автоматическое масштабирование"), isOn: $localAutoScale)
                .font(.system(size: 11))
            
            Text(localAutoScale
                 ? state.localized("Данные будут масштабированы в диапазон целевого типа")
                 : state.localized("Значения будут обрезаны (clamped)"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clippingEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.localized("Ограничение значений (clipping):"))
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Нижний порог"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("0", value: $localClippingParams.lower, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("Верхний порог"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("1", value: $localClippingParams.upper, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            
            if localClippingParams.upper < localClippingParams.lower {
                Text(state.localized("Верхний порог меньше нижнего — значения будут поменяны местами при применении."))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func rotationEditor(for op: PipelineOperation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.localized("Угол поворота:"))
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
                            
                            Text(AppLocalizer.localized(angle.rawValue))
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
                Text(state.localized("Поворот выполняется по часовой стрелке относительно центра изображения"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func transposeEditor(for op: PipelineOperation) -> some View {
        let normalized = localTransposeParams.normalizedOrder
        let resolvedLayout = localTransposeParams.targetLayout
        
        return VStack(alignment: .leading, spacing: 14) {
            Text(state.localized("Порядок осей HWC:"))
                .font(.system(size: 11, weight: .medium))
            
            TextField(state.localized("Например: HWC, CHW, WCH"), text: $localTransposeParams.order)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            
            HStack(spacing: 8) {
                ForEach(CubeLayout.explicitCases) { layout in
                    Button(layout.rawValue) {
                        localTransposeParams.order = layout.rawValue
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            if let target = resolvedLayout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LF("pipeline.transpose.source_layout", op.layout.rawValue))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(LF("pipeline.transpose.result_layout", target.rawValue))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if op.layout == target {
                        Text(state.localized("Порядок не изменится (no-op)."))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(LF("pipeline.transpose.after_apply_layout", target.rawValue))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(state.localized("Некорректный порядок. Используйте ровно 3 символа H/W/C без повторов (например HWC)."))
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
            
            if !normalized.isEmpty, normalized != localTransposeParams.order.uppercased() {
                Text(LF("pipeline.transpose.normalized_input", normalized))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func cropEditor(for op: PipelineOperation) -> some View {
        let preview = currentPreviewImage()
        let currentSpatialSize = spatialSize(for: op)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text(state.localized("Выбор области обрезки:"))
                .font(.system(size: 11, weight: .medium))
            
            if let cropSize = currentSpatialSize, cropSize.width > 0, cropSize.height > 0 {
                HStack(alignment: .top, spacing: 20) {
                    SpatialCropPreview(
                        image: preview,
                        pixelWidth: cropSize.width,
                        pixelHeight: cropSize.height,
                        parameters: bindingForParameters(width: cropSize.width, height: cropSize.height)
                    )
                    .frame(height: 430)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.15))
                    .cornerRadius(14)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(state.localized("Размер области"))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(LF("pipeline.crop.size_px", cropSize.width, cropSize.height))
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                Text("Layout: \(op.layout.rawValue)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 12) {
                                Text(state.localized("Границы (px)"))
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

                            Divider()

                            autoCropSettingsSection(for: op, cropSize: cropSize)
                        }
                        .padding(14)
                    }
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    )
                }
                .onAppear {
                    clampCropParametersIfNeeded(width: cropSize.width, height: cropSize.height)
                    syncAutoCropStateFromLocalParameters(size: cropSize)
                }
                .onChange(of: state.cube?.id) { _ in
                    if let freshSize = spatialSize(for: op) {
                        clampCropParametersIfNeeded(width: freshSize.width, height: freshSize.height)
                        syncAutoCropStateFromLocalParameters(size: freshSize)
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
                            Text(state.localized("Предпросмотр недоступен"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
    }

    @ViewBuilder
    private func autoCropSettingsSection(for op: PipelineOperation, cropSize: (width: Int, height: Int)) -> some View {
        let estimatedCandidates = estimatedAutoCropCandidates(cropSize: cropSize)

        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $autoCropEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text(state.localized("Автоподбор обрезки по ГСИ-референсу"))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            if autoCropEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("ГСИ-референс из библиотеки"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker("", selection: $autoCropReferenceEntryID) {
                            Text(state.localized("Не выбран")).tag(String?.none)
                            ForEach(state.libraryEntries) { entry in
                                Text(entry.displayName).tag(Optional(entry.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Целевая метрика"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker("", selection: $autoCropMetric) {
                            ForEach(SpatialAutoCropMetric.allCases) { metric in
                                Text(AppLocalizer.localized(metric.rawValue)).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localized("Каналы source/ref (через запятую)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("Source: 0, 3, 5", text: $autoCropSourceChannelsText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Reference: 0, 2, 4", text: $autoCropReferenceChannelsText)
                            .textFieldStyle(.roundedBorder)
                        Text(state.localized("Должно быть одинаковое количество каналов, минимум 1."))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(state.localized("Ограничить ширину"), isOn: $autoCropLimitWidth)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        if autoCropLimitWidth {
                            HStack(spacing: 8) {
                                Text("Min")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("1", value: $autoCropMinWidth, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                Text("Max")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("\(cropSize.width)", value: $autoCropMaxWidth, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                            }
                        }

                        Toggle(state.localized("Ограничить высоту"), isOn: $autoCropLimitHeight)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        if autoCropLimitHeight {
                            HStack(spacing: 8) {
                                Text("Min")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("1", value: $autoCropMinHeight, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                Text("Max")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                TextField("\(cropSize.height)", value: $autoCropMaxHeight, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(state.localized("Оптимизация перебора"))
                            .font(.system(size: 10, weight: .semibold))

                        HStack(spacing: 8) {
                            Text(state.localized("Шаг позиции"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("4", value: $autoCropPositionStep, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                            Stepper("", value: $autoCropPositionStep, in: 1...64)
                                .labelsHidden()
                                .controlSize(.mini)
                        }

                        HStack(spacing: 8) {
                            Text(state.localized("Шаг размера"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            TextField("4", value: $autoCropSizeStep, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                            Stepper("", value: $autoCropSizeStep, in: 1...64)
                                .labelsHidden()
                                .controlSize(.mini)
                        }

                        Toggle(state.localized("Грубый поиск + уточнение (coarse-to-fine)"), isOn: $autoCropUseCoarseToFine)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)

                        Toggle(state.localized("Оставлять уточняющий резерв"), isOn: $autoCropKeepRefinementReserve)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .disabled(!autoCropUseCoarseToFine)

                        HStack(spacing: 8) {
                            Text(state.localized("Downsample для метрики"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Picker("", selection: $autoCropDownsampleFactor) {
                                Text("1x").tag(1)
                                Text("2x").tag(2)
                                Text("4x").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }

                        HStack(spacing: 6) {
                            Button(state.localized("Быстро")) {
                                applyAutoCropPreset(speed: .fast)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button(state.localized("Баланс")) {
                                applyAutoCropPreset(speed: .balanced)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button(state.localized("Точно")) {
                                applyAutoCropPreset(speed: .precise)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }

                    Text(LF("pipeline.auto_crop.candidate_estimate", estimatedCandidates))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(state.localized("Для ускорения увеличьте шаги, включите coarse-to-fine и используйте downsample 2x/4x."))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        runAutoCropSearch(for: op, cropSize: cropSize)
                    }) {
                        HStack {
                            Image(systemName: "scope")
                            Text(isComputingAutoCrop ? "Подбор..." : "Подобрать обрезку")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isComputingAutoCrop || autoCropReferenceEntryID == nil)

                    if isComputingAutoCrop {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(autoCropProgressMessage.isEmpty ? "Вычисление..." : autoCropProgressMessage)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(autoCropProgress * 100))%")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            ProgressView(value: autoCropProgress)
                                .progressViewStyle(.linear)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                    }

                    if let info = autoCropInfoMessage {
                        Text(info)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if let error = autoCropErrorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }

                    if let result = localCropParameters.autoCropResult {
                        let scoreText = String(format: result.metric == .ssim ? "%.4f" : "%.6f", result.bestScore)
                        Text(
                            LF(
                                "pipeline.auto_crop.best_result",
                                result.metric.rawValue,
                                scoreText,
                                result.selectedWidth,
                                result.selectedHeight,
                                result.evaluatedCandidates
                            )
                        )
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onChange(of: autoCropMinWidth) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropMaxWidth) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropMinHeight) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropMaxHeight) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropPositionStep) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropSizeStep) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropDownsampleFactor) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
        }
        .onChange(of: autoCropKeepRefinementReserve) { _ in
            clampAutoCropLimitInputs(cropSize: cropSize)
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
            Text(state.localized("Калибровка изображения"))
                .font(.system(size: 11, weight: .medium))
            
            Text(state.localized("Выберите спектры или REF файлы для белой и/или чёрной точки калибровки."))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text(state.localized("Белая точка (эталон белого)"))
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
                        Button(state.localized("Убрать")) {
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
                        
                        Button(state.localized("Выбрать файл REF")) {
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
                    Text(state.localized("Чёрная точка (эталон чёрного)"))
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
                        Button(state.localized("Убрать")) {
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
                        
                        Button(state.localized("Выбрать файл REF")) {
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
                Text(state.localized("Направление сканирования:"))
                    .font(.system(size: 11, weight: .medium))

                Toggle(state.localized("Использовать параметры сканирования"), isOn: $localCalibrationParams.useScanDirection)
                    .font(.system(size: 10))
                
                if !localCalibrationParams.useScanDirection,
                   localCalibrationParams.whiteRef != nil || localCalibrationParams.blackRef != nil {
                    Text(state.localized("REF файлы обнаружены — возможно, стоит включить параметры сканирования."))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Picker("", selection: $localCalibrationParams.scanDirection) {
                    ForEach(CalibrationScanDirection.allCases) { direction in
                        Text(direction.localizedTitle).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .disabled(!localCalibrationParams.useScanDirection)
                
                if let scanAxisSize,
                   (localCalibrationParams.whiteRef?.scanLength != nil || localCalibrationParams.blackRef?.scanLength != nil) {
                    if localCalibrationParams.whiteRef?.scanLength != nil && localCalibrationParams.whiteRef?.scanLength != scanAxisSize {
                        calibrationRefWarning(text: LF("pipeline.calibration.white_ref_scan_size_mismatch", scanAxisSize))
                    }
                    if localCalibrationParams.blackRef?.scanLength != nil && localCalibrationParams.blackRef?.scanLength != scanAxisSize {
                        calibrationRefWarning(text: LF("pipeline.calibration.black_ref_scan_size_mismatch", scanAxisSize))
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("Целевой диапазон:"))
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
                
                Toggle(state.localized("Ограничивать в диапазоне"), isOn: $localCalibrationParams.clampOutput)
                    .font(.system(size: 10))
            }
            
            if !localCalibrationParams.isConfigured {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(state.localized("Выберите хотя бы одну точку или REF для калибровки"))
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
                Text(state.localized("Нет сохранённых спектров"))
                    .foregroundColor(.secondary)
            }
            
            if !pointSamples.isEmpty {
                Section(state.localized("Точки")) {
                    ForEach(pointSamples) { sample in
                        Button(sample.effectiveName) {
                            onSelect(CalibrationSpectrum.from(sample: sample))
                        }
                    }
                }
            }
            
            if !roiSamples.isEmpty {
                Section(state.localized("Области ROI")) {
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
                Text(state.localized(label))
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
                Text(LF("pipeline.calibration.ref_dimensions", ref.channels, ref.scanLength))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(state.localized("Убрать")) {
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
        panel.message = state.localized("Выберите REF файл (HDR/RAW)")
        
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

    private func importSpectralInterpolationTargetsFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = state.localized("Выберите txt файл со списком длин волн (по одному значению на строку)")
        panel.prompt = state.localized("Загрузить")
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "txt") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let wavelengths = try parseWavelengthListFile(url: url)
            localSpectralInterpolationParams.targetWavelengths = wavelengths
            localSpectralInterpolationParams.targetChannelCount = wavelengths.count
            localSpectralInterpolationParams.targetMinLambda = wavelengths.min() ?? 0
            localSpectralInterpolationParams.targetMaxLambda = wavelengths.max() ?? 0
            spectralInterpolationTargetMode = .fromFile
            spectralInterpolationImportError = nil
            spectralInterpolationImportInfo = LF("pipeline.spectral_interp.loaded_wavelengths", wavelengths.count, url.lastPathComponent)
        } catch {
            spectralInterpolationImportError = error.localizedDescription
            spectralInterpolationImportInfo = nil
        }
    }

    private enum SpectralInterpolationFileError: LocalizedError {
        case readFailed
        case empty
        case invalidValue(line: Int)

        var errorDescription: String? {
            switch self {
            case .readFailed:
                return L("Не удалось прочитать txt файл длин волн")
            case .empty:
                return L("Файл длин волн пуст")
            case .invalidValue(let line):
                return LF("pipeline.spectral_interp.invalid_wavelength_line", line)
            }
        }
    }

    private func parseWavelengthListFile(url: URL) throws -> [Double] {
        guard let text = readTextFile(url: url) else {
            throw SpectralInterpolationFileError.readFailed
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw SpectralInterpolationFileError.empty
        }

        var values: [Double] = []
        values.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            let normalized = line.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite else {
                throw SpectralInterpolationFileError.invalidValue(line: index + 1)
            }
            values.append(value)
        }

        return values
    }

    private func readTextFile(url: URL) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1251, .isoLatin1]
        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return text
            }
        }
        return nil
    }
    
    private struct SpectralAlignmentPresetFile: Codable {
        static let formatID = "HSIView.SpectralAlignmentPreset"
        static let currentVersion = 1
        
        struct Source: Codable {
            let fileName: String?
            let layout: String
            let dims: [Int]
            let width: Int
            let height: Int
            let channels: Int
            let wavelengths: [Double]?
        }
        
        struct ReferencePoint: Codable {
            let x: Double
            let y: Double
        }
        
        struct Parameters: Codable {
            let referenceChannel: Int
            let method: String
            let offsetMin: Int
            let offsetMax: Int
            let step: Int
            let metric: String
            let iterations: Int
            let enableSubpixel: Bool
            let enableMultiscale: Bool
            let useManualPoints: Bool
            let referencePoints: [ReferencePoint]
        }
        
        struct ChannelOffset: Codable {
            let dx: Int
            let dy: Int
        }
        
        struct ResultPayload: Codable {
            let metricName: String
            let averageScore: Double
            let channelScores: [Double]
            let channelOffsets: [ChannelOffset]
        }
        
        let format: String
        let version: Int
        let createdAt: String
        let source: Source
        let parameters: Parameters
        let homographies: [[Double]]
        let result: ResultPayload?
    }
    
    private enum SpectralAlignmentPresetError: LocalizedError {
        case cubeUnavailable
        case dataUnavailable
        case readFailed
        case writeFailed
        case invalidFormat
        case unsupportedVersion(Int)
        case invalidLayout(String)
        case invalidMethod(String)
        case invalidMetric(String)
        case invalidReferenceChannel(Int, Int)
        case invalidReferencePoints
        case invalidHomography(Int)
        case incompatibleLayout(expected: String, actual: String)
        case incompatibleSpatial(expected: String, actual: String)
        case incompatibleChannels(expected: Int, actual: Int)
        case missingCurrentWavelengths
        case incompatibleWavelengthCount(expected: Int, actual: Int)
        case incompatibleWavelength(index: Int)
        case invalidResult
        
        var errorDescription: String? {
            switch self {
            case .cubeUnavailable:
                return L("Откройте куб перед экспортом/импортом гомографий")
            case .dataUnavailable:
                return L("Нет рассчитанных гомографий для экспорта")
            case .readFailed:
                return L("Не удалось прочитать файл гомографий")
            case .writeFailed:
                return L("Не удалось сохранить файл гомографий")
            case .invalidFormat:
                return L("Некорректный формат файла гомографий")
            case .unsupportedVersion(let version):
                return LF("pipeline.alignment.error.unsupported_version", version)
            case .invalidLayout(let value):
                return LF("pipeline.alignment.error.invalid_layout", value)
            case .invalidMethod(let value):
                return LF("pipeline.alignment.error.invalid_method", value)
            case .invalidMetric(let value):
                return LF("pipeline.alignment.error.invalid_metric", value)
            case .invalidReferenceChannel(let value, let max):
                return LF("pipeline.alignment.error.invalid_reference_channel", value, max)
            case .invalidReferencePoints:
                return L("Некорректные опорные точки в файле")
            case .invalidHomography(let index):
                return LF("pipeline.alignment.error.invalid_homography", index)
            case .incompatibleLayout(let expected, let actual):
                return LF("pipeline.alignment.error.layout_mismatch", expected, actual)
            case .incompatibleSpatial(let expected, let actual):
                return LF("pipeline.alignment.error.spatial_mismatch", expected, actual)
            case .incompatibleChannels(let expected, let actual):
                return LF("pipeline.alignment.error.channels_mismatch", expected, actual)
            case .missingCurrentWavelengths:
                return L("В файле есть длины волн, но в текущем кубе они не заданы")
            case .incompatibleWavelengthCount(let expected, let actual):
                return LF("pipeline.alignment.error.wavelength_count_mismatch", expected, actual)
            case .incompatibleWavelength(let index):
                return LF("pipeline.alignment.error.wavelength_mismatch", index)
            case .invalidResult:
                return L("Сводка результата в файле повреждена")
            }
        }
    }
    
    private func exportSpectralAlignmentPreset(for op: PipelineOperation) {
        guard let cube = state.cube else {
            spectralAlignmentIOError = SpectralAlignmentPresetError.cubeUnavailable.localizedDescription
            spectralAlignmentIOInfo = nil
            return
        }
        
        let currentParams = state.pipelineOperations.first(where: { $0.id == op.id })?.spectralAlignmentParams
            ?? localSpectralAlignmentParams
        
        do {
            let preset = try makeSpectralAlignmentPresetFile(
                params: currentParams,
                for: op,
                cube: cube
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(preset)
            guard let text = String(data: encoded, encoding: .utf8) else {
                throw SpectralAlignmentPresetError.writeFailed
            }
            
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "txt") ?? .plainText]
            let baseName = state.cubeURL?.deletingPathExtension().lastPathComponent ?? "alignment"
            panel.nameFieldStringValue = "\(baseName)_spectral_alignment.txt"
            panel.message = state.localized("Сохранить рассчитанные параметры спектрального выравнивания")
            panel.prompt = state.localized("Сохранить")
            
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw SpectralAlignmentPresetError.writeFailed
            }
            
            spectralAlignmentIOError = nil
            spectralAlignmentIOInfo = LF("pipeline.alignment.homographies_saved", url.lastPathComponent)
        } catch {
            spectralAlignmentIOError = error.localizedDescription
            spectralAlignmentIOInfo = nil
        }
    }
    
    private func importSpectralAlignmentPreset(for op: PipelineOperation) {
        guard let cube = state.cube else {
            spectralAlignmentIOError = SpectralAlignmentPresetError.cubeUnavailable.localizedDescription
            spectralAlignmentIOInfo = nil
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = state.localized("Выберите txt файл с рассчитанными гомографиями")
        panel.prompt = state.localized("Загрузить")
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "txt") ?? .plainText]
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        do {
            guard let text = readTextFile(url: url) else {
                throw SpectralAlignmentPresetError.readFailed
            }
            let data = Data(text.utf8)
            let decoder = JSONDecoder()
            let preset = try decoder.decode(SpectralAlignmentPresetFile.self, from: data)
            try applySpectralAlignmentPreset(
                preset,
                to: op,
                cube: cube
            )
            
            saveLocalState()
            if state.pipelineAutoApply {
                state.applyPipeline()
            }
            
            spectralAlignmentIOError = nil
            spectralAlignmentIOInfo = LF("pipeline.alignment.homographies_loaded", url.lastPathComponent)
        } catch {
            spectralAlignmentIOError = error.localizedDescription
            spectralAlignmentIOInfo = nil
        }
    }
    
    private func makeSpectralAlignmentPresetFile(
        params: SpectralAlignmentParameters,
        for op: PipelineOperation,
        cube: HyperCube
    ) throws -> SpectralAlignmentPresetFile {
        guard params.isComputed,
              let homographies = params.cachedHomographies,
              !homographies.isEmpty else {
            throw SpectralAlignmentPresetError.dataUnavailable
        }
        
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let layout = resolvedLayoutForAlignment(operation: op, cube: cube)
        guard let axes = cube.axes(for: layout) else {
            throw SpectralAlignmentPresetError.cubeUnavailable
        }
        let width = dims[axes.width]
        let height = dims[axes.height]
        let channels = dims[axes.channel]
        guard homographies.count == channels else {
            throw SpectralAlignmentPresetError.incompatibleChannels(expected: channels, actual: homographies.count)
        }
        
        for (index, matrix) in homographies.enumerated() {
            guard matrix.count == 9, matrix.allSatisfy({ $0.isFinite }) else {
                throw SpectralAlignmentPresetError.invalidHomography(index + 1)
            }
        }
        
        let wavelengths = currentWavelengthsForAlignment(channelCount: channels, cube: cube)
        let resultPayload: SpectralAlignmentPresetFile.ResultPayload?
        if let result = params.alignmentResult,
           result.channelScores.count == channels,
           result.channelOffsets.count == channels {
            resultPayload = SpectralAlignmentPresetFile.ResultPayload(
                metricName: result.metricName,
                averageScore: result.averageScore,
                channelScores: result.channelScores,
                channelOffsets: result.channelOffsets.map {
                    SpectralAlignmentPresetFile.ChannelOffset(dx: $0.dx, dy: $0.dy)
                }
            )
        } else {
            resultPayload = nil
        }
        
        let points = params.referencePoints.map {
            SpectralAlignmentPresetFile.ReferencePoint(x: $0.x, y: $0.y)
        }
        let createdAt = ISO8601DateFormatter().string(from: Date())
        
        return SpectralAlignmentPresetFile(
            format: SpectralAlignmentPresetFile.formatID,
            version: SpectralAlignmentPresetFile.currentVersion,
            createdAt: createdAt,
            source: SpectralAlignmentPresetFile.Source(
                fileName: state.cubeURL?.lastPathComponent,
                layout: layout.rawValue,
                dims: dims,
                width: width,
                height: height,
                channels: channels,
                wavelengths: wavelengths
            ),
            parameters: SpectralAlignmentPresetFile.Parameters(
                referenceChannel: params.referenceChannel,
                method: params.method.rawValue,
                offsetMin: params.offsetMin,
                offsetMax: params.offsetMax,
                step: params.step,
                metric: params.metric.rawValue,
                iterations: params.iterations,
                enableSubpixel: params.enableSubpixel,
                enableMultiscale: params.enableMultiscale,
                useManualPoints: params.useManualPoints,
                referencePoints: points
            ),
            homographies: homographies,
            result: resultPayload
        )
    }
    
    private func applySpectralAlignmentPreset(
        _ preset: SpectralAlignmentPresetFile,
        to op: PipelineOperation,
        cube: HyperCube
    ) throws {
        guard preset.format == SpectralAlignmentPresetFile.formatID else {
            throw SpectralAlignmentPresetError.invalidFormat
        }
        guard preset.version == SpectralAlignmentPresetFile.currentVersion else {
            throw SpectralAlignmentPresetError.unsupportedVersion(preset.version)
        }
        
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let layout = resolvedLayoutForAlignment(operation: op, cube: cube)
        guard let axes = cube.axes(for: layout) else {
            throw SpectralAlignmentPresetError.cubeUnavailable
        }
        
        let width = dims[axes.width]
        let height = dims[axes.height]
        let channels = dims[axes.channel]
        
        guard preset.source.layout == layout.rawValue else {
            throw SpectralAlignmentPresetError.incompatibleLayout(expected: preset.source.layout, actual: layout.rawValue)
        }
        guard preset.source.width == width, preset.source.height == height else {
            throw SpectralAlignmentPresetError.incompatibleSpatial(
                expected: "\(preset.source.width)x\(preset.source.height)",
                actual: "\(width)x\(height)"
            )
        }
        guard preset.source.channels == channels else {
            throw SpectralAlignmentPresetError.incompatibleChannels(
                expected: preset.source.channels,
                actual: channels
            )
        }
        
        guard preset.homographies.count == channels else {
            throw SpectralAlignmentPresetError.incompatibleChannels(
                expected: channels,
                actual: preset.homographies.count
            )
        }
        for (index, matrix) in preset.homographies.enumerated() {
            guard matrix.count == 9, matrix.allSatisfy({ $0.isFinite }) else {
                throw SpectralAlignmentPresetError.invalidHomography(index + 1)
            }
        }
        
        if let expectedWavelengths = preset.source.wavelengths {
            guard let currentWavelengths = currentWavelengthsForAlignment(channelCount: channels, cube: cube) else {
                throw SpectralAlignmentPresetError.missingCurrentWavelengths
            }
            guard currentWavelengths.count == expectedWavelengths.count else {
                throw SpectralAlignmentPresetError.incompatibleWavelengthCount(
                    expected: expectedWavelengths.count,
                    actual: currentWavelengths.count
                )
            }
            let tolerance = 1e-2
            for i in 0..<expectedWavelengths.count {
                if abs(currentWavelengths[i] - expectedWavelengths[i]) > tolerance {
                    throw SpectralAlignmentPresetError.incompatibleWavelength(index: i + 1)
                }
            }
        }
        
        guard let method = SpectralAlignmentMethod(rawValue: preset.parameters.method) else {
            throw SpectralAlignmentPresetError.invalidMethod(preset.parameters.method)
        }
        guard let metric = SpectralAlignmentMetric(rawValue: preset.parameters.metric) else {
            throw SpectralAlignmentPresetError.invalidMetric(preset.parameters.metric)
        }
        guard preset.parameters.referenceChannel >= 0,
              preset.parameters.referenceChannel < channels else {
            throw SpectralAlignmentPresetError.invalidReferenceChannel(
                preset.parameters.referenceChannel,
                max(0, channels - 1)
            )
        }
        guard !preset.parameters.referencePoints.isEmpty else {
            throw SpectralAlignmentPresetError.invalidReferencePoints
        }
        
        var restoredResult: SpectralAlignmentResult?
        if let resultPayload = preset.result {
            guard resultPayload.channelScores.count == channels,
                  resultPayload.channelOffsets.count == channels else {
                throw SpectralAlignmentPresetError.invalidResult
            }
            restoredResult = SpectralAlignmentResult(
                channelScores: resultPayload.channelScores,
                channelOffsets: resultPayload.channelOffsets.map { (dx: $0.dx, dy: $0.dy) },
                averageScore: resultPayload.averageScore,
                referenceChannel: preset.parameters.referenceChannel,
                metricName: resultPayload.metricName
            )
        }
        
        localSpectralAlignmentParams.referenceChannel = preset.parameters.referenceChannel
        localSpectralAlignmentParams.method = method
        localSpectralAlignmentParams.offsetMin = preset.parameters.offsetMin
        localSpectralAlignmentParams.offsetMax = preset.parameters.offsetMax
        localSpectralAlignmentParams.step = max(1, preset.parameters.step)
        localSpectralAlignmentParams.metric = metric
        localSpectralAlignmentParams.iterations = max(1, preset.parameters.iterations)
        localSpectralAlignmentParams.enableSubpixel = preset.parameters.enableSubpixel
        localSpectralAlignmentParams.enableMultiscale = preset.parameters.enableMultiscale
        localSpectralAlignmentParams.useManualPoints = preset.parameters.useManualPoints
        localSpectralAlignmentParams.referencePoints = preset.parameters.referencePoints.map {
            AlignmentPoint(x: $0.x, y: $0.y)
        }
        localSpectralAlignmentParams.cachedHomographies = preset.homographies
        localSpectralAlignmentParams.alignmentResult = restoredResult
        localSpectralAlignmentParams.isComputed = true
        localSpectralAlignmentParams.shouldCompute = false
    }
    
    private func resolvedLayoutForAlignment(operation: PipelineOperation, cube: HyperCube) -> CubeLayout {
        if operation.layout != .auto {
            return operation.layout
        }
        if state.activeLayout != .auto {
            return state.activeLayout
        }
        if let axes = cube.axes(for: .auto) {
            switch axes.channel {
            case 0:
                return .chw
            case 1:
                return .hcw
            case 2:
                return .hwc
            default:
                return .chw
            }
        }
        return .chw
    }
    
    private func currentWavelengthsForAlignment(channelCount: Int, cube: HyperCube) -> [Double]? {
        if let wl = state.wavelengths, wl.count == channelCount {
            return wl
        }
        if let wl = cube.wavelengths, wl.count == channelCount {
            return wl
        }
        return nil
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
            case .rangeWideRGB:
                return ImageRenderer.renderRGBRange(
                    cube: cube,
                    layout: layout,
                    wavelengths: state.wavelengths,
                    rangeMapping: state.colorSynthesisConfig.rangeMapping
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
            switch state.colorSynthesisConfig.mode {
            case .trueColorRGB:
                return ImageRenderer.renderRGB(
                    cube: cube,
                    layout: layout,
                    wavelengths: state.wavelengths,
                    mapping: state.colorSynthesisConfig.mapping
                )
            case .rangeWideRGB:
                return ImageRenderer.renderRGBRange(
                    cube: cube,
                    layout: layout,
                    wavelengths: state.wavelengths,
                    rangeMapping: state.colorSynthesisConfig.rangeMapping
                )
            case .pcaVisualization:
                return state.pcaRenderedImage
            }
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
            Text(state.localized(label))
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

    private enum AutoCropSpeedPreset {
        case fast
        case balanced
        case precise
    }

    private func syncAutoCropStateFromLocalParameters(size: (width: Int, height: Int)) {
        let settings = localCropParameters.autoCropSettings
        autoCropEnabled = settings != nil
        let effective = settings ?? .default

        autoCropReferenceEntryID = effective.referenceLibraryID
        autoCropMetric = effective.metric
        autoCropSourceChannelsText = formatChannelList(effective.sourceChannels.isEmpty ? [0] : effective.sourceChannels)
        autoCropReferenceChannelsText = formatChannelList(effective.referenceChannels.isEmpty ? [0] : effective.referenceChannels)

        autoCropLimitWidth = (effective.minWidth != nil || effective.maxWidth != nil)
        autoCropLimitHeight = (effective.minHeight != nil || effective.maxHeight != nil)

        let widthLimit = max(size.width, 1)
        let heightLimit = max(size.height, 1)
        autoCropMinWidth = boundedInt(effective.minWidth ?? min(widthLimit, max(1, widthLimit / 2)), min: 1, max: widthLimit)
        autoCropMaxWidth = boundedInt(effective.maxWidth ?? widthLimit, min: autoCropMinWidth, max: widthLimit)
        autoCropMinHeight = boundedInt(effective.minHeight ?? min(heightLimit, max(1, heightLimit / 2)), min: 1, max: heightLimit)
        autoCropMaxHeight = boundedInt(effective.maxHeight ?? heightLimit, min: autoCropMinHeight, max: heightLimit)
        autoCropPositionStep = max(1, effective.positionStep)
        autoCropSizeStep = max(1, effective.sizeStep)
        autoCropUseCoarseToFine = effective.useCoarseToFine
        autoCropKeepRefinementReserve = effective.keepRefinementReserve
        autoCropDownsampleFactor = max(1, effective.downsampleFactor)
    }

    private func buildAutoCropSettingsIfEnabled() -> SpatialAutoCropSettings? {
        guard autoCropEnabled else { return nil }

        let sourceChannels = parseChannelList(autoCropSourceChannelsText)
        let referenceChannels = parseChannelList(autoCropReferenceChannelsText)
        let minWidth = autoCropLimitWidth ? min(autoCropMinWidth, autoCropMaxWidth) : nil
        let maxWidth = autoCropLimitWidth ? max(autoCropMinWidth, autoCropMaxWidth) : nil
        let minHeight = autoCropLimitHeight ? min(autoCropMinHeight, autoCropMaxHeight) : nil
        let maxHeight = autoCropLimitHeight ? max(autoCropMinHeight, autoCropMaxHeight) : nil

        return SpatialAutoCropSettings(
            referenceLibraryID: autoCropReferenceEntryID,
            metric: autoCropMetric,
            sourceChannels: sourceChannels,
            referenceChannels: referenceChannels,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight,
            positionStep: max(1, autoCropPositionStep),
            sizeStep: max(1, autoCropSizeStep),
            useCoarseToFine: autoCropUseCoarseToFine,
            keepRefinementReserve: autoCropKeepRefinementReserve,
            downsampleFactor: max(1, autoCropDownsampleFactor)
        )
    }

    private func parseChannelList(_ text: String) -> [Int] {
        let separators = CharacterSet(charactersIn: ",; \n\t")
        let tokens = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var values: [Int] = []
        for token in tokens {
            guard let value = Int(token), value >= 0 else { continue }
            if !values.contains(value) {
                values.append(value)
            }
        }
        return values
    }

    private func formatChannelList(_ channels: [Int]) -> String {
        channels.map { String($0) }.joined(separator: ", ")
    }

    private func clampAutoCropLimitInputs(cropSize: (width: Int, height: Int)) {
        let widthLimit = max(cropSize.width, 1)
        let heightLimit = max(cropSize.height, 1)

        autoCropMinWidth = boundedInt(autoCropMinWidth, min: 1, max: widthLimit)
        autoCropMaxWidth = boundedInt(autoCropMaxWidth, min: autoCropMinWidth, max: widthLimit)
        autoCropMinHeight = boundedInt(autoCropMinHeight, min: 1, max: heightLimit)
        autoCropMaxHeight = boundedInt(autoCropMaxHeight, min: autoCropMinHeight, max: heightLimit)
        autoCropPositionStep = max(1, autoCropPositionStep)
        autoCropSizeStep = max(1, autoCropSizeStep)
        autoCropDownsampleFactor = max(1, autoCropDownsampleFactor)
    }

    private func estimatedAutoCropCandidates(cropSize: (width: Int, height: Int)) -> Int {
        let widthMin = autoCropLimitWidth ? min(autoCropMinWidth, autoCropMaxWidth) : 1
        let widthMax = autoCropLimitWidth ? max(autoCropMinWidth, autoCropMaxWidth) : cropSize.width
        let heightMin = autoCropLimitHeight ? min(autoCropMinHeight, autoCropMaxHeight) : 1
        let heightMax = autoCropLimitHeight ? max(autoCropMinHeight, autoCropMaxHeight) : cropSize.height

        let clampedWidthMin = boundedInt(widthMin, min: 1, max: max(cropSize.width, 1))
        let clampedWidthMax = boundedInt(widthMax, min: clampedWidthMin, max: max(cropSize.width, 1))
        let clampedHeightMin = boundedInt(heightMin, min: 1, max: max(cropSize.height, 1))
        let clampedHeightMax = boundedInt(heightMax, min: clampedHeightMin, max: max(cropSize.height, 1))

        let positionStep = max(1, autoCropPositionStep)
        let sizeStep = max(1, autoCropSizeStep)
        let coarsePositionStep = autoCropUseCoarseToFine ? max(positionStep * 2, positionStep) : positionStep
        let coarseSizeStep = autoCropUseCoarseToFine ? max(sizeStep * 2, sizeStep) : sizeStep

        func values(minValue: Int, maxValue: Int, step: Int) -> [Int] {
            guard minValue <= maxValue else { return [] }
            var result = Array(stride(from: minValue, through: maxValue, by: Swift.max(1, step)))
            if result.last != maxValue {
                result.append(maxValue)
            }
            return result
        }

        let widths = values(minValue: clampedWidthMin, maxValue: clampedWidthMax, step: coarseSizeStep)
        let heights = values(minValue: clampedHeightMin, maxValue: clampedHeightMax, step: coarseSizeStep)
        var coarseTotal = 0
        for h in heights where h <= cropSize.height {
            let yValues = values(minValue: 0, maxValue: max(cropSize.height - h, 0), step: coarsePositionStep)
            for w in widths where w <= cropSize.width {
                let xValues = values(minValue: 0, maxValue: max(cropSize.width - w, 0), step: coarsePositionStep)
                coarseTotal += xValues.count * yValues.count
            }
        }

        guard autoCropUseCoarseToFine else { return coarseTotal }
        let refinePositionStep = max(1, positionStep / 2)
        let refineSizeStep = max(1, sizeStep / 2)
        let refinementReserve = autoCropKeepRefinementReserve ? max(positionStep, sizeStep) : 0
        let sizeRadius = sizeStep + refinementReserve
        let positionRadius = positionStep + refinementReserve
        let refinePerSeed = max(1, (2 * sizeRadius / refineSizeStep + 1) * (2 * sizeRadius / refineSizeStep + 1))
            * max(1, (2 * positionRadius / refinePositionStep + 1) * (2 * positionRadius / refinePositionStep + 1))
        return coarseTotal + 8 * refinePerSeed
    }

    private func applyAutoCropPreset(speed: AutoCropSpeedPreset) {
        switch speed {
        case .fast:
            autoCropPositionStep = 8
            autoCropSizeStep = 8
            autoCropDownsampleFactor = 4
            autoCropUseCoarseToFine = true
            autoCropKeepRefinementReserve = true
        case .balanced:
            autoCropPositionStep = 4
            autoCropSizeStep = 4
            autoCropDownsampleFactor = 2
            autoCropUseCoarseToFine = true
            autoCropKeepRefinementReserve = true
        case .precise:
            autoCropPositionStep = 1
            autoCropSizeStep = 1
            autoCropDownsampleFactor = 1
            autoCropUseCoarseToFine = false
        }
    }

    private func runAutoCropSearch(for op: PipelineOperation, cropSize: (width: Int, height: Int)) {
        autoCropErrorMessage = nil
        autoCropInfoMessage = nil

        guard autoCropEnabled else {
            autoCropErrorMessage = state.localized("Включите автоподбор обрезки")
            return
        }
        guard let sourceCube = state.cube else {
            autoCropErrorMessage = state.localized("Откройте ГСИ перед автоподбором")
            return
        }
        guard let referenceID = autoCropReferenceEntryID,
              let referenceEntry = state.libraryEntry(for: referenceID) else {
            autoCropErrorMessage = state.localized("Выберите ГСИ-референс из библиотеки")
            return
        }

        clampAutoCropLimitInputs(cropSize: cropSize)

        let sourceChannels = parseChannelList(autoCropSourceChannelsText)
        let referenceChannels = parseChannelList(autoCropReferenceChannelsText)
        guard !sourceChannels.isEmpty, !referenceChannels.isEmpty else {
            autoCropErrorMessage = state.localized("Укажите хотя бы один канал source и reference")
            return
        }
        guard sourceChannels.count == referenceChannels.count else {
            autoCropErrorMessage = state.localized("Количество каналов source и reference должно совпадать")
            return
        }

        let sourceLayout = resolvedLayoutForAutoCrop(operation: op, cube: sourceCube)
        let sourceChannelCount = sourceCube.channelCount(for: sourceLayout)
        guard sourceChannels.allSatisfy({ $0 >= 0 && $0 < sourceChannelCount }) else {
            autoCropErrorMessage = LF("pipeline.auto_crop.source_channels_out_of_range", max(0, sourceChannelCount - 1))
            return
        }

        let settings = SpatialAutoCropSettings(
            referenceLibraryID: referenceID,
            metric: autoCropMetric,
            sourceChannels: sourceChannels,
            referenceChannels: referenceChannels,
            minWidth: autoCropLimitWidth ? min(autoCropMinWidth, autoCropMaxWidth) : nil,
            maxWidth: autoCropLimitWidth ? max(autoCropMinWidth, autoCropMaxWidth) : nil,
            minHeight: autoCropLimitHeight ? min(autoCropMinHeight, autoCropMaxHeight) : nil,
            maxHeight: autoCropLimitHeight ? max(autoCropMinHeight, autoCropMaxHeight) : nil,
            positionStep: max(1, autoCropPositionStep),
            sizeStep: max(1, autoCropSizeStep),
            useCoarseToFine: autoCropUseCoarseToFine,
            keepRefinementReserve: autoCropKeepRefinementReserve,
            downsampleFactor: max(1, autoCropDownsampleFactor)
        )

        isComputingAutoCrop = true
        autoCropProgress = 0
        autoCropProgressMessage = state.localized("Загрузка ГСИ-референса...")
        localCropParameters.autoCropResult = nil

        DispatchQueue.global(qos: .userInitiated).async {
            guard let payload = state.exportPayload(for: referenceEntry) else {
                DispatchQueue.main.async {
                    self.isComputingAutoCrop = false
                    self.autoCropErrorMessage = self.state.localized("Не удалось загрузить ГСИ-референс")
                }
                return
            }

            let referenceCube = payload.cube
            let referenceLayout = payload.layout
            let referenceChannelCount = referenceCube.channelCount(for: referenceLayout)
            guard referenceChannels.allSatisfy({ $0 >= 0 && $0 < referenceChannelCount }) else {
                DispatchQueue.main.async {
                    self.isComputingAutoCrop = false
                    self.autoCropErrorMessage = LF("pipeline.auto_crop.reference_channels_out_of_range", max(0, referenceChannelCount - 1))
                }
                return
            }

            let result = CubeAutoSpatialCropper.findBestCrop(
                sourceCube: sourceCube,
                sourceLayout: sourceLayout,
                referenceCube: referenceCube,
                referenceLayout: referenceLayout,
                settings: settings
            ) { info in
                DispatchQueue.main.async {
                    guard self.isComputingAutoCrop else { return }
                    if let bestCrop = info.bestCrop {
                        var preview = bestCrop.clamped(
                            maxWidth: max(cropSize.width, 1),
                            maxHeight: max(cropSize.height, 1)
                        )
                        preview.autoCropSettings = settings
                        preview.autoCropResult = nil
                        self.localCropParameters = preview
                    }
                    self.autoCropProgress = info.progress
                    self.autoCropProgressMessage = info.message
                }
            }

            DispatchQueue.main.async {
                self.isComputingAutoCrop = false

                guard let result else {
                    self.autoCropErrorMessage = self.state.localized("Автоподбор не нашёл корректную область. Проверьте ограничения и каналы.")
                    return
                }

                var updated = result.crop.clamped(
                    maxWidth: max(cropSize.width, 1),
                    maxHeight: max(cropSize.height, 1)
                )
                updated.autoCropSettings = settings
                self.localCropParameters = updated

                self.autoCropProgress = 1.0
                self.autoCropProgressMessage = self.state.localized("Готово")
                let scoreText = String(format: settings.metric == .ssim ? "%.4f" : "%.6f", result.score)
                self.autoCropInfoMessage = LF(
                    "pipeline.auto_crop.area_found",
                    updated.width,
                    updated.height,
                    settings.metric.rawValue,
                    scoreText,
                    result.evaluatedCandidates
                )
            }
        }
    }

    private func resolvedLayoutForAutoCrop(operation: PipelineOperation, cube: HyperCube) -> CubeLayout {
        if operation.layout != .auto {
            return operation.layout
        }
        if state.activeLayout != .auto {
            return state.activeLayout
        }
        if let axes = cube.axes(for: .auto) {
            switch axes.channel {
            case 0:
                return .chw
            case 1:
                return .hcw
            case 2:
                return .hwc
            default:
                return .chw
            }
        }
        return .chw
    }

    private func boundedInt(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
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
                        Text(state.localized("Применить изменения"))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            Spacer()
            
            Button(state.localized("Готово")) {
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
                            Text(AppLocalizer.localized("Нет предпросмотра"))
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
                Text(AppLocalizer.localized("Результаты выравнивания"))
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
                            Text(AppLocalizer.localized("Метрика"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(result.metricName)
                                .font(.system(size: 12, weight: .medium))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalizer.localized("Среднее значение"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.6f", result.averageScore))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalizer.localized("Эталонный канал"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            if let wavelengths, result.referenceChannel < wavelengths.count {
                                Text(
                                    LF(
                                        "pipeline.alignment.reference_channel_with_lambda",
                                        result.referenceChannel,
                                        wavelengths[result.referenceChannel]
                                    )
                                )
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
                    
                    Text(AppLocalizer.localized("Результаты по каналам"))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 16)
                    
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            HStack {
                                Text(AppLocalizer.localized("Канал"))
                                    .frame(width: 50, alignment: .leading)
                                Text(AppLocalizer.localized("λ (нм)"))
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
                                        Text(AppLocalizer.localized("(эталон)"))
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
                    Text(AppLocalizer.localized("Нет данных о результатах"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button(AppLocalizer.localized("Закрыть")) {
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
