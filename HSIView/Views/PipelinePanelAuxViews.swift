import SwiftUI
import AppKit
import Charts

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

struct CropOverlayView: View {
    @Binding var parameters: SpatialCropParameters
    let pixelWidth: Int
    let pixelHeight: Int
    
    @State private var dragSnapshot: SpatialCropParameters?
    @State private var hoveredZone: HoverZone?
    @State private var activeDragZone: HoverZone?
    
    private let edgeVisualThickness: CGFloat = 3
    private let edgeHitThickness: CGFloat = 14
    private let edgeSpanPadding: CGFloat = 24
    
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
                        .strokeBorder(
                            isHighlighted(.inside) ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.9),
                            lineWidth: isHighlighted(.inside) ? 1.8 : 1.2
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    if isHighlighted(.inside) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            updateHoverState(for: .inside, hovering: hovering)
                        }
                        .gesture(moveGesture(xScale: xScale, yScale: yScale))
                    
                    edgeHandle(orientation: .vertical, zone: .left, length: rect.height + edgeSpanPadding)
                        .position(x: rect.minX, y: rect.midY)
                        .gesture(edgeGesture(.left, xScale: xScale, yScale: yScale))
                    
                    edgeHandle(orientation: .vertical, zone: .right, length: rect.height + edgeSpanPadding)
                        .position(x: rect.maxX, y: rect.midY)
                        .gesture(edgeGesture(.right, xScale: xScale, yScale: yScale))
                    
                    edgeHandle(orientation: .horizontal, zone: .top, length: rect.width + edgeSpanPadding)
                        .position(x: rect.midX, y: rect.minY)
                        .gesture(edgeGesture(.top, xScale: xScale, yScale: yScale))
                    
                    edgeHandle(orientation: .horizontal, zone: .bottom, length: rect.width + edgeSpanPadding)
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
    private func edgeHandle(orientation: HandleOrientation, zone: HoverZone, length: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isHighlighted(zone) ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.9))
                .frame(
                    width: orientation == .vertical ? edgeVisualThickness : max(length, 1),
                    height: orientation == .horizontal ? edgeVisualThickness : max(length, 1)
                )
        }
        .frame(
            width: orientation == .vertical ? edgeHitThickness : max(length, 1),
            height: orientation == .horizontal ? edgeHitThickness : max(length, 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            updateHoverState(for: zone, hovering: hovering)
        }
    }
    
    private func edgeGesture(_ edge: CropEdge, xScale: CGFloat, yScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragSnapshot == nil {
                    dragSnapshot = parameters
                    activeDragZone = edge.zone
                    setCursor(for: edge.zone, dragging: true)
                }
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
                activeDragZone = nil
                restoreCursorAfterInteraction()
            }
    }
    
    private func moveGesture(xScale: CGFloat, yScale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragSnapshot == nil {
                    dragSnapshot = parameters
                    activeDragZone = .inside
                    setCursor(for: .inside, dragging: true)
                }
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
                activeDragZone = nil
                restoreCursorAfterInteraction()
            }
    }
    
    private func deltaPixels(_ translation: CGFloat, scale: CGFloat) -> Int {
        guard scale.isFinite, scale != 0 else { return 0 }
        return Int((translation / scale).rounded())
    }
    
    private func isHighlighted(_ zone: HoverZone) -> Bool {
        activeDragZone == zone || hoveredZone == zone
    }
    
    private func updateHoverState(for zone: HoverZone, hovering: Bool) {
        if hovering {
            hoveredZone = zone
            guard activeDragZone == nil else { return }
            setCursor(for: zone, dragging: false)
            return
        }
        
        guard hoveredZone == zone else { return }
        hoveredZone = nil
        guard activeDragZone == nil else { return }
        restoreCursorAfterInteraction()
    }
    
    private func restoreCursorAfterInteraction() {
        if let zone = hoveredZone {
            setCursor(for: zone, dragging: false)
        } else {
            NSCursor.arrow.set()
        }
    }
    
    private func setCursor(for zone: HoverZone, dragging: Bool) {
        switch zone {
        case .inside:
            if dragging {
                NSCursor.closedHand.set()
            } else {
                NSCursor.openHand.set()
            }
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        }
    }
    
    private enum CropEdge {
        case left, right, top, bottom
        
        var zone: HoverZone {
            switch self {
            case .left: return .left
            case .right: return .right
            case .top: return .top
            case .bottom: return .bottom
            }
        }
    }
    
    private enum HoverZone: Equatable {
        case inside
        case left
        case right
        case top
        case bottom
    }
    
    private enum HandleOrientation {
        case vertical
        case horizontal
    }
}

struct AutoWhitePointSearchWindow: View {
    let cube: HyperCube
    let layout: CubeLayout
    let previewImage: NSImage?
    let wavelengths: [Double]?
    let onPresetChange: (WhitePointSearchPreset) -> Void
    let onWindowPresetChange: (WhitePointWindowPreset) -> Void
    let onApply: (WhitePointCandidate, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: WhitePointSearchPreset
    @State private var selectedWindowPreset: WhitePointWindowPreset
    @State private var factorWeights: WhitePointSearchFactorWeights = .identity
    @State private var showAdvancedFactors: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var progress: Double = 0.0
    @State private var progressMessage: String = L("Подготовка данных сцены…")
    @State private var candidates: [WhitePointCandidate] = []
    @State private var selectedCandidateID: UUID?
    @State private var evaluatedCandidates: Int = 0
    @State private var totalCandidates: Int = 0
    @State private var rejectedByGlare: Int = 0
    @State private var errorMessage: String?

    init(
        cube: HyperCube,
        layout: CubeLayout,
        preset: WhitePointSearchPreset,
        windowPreset: WhitePointWindowPreset,
        previewImage: NSImage?,
        wavelengths: [Double]?,
        onPresetChange: @escaping (WhitePointSearchPreset) -> Void,
        onWindowPresetChange: @escaping (WhitePointWindowPreset) -> Void,
        onApply: @escaping (WhitePointCandidate, Int) -> Void
    ) {
        self.cube = cube
        self.layout = layout
        self.previewImage = previewImage
        self.wavelengths = wavelengths
        self.onPresetChange = onPresetChange
        self.onWindowPresetChange = onWindowPresetChange
        self.onApply = onApply
        _selectedPreset = State(initialValue: preset)
        _selectedWindowPreset = State(initialValue: windowPreset)
    }

    private var spatialSize: (width: Int, height: Int) {
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        if let axes = cube.axes(for: layout) {
            return (dims[axes.width], dims[axes.height])
        }
        return (1, 1)
    }

    private var selectedCandidate: WhitePointCandidate? {
        guard let selectedCandidateID else { return nil }
        return candidates.first(where: { $0.id == selectedCandidateID })
    }

    private var selectedCandidateRank: Int? {
        guard let selectedCandidateID,
              let idx = candidates.firstIndex(where: { $0.id == selectedCandidateID }) else {
            return nil
        }
        return idx + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("pipeline.calibration.auto_white.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(LF("pipeline.calibration.auto_white.preset_used", selectedPreset.localizedTitle))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    runAnalysis()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("pipeline.calibration.auto_white.reanalyze"))
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isAnalyzing)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    WhitePointCandidatePreview(
                        image: previewImage,
                        pixelWidth: spatialSize.width,
                        pixelHeight: spatialSize.height,
                        candidates: candidates,
                        selectedCandidateID: $selectedCandidateID
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.65))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(progressMessage)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)

                    HStack(spacing: 14) {
                        Text(LF("pipeline.calibration.auto_white.evaluated", evaluatedCandidates, max(totalCandidates, evaluatedCandidates)))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(LF("pipeline.calibration.auto_white.rejected_glare", rejectedByGlare))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("Пресет автопоиска"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Picker("", selection: presetBinding) {
                                        ForEach(WhitePointSearchPreset.allCases) { preset in
                                            Text(preset.localizedTitle).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 260)
                                    .disabled(isAnalyzing)
                                    Text(selectedPreset.localizedDescription)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("pipeline.calibration.auto_white.window_preset.title"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Picker("", selection: windowPresetBinding) {
                                        ForEach(WhitePointWindowPreset.allCases) { preset in
                                            Text(preset.localizedTitle).tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 260)
                                    .disabled(isAnalyzing)
                                    Text(selectedWindowPreset.localizedDescription)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }

                            DisclosureGroup(isExpanded: $showAdvancedFactors) {
                                VStack(alignment: .leading, spacing: 8) {
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.brightness"),
                                        value: Binding(
                                            get: { factorWeights.brightness },
                                            set: { factorWeights.brightness = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.local_homogeneity"),
                                        value: Binding(
                                            get: { factorWeights.localHomogeneity },
                                            set: { factorWeights.localHomogeneity = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.flatness"),
                                        value: Binding(
                                            get: { factorWeights.spectralFlatness },
                                            set: { factorWeights.spectralFlatness = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.dispersion"),
                                        value: Binding(
                                            get: { factorWeights.spectralDispersion },
                                            set: { factorWeights.spectralDispersion = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.spectral_homogeneity"),
                                        value: Binding(
                                            get: { factorWeights.spectralHomogeneity },
                                            set: { factorWeights.spectralHomogeneity = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.contrast"),
                                        value: Binding(
                                            get: { factorWeights.contrast },
                                            set: { factorWeights.contrast = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.neutrality"),
                                        value: Binding(
                                            get: { factorWeights.neutrality },
                                            set: { factorWeights.neutrality = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.area"),
                                        value: Binding(
                                            get: { factorWeights.area },
                                            set: { factorWeights.area = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.shape"),
                                        value: Binding(
                                            get: { factorWeights.shape },
                                            set: { factorWeights.shape = $0 }
                                        )
                                    )
                                    factorSlider(
                                        title: L("pipeline.calibration.auto_white.factor.glare_penalty"),
                                        value: Binding(
                                            get: { factorWeights.glarePenalty },
                                            set: { factorWeights.glarePenalty = $0 }
                                        )
                                    )

                                    Button(L("pipeline.calibration.auto_white.factor.reset")) {
                                        factorWeights = .identity
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isAnalyzing)
                                }
                                .padding(.top, 6)
                            } label: {
                                HStack {
                                    Text(L("pipeline.calibration.auto_white.advanced.title"))
                                        .font(.system(size: 10, weight: .semibold))
                                    Spacer()
                                    Text(L("pipeline.calibration.auto_white.advanced.range_hint"))
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.system(size: 10))
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
                            .cornerRadius(8)

                            Text(L("pipeline.calibration.auto_white.candidates"))
                                .font(.system(size: 11, weight: .semibold))

                            VStack(spacing: 6) {
                                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                    candidateRow(candidate: candidate, rank: index + 1)
                                }
                            }

                            Divider()

                            if let selectedCandidate, let rank = selectedCandidateRank {
                                Text(LF("pipeline.calibration.auto_white.candidate_title", rank))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(
                                    LF(
                                        "pipeline.calibration.auto_white.coords",
                                        selectedCandidate.rect.minX,
                                        selectedCandidate.rect.minY,
                                        selectedCandidate.rect.width,
                                        selectedCandidate.rect.height
                                    )
                                )
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                                WhitePointCandidateMetricsView(candidate: selectedCandidate)
                                WhitePointSpectrumChart(
                                    values: selectedCandidate.meanSpectrum,
                                    wavelengths: wavelengths,
                                    height: 210
                                )
                                .padding(.top, 4)
                            } else {
                                Text(L("pipeline.calibration.auto_white.select_hint"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                    }

                    Button {
                        guard let selectedCandidate,
                              let rank = selectedCandidateRank else { return }
                        onApply(selectedCandidate, rank)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(L("pipeline.calibration.auto_white.apply"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCandidate == nil || isAnalyzing)
                }
                .padding(14)
                .frame(width: 390)
            }
        }
        .frame(width: 1200, height: 760)
        .onAppear {
            runAnalysis()
        }
    }

    @ViewBuilder
    private func candidateRow(candidate: WhitePointCandidate, rank: Int) -> some View {
        let isSelected = selectedCandidateID == candidate.id
        Button {
            selectedCandidateID = candidate.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.yellow : Color.cyan.opacity(0.9))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("pipeline.calibration.auto_white.candidate_title", rank))
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                    Text(
                        LF(
                            "pipeline.calibration.auto_white.coords",
                            candidate.rect.minX,
                            candidate.rect.minY,
                            candidate.rect.width,
                            candidate.rect.height
                        )
                    )
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.3f", candidate.score))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .yellow : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.yellow.opacity(0.14) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private func runAnalysis() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        progress = 0.01
        progressMessage = L("Подготовка данных сцены…")
        candidates = []
        selectedCandidateID = nil
        errorMessage = nil
        evaluatedCandidates = 0
        totalCandidates = 0
        rejectedByGlare = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let result = CubeWhitePointAutoDetector.findCandidates(
                cube: cube,
                layout: layout,
                preset: selectedPreset,
                windowPreset: selectedWindowPreset,
                factorWeights: factorWeights,
                maxCandidates: 10
            ) { info in
                DispatchQueue.main.async {
                    self.progress = info.progress
                    self.progressMessage = info.message
                    self.evaluatedCandidates = info.evaluatedCandidates
                    self.totalCandidates = info.totalCandidates
                }
            }

            DispatchQueue.main.async {
                self.isAnalyzing = false
                self.progress = 1.0
                if let result {
                    self.candidates = result.candidates
                    self.selectedCandidateID = result.candidates.first?.id
                    self.rejectedByGlare = result.rejectedByGlare
                    self.evaluatedCandidates = result.evaluatedCandidates
                    self.totalCandidates = max(self.totalCandidates, result.evaluatedCandidates)
                    self.progressMessage = LF("pipeline.calibration.auto_white.progress_done", result.candidates.count)
                } else {
                    self.progressMessage = L("Подходящие области не найдены")
                    self.errorMessage = L("pipeline.calibration.auto_white.not_found")
                }
            }
        }
    }

    private var presetBinding: Binding<WhitePointSearchPreset> {
        Binding(
            get: { selectedPreset },
            set: { newValue in
                guard selectedPreset != newValue else { return }
                selectedPreset = newValue
                onPresetChange(newValue)
                if !isAnalyzing {
                    runAnalysis()
                }
            }
        )
    }

    private var windowPresetBinding: Binding<WhitePointWindowPreset> {
        Binding(
            get: { selectedWindowPreset },
            set: { newValue in
                guard selectedWindowPreset != newValue else { return }
                selectedWindowPreset = newValue
                onWindowPresetChange(newValue)
                if !isAnalyzing {
                    runAnalysis()
                }
            }
        )
    }

    @ViewBuilder
    private func factorSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            HStack(spacing: 8) {
                Slider(
                    value: value,
                    in: 0...2,
                    step: 0.05
                )
                .disabled(isAnalyzing)
            }
        }
    }
}

struct WhitePointCandidatePreview: View {
    let image: NSImage?
    let pixelWidth: Int
    let pixelHeight: Int
    let candidates: [WhitePointCandidate]
    @Binding var selectedCandidateID: UUID?
    @State private var baseZoom: CGFloat = 1.0
    @State private var basePan: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let fitted = fittedSize(for: image?.size ?? CGSize(width: 1, height: 1), in: container)
            let activeZoom = clamp(baseZoom * pinchScale, min: minZoom, max: maxZoom)
            let rawPan = CGSize(width: basePan.width + dragOffset.width, height: basePan.height + dragOffset.height)
            let activePan = clampedPan(rawPan, scale: activeZoom, fittedSize: fitted, containerSize: container)
            let offsetX = (container.width - fitted.width) / 2
            let offsetY = (container.height - fitted.height) / 2

            ZStack {
                ZStack {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fitted.width, height: fitted.height)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .overlay(
                                Text(L("pipeline.calibration.auto_white.no_preview"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            )
                            .frame(width: fitted.width, height: fitted.height)
                    }

                    if pixelWidth > 0 && pixelHeight > 0 {
                        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                            let phase = timeline.date.timeIntervalSinceReferenceDate
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, candidate in
                                let rect = displayRect(for: candidate.rect, imageSize: fitted)
                                let selected = selectedCandidateID == candidate.id
                                let pulse = 0.5 + 0.5 * sin(phase * 4.0 + Double(idx) * 0.9)

                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill((selected ? Color.yellow : Color.cyan).opacity(0.08 + (selected ? 0.14 : 0.05) * pulse))
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(
                                            (selected ? Color.yellow : Color.cyan).opacity(selected ? 0.92 : 0.55 + 0.2 * pulse),
                                            lineWidth: selected ? 2.2 : 1.4
                                        )
                                }
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCandidateID = candidate.id
                                }
                            }
                        }
                        .frame(width: fitted.width, height: fitted.height)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .scaleEffect(activeZoom, anchor: .center)
                .offset(activePan)
                .position(x: offsetX + fitted.width / 2, y: offsetY + fitted.height / 2)

                zoomControls(fittedSize: fitted, containerSize: container)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(magnificationGesture(fittedSize: fitted, containerSize: container))
            .simultaneousGesture(panGesture(fittedSize: fitted, containerSize: container))
        }
    }

    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            let side = min(container.width, container.height)
            return CGSize(width: side, height: side)
        }
        let widthScale = container.width / imageSize.width
        let heightScale = container.height / imageSize.height
        let scale = min(widthScale, heightScale)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func displayRect(for rect: SpectrumROIRect, imageSize: CGSize) -> CGRect {
        let widthScale = imageSize.width / CGFloat(max(pixelWidth, 1))
        let heightScale = imageSize.height / CGFloat(max(pixelHeight, 1))
        return CGRect(
            x: CGFloat(rect.minX) * widthScale,
            y: CGFloat(rect.minY) * heightScale,
            width: max(1, CGFloat(rect.width) * widthScale),
            height: max(1, CGFloat(rect.height) * heightScale)
        )
    }

    @ViewBuilder
    private func zoomControls(fittedSize: CGSize, containerSize: CGSize) -> some View {
        HStack(spacing: 8) {
            Button {
                updateZoom(
                    to: baseZoom - 0.25,
                    fittedSize: fittedSize,
                    containerSize: containerSize
                )
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Slider(
                value: Binding(
                    get: { Double(baseZoom) },
                    set: { newValue in
                        updateZoom(
                            to: CGFloat(newValue),
                            fittedSize: fittedSize,
                            containerSize: containerSize
                        )
                    }
                ),
                in: Double(minZoom)...Double(maxZoom)
            )
            .frame(width: 120)

            Text("\(Int(baseZoom * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(width: 44, alignment: .trailing)

            Button {
                updateZoom(
                    to: baseZoom + 0.25,
                    fittedSize: fittedSize,
                    containerSize: containerSize
                )
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                baseZoom = 1.0
                basePan = .zero
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82))
        .cornerRadius(9)
    }

    private func magnificationGesture(fittedSize: CGSize, containerSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                updateZoom(
                    to: baseZoom * value,
                    fittedSize: fittedSize,
                    containerSize: containerSize
                )
            }
    }

    private func panGesture(fittedSize: CGSize, containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let rawPan = CGSize(
                    width: basePan.width + value.translation.width,
                    height: basePan.height + value.translation.height
                )
                basePan = clampedPan(
                    rawPan,
                    scale: baseZoom,
                    fittedSize: fittedSize,
                    containerSize: containerSize
                )
            }
    }

    private func updateZoom(to value: CGFloat, fittedSize: CGSize, containerSize: CGSize) {
        baseZoom = clamp(value, min: minZoom, max: maxZoom)
        basePan = clampedPan(basePan, scale: baseZoom, fittedSize: fittedSize, containerSize: containerSize)
    }

    private func clampedPan(_ pan: CGSize, scale: CGFloat, fittedSize: CGSize, containerSize: CGSize) -> CGSize {
        let scaledWidth = fittedSize.width * scale
        let scaledHeight = fittedSize.height * scale
        let maxPanX = max(0, (scaledWidth - containerSize.width) / 2)
        let maxPanY = max(0, (scaledHeight - containerSize.height) / 2)
        return CGSize(
            width: clamp(pan.width, min: -maxPanX, max: maxPanX),
            height: clamp(pan.height, min: -maxPanY, max: maxPanY)
        )
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

struct WhitePointCandidateMetricsView: View {
    let candidate: WhitePointCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            metricRow(label: L("pipeline.calibration.auto_white.metric.total"), value: candidate.score)
            metricRow(label: L("pipeline.calibration.auto_white.metric.brightness"), value: candidate.brightnessScore)
            metricRow(label: L("pipeline.calibration.auto_white.metric.homogeneity"), value: candidate.spectralHomogeneityScore)
            metricRow(label: L("pipeline.calibration.auto_white.metric.flatness"), value: candidate.spectralFlatnessScore)
            metricRow(label: L("pipeline.calibration.auto_white.metric.dispersion"), value: candidate.spectralDispersionScore)
            metricRow(label: L("pipeline.calibration.auto_white.metric.contrast"), value: candidate.contrastScore)
            metricRow(label: L("pipeline.calibration.auto_white.metric.glare"), value: candidate.glarePenalty)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(8)
    }

    private func metricRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.3f", value))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
    }
}

struct WhitePointSpectrumChart: View {
    let values: [Double]
    let wavelengths: [Double]?
    let height: CGFloat

    private var points: [(x: Double, y: Double)] {
        guard !values.isEmpty else { return [] }
        if let wavelengths, wavelengths.count == values.count {
            return zip(wavelengths, values).map { ($0.0, $0.1) }
        }
        return values.enumerated().map { (Double($0.offset), $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("pipeline.calibration.auto_white.spectrum"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value(xAxisLabel, point.x),
                        y: .value(L("graph.axis.intensity"), point.y)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.cyan)
                }
            }
            .chartXAxisLabel(xAxisLabel)
            .chartYAxisLabel("I")
            .chartLegend(.hidden)
            .frame(height: height)
            .padding(.horizontal, 4)
        }
    }

    private var xAxisLabel: String {
        if let wavelengths, wavelengths.count == values.count {
            return L("pipeline.calibration.auto_white.lambda_axis")
        }
        return L("pipeline.calibration.auto_white.channel_axis")
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
