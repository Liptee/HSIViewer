import Foundation
import AppKit

final class AppState: ObservableObject {
    @Published var cube: HyperCube? {
        didSet {
            handleCubeChange(previousCube: oldValue)
        }
    }
    @Published var cubeURL: URL?
    @Published var layout: CubeLayout = .auto {
        didSet {
            guard oldValue != layout else { return }
            updateResolvedLayout()
            updateChannelCount()
            refreshWavelengthsForLayoutChange()
        }
    }
    @Published var currentChannel: Double = 0
    @Published var channelCount: Int = 0
    @Published var loadError: String?
    
    @Published var viewMode: ViewMode = .gray
    @Published var colorSynthesisConfig: ColorSynthesisConfig = .default(channelCount: 0, wavelengths: nil)
    @Published var ndPreset: NDIndexPreset = .ndvi
    @Published var ndviRedTarget: String = "660"
    @Published var ndviNIRTarget: String = "840"
    @Published var ndsiGreenTarget: String = "555"
    @Published var ndsiSWIRTarget: String = "1610"
    @Published var wdviSlope: String = "1.0"
    @Published var wdviIntercept: String = "0.0"
    @Published var ndPalette: NDPalette = .classic
    @Published var ndThreshold: Double = 0.3
    
    @Published var wavelengths: [Double]? = nil {
        didSet {
            if suppressSpectrumRefresh { return }
            if oldValue == nil && wavelengths == nil { return }
            refreshSpectrumSamples()
            refreshROISamples()
            refreshColorSynthesisDefaultsIfNeeded()
        }
    }
    @Published var lambdaStart: String = "400"
    @Published var lambdaEnd: String = "1000"
    @Published var lambdaStep: String = ""
    
    @Published var zoomScale: CGFloat = 1.0
    @Published var imageOffset: CGSize = .zero
    
    @Published var normalizationType: CubeNormalizationType = .none
    @Published var normalizationParams: CubeNormalizationParameters = .default
    
    @Published var autoScaleOnTypeConversion: Bool = true
    
    @Published var pipelineOperations: [PipelineOperation] = []
    @Published var pipelineAutoApply: Bool = true
    @Published var showAlignmentVisualization: Bool = false {
        didSet {
            if !showAlignmentVisualization {
                alignmentPointsEditable = false
            }
        }
    }
    @Published var alignmentPointsEditable: Bool = false
    
    @Published var showExportView: Bool = false
    @Published var pendingExport: PendingExportInfo? = nil
    @Published var exportEntireLibrary: Bool = false
    
    @Published var isTrimMode: Bool = false
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    
    @Published var isBusy: Bool = false
    @Published var busyMessage: String?
    @Published var alignmentProgress: Double = 0.0
    @Published var alignmentProgressMessage: String = ""
    @Published var alignmentCurrentChannel: Int = 0
    @Published var alignmentTotalChannels: Int = 0
    @Published var alignmentStartTime: Date?
    @Published var alignmentElapsedTime: String = ""
    @Published var alignmentEstimatedTimeRemaining: String = ""
    @Published var alignmentStage: String = ""
    @Published var isAlignmentInProgress: Bool = false
    
    func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval)) сек"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes) мин \(seconds) сек"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours) ч \(minutes) мин"
        }
    }
    
    @Published var pendingMatSelection: MatSelectionRequest?
    @Published var libraryEntries: [CubeLibraryEntry] = []
    @Published private(set) var hasProcessingClipboard: Bool = false
    @Published var libraryExportProgressState: LibraryExportProgressState?
    
    @Published var activeAnalysisTool: AnalysisTool = .none
    @Published var isGraphPanelExpanded: Bool = false
    @Published var spectrumSamples: [SpectrumSample] = []
    @Published var pendingSpectrumSample: SpectrumSample?
    @Published var roiSamples: [SpectrumROISample] = []
    @Published var pendingROISample: SpectrumROISample?
    @Published var roiAggregationMode: SpectrumROIAggregationMode = .mean {
        didSet {
            guard oldValue != roiAggregationMode else { return }
            refreshROISamples()
        }
    }
    
    private var originalCube: HyperCube?
    private var baseWavelengths: [Double]? = nil
    private let processingQueue = DispatchQueue(label: "com.hsiview.processing", qos: .userInitiated)
    private var resolvedAutoLayout: CubeLayout = .auto
    private var sessionSnapshots: [URL: CubeSessionSnapshot] = [:]
    private var pendingSessionRestore: CubeSessionSnapshot?
    private var spectralTrimRange: ClosedRange<Int>?
    private var libraryExportDismissWorkItem: DispatchWorkItem?
    private var spectrumColorCounter: Int = 0
    private var roiColorCounter: Int = 0
    private var suppressSpectrumRefresh: Bool = false
    private var spectrumRotationTurns: Int = 0
    private var spectrumSpatialSize: (width: Int, height: Int)?
    private var spectrumSpatialOps: [PipelineOperation] = []
    private var spectrumSpatialBaseSize: (width: Int, height: Int)?
    @Published var pcaPendingConfig: PCAVisualizationConfig?
    @Published var pcaRenderedImage: NSImage?
    @Published var isPCAApplying: Bool = false
    @Published var pcaProgressMessage: String?
    
    @Published var maskEditorState = MaskEditorState()
    @Published var librarySpectrumCache = LibrarySpectrumCache()
    @Published var graphSeriesColors: [UUID: NSColor] = [:]
    @Published var graphSeriesHiddenIDs: Set<UUID> = []
    @Published var graphSeriesOverrides: [UUID: SeriesStyleOverride] = [:]
    @Published var graphWindowPalette: String = "default"
    @Published var graphWindowStyle: String = "lines"
    @Published var graphWindowShowLegend: Bool = true
    @Published var graphWindowShowGrid: Bool = true
    @Published var graphWindowLineWidth: Double = 1.5
    @Published var graphWindowPointSize: Double = 24
    @Published var graphWindowAutoScaleX: Bool = true
    @Published var graphWindowAutoScaleY: Bool = true
    @Published var graphWindowXMin: Double = 0
    @Published var graphWindowXMax: Double = 1000
    @Published var graphWindowYMin: Double = 0
    @Published var graphWindowYMax: Double = 1
    @Published var showAccessManager: Bool = false
    @Published private(set) var pipelineOperationClipboard: PipelineOperation?
    @Published private(set) var spectrumClipboard: SpectrumClipboardContent?
    private var hasCustomColorSynthesisMapping: Bool = false
    private var ndFallbackIndices: [NDIndexPreset: (positive: Int, negative: Int)] = [
        .ndvi: (0, 0),
        .ndsi: (0, 0),
        .wdvi: (0, 0)
    ]
    private var lastPipelineAppliedOperations: [PipelineOperation] = []
    private var lastPipelineResult: HyperCube?
    private var lastPipelineBaseCubeID: UUID?
    private var pendingRestoreSpectrumDescriptors: [SpectrumSampleDescriptor]?
    private var pendingRestoreROISampleDescriptors: [SpectrumROISampleDescriptor]?
    private var processingClipboard: ProcessingClipboard? {
        didSet {
            hasProcessingClipboard = processingClipboard != nil
        }
    }

    struct SpectrumSampleClipboard {
        let normalizedX: Double
        let normalizedY: Double
        let displayName: String?
    }
    
    struct SpectrumROISampleClipboard {
        let normalizedMinX: Double
        let normalizedMinY: Double
        let normalizedMaxX: Double
        let normalizedMaxY: Double
        let displayName: String?
    }
    
    enum SpectrumClipboardContent {
        case point(SpectrumSampleClipboard)
        case roi(SpectrumROISampleClipboard)
    }
    
    var displayCube: HyperCube? {
        guard let original = originalCube else { return cube }
        return cube
    }

    var activeLayout: CubeLayout {
        if layout == .auto {
            if resolvedAutoLayout == .auto {
                resolvedAutoLayout = inferLayout(for: cube ?? originalCube)
            }
            if resolvedAutoLayout == .auto {
                return .chw
            }
            return resolvedAutoLayout
        }
        return layout
    }
    
    var activeSpectrumSamples: [SpectrumSample] {
        var result = spectrumSamples
        if let pending = pendingSpectrumSample {
            result.append(pending)
        }
        return result
    }
    
    var activeAlignmentResult: SpectralAlignmentResult? {
        guard showAlignmentVisualization else { return nil }
        for op in pipelineOperations {
            if op.type == .spectralAlignment,
               let params = op.spectralAlignmentParams,
               let result = params.alignmentResult {
                return result
            }
        }
        return nil
    }
    
    var activeAlignmentParams: SpectralAlignmentParameters? {
        guard showAlignmentVisualization else { return nil }
        for op in pipelineOperations {
            if op.type == .spectralAlignment,
               let params = op.spectralAlignmentParams {
                return params
            }
        }
        return nil
    }
    
    func updateAlignmentPoint(at index: Int, to point: AlignmentPoint) {
        guard index >= 0, index < 4 else { return }
        for i in 0..<pipelineOperations.count {
            if pipelineOperations[i].type == .spectralAlignment {
                pipelineOperations[i].spectralAlignmentParams?.referencePoints[index] = point
                pipelineOperations[i].spectralAlignmentParams?.isComputed = false
                pipelineOperations[i].spectralAlignmentParams?.cachedHomographies = nil
                pipelineOperations[i].spectralAlignmentParams?.alignmentResult = nil
                break
            }
        }
    }
    
    func resetAlignmentPoints() {
        for i in 0..<pipelineOperations.count {
            if pipelineOperations[i].type == .spectralAlignment {
                pipelineOperations[i].spectralAlignmentParams?.referencePoints = AlignmentPoint.defaultCorners()
                pipelineOperations[i].spectralAlignmentParams?.isComputed = false
                pipelineOperations[i].spectralAlignmentParams?.cachedHomographies = nil
                pipelineOperations[i].spectralAlignmentParams?.alignmentResult = nil
                break
            }
        }
    }
    
    var displayedSpectrumSamples: [SpectrumSample] {
        let samples = activeSpectrumSamples
        guard isTrimMode else { return samples }
        let maxIndex = max(channelCount - 1, 0)
        let lower = max(0, min(Int(trimStart), maxIndex))
        let upper = max(lower, min(Int(trimEnd), maxIndex))
        let range = lower...upper
        return samples.compactMap { $0.trimmed(to: range) }
    }
    
    var activeROISamples: [SpectrumROISample] {
        var items = roiSamples
        if let pending = pendingROISample {
            items.append(pending)
        }
        return items
    }
    
    var displayedROISamples: [SpectrumROISample] {
        let samples = activeROISamples
        guard isTrimMode else { return samples }
        let maxIndex = max(channelCount - 1, 0)
        let lower = max(0, min(Int(trimStart), maxIndex))
        let upper = max(lower, min(Int(trimEnd), maxIndex))
        let range = lower...upper
        return samples.compactMap { $0.trimmed(to: range) }
    }

    var currentCubeDisplayName: String {
        guard let url = cubeURL else { return "Куб" }
        return displayName(for: url)
    }
    
    var defaultExportBaseName: String {
        guard let url = cubeURL else { return "hypercube" }
        return exportBaseName(for: url)
    }
    
    func displayName(for url: URL) -> String {
        let canonical = canonicalURL(url)
        return libraryEntries.first(where: { $0.canonicalPath == canonical.path })?.displayName ?? canonical.lastPathComponent
    }
    
    func exportBaseName(for url: URL) -> String {
        let canonical = canonicalURL(url)
        if let entry = libraryEntries.first(where: { $0.canonicalPath == canonical.path }) {
            return entry.exportBaseName
        }
        let rawName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawName.isEmpty ? "hypercube" : rawName
    }
    
    func open(url: URL) {
        _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: url)
        persistCurrentSession()
        let canonical = canonicalURL(url)
        cubeURL = canonical
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0
        resetZoom()
        pendingMatSelection = nil
        pendingSessionRestore = sessionSnapshots[canonical]
        resetSessionState()
        
        if handleMatOpenIfNeeded(for: canonical) {
            return
        }
        
        beginBusy(message: "Импорт гиперкуба…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = ImageLoaderFactory.load(from: canonical)
            DispatchQueue.main.async {
                self.handleLoadResult(result: result, url: canonical)
            }
        }
    }
    
    func updateChannelCount() {
        guard let cube = cube else {
            channelCount = 0
            currentChannel = 0
            clampColorSynthesisMapping()
            return
        }
        
        channelCount = cube.channelCount(for: activeLayout)
        
        if channelCount <= 0 {
            currentChannel = 0
        } else if Int(currentChannel) >= channelCount {
            currentChannel = Double(channelCount - 1)
        }
        
        clampColorSynthesisMapping()
        refreshColorSynthesisDefaultsIfNeeded()
    }
    
    func setColorSynthesisMode(_ mode: ColorSynthesisMode) {
        colorSynthesisConfig.mode = mode
        hasCustomColorSynthesisMapping = true
        if mode == .pcaVisualization {
            pcaPendingConfig = colorSynthesisConfig.pcaConfig
        }
    }
    
    func updateColorSynthesisMapping(_ mapping: RGBChannelMapping, userInitiated: Bool) {
        colorSynthesisConfig.mapping = mapping.clamped(maxChannelCount: channelCount)
        if userInitiated {
            hasCustomColorSynthesisMapping = true
        }
    }

    func updateColorSynthesisRangeMapping(_ mapping: RGBChannelRangeMapping, userInitiated: Bool) {
        colorSynthesisConfig.rangeMapping = mapping.clamped(maxChannelCount: channelCount)
        if userInitiated {
            hasCustomColorSynthesisMapping = true
        }
    }
    
    func updatePCAConfig(_ updater: (inout PCAVisualizationConfig) -> Void) {
        if pcaPendingConfig == nil {
            pcaPendingConfig = colorSynthesisConfig.pcaConfig
        }
        updater(&pcaPendingConfig!)
        hasCustomColorSynthesisMapping = true
        if let pending = pcaPendingConfig, !pending.lockBasis {
            pcaPendingConfig?.basis = nil
            pcaPendingConfig?.clipUpper = nil
            pcaPendingConfig?.explainedVariance = nil
            pcaPendingConfig?.sourceCubeID = nil
        }
    }

    func applyPCAVisualization() {
        guard !isPCAApplying else { return }
        guard let cube = cube else { return }
        let layout = activeLayout
        var configToApply = pcaPendingConfig ?? colorSynthesisConfig.pcaConfig
        var roiRect: SpectrumROIRect?
        if configToApply.computeScope == .roi {
            guard let roiID = configToApply.selectedROI,
                  let roi = displayedROISamples.first(where: { $0.id == roiID })?.rect else {
                pcaProgressMessage = "Выберите ROI для PCA"
                return
            }
            roiRect = roi
        }
        pcaRenderedImage = nil
        isPCAApplying = true
        pcaProgressMessage = "Подготовка…"
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = PCARenderer.render(
                cube: cube,
                layout: layout,
                config: configToApply,
                roi: roiRect,
                progress: { message in
                    DispatchQueue.main.async {
                        self.pcaProgressMessage = message
                    }
                }
            )
            
            DispatchQueue.main.async {
                self.colorSynthesisConfig.pcaConfig = result.updatedConfig
                self.pcaPendingConfig = nil
                self.pcaRenderedImage = result.image
                self.isPCAApplying = false
                self.pcaProgressMessage = nil
            }
        }
    }
    
    private func refreshColorSynthesisDefaultsIfNeeded() {
        guard !hasCustomColorSynthesisMapping else { return }
        colorSynthesisConfig.mapping = RGBChannelMapping.defaultMapping(
            channelCount: channelCount,
            wavelengths: wavelengths
        )
        colorSynthesisConfig.rangeMapping = RGBChannelRangeMapping.defaultMapping(
            channelCount: channelCount,
            wavelengths: wavelengths
        )
        colorSynthesisConfig.pcaConfig.mapping = PCAComponentMapping(red: 0, green: 1, blue: 2).clamped(maxComponents: max(channelCount, 1))
    }
    
    private func clampColorSynthesisMapping() {
        colorSynthesisConfig.mapping = colorSynthesisConfig.mapping.clamped(maxChannelCount: channelCount)
        colorSynthesisConfig.rangeMapping = colorSynthesisConfig.rangeMapping.clamped(maxChannelCount: channelCount)
        colorSynthesisConfig.pcaConfig.mapping = colorSynthesisConfig.pcaConfig.mapping.clamped(maxComponents: max(channelCount, 1))
        if let basis = colorSynthesisConfig.pcaConfig.basis,
           let first = basis.first,
           first.count != channelCount {
            colorSynthesisConfig.pcaConfig.basis = nil
            colorSynthesisConfig.pcaConfig.clipUpper = nil
            colorSynthesisConfig.pcaConfig.explainedVariance = nil
            colorSynthesisConfig.pcaConfig.sourceCubeID = nil
        }
        if let roiID = colorSynthesisConfig.pcaConfig.selectedROI,
           !displayedROISamples.contains(where: { $0.id == roiID }) {
            colorSynthesisConfig.pcaConfig.selectedROI = displayedROISamples.first?.id
        }
    }
    
    func ndChannelIndices() -> (positive: Int, negative: Int)? {
        guard channelCount > 1 else { return nil }
        let count = channelCount
        
        let targets: (positive: Double, negative: Double)
        let fallback: (positive: Int, negative: Int)
        
        switch ndPreset {
        case .ndvi:
            targets = (
                positive: Double(ndviNIRTarget.replacingOccurrences(of: ",", with: ".")) ?? 840,
                negative: Double(ndviRedTarget.replacingOccurrences(of: ",", with: ".")) ?? 660
            )
            let fallbackNeg = min(max(0, count / 3), count - 1)
            let fallbackPos = max(fallbackNeg + 1, count - 1)
            fallback = (positive: fallbackPos, negative: fallbackNeg)
        case .ndsi:
            targets = (
                positive: Double(ndsiGreenTarget.replacingOccurrences(of: ",", with: ".")) ?? 555,
                negative: Double(ndsiSWIRTarget.replacingOccurrences(of: ",", with: ".")) ?? 1610
            )
            let fallbackPos = min(max(0, count / 3), count - 1)
            let fallbackNeg = max(fallbackPos + 1, count - 1)
            fallback = (positive: fallbackPos, negative: fallbackNeg)
        case .wdvi:
            targets = (
                positive: Double(ndviNIRTarget.replacingOccurrences(of: ",", with: ".")) ?? 840,
                negative: Double(ndviRedTarget.replacingOccurrences(of: ",", with: ".")) ?? 660
            )
            let fallbackNeg = min(max(0, count / 3), count - 1)
            let fallbackPos = max(fallbackNeg + 1, count - 1)
            fallback = (positive: fallbackPos, negative: fallbackNeg)
        }
        
        if let wl = wavelengths, wl.count >= count {
            let posIndex = closestIndex(in: wl, to: targets.positive, limit: count) ?? fallback.positive
            let negIndex = closestIndex(in: wl, to: targets.negative, limit: count) ?? fallback.negative
            ndFallbackIndices[ndPreset] = (positive: posIndex, negative: negIndex)
            return (posIndex, negIndex)
        } else {
            var stored = ndFallbackIndices[ndPreset] ?? (0, 0)
            if stored == (0, 0) {
                stored = fallback
                ndFallbackIndices[ndPreset] = stored
            }
            return stored
        }
    }
    
    func runWDVIAutoEstimation(config: WDVIAutoEstimationConfig) {
        guard ndPreset == .wdvi else { return }
        guard let cube = cube else {
            loadError = "Нет данных для оценки WDVI"
            return
        }
        guard let axes = cube.axes(for: activeLayout) else {
            loadError = "Не удалось определить layout"
            return
        }
        guard let indices = ndChannelIndices() else {
            loadError = "Не удалось определить каналы Red/NIR"
            return
        }
        
        let selectedROIs = roiSamples.filter { config.selectedROIIDs.contains($0.id) }
        guard !selectedROIs.isEmpty else {
            loadError = "Выберите хотя бы один ROI для оценки"
            return
        }
        
        beginBusy(message: "Оценка линии почвы…")
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.computeWDVISoilLine(
                cube: cube,
                axes: axes,
                indices: indices,
                rois: selectedROIs,
                config: config
            )
            DispatchQueue.main.async {
                self.endBusy()
                switch result {
                case .success(let (slope, intercept, pairsCount)):
                    self.wdviSlope = String(format: "%.4f", slope)
                    self.wdviIntercept = String(format: "%.4f", intercept)
                    let aText = String(format: "%.4f", slope)
                    let bText = String(format: "%.4f", intercept)
                    self.loadError = "Оценка WDVI: a=\(aText), b=\(bText) по \(pairsCount) пикселям"
                case .failure(let error):
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
    
    private func closestIndex(in wavelengths: [Double], to target: Double, limit: Int) -> Int? {
        guard !wavelengths.isEmpty else { return nil }
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0..<min(limit, wavelengths.count) {
            let d = abs(wavelengths[i] - target)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return bestIdx
    }
    
    private func computeWDVISoilLine(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        indices: (positive: Int, negative: Int),
        rois: [SpectrumROISample],
        config: WDVIAutoEstimationConfig
    ) -> Result<(Double, Double, Int), WDVIEstimationError> {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        guard width > 0, height > 0 else { return .failure(.message("Размеры изображения некорректны")) }
        
        var pairs: [(Double, Double)] = []
        for roi in rois {
            guard let rect = roi.rect.clamped(maxWidth: width, maxHeight: height) else { continue }
            guard rect.area > 0 else { continue }
            for y in rect.minY..<(rect.minY + rect.height) {
                for x in rect.minX..<(rect.minX + rect.width) {
                    var idx = [0, 0, 0]
                    idx[axes.height] = y
                    idx[axes.width] = x
                    
                    idx[axes.channel] = indices.negative
                    let red = cube.getValue(i0: idx[0], i1: idx[1], i2: idx[2])
                    
                    idx[axes.channel] = indices.positive
                    let nir = cube.getValue(i0: idx[0], i1: idx[1], i2: idx[2])
                    
                    if red.isFinite && nir.isFinite {
                        pairs.append((red, nir))
                    }
                }
            }
        }
        
        guard !pairs.isEmpty else { return .failure(.message("Нет данных в выбранных ROI")) }
        
        // percentile filtering
        let reds = pairs.map { $0.0 }.sorted()
        let nirs = pairs.map { $0.1 }.sorted()
        let lowerP = max(0.0, min(config.lowerPercentile, 0.5))
        let upperP = min(1.0, max(config.upperPercentile, lowerP))
        let redLower = quantile(sorted: reds, q: lowerP)
        let redUpper = quantile(sorted: reds, q: upperP)
        let nirLower = quantile(sorted: nirs, q: lowerP)
        let nirUpper = quantile(sorted: nirs, q: upperP)
        
        var filtered = pairs.filter { pair in
            pair.0 >= redLower && pair.0 <= redUpper && pair.1 >= nirLower && pair.1 <= nirUpper
        }
        
        // z-score trimming
        if config.zScoreThreshold > 0 {
            let meanRed = filtered.map { $0.0 }.reduce(0, +) / Double(filtered.count)
            let meanNir = filtered.map { $0.1 }.reduce(0, +) / Double(filtered.count)
            let stdRed = sqrt(filtered.map { pow($0.0 - meanRed, 2) }.reduce(0, +) / Double(max(filtered.count - 1, 1)))
            let stdNir = sqrt(filtered.map { pow($0.1 - meanNir, 2) }.reduce(0, +) / Double(max(filtered.count - 1, 1)))
            
            if stdRed > 0, stdNir > 0 {
                filtered = filtered.filter { pair in
                    let zr = abs(pair.0 - meanRed) / stdRed
                    let zn = abs(pair.1 - meanNir) / stdNir
                    return zr <= config.zScoreThreshold && zn <= config.zScoreThreshold
                }
            }
        }
        
        guard filtered.count >= 2 else { return .failure(.message("Недостаточно данных после фильтрации")) }
        
        let regression: (Double, Double)
        switch config.method {
        case .ols:
            regression = linearRegression(pairs: filtered)
        case .huber:
            regression = huberRegression(pairs: filtered)
        }
        
        return .success((regression.0, regression.1, filtered.count))
    }
    
    private func quantile(sorted values: [Double], q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clampedQ = max(0.0, min(1.0, q))
        let pos = clampedQ * Double(values.count - 1)
        let idx = Int(pos)
        if idx >= values.count - 1 { return values.last! }
        let frac = pos - Double(idx)
        return values[idx] * (1 - frac) + values[idx + 1] * frac
    }
    
    private func linearRegression(pairs: [(Double, Double)]) -> (Double, Double) {
        let n = Double(pairs.count)
        let sumX = pairs.map { $0.0 }.reduce(0, +)
        let sumY = pairs.map { $0.1 }.reduce(0, +)
        let sumXY = pairs.map { $0.0 * $0.1 }.reduce(0, +)
        let sumXX = pairs.map { $0.0 * $0.0 }.reduce(0, +)
        let denom = n * sumXX - sumX * sumX
        if abs(denom) < 1e-12 {
            let meanY = sumY / n
            return (0.0, meanY)
        }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }
    
    private func huberRegression(pairs: [(Double, Double)], iterations: Int = 6, delta: Double = 1.5) -> (Double, Double) {
        var weights = Array(repeating: 1.0, count: pairs.count)
        var slope = 0.0
        var intercept = 0.0
        
        for _ in 0..<iterations {
            let result = weightedLinearRegression(pairs: pairs, weights: weights)
            slope = result.0
            intercept = result.1
            
            let residuals = pairs.enumerated().map { idx, pair in
                let pred = slope * pair.0 + intercept
                return pair.1 - pred
            }
            let scale = max(1e-6, medianAbsoluteDeviation(residuals))
            for i in 0..<weights.count {
                let r = residuals[i] / (delta * scale)
                let w = abs(r) <= 1 ? 1.0 : (delta / abs(residuals[i] / scale))
                weights[i] = w.isFinite ? max(1e-6, w) : 1e-6
            }
        }
        
        return (slope, intercept)
    }
    
    private func weightedLinearRegression(pairs: [(Double, Double)], weights: [Double]) -> (Double, Double) {
        var sumW = 0.0
        var sumWX = 0.0
        var sumWY = 0.0
        var sumWXX = 0.0
        var sumWXY = 0.0
        
        for (pair, w) in zip(pairs, weights) {
            sumW += w
            sumWX += w * pair.0
            sumWY += w * pair.1
            sumWXX += w * pair.0 * pair.0
            sumWXY += w * pair.0 * pair.1
        }
        let denom = sumW * sumWXX - sumWX * sumWX
        if abs(denom) < 1e-12 {
            let meanY = sumWY / max(sumW, 1e-6)
            return (0.0, meanY)
        }
        let slope = (sumW * sumWXY - sumWX * sumWY) / denom
        let intercept = (sumWY - slope * sumWX) / sumW
        return (slope, intercept)
    }
    
    private func medianAbsoluteDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 1e-6 }
        let median = quantile(sorted: values.sorted(), q: 0.5)
        let deviations = values.map { abs($0 - median) }.sorted()
        return quantile(sorted: deviations, q: 0.5) / 0.6745
    }
    
    private func clampedPCAConfig(_ config: PCAVisualizationConfig) -> PCAVisualizationConfig {
        var cfg = config
        cfg.mapping = cfg.mapping.clamped(maxComponents: max(channelCount, 1))
        if let basis = cfg.basis, let first = basis.first, first.count != channelCount {
            cfg.basis = nil
            cfg.clipUpper = nil
            cfg.explainedVariance = nil
            cfg.sourceCubeID = nil
        }
        return cfg
    }
    
    func setWavelengths(_ lambda: [Double]) {
        guard !lambda.isEmpty else {
            wavelengths = nil
            baseWavelengths = nil
            return
        }
        wavelengths = lambda
        baseWavelengths = lambda
    }
    
    func loadWavelengthsFromTXT(url: URL) {
        let result = WavelengthManager.loadFromFile(url: url)
        
        switch result {
        case .success(let values):
            wavelengths = values
            baseWavelengths = values
            loadError = nil
        case .failure(let error):
            loadError = "Ошибка чтения длин волн: \(error.localizedDescription)"
        }
    }
    
    func generateWavelengthsFromParams() {
        guard cube != nil else {
            loadError = "Сначала открой гиперкуб"
            return
        }
        pcaRenderedImage = nil
        pcaPendingConfig = nil
        
        let channels = channelCount
        guard channels > 0 else {
            loadError = "Не удалось определить число каналов"
            return
        }
        
        guard let start = Double(lambdaStart.replacingOccurrences(of: ",", with: ".")),
              let end = Double(lambdaEnd.replacingOccurrences(of: ",", with: ".")) else {
            loadError = "Некорректные параметры λ (от/до)"
            return
        }
        
        guard end > start else {
            loadError = "Значение 'до' должно быть больше 'от'"
            return
        }
        
        let step = WavelengthManager.calculateStep(start: start, end: end, channels: channels)
        lambdaStep = String(format: "%.4g", step)
        
        wavelengths = WavelengthManager.generateFromRange(start: start, end: end, channels: channels)
        baseWavelengths = wavelengths
        loadError = nil
    }
    
    func resetZoom() {
        zoomScale = 1.0
        imageOffset = .zero
    }
    
    func moveImage(by delta: CGSize) {
        imageOffset.width += delta.width
        imageOffset.height += delta.height
    }
    
    func toggleAnalysisTool(_ tool: AnalysisTool) {
        if activeAnalysisTool == tool {
            activeAnalysisTool = .none
        } else {
            activeAnalysisTool = tool
            if tool == .spectrumGraph || tool == .spectrumGraphROI {
                isGraphPanelExpanded = true
            }
        }
    }
    
    func extractSpectrum(at pixelX: Int, pixelY: Int) {
        guard let cube = cube else { return }
        guard activeAnalysisTool == .spectrumGraph else { return }
        
        let layout = activeLayout
        let (d0, d1, d2) = cube.dims
        let dimsArray = [d0, d1, d2]
        
        guard let axes = cube.axes(for: layout) else { return }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else { return }
        
        var spectrum = [Double]()
        spectrum.reserveCapacity(channels)
        
        for ch in 0..<channels {
            var indices = [0, 0, 0]
            indices[axes.channel] = ch
            indices[axes.height] = pixelY
            indices[axes.width] = pixelX
            
            let value = cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
            spectrum.append(value)
        }
        
        let colorIndex = pendingSpectrumSample?.colorIndex ?? spectrumColorCounter
        
        let sample = SpectrumSample(
            pixelX: pixelX,
            pixelY: pixelY,
            values: spectrum,
            wavelengths: wavelengths,
            colorIndex: colorIndex
        )
        pendingSpectrumSample = sample
        
        if !isGraphPanelExpanded {
            isGraphPanelExpanded = true
        }
    }
    
    func extractROISpectrum(for rect: SpectrumROIRect) {
        guard cube != nil else { return }
        guard activeAnalysisTool == .spectrumGraphROI else { return }
        guard rect.width > 0, rect.height > 0 else { return }
        guard let sample = makeROISample(
            rect: rect,
            colorIndex: pendingROISample?.colorIndex ?? roiColorCounter,
            id: pendingROISample?.id ?? UUID()
        ) else { return }
        pendingROISample = sample
        if !isGraphPanelExpanded {
            isGraphPanelExpanded = true
        }
    }
    
    func savePendingSpectrumSample() {
        guard let pending = pendingSpectrumSample else { return }
        spectrumSamples.append(pending)
        pendingSpectrumSample = nil
        spectrumColorCounter = max(spectrumColorCounter, pending.colorIndex + 1)
    }
    
    func removeSpectrumSample(with id: UUID) {
        spectrumSamples.removeAll { $0.id == id }
    }
    
    func renameSpectrumSample(id: UUID, to name: String?) {
        guard let idx = spectrumSamples.firstIndex(where: { $0.id == id }) else { return }
        var sample = spectrumSamples[idx]
        sample.displayName = name?.isEmpty == true ? nil : name
        spectrumSamples[idx] = sample
    }
    
    func savePendingROISample() {
        guard let pending = pendingROISample else { return }
        roiSamples.append(pending)
        pendingROISample = nil
        roiColorCounter = max(roiColorCounter, pending.colorIndex + 1)
    }
    
    func removeROISample(with id: UUID) {
        roiSamples.removeAll { $0.id == id }
    }
    
    func renameROISample(id: UUID, to name: String?) {
        guard let idx = roiSamples.firstIndex(where: { $0.id == id }) else { return }
        var sample = roiSamples[idx]
        sample.displayName = name?.isEmpty == true ? nil : name
        roiSamples[idx] = sample
    }

    func updateROISampleRect(id: UUID, rect: SpectrumROIRect) -> Bool {
        if let idx = roiSamples.firstIndex(where: { $0.id == id }) {
            let existing = roiSamples[idx]
            guard let updated = makeROISample(
                rect: rect,
                colorIndex: existing.colorIndex,
                id: existing.id,
                displayName: existing.displayName
            ) else { return false }
            roiSamples[idx] = updated
            return true
        }

        if let pending = pendingROISample, pending.id == id {
            guard let updated = makeROISample(
                rect: rect,
                colorIndex: pending.colorIndex,
                id: pending.id,
                displayName: pending.displayName
            ) else { return false }
            pendingROISample = updated
            return true
        }

        return false
    }
    
    func toggleGraphPanel() {
        isGraphPanelExpanded.toggle()
    }
    
    func initializeMaskEditor() {
        guard let cube = cube else { return }
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        
        let rgbImage: NSImage?
        switch colorSynthesisConfig.mode {
        case .trueColorRGB:
            rgbImage = ImageRenderer.renderRGB(
                cube: cube,
                layout: activeLayout,
                wavelengths: wavelengths,
                mapping: colorSynthesisConfig.mapping
            )
        case .rangeWideRGB:
            rgbImage = ImageRenderer.renderRGBRange(
                cube: cube,
                layout: activeLayout,
                wavelengths: wavelengths,
                rangeMapping: colorSynthesisConfig.rangeMapping
            )
        case .pcaVisualization:
            rgbImage = pcaRenderedImage
        }
        
        maskEditorState.initialize(width: width, height: height, rgbImage: rgbImage)
    }
    
    func syncMaskEditorWithPipeline() {
        guard viewMode == .mask, let cube = cube else { return }
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let rotationTurns = pipelineRotationTurns()
        
        maskEditorState.syncWithImageSize(width: width, height: height, rotationTurns: rotationTurns)
    }
    
    func updateMaskReferenceImage() {
        guard viewMode == .mask, let cube = cube else { return }
        let rgbImage: NSImage?
        switch colorSynthesisConfig.mode {
        case .trueColorRGB:
            rgbImage = ImageRenderer.renderRGB(
                cube: cube,
                layout: activeLayout,
                wavelengths: wavelengths,
                mapping: colorSynthesisConfig.mapping
            )
        case .rangeWideRGB:
            rgbImage = ImageRenderer.renderRGBRange(
                cube: cube,
                layout: activeLayout,
                wavelengths: wavelengths,
                rangeMapping: colorSynthesisConfig.rangeMapping
            )
        case .pcaVisualization:
            rgbImage = pcaRenderedImage
        }
        
        if let refLayer = maskEditorState.referenceLayers.first,
           let index = maskEditorState.layers.firstIndex(where: { $0.id == refLayer.id }),
           var ref = maskEditorState.layers[index] as? ReferenceLayer {
            ref.rgbImage = rgbImage
            maskEditorState.layers[index] = ref
        }
    }
    
    func applyNormalization() {
        guard let original = originalCube else { return }
        
        if normalizationType == .none {
            cube = original
        } else {
            cube = CubeNormalizer.apply(normalizationType, to: original, parameters: normalizationParams)
        }
    }
    
    func convertDataType(to targetType: DataType) {
        guard let current = cube else { return }
        guard current.originalDataType != targetType else { return }
        
        if let converted = DataTypeConverter.convert(current, to: targetType, autoScale: autoScaleOnTypeConversion) {
            cube = converted
            if originalCube?.originalDataType == current.originalDataType {
                originalCube = converted
            }
        }
    }

    private func pasteSpectrumPoint(_ clipboard: SpectrumSampleClipboard, to entry: CubeLibraryEntry) {
        let canonical = canonicalURL(entry.url)
        var snapshot = sessionSnapshots[canonical] ?? CubeSessionSnapshot.empty
        let isCurrent = cubeURL?.standardizedFileURL == canonical
        let newID = UUID()
        let colorIndex = isCurrent ? spectrumColorCounter : nextSpectrumColorIndex(in: snapshot.spectrumSamples)
        let ops = spatialOperations(from: snapshot.pipelineOperations)
        
        if isCurrent {
            let fallbackSize = cube.flatMap { cubeSpatialSize(for: $0) }
            guard let baseSize = spatialBaseSize() ?? fallbackSize,
                  let basePoint = denormalizePoint(clipboard, size: baseSize) else { return }
            let baseSpatial = SpatialSize(width: baseSize.width, height: baseSize.height)
            let mapped = applySpatialOpsToPoint(
                basePoint,
                base: baseSpatial,
                ops: ops,
                direction: .forward
            ) ?? basePoint
            if let sample = makeSpectrumSample(
                pixelX: mapped.x,
                pixelY: mapped.y,
                colorIndex: colorIndex,
                id: newID,
                displayName: clipboard.displayName
            ) {
                spectrumSamples.append(sample)
                spectrumColorCounter = max(spectrumColorCounter, sample.colorIndex + 1)
                persistCurrentSession()
            }
            return
        }
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let loadResult = ImageLoaderFactory.load(from: canonical)
            guard case .success(let rawCube) = loadResult,
                  let baseSize = self.cubeSpatialSize(for: rawCube, layout: snapshot.layout),
                  let basePoint = self.denormalizePoint(clipboard, size: baseSize) else {
                return
            }
            let baseSpatial = SpatialSize(width: baseSize.width, height: baseSize.height)
            let mapped = self.applySpatialOpsToPoint(
                basePoint,
                base: baseSpatial,
                ops: ops,
                direction: .forward
            ) ?? basePoint
            let descriptor = SpectrumSampleDescriptor(
                id: newID,
                pixelX: mapped.x,
                pixelY: mapped.y,
                colorIndex: colorIndex,
                displayName: clipboard.displayName,
                values: [],
                wavelengths: nil
            )
            DispatchQueue.main.async {
                snapshot.spectrumSamples.append(descriptor)
                self.sessionSnapshots[canonical] = snapshot
            }
        }
    }
    
    private func pasteSpectrumROI(_ clipboard: SpectrumROISampleClipboard, to entry: CubeLibraryEntry) {
        let canonical = canonicalURL(entry.url)
        var snapshot = sessionSnapshots[canonical] ?? CubeSessionSnapshot.empty
        let isCurrent = cubeURL?.standardizedFileURL == canonical
        let newID = UUID()
        let colorIndex = isCurrent ? roiColorCounter : nextSpectrumColorIndex(in: snapshot.roiSamples)
        let ops = spatialOperations(from: snapshot.pipelineOperations)
        
        if isCurrent {
            let fallbackSize = cube.flatMap { cubeSpatialSize(for: $0) }
            guard let baseSize = spatialBaseSize() ?? fallbackSize,
                  let baseRect = denormalizeRect(clipboard, size: baseSize) else { return }
            let baseSpatial = SpatialSize(width: baseSize.width, height: baseSize.height)
            let mapped = applySpatialOpsToRect(
                baseRect,
                base: baseSpatial,
                ops: ops,
                direction: .forward
            ) ?? baseRect
            if let sample = makeROISample(
                rect: mapped,
                colorIndex: colorIndex,
                id: newID,
                displayName: clipboard.displayName
            ) {
                roiSamples.append(sample)
                roiColorCounter = max(roiColorCounter, sample.colorIndex + 1)
                persistCurrentSession()
            }
            return
        }
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let loadResult = ImageLoaderFactory.load(from: canonical)
            guard case .success(let rawCube) = loadResult,
                  let baseSize = self.cubeSpatialSize(for: rawCube, layout: snapshot.layout),
                  let baseRect = self.denormalizeRect(clipboard, size: baseSize) else {
                return
            }
            let baseSpatial = SpatialSize(width: baseSize.width, height: baseSize.height)
            let mapped = self.applySpatialOpsToRect(
                baseRect,
                base: baseSpatial,
                ops: ops,
                direction: .forward
            ) ?? baseRect
            let descriptor = SpectrumROISampleDescriptor(
                id: newID,
                minX: mapped.minX,
                minY: mapped.minY,
                width: mapped.width,
                height: mapped.height,
                colorIndex: colorIndex,
                displayName: clipboard.displayName,
                values: [],
                wavelengths: nil
            )
            DispatchQueue.main.async {
                snapshot.roiSamples.append(descriptor)
                self.sessionSnapshots[canonical] = snapshot
            }
        }
    }
    
    private func handleCubeChange(previousCube: HyperCube?) {
        adjustSpectrumGeometry(previousCube: previousCube, newCube: cube)
        refreshSpectrumSamples()
        refreshROISamples()
    }
    
    func addOperation(type: PipelineOperationType) {
        var operation = PipelineOperation(type: type)
        operation.layout = activeLayout
        operation.configureDefaults(with: cube, layout: activeLayout)
        pipelineOperations.append(operation)
        if pipelineAutoApply {
            let isNoOp = operation.isNoOp(for: cube, layout: activeLayout)
            if !isNoOp {
            applyPipeline()
            }
        }
    }
    
    func removeOperation(at index: Int) {
        guard index >= 0 && index < pipelineOperations.count else { return }
        let removedType = pipelineOperations[index].type
        pipelineOperations.remove(at: index)
        if removedType == .spectralTrim {
            updateSpectralTrimRangeFromPipeline()
        }
        if pipelineAutoApply {
            applyPipeline()
        }
    }

    func copyPipelineOperation(_ operation: PipelineOperation) {
        pipelineOperationClipboard = operation
    }

    func pastePipelineOperation() {
        guard let clipboardOperation = pipelineOperationClipboard else { return }
        let newOperation = clipboardOperation.clonedWithNewID()
        pipelineOperations.append(newOperation)
        if pipelineAutoApply {
            let isNoOp = newOperation.isNoOp(for: cube, layout: activeLayout)
            if !isNoOp {
                applyPipeline()
            }
        }
    }

    var canPasteSpectrumPoint: Bool {
        if case .point = spectrumClipboard { return true }
        return false
    }
    
    var canPasteSpectrumROI: Bool {
        if case .roi = spectrumClipboard { return true }
        return false
    }

    func copySpectrumSample(_ sample: SpectrumSample) {
        let fallbackSize = cube.flatMap { cubeSpatialSize(for: $0) }
        let baseSize = spectrumSpatialBaseSize ?? spatialBaseSize() ?? fallbackSize
        let ops = spatialOperations(from: pipelineOperations)
        let originalPoint: SpatialPoint
        if let baseSize,
           let mapped = applySpatialOpsToPoint(
            SpatialPoint(x: sample.pixelX, y: sample.pixelY),
            base: SpatialSize(width: baseSize.width, height: baseSize.height),
            ops: ops,
            direction: .inverse
           ) {
            originalPoint = mapped
        } else {
            originalPoint = SpatialPoint(x: sample.pixelX, y: sample.pixelY)
        }
        
        let normalizedX = normalizeCoordinate(originalPoint.x, size: baseSize?.width)
        let normalizedY = normalizeCoordinate(originalPoint.y, size: baseSize?.height)
        
        spectrumClipboard = .point(
            SpectrumSampleClipboard(
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                displayName: sample.displayName
            )
        )
    }
    
    func copyROISample(_ sample: SpectrumROISample) {
        let fallbackSize = cube.flatMap { cubeSpatialSize(for: $0) }
        let baseSize = spectrumSpatialBaseSize ?? spatialBaseSize() ?? fallbackSize
        let ops = spatialOperations(from: pipelineOperations)
        let originalRect: SpectrumROIRect
        if let baseSize,
           let mapped = applySpatialOpsToRect(
            sample.rect,
            base: SpatialSize(width: baseSize.width, height: baseSize.height),
            ops: ops,
            direction: .inverse
           ) {
            originalRect = mapped
        } else {
            originalRect = sample.rect
        }
        
        let normalized = normalizeRect(originalRect, size: baseSize)
        spectrumClipboard = .roi(
            SpectrumROISampleClipboard(
                normalizedMinX: normalized.minX,
                normalizedMinY: normalized.minY,
                normalizedMaxX: normalized.maxX,
                normalizedMaxY: normalized.maxY,
                displayName: sample.displayName
            )
        )
    }
    
    func pasteSpectrumPoint(to entry: CubeLibraryEntry) {
        guard case .point(let clipboard) = spectrumClipboard else { return }
        pasteSpectrumPoint(clipboard, to: entry)
    }
    
    func pasteSpectrumROI(to entry: CubeLibraryEntry) {
        guard case .roi(let clipboard) = spectrumClipboard else { return }
        pasteSpectrumROI(clipboard, to: entry)
    }
    
    func moveOperation(from source: Int, to destination: Int) {
        guard source >= 0 && source < pipelineOperations.count else { return }
        guard destination >= 0 && destination <= pipelineOperations.count else { return }
        
        let adjustedDestination: Int
        if source < destination {
            adjustedDestination = destination - 1
        } else {
            adjustedDestination = destination
        }
        
        guard source != adjustedDestination else { return }
        
        let operation = pipelineOperations.remove(at: source)
        pipelineOperations.insert(operation, at: min(adjustedDestination, pipelineOperations.count))
        
        if pipelineAutoApply {
            applyPipeline()
        }
    }
    
    func clearPipeline() {
        pipelineOperations.removeAll()
        showAlignmentVisualization = false
        applyPipeline()
    }
    
    func startAlignmentComputation(operationId: UUID) {
        guard let opIndex = pipelineOperations.firstIndex(where: { $0.id == operationId }),
              var params = pipelineOperations[opIndex].spectralAlignmentParams else { return }
        
        params.shouldCompute = true
        params.isComputed = false
        params.cachedHomographies = nil
        params.alignmentResult = nil
        pipelineOperations[opIndex].spectralAlignmentParams = params
        
        isAlignmentInProgress = true
        alignmentProgress = 0.0
        alignmentProgressMessage = "Подготовка…"
        alignmentStartTime = Date()
        alignmentElapsedTime = "0 сек"
        alignmentEstimatedTimeRemaining = ""
        alignmentStage = "init"
        alignmentCurrentChannel = 0
        alignmentTotalChannels = 0
        
        applyPipelineWithAlignmentProgress(targetOperationId: operationId)
    }
    
    private func applyPipelineWithAlignmentProgress(targetOperationId: UUID) {
        guard let original = originalCube else { return }
        
        beginBusy(message: "Вычисление выравнивания…")
        
        var progressTimer: Timer?
        DispatchQueue.main.async { [weak self] in
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                guard let self, let startTime = self.alignmentStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                self.alignmentElapsedTime = self.formatTimeInterval(elapsed)
                
                if self.alignmentProgress > 0.05 {
                    let estimatedTotal = elapsed / self.alignmentProgress
                    let remaining = estimatedTotal - elapsed
                    if remaining > 0 {
                        self.alignmentEstimatedTimeRemaining = "~" + self.formatTimeInterval(remaining)
                    }
                }
            }
        }
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            
            let baseCube = self.cubeWithWavelengthsIfNeeded(original, layout: self.activeLayout)
            var currentCube = baseCube
            var mutableOperations = self.pipelineOperations
            
            for i in 0..<mutableOperations.count {
                if mutableOperations[i].type == .spectralAlignment && mutableOperations[i].id == targetOperationId {
                    let layout = mutableOperations[i].layout
                    let opCube = self.cubeWithWavelengthsIfNeeded(currentCube, layout: layout)
                    
                    let result = mutableOperations[i].applyWithUpdateDetailed(to: opCube) { info in
                        DispatchQueue.main.async {
                            self.alignmentProgress = info.progress
                            self.alignmentProgressMessage = info.message
                            self.alignmentCurrentChannel = info.currentChannel
                            self.alignmentTotalChannels = info.totalChannels
                            self.alignmentStage = info.stage
                        }
                    }
                    currentCube = result ?? opCube
                } else {
                    let layout = mutableOperations[i].layout
                    let opCube = self.cubeWithWavelengthsIfNeeded(currentCube, layout: layout)
                    let result = mutableOperations[i].apply(to: opCube)
                    currentCube = result ?? opCube
                }
            }
            
            DispatchQueue.main.async {
                progressTimer?.invalidate()
                self.cube = currentCube
                self.pipelineOperations = mutableOperations
                self.lastPipelineResult = currentCube
                self.lastPipelineAppliedOperations = mutableOperations
                self.lastPipelineBaseCubeID = original.id
                self.updateWavelengthsFromPipelineResult()
                self.updateSpectralTrimRangeFromPipeline()
                self.updateChannelCount()
                self.isAlignmentInProgress = false
                self.alignmentProgress = 0.0
                self.alignmentProgressMessage = ""
                self.alignmentCurrentChannel = 0
                self.alignmentTotalChannels = 0
                self.alignmentStartTime = nil
                self.alignmentElapsedTime = ""
                self.alignmentEstimatedTimeRemaining = ""
                self.alignmentStage = ""
                self.endBusy()
            }
        }
    }
    
    func applyPipeline() {
        guard let original = originalCube else { return }
        
        if pipelineOperations.isEmpty {
            cube = original
            lastPipelineAppliedOperations = []
            lastPipelineResult = original
            lastPipelineBaseCubeID = original.id
            updateWavelengthsFromPipelineResult()
            updateSpectralTrimRangeFromPipeline()
            updateChannelCount()
            if let descriptors = pendingRestoreSpectrumDescriptors,
               let roiDescriptors = pendingRestoreROISampleDescriptors {
                restoreSpectrumSamples(from: descriptors)
                restoreROISamples(from: roiDescriptors)
                pendingRestoreSpectrumDescriptors = nil
                pendingRestoreROISampleDescriptors = nil
            }
            return
        }
        
        let operations = pipelineOperations
        
        if let baseID = lastPipelineBaseCubeID,
           baseID == original.id,
           operations.count == lastPipelineAppliedOperations.count + 1,
           operations.dropLast() == lastPipelineAppliedOperations,
           let cachedResult = lastPipelineResult {
            
            beginBusy(message: "Применение последней операции…")
            var newOp = operations.last!
            processingQueue.async { [weak self] in
                guard let self else { return }
                let baseCube = self.cubeWithWavelengthsIfNeeded(cachedResult, layout: newOp.layout)
                let result = newOp.applyWithUpdate(to: baseCube)
                DispatchQueue.main.async {
                    self.cube = result ?? baseCube
                    self.lastPipelineResult = self.cube
                    var updatedOperations = operations
                    updatedOperations[updatedOperations.count - 1] = newOp
                    self.lastPipelineAppliedOperations = updatedOperations
                    self.pipelineOperations = updatedOperations
                    self.lastPipelineBaseCubeID = original.id
                    self.updateWavelengthsFromPipelineResult()
                    self.updateSpectralTrimRangeFromPipeline()
                    self.updateChannelCount()
                    if let descriptors = self.pendingRestoreSpectrumDescriptors,
                       let roiDescriptors = self.pendingRestoreROISampleDescriptors {
                        self.restoreSpectrumSamples(from: descriptors)
                        self.restoreROISamples(from: roiDescriptors)
                        self.pendingRestoreSpectrumDescriptors = nil
                        self.pendingRestoreROISampleDescriptors = nil
                    }
                    self.endBusy()
                }
            }
            
        } else {
        beginBusy(message: "Применение пайплайна…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
                let baseCube = self.cubeWithWavelengthsIfNeeded(original, layout: activeLayout)
                var mutableOperations = operations
                let result = self.processPipeline(original: baseCube, operations: &mutableOperations)
            DispatchQueue.main.async {
                    self.cube = result ?? baseCube
                    self.lastPipelineResult = self.cube
                    self.lastPipelineAppliedOperations = mutableOperations
                    self.lastPipelineBaseCubeID = original.id
                    self.pipelineOperations = mutableOperations
                    self.updateWavelengthsFromPipelineResult()
                    self.updateSpectralTrimRangeFromPipeline()
                    self.updateChannelCount()
                    if let descriptors = self.pendingRestoreSpectrumDescriptors,
                       let roiDescriptors = self.pendingRestoreROISampleDescriptors {
                        self.restoreSpectrumSamples(from: descriptors)
                        self.restoreROISamples(from: roiDescriptors)
                        self.pendingRestoreSpectrumDescriptors = nil
                        self.pendingRestoreROISampleDescriptors = nil
                    }
                self.endBusy()
                }
            }
        }
    }

    private func cubeWithWavelengthsIfNeeded(
        _ cube: HyperCube,
        layout: CubeLayout,
        baseWavelengths override: [Double]? = nil
    ) -> HyperCube {
        let existing = cube.wavelengths
        guard existing == nil || existing?.isEmpty == true else { return cube }
        let stored = override ?? baseWavelengths
        guard let stored, !stored.isEmpty else { return cube }
        guard stored.count == cube.channelCount(for: layout) else { return cube }
        return HyperCube(
            dims: cube.dims,
            storage: cube.storage,
            sourceFormat: cube.sourceFormat,
            isFortranOrder: cube.isFortranOrder,
            wavelengths: stored
        )
    }

    private func updateWavelengthsFromPipelineResult() {
        guard let result = cube?.wavelengths, !result.isEmpty else { return }
        wavelengths = result
        updateLambdaRange(from: result)
    }

    private func updateSpectralTrimRangeFromPipeline() {
        if let op = pipelineOperations.first(where: { $0.type == .spectralTrim }),
           let params = op.spectralTrimParams {
            spectralTrimRange = params.startChannel...params.endChannel
        } else {
            spectralTrimRange = nil
        }
    }

    private func updateLambdaRange(from wavelengths: [Double]) {
        guard let first = wavelengths.first, let last = wavelengths.last else { return }
        lambdaStart = String(format: "%.1f", first)
        lambdaEnd = String(format: "%.1f", last)
        if wavelengths.count > 1 {
            let step = (last - first) / Double(wavelengths.count - 1)
            lambdaStep = String(format: "%.2f", step)
        } else {
            lambdaStep = ""
        }
    }

    private func refreshWavelengthsForLayoutChange() {
        guard let cube else { return }
        let count = cube.channelCount(for: activeLayout)
        if let wl = wavelengths, wl.count == count {
            updateLambdaRange(from: wl)
            return
        }
        if let base = baseWavelengths, base.count == count {
            wavelengths = base
            updateLambdaRange(from: base)
            return
        }
        if let wl = cube.wavelengths, wl.count == count {
            wavelengths = wl
            updateLambdaRange(from: wl)
            return
        }
        lambdaStep = ""
    }
    
    func enterTrimMode() {
        isTrimMode = true
        trimStart = 0
        trimEnd = Double(max(channelCount - 1, 0))
    }
    
    func exitTrimMode() {
        isTrimMode = false
    }
    
    func applyTrim() {
        let startChannel = Int(trimStart)
        let endChannel = Int(trimEnd)
        let currentChannels = channelCount
        
        guard startChannel >= 0, endChannel < currentChannels, startChannel <= endChannel else {
            loadError = "Некорректный диапазон обрезки"
            return
        }
        let maxChannelIndex = max(currentChannels - 1, 0)
        guard startChannel != 0 || endChannel != maxChannelIndex else {
            isTrimMode = false
            loadError = nil
            return
        }
        
        let baseRange: ClosedRange<Int> = {
            if let range = spectralTrimRange {
                return range
            }
            if let op = pipelineOperations.first(where: { $0.type == .spectralTrim }),
               let params = op.spectralTrimParams {
                return params.startChannel...params.endChannel
            }
            return 0...maxChannelIndex
        }()
        let absoluteRange = (baseRange.lowerBound + startChannel)...(baseRange.lowerBound + endChannel)
        
        var trimOp = PipelineOperation(type: .spectralTrim)
        trimOp.layout = activeLayout
        trimOp.spectralTrimParams = SpectralTrimParameters(
            startChannel: absoluteRange.lowerBound,
            endChannel: absoluteRange.upperBound
        )
        
        if let index = pipelineOperations.firstIndex(where: { $0.type == .spectralTrim }) {
            pipelineOperations[index] = trimOp
        } else {
            pipelineOperations.append(trimOp)
        }
        
        spectralTrimRange = absoluteRange
        isTrimMode = false
        loadError = nil
        
        applyPipeline()
    }
    
    private func trimChannels(cube: HyperCube, layout: CubeLayout, from startChannel: Int, to endChannel: Int) -> HyperCube? {
        let (d0, d1, d2) = cube.dims
        let dimsArray = [d0, d1, d2]
        
        guard let axesInfo = cube.axes(for: layout) else { return nil }
        let channelAxis = axesInfo.channel
        let heightAxis = axesInfo.height
        let widthAxis = axesInfo.width
        
        let heightSize = dimsArray[heightAxis]
        let widthSize = dimsArray[widthAxis]
        
        let newChannelCount = endChannel - startChannel + 1
        
        let newDims = (newChannelCount, heightSize, widthSize)
        let totalNewElements = newDims.0 * newDims.1 * newDims.2
        
        func buildIndices(ch: Int, h: Int, w: Int) -> (Int, Int, Int) {
            var i0 = 0, i1 = 0, i2 = 0
            
            if channelAxis == 0 { i0 = ch }
            else if channelAxis == 1 { i1 = ch }
            else { i2 = ch }
            
            if heightAxis == 0 { i0 = h }
            else if heightAxis == 1 { i1 = h }
            else { i2 = h }
            
            if widthAxis == 0 { i0 = w }
            else if widthAxis == 1 { i1 = w }
            else { i2 = w }
            
            return (i0, i1, i2)
        }
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .float32(let arr):
            var newData = [Float]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .uint16(let arr):
            var newData = [UInt16]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .uint8(let arr):
            var newData = [UInt8]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .int16(let arr):
            var newData = [Int16]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .int32(let arr):
            var newData = [Int32]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
            
        case .int8(let arr):
            var newData = [Int8]()
            newData.reserveCapacity(totalNewElements)
            
            for ch in startChannel...endChannel {
                for h in 0..<heightSize {
                    for w in 0..<widthSize {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        newData.append(arr[idx])
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: nil)
        }
    }
    
    private func processPipeline(original: HyperCube, operations: inout [PipelineOperation]) -> HyperCube? {
        guard !operations.isEmpty else { return original }
        
        var result: HyperCube? = original
        
        for i in 0..<operations.count {
            guard let current = result else { break }
            result = operations[i].applyWithUpdate(to: current)
        }
        
        return result ?? original
    }
    
    private func beginBusy(message: String) {
        DispatchQueue.main.async {
            self.busyMessage = message
            if !self.isBusy {
                self.isBusy = true
            }
        }
    }
    
    private func endBusy() {
        DispatchQueue.main.async {
            self.busyMessage = nil
            self.isBusy = false
        }
    }
    
    private func handleLoadResult(result: Result<HyperCube, ImageLoadError>, url: URL) {
        switch result {
        case .success(let hyperCube):
            originalCube = hyperCube
            cube = hyperCube
            normalizationType = .none
            normalizationParams = .default
            updateResolvedLayout()
            
            let ext = url.pathExtension.lowercased()
            if ext == "mat" {
                layout = .auto
            } else if ext == "tif" || ext == "tiff" {
                layout = .hwc
            } else if ext == "dat" || ext == "hdr" || ext == "raw" || ext == "img" || ext == "bsq" || ext == "bil" || ext == "bip" {
                layout = .hwc
            } else {
                layout = .auto
            }
            updateResolvedLayout()
            
            updateChannelCount()
            spectralTrimRange = nil
            
            if let enviWavelengths = hyperCube.wavelengths, !enviWavelengths.isEmpty {
                wavelengths = enviWavelengths
                baseWavelengths = enviWavelengths
                if let first = enviWavelengths.first, let last = enviWavelengths.last {
                    lambdaStart = String(format: "%.1f", first)
                    lambdaEnd = String(format: "%.1f", last)
                    if enviWavelengths.count > 1 {
                        let step = (last - first) / Double(enviWavelengths.count - 1)
                        lambdaStep = String(format: "%.2f", step)
                    }
                }
            } else if wavelengths == nil {
                generateWavelengthsFromParams()
            }
            
            ensureLibraryContains(url: url)
            let snapshot = pendingSessionRestore
            pendingSessionRestore = nil
            restoreSessionIfNeeded(snapshot)
            
        case .failure(let error):
            loadError = error.localizedDescription
            pendingSessionRestore = nil
            endBusy()
        }
    }
    
    private func handleMatOpenIfNeeded(for url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "mat" else {
            return false
        }
        
        switch MatImageLoader.availableVariables(at: url) {
        case .failure(let error):
            loadError = error.localizedDescription
        case .success(let options):
            guard !options.isEmpty else {
                loadError = "MAT файл не содержит подходящих 3D переменных"
                return true
            }
            
            if options.count == 1 {
                loadMatCube(url: url, variableName: options[0].name)
            } else {
                pendingMatSelection = MatSelectionRequest(fileURL: url, options: options)
            }
        }
        
        return true
    }
    
    private func loadMatCube(url: URL, variableName: String) {
        beginBusy(message: "Импорт гиперкуба…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = MatImageLoader.load(from: url, variableName: variableName)
            DispatchQueue.main.async {
                self.handleLoadResult(result: result, url: url)
            }
        }
    }
    
    func cancelMatSelection() {
        pendingMatSelection = nil
        loadError = "Выбор переменной отменён"
    }
    
    func confirmMatSelection(option: MatVariableOption) {
        guard let request = pendingMatSelection else { return }
        pendingMatSelection = nil
        loadMatCube(url: request.fileURL, variableName: option.name)
    }
    
    func addLibraryEntries(from urls: [URL]) {
        for rawURL in urls {
            let canonical = canonicalURL(rawURL)
            guard ImageLoaderFactory.loader(for: canonical) != nil else { continue }
            if !libraryEntries.contains(where: { $0.url.standardizedFileURL == canonical }) {
                libraryEntries.append(CubeLibraryEntry(url: canonical))
            }
        }
    }
    
    func renameLibraryEntry(id: CubeLibraryEntry.ID, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = (trimmed?.isEmpty == false) ? trimmed : nil
        guard let index = libraryEntries.firstIndex(where: { $0.id == id }) else { return }
        var entry = libraryEntries[index]
        entry.customName = newName
        libraryEntries[index] = entry
        librarySpectrumCache.renameEntry(libraryID: id, displayName: entry.displayName)
    }
    
    func removeLibraryEntry(_ entry: CubeLibraryEntry) {
        let canonical = canonicalURL(entry.url)
        libraryEntries.removeAll { $0.canonicalPath == entry.canonicalPath }
        sessionSnapshots.removeValue(forKey: canonical)
    }
    
    func exportPayload(for entry: CubeLibraryEntry) -> CubeExportPayload? {
        let canonical = canonicalURL(entry.url)
        let entrySnapshot: CubeSessionSnapshot = {
            if Thread.isMainThread {
                return snapshot(for: entry) ?? CubeSessionSnapshot.empty
            } else {
                return DispatchQueue.main.sync {
                    snapshot(for: entry) ?? CubeSessionSnapshot.empty
                }
            }
        }()
        let loadResult = ImageLoaderFactory.load(from: canonical)
        
        guard case .success(let rawCube) = loadResult else {
            return nil
        }
        
        guard let prepared = prepareCubeForExport(cube: rawCube, snapshot: entrySnapshot) else {
            return nil
        }
        
        let baseName = entry.exportBaseName
        return CubeExportPayload(
            cube: prepared.cube,
            wavelengths: prepared.wavelengths,
            layout: prepared.layout,
            baseName: baseName,
            colorSynthesisConfig: entrySnapshot.colorSynthesisConfig
        )
    }
    
    func canCopyProcessing(from entry: CubeLibraryEntry) -> Bool {
        return snapshot(for: entry) != nil
    }
    
    func copyProcessing(from entry: CubeLibraryEntry) {
        guard let snapshot = snapshot(for: entry) else { return }
        processingClipboard = ProcessingClipboard(
            pipelineOperations: snapshot.pipelineOperations,
            spectralTrimRange: snapshot.spectralTrimRange,
            trimStart: snapshot.trimStart,
            trimEnd: snapshot.trimEnd
        )
    }
    
    func pasteProcessing(to entry: CubeLibraryEntry) {
        guard let clipboard = processingClipboard else { return }
        let canonical = canonicalURL(entry.url)
        var snapshot = sessionSnapshots[canonical] ?? CubeSessionSnapshot.empty
        snapshot.pipelineOperations = clipboard.pipelineOperations
        snapshot.spectralTrimRange = clipboard.spectralTrimRange
        snapshot.trimStart = clipboard.trimStart
        snapshot.trimEnd = clipboard.trimEnd
        sessionSnapshots[canonical] = snapshot
        
        if let currentURL = cubeURL?.standardizedFileURL, currentURL == canonical {
            pipelineOperations = clipboard.pipelineOperations
            trimStart = clipboard.trimStart
            trimEnd = max(trimStart, clipboard.trimEnd)
            spectralTrimRange = clipboard.spectralTrimRange
            if pipelineAutoApply {
                applyPipeline()
            }
        }
    }
    
    var canPropagateProcessing: Bool {
        cube != nil && !libraryEntries.isEmpty
    }
    
    func propagateProcessingToLibrary() {
        guard let snapshot = makeSnapshot() else { return }
        let clipboard = ProcessingClipboard(
            pipelineOperations: snapshot.pipelineOperations,
            spectralTrimRange: snapshot.spectralTrimRange,
            trimStart: snapshot.trimStart,
            trimEnd: snapshot.trimEnd
        )
        processingClipboard = clipboard
        let entries = libraryEntries
        for entry in entries {
            pasteProcessing(to: entry)
        }
    }

    func beginLibraryExportProgress(total: Int) {
        DispatchQueue.main.async {
            self.libraryExportDismissWorkItem?.cancel()
            self.libraryExportProgressState = LibraryExportProgressState(
                phase: .running,
                completed: 0,
                total: total,
                message: "Экспорт библиотеки…"
            )
        }
    }
    
    func updateLibraryExportProgress(completed: Int, total: Int) {
        DispatchQueue.main.async {
            guard self.libraryExportProgressState != nil else { return }
            self.libraryExportProgressState = LibraryExportProgressState(
                phase: .running,
                completed: completed,
                total: total,
                message: "Экспорт библиотеки…"
            )
        }
    }
    
    func finishLibraryExportProgress(success: Bool, total: Int, message: String) {
        DispatchQueue.main.async {
            self.libraryExportDismissWorkItem?.cancel()
            self.libraryExportProgressState = LibraryExportProgressState(
                phase: success ? .success : .failure,
                completed: total,
                total: total,
                message: message
            )
            
            let delay: TimeInterval = success ? 3 : 5
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.libraryExportProgressState?.phase == (success ? .success : .failure) {
                    self.libraryExportProgressState = nil
                }
            }
            self.libraryExportDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func updateResolvedLayout() {
        if layout == .auto {
            resolvedAutoLayout = inferLayout(for: cube ?? originalCube)
        } else {
            resolvedAutoLayout = layout
        }
    }
    
    private func inferLayout(for cube: HyperCube?) -> CubeLayout {
        guard let cube = cube,
              let axes = cube.axes(for: .auto) else {
            return resolvedAutoLayout
        }
        switch axes.channel {
        case 0:
            return .chw
        case 2:
            return .hwc
        default:
            return resolvedAutoLayout == .auto ? .chw : resolvedAutoLayout
        }
    }
    
    private func restoreSessionIfNeeded(_ snapshot: CubeSessionSnapshot?) {
        guard let snapshot else {
            spectralTrimRange = nil
            endBusy()
            return
        }
        pcaRenderedImage = nil
        pcaPendingConfig = nil
        busyMessage = "Восстановление настроек…"
            applySnapshot(snapshot)
            endBusy()
    }
    
    private func applySnapshot(_ snapshot: CubeSessionSnapshot) {
        let baseChannelCount: Int = {
            if let cube {
                return cube.channelCount(for: snapshot.layout)
            }
            return channelCount
        }()
        if let snapshotBase = snapshot.baseWavelengths,
           snapshotBase.count == baseChannelCount {
            baseWavelengths = snapshotBase
        } else if let snapshotWavelengths = snapshot.wavelengths,
                  snapshotWavelengths.count == baseChannelCount {
            baseWavelengths = snapshotWavelengths
        }

        if let snapshotWavelengths = snapshot.wavelengths,
           snapshotWavelengths.count == baseChannelCount {
            wavelengths = snapshotWavelengths
        lambdaStart = snapshot.lambdaStart
        lambdaEnd = snapshot.lambdaEnd
        lambdaStep = snapshot.lambdaStep
        } else if let currentWavelengths = baseWavelengths, !currentWavelengths.isEmpty {
            updateLambdaRange(from: currentWavelengths)
        }
        trimStart = snapshot.trimStart
        trimEnd = snapshot.trimEnd
        isTrimMode = false
        normalizationType = snapshot.normalizationType
        normalizationParams = snapshot.normalizationParams
        autoScaleOnTypeConversion = snapshot.autoScaleOnTypeConversion
        pipelineOperations = snapshot.pipelineOperations
        pipelineAutoApply = snapshot.pipelineAutoApply
        layout = snapshot.layout
        viewMode = snapshot.viewMode
        zoomScale = snapshot.zoomScale
        imageOffset = snapshot.imageOffset
        spectralTrimRange = snapshot.spectralTrimRange
        roiAggregationMode = snapshot.roiAggregationMode
        colorSynthesisConfig = ColorSynthesisConfig(
            mode: snapshot.colorSynthesisConfig.mode,
            mapping: snapshot.colorSynthesisConfig.mapping,
            rangeMapping: snapshot.colorSynthesisConfig.rangeMapping,
            pcaConfig: clampedPCAConfig(snapshot.colorSynthesisConfig.pcaConfig)
        )
        ndPreset = snapshot.ndPreset
        ndviRedTarget = snapshot.ndviRedTarget
        ndviNIRTarget = snapshot.ndviNIRTarget
        ndsiGreenTarget = snapshot.ndsiGreenTarget
        ndsiSWIRTarget = snapshot.ndsiSWIRTarget
        wdviSlope = snapshot.wdviSlope
        wdviIntercept = snapshot.wdviIntercept
        ndPalette = NDPalette(rawValue: snapshot.ndPaletteRaw) ?? .classic
        ndThreshold = snapshot.ndThreshold
        pcaPendingConfig = nil
        pcaRenderedImage = nil
        hasCustomColorSynthesisMapping = true

        if let range = snapshot.spectralTrimRange,
           !pipelineOperations.contains(where: { $0.type == .spectralTrim }) {
            var trimOp = PipelineOperation(type: .spectralTrim)
            trimOp.layout = layout
            trimOp.spectralTrimParams = SpectralTrimParameters(
                startChannel: range.lowerBound,
                endChannel: range.upperBound
            )
            pipelineOperations.append(trimOp)
            spectralTrimRange = range
        }
        
        let maxChannel = max(channelCount - 1, 0)
        if maxChannel >= 0 {
            currentChannel = max(0, min(snapshot.currentChannel, Double(maxChannel)))
        } else {
            currentChannel = 0
        }
        
        let maxTrim = Double(max(channelCount - 1, 0))
        trimStart = max(0, min(snapshot.trimStart, maxTrim))
        trimEnd = max(trimStart, min(snapshot.trimEnd, maxTrim))
        
        updateResolvedLayout()
        clampColorSynthesisMapping()
        
        if !pipelineOperations.isEmpty {
            spectrumRotationTurns = pipelineRotationTurns()
            spectrumSpatialSize = nil
            pendingRestoreSpectrumDescriptors = snapshot.spectrumSamples
            pendingRestoreROISampleDescriptors = snapshot.roiSamples
            spectrumSpatialOps = spatialOperations(from: pipelineOperations)
            spectrumSpatialBaseSize = spatialBaseSize()
            applyPipeline()
        } else {
            spectrumRotationTurns = pipelineRotationTurns()
            if let cube = cube {
                spectrumSpatialSize = cubeSpatialSize(for: cube)
            }
            restoreSpectrumSamples(from: snapshot.spectrumSamples)
            restoreROISamples(from: snapshot.roiSamples)
            pendingRestoreSpectrumDescriptors = nil
            pendingRestoreROISampleDescriptors = nil
        }
    }
    
    private func applySnapshotWithoutTrim(_ snapshot: CubeSessionSnapshot) {
        var adjusted = snapshot
        adjusted.spectralTrimRange = nil
        applySnapshot(adjusted)
    }
    
    private func persistCurrentSession() {
        guard let url = cubeURL?.standardizedFileURL else { return }
        guard let snapshot = makeSnapshot() else { return }
        let canonical = canonicalURL(url)
        sessionSnapshots[canonical] = snapshot
        
        let libraryID = canonical.path
        let displayName = displayName(for: url)
        librarySpectrumCache.updateEntry(
            libraryID: libraryID,
            displayName: displayName,
            spectrumSamples: snapshot.spectrumSamples,
            roiSamples: snapshot.roiSamples
        )
    }
    
    private func resetSessionState() {
        pipelineOperations.removeAll()
        pipelineAutoApply = true
        showAlignmentVisualization = false
        alignmentPointsEditable = false
        wavelengths = nil
        lambdaStart = "400"
        lambdaEnd = "1000"
        lambdaStep = ""
        baseWavelengths = nil
        normalizationType = .none
        normalizationParams = .default
        autoScaleOnTypeConversion = true
        trimStart = 0
        trimEnd = 0
        currentChannel = 0
        zoomScale = 1.0
        imageOffset = .zero
        isTrimMode = false
        spectralTrimRange = nil
        viewMode = .gray
        colorSynthesisConfig = .default(channelCount: channelCount, wavelengths: wavelengths)
        ndPreset = .ndvi
        ndviRedTarget = "660"
        ndviNIRTarget = "840"
        ndsiGreenTarget = "555"
        ndsiSWIRTarget = "1610"
        wdviSlope = "1.0"
        wdviIntercept = "0.0"
        ndPalette = .classic
        ndThreshold = 0.3
        ndFallbackIndices = [.ndvi: (0, 0), .ndsi: (0, 0), .wdvi: (0, 0)]
        pcaPendingConfig = nil
        pcaRenderedImage = nil
        isPCAApplying = false
        pcaProgressMessage = nil
        hasCustomColorSynthesisMapping = false
        lastPipelineAppliedOperations = []
        lastPipelineResult = nil
        lastPipelineBaseCubeID = nil
        layout = .auto
        resetSpectrumSelections()
        spectrumSpatialSize = nil
        spectrumRotationTurns = pipelineRotationTurns()
        spectrumSpatialOps = []
        spectrumSpatialBaseSize = nil
        updateResolvedLayout()
    }
    
    private func ensureLibraryContains(url: URL) {
        let canonical = canonicalURL(url)
        if !libraryEntries.contains(where: { $0.url.standardizedFileURL == canonical }) {
            libraryEntries.append(CubeLibraryEntry(url: canonical))
        }
    }
    
    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
    
    private func makeSnapshot() -> CubeSessionSnapshot? {
        guard cube != nil else { return nil }
        let descriptors = spectrumSamples.map {
            SpectrumSampleDescriptor(
                id: $0.id,
                pixelX: $0.pixelX,
                pixelY: $0.pixelY,
                colorIndex: $0.colorIndex,
                displayName: $0.displayName,
                values: $0.values,
                wavelengths: $0.wavelengths
            )
        }
        let roiDescriptors = roiSamples.map {
            SpectrumROISampleDescriptor(
                id: $0.id,
                minX: $0.rect.minX,
                minY: $0.rect.minY,
                width: $0.rect.width,
                height: $0.rect.height,
                colorIndex: $0.colorIndex,
                displayName: $0.displayName,
                values: $0.values,
                wavelengths: $0.wavelengths
            )
        }
        
        let clampedConfig = ColorSynthesisConfig(
            mode: colorSynthesisConfig.mode,
            mapping: colorSynthesisConfig.mapping.clamped(maxChannelCount: channelCount),
            rangeMapping: colorSynthesisConfig.rangeMapping.clamped(maxChannelCount: channelCount),
            pcaConfig: clampedPCAConfig(colorSynthesisConfig.pcaConfig)
        )
        
        return CubeSessionSnapshot(
            pipelineOperations: pipelineOperations,
            pipelineAutoApply: pipelineAutoApply,
            wavelengths: wavelengths,
            baseWavelengths: baseWavelengths,
            lambdaStart: lambdaStart,
            lambdaEnd: lambdaEnd,
            lambdaStep: lambdaStep,
            trimStart: trimStart,
            trimEnd: trimEnd,
            spectralTrimRange: spectralTrimRange,
            normalizationType: normalizationType,
            normalizationParams: normalizationParams,
            autoScaleOnTypeConversion: autoScaleOnTypeConversion,
            layout: layout,
            viewMode: viewMode,
            currentChannel: currentChannel,
            zoomScale: zoomScale,
            imageOffset: imageOffset,
            spectrumSamples: descriptors,
            roiSamples: roiDescriptors,
            roiAggregationMode: roiAggregationMode,
            colorSynthesisConfig: clampedConfig,
            ndPreset: ndPreset,
            ndviRedTarget: ndviRedTarget,
            ndviNIRTarget: ndviNIRTarget,
            ndsiGreenTarget: ndsiGreenTarget,
            ndsiSWIRTarget: ndsiSWIRTarget,
            wdviSlope: wdviSlope,
            wdviIntercept: wdviIntercept,
            ndPaletteRaw: ndPalette.rawValue,
            ndThreshold: ndThreshold
        )
    }
    
    private func snapshot(for entry: CubeLibraryEntry) -> CubeSessionSnapshot? {
        let canonical = canonicalURL(entry.url)
        if let currentURL = cubeURL?.standardizedFileURL, currentURL == canonical {
            return makeSnapshot()
        }
        return sessionSnapshots[canonical]
    }
    
    private func prepareCubeForExport(cube: HyperCube, snapshot: CubeSessionSnapshot) -> (cube: HyperCube, wavelengths: [Double]?, layout: CubeLayout)? {
        var workingCube = cube
        var layout = snapshot.layout
        var wavelengths = snapshot.wavelengths ?? cube.wavelengths
        
        if let trimRange = snapshot.spectralTrimRange,
           !snapshot.pipelineOperations.contains(where: { $0.type == .spectralTrim }) {
            guard trimRange.lowerBound >= 0 else { return nil }
            guard let trimmed = trimChannels(
                cube: workingCube,
                layout: layout,
                from: trimRange.lowerBound,
                to: trimRange.upperBound
            ) else {
                return nil
            }
            workingCube = trimmed
            layout = .chw
            if let stored = snapshot.wavelengths, !stored.isEmpty {
                wavelengths = stored
            } else if let wl = wavelengths, wl.count > trimRange.lowerBound {
                let lower = max(0, min(trimRange.lowerBound, wl.count - 1))
                let upper = max(lower, min(trimRange.upperBound, wl.count - 1))
                wavelengths = Array(wl[lower...upper])
            }
        }
        
        if !snapshot.pipelineOperations.isEmpty {
            let baseWavelengths = snapshot.baseWavelengths ?? wavelengths
            let baseCube = cubeWithWavelengthsIfNeeded(workingCube, layout: layout, baseWavelengths: baseWavelengths)
            var ops = snapshot.pipelineOperations
            workingCube = processPipeline(original: baseCube, operations: &ops) ?? baseCube
        }
        
        let resolvedLayout = resolveLayout(for: workingCube, preferred: layout)
        return (workingCube, wavelengths, resolvedLayout)
    }
    
    private func resolveLayout(for cube: HyperCube, preferred: CubeLayout) -> CubeLayout {
        guard preferred == .auto else { return preferred }
        guard let axes = cube.axes(for: .auto) else {
            return .chw
        }
        switch axes.channel {
        case 0:
            return .chw
        case 2:
            return .hwc
        default:
            return .chw
        }
    }
    
    private func makeSpectrumSample(
        pixelX: Int,
        pixelY: Int,
        colorIndex: Int,
        id: UUID = UUID(),
        displayName: String? = nil
    ) -> SpectrumSample? {
        guard let spectrumValues = buildSpectrumValues(pixelX: pixelX, pixelY: pixelY) else { return nil }
        return SpectrumSample(
            id: id,
            pixelX: pixelX,
            pixelY: pixelY,
            values: spectrumValues,
            wavelengths: wavelengths,
            colorIndex: colorIndex,
            displayName: displayName
        )
    }

    private func clampedSpectrumPoint(x: Int, y: Int) -> (x: Int, y: Int)? {
        guard let cube = cube else { return nil }
        let layout = activeLayout
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: layout) else { return nil }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        guard width > 0, height > 0 else { return nil }
        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))
        return (clampedX, clampedY)
    }

    private func normalizeCoordinate(_ value: Int, size: Int?) -> Double {
        guard let size, size > 0 else { return 0.0 }
        let normalized = (Double(value) + 0.5) / Double(size)
        return max(0.0, min(1.0, normalized))
    }
    
    private func denormalizeCoordinate(_ normalized: Double, size: Int?) -> Int? {
        guard let size, size > 0 else { return nil }
        let clamped = max(0.0, min(1.0, normalized))
        let scaled = clamped * Double(size) - 0.5
        let rounded = Int(round(scaled))
        return max(0, min(rounded, size - 1))
    }
    
    private func normalizeRect(_ rect: SpectrumROIRect, size: (width: Int, height: Int)?) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let minX = normalizeCoordinate(rect.minX, size: size?.width)
        let maxX = normalizeCoordinate(rect.maxX, size: size?.width)
        let minY = normalizeCoordinate(rect.minY, size: size?.height)
        let maxY = normalizeCoordinate(rect.maxY, size: size?.height)
        return (minX, minY, maxX, maxY)
    }
    
    private func denormalizePoint(_ clipboard: SpectrumSampleClipboard, size: (width: Int, height: Int)) -> SpatialPoint? {
        guard let x = denormalizeCoordinate(clipboard.normalizedX, size: size.width),
              let y = denormalizeCoordinate(clipboard.normalizedY, size: size.height) else {
            return nil
        }
        return SpatialPoint(x: x, y: y)
    }
    
    private func denormalizeRect(_ clipboard: SpectrumROISampleClipboard, size: (width: Int, height: Int)) -> SpectrumROIRect? {
        guard let minX = denormalizeCoordinate(clipboard.normalizedMinX, size: size.width),
              let maxX = denormalizeCoordinate(clipboard.normalizedMaxX, size: size.width),
              let minY = denormalizeCoordinate(clipboard.normalizedMinY, size: size.height),
              let maxY = denormalizeCoordinate(clipboard.normalizedMaxY, size: size.height) else {
            return nil
        }
        let lowerX = min(minX, maxX)
        let upperX = max(minX, maxX)
        let lowerY = min(minY, maxY)
        let upperY = max(minY, maxY)
        return SpectrumROIRect(
            minX: lowerX,
            minY: lowerY,
            width: upperX - lowerX + 1,
            height: upperY - lowerY + 1
        )
    }
    
    private func buildSpectrumValues(pixelX: Int, pixelY: Int) -> [Double]? {
        guard let cube = cube else { return nil }
        
        let layout = activeLayout
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else { return nil }
        
        var spectrum: [Double] = Array(repeating: 0, count: channels)
        for ch in 0..<channels {
            var indices = [0, 0, 0]
            indices[axes.channel] = ch
            indices[axes.height] = pixelY
            indices[axes.width] = pixelX
            
            let value = cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
            spectrum[ch] = value
        }
        return spectrum
    }
    
    private func makeROISample(
        rect: SpectrumROIRect,
        colorIndex: Int,
        id: UUID = UUID(),
        displayName: String? = nil
    ) -> SpectrumROISample? {
        guard let normalizedRect = normalizedROIRect(rect) else { return nil }
        guard let spectrumValues = buildROISpectrumValues(rect: normalizedRect) else { return nil }
        return SpectrumROISample(
            id: id,
            rect: normalizedRect,
            values: spectrumValues,
            wavelengths: wavelengths,
            colorIndex: colorIndex,
            displayName: displayName
        )
    }
    
    private func normalizedROIRect(_ rect: SpectrumROIRect) -> SpectrumROIRect? {
        guard let cube = cube else { return nil }
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return nil }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        return rect.clamped(maxWidth: width, maxHeight: height)
    }
    
    private func buildROISpectrumValues(rect: SpectrumROIRect) -> [Double]? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard let cube = cube else { return nil }
        
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return nil }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        guard rect.minX >= 0, rect.maxX < width, rect.minY >= 0, rect.maxY < height else { return nil }
        let pixelCount = rect.area
        guard pixelCount > 0 else { return nil }
        
        var aggregated: [Double] = []
        aggregated.reserveCapacity(channels)
        
        for ch in 0..<channels {
            var buffer: [Double] = []
            buffer.reserveCapacity(pixelCount)
            for y in rect.minY..<(rect.minY + rect.height) {
                for x in rect.minX..<(rect.minX + rect.width) {
                    var indices = [0, 0, 0]
                    indices[axes.channel] = ch
                    indices[axes.height] = y
                    indices[axes.width] = x
                    let value = cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
                    buffer.append(value)
                }
            }
            
            let aggregatedValue: Double
            switch roiAggregationMode {
            case .mean:
                aggregatedValue = buffer.reduce(0, +) / Double(buffer.count)
            case .median:
                let sorted = buffer.sorted()
                let mid = sorted.count / 2
                if sorted.count % 2 == 0 {
                    aggregatedValue = (sorted[mid - 1] + sorted[mid]) / 2.0
                } else {
                    aggregatedValue = sorted[mid]
                }
            }
            aggregated.append(aggregatedValue)
        }
        
        return aggregated
    }

    private func nextSpectrumColorIndex(in descriptors: [SpectrumSampleDescriptor]) -> Int {
        let maxIndex = descriptors.map(\.colorIndex).max() ?? -1
        return maxIndex + 1
    }
    
    private func nextSpectrumColorIndex(in descriptors: [SpectrumROISampleDescriptor]) -> Int {
        let maxIndex = descriptors.map(\.colorIndex).max() ?? -1
        return maxIndex + 1
    }
    
    private func refreshSpectrumSamples() {
        guard cube != nil else {
            spectrumSamples.removeAll()
            pendingSpectrumSample = nil
            return
        }
        if spectrumSamples.isEmpty && pendingSpectrumSample == nil {
            return
        }
        
        var updated: [SpectrumSample] = []
        for sample in spectrumSamples {
            if let refreshed = makeSpectrumSample(
                pixelX: sample.pixelX,
                pixelY: sample.pixelY,
                colorIndex: sample.colorIndex,
                id: sample.id,
                displayName: sample.displayName
            ) {
                updated.append(refreshed)
            }
        }
        spectrumSamples = updated
        
        if let pending = pendingSpectrumSample {
            pendingSpectrumSample = makeSpectrumSample(
                pixelX: pending.pixelX,
                pixelY: pending.pixelY,
                colorIndex: pending.colorIndex,
                id: pending.id,
                displayName: pending.displayName
            )
        }
    }
    
    private func refreshROISamples() {
        guard cube != nil else {
            roiSamples.removeAll()
            pendingROISample = nil
            roiColorCounter = 0
            return
        }
        if roiSamples.isEmpty && pendingROISample == nil {
            return
        }
        
        var updated: [SpectrumROISample] = []
        for sample in roiSamples {
            if let refreshed = makeROISample(
                rect: sample.rect,
                colorIndex: sample.colorIndex,
                id: sample.id,
                displayName: sample.displayName
            ) {
                updated.append(refreshed)
            }
        }
        roiSamples = updated
        
        if let pending = pendingROISample {
            pendingROISample = makeROISample(
                rect: pending.rect,
                colorIndex: pending.colorIndex,
                id: pending.id,
                displayName: pending.displayName
            )
        }
    }
    
    private func adjustSpectrumGeometry(previousCube: HyperCube?, newCube: HyperCube?) {
        let currentTurns = pipelineRotationTurns()
        let currentSpatialOps = spatialOperations(from: pipelineOperations)
        let currentBaseSize = spectrumSpatialBaseSize ?? spatialBaseSize()
        
        guard let newCube else {
            spectrumSpatialSize = nil
            spectrumRotationTurns = currentTurns
            spectrumSpatialOps = currentSpatialOps
            spectrumSpatialBaseSize = currentBaseSize
            return
        }
        
        let newSize = cubeSpatialSize(for: newCube)
        
        let hasSamples = !spectrumSamples.isEmpty
            || pendingSpectrumSample != nil
            || !roiSamples.isEmpty
            || pendingROISample != nil
        
        if !hasSamples {
            spectrumSpatialOps = currentSpatialOps
            spectrumSpatialBaseSize = currentBaseSize
        } else if let previousBaseSize = spectrumSpatialBaseSize ?? spatialBaseSize(),
                  let nextBaseSize = currentBaseSize,
                  currentSpatialOps != spectrumSpatialOps || previousBaseSize != nextBaseSize {
            transformSpectrumSamples(
                fromOps: spectrumSpatialOps,
                fromBaseSize: previousBaseSize,
                toOps: currentSpatialOps,
                toBaseSize: nextBaseSize
            )
            spectrumSpatialOps = currentSpatialOps
            spectrumSpatialBaseSize = nextBaseSize
        }
        
        spectrumSpatialSize = newSize ?? spectrumSpatialSize
        spectrumRotationTurns = currentTurns
    }

    private func spatialOperations(from operations: [PipelineOperation]) -> [PipelineOperation] {
        operations.filter {
            switch $0.type {
            case .rotation, .resize, .spatialCrop:
                return true
            default:
                return false
            }
        }
    }

    private func spatialBaseSize() -> (width: Int, height: Int)? {
        if let originalCube {
            return cubeSpatialSize(for: originalCube)
        }
        if let cube {
            return cubeSpatialSize(for: cube)
        }
        return nil
    }

    private func transformSpectrumSamples(
        fromOps: [PipelineOperation],
        fromBaseSize: (width: Int, height: Int),
        toOps: [PipelineOperation],
        toBaseSize: (width: Int, height: Int)
    ) {
        let oldBase = SpatialSize(width: fromBaseSize.width, height: fromBaseSize.height)
        let newBase = SpatialSize(width: toBaseSize.width, height: toBaseSize.height)
        
        spectrumSamples = spectrumSamples.compactMap { sample in
            guard let mapped = transformPoint(
                x: sample.pixelX,
                y: sample.pixelY,
                fromOps: fromOps,
                fromBaseSize: oldBase,
                toOps: toOps,
                toBaseSize: newBase
            ) else { return nil }
            
            return SpectrumSample(
                id: sample.id,
                pixelX: mapped.x,
                pixelY: mapped.y,
                values: sample.values,
                wavelengths: sample.wavelengths,
                colorIndex: sample.colorIndex,
                displayName: sample.displayName
            )
        }
        
        if let pending = pendingSpectrumSample {
            if let mapped = transformPoint(
                x: pending.pixelX,
                y: pending.pixelY,
                fromOps: fromOps,
                fromBaseSize: oldBase,
                toOps: toOps,
                toBaseSize: newBase
            ) {
                pendingSpectrumSample = SpectrumSample(
                    id: pending.id,
                    pixelX: mapped.x,
                    pixelY: mapped.y,
                    values: pending.values,
                    wavelengths: pending.wavelengths,
                    colorIndex: pending.colorIndex,
                    displayName: pending.displayName
                )
            } else {
                pendingSpectrumSample = nil
            }
        }
        
        roiSamples = roiSamples.compactMap { sample in
            guard let mapped = transformRect(
                sample.rect,
                fromOps: fromOps,
                fromBaseSize: oldBase,
                toOps: toOps,
                toBaseSize: newBase
            ) else { return nil }
            
            return SpectrumROISample(
                id: sample.id,
                rect: mapped,
                values: sample.values,
                wavelengths: sample.wavelengths,
                colorIndex: sample.colorIndex,
                displayName: sample.displayName
            )
        }
        
        if let pending = pendingROISample {
            if let mapped = transformRect(
                pending.rect,
                fromOps: fromOps,
                fromBaseSize: oldBase,
                toOps: toOps,
                toBaseSize: newBase
            ) {
                pendingROISample = SpectrumROISample(
                    id: pending.id,
                    rect: mapped,
                    values: pending.values,
                    wavelengths: pending.wavelengths,
                    colorIndex: pending.colorIndex,
                    displayName: pending.displayName
                )
            } else {
                pendingROISample = nil
            }
        }
    }

    private enum SpatialTransformDirection {
        case forward
        case inverse
    }

    private struct SpatialSize: Equatable {
        let width: Int
        let height: Int
    }

    private struct SpatialPoint {
        let x: Int
        let y: Int
    }

    private func spatialSizes(from base: SpatialSize, ops: [PipelineOperation]) -> [SpatialSize] {
        var sizes: [SpatialSize] = [base]
        var current = base
        
        for op in ops {
            current = applySpatialOpToSize(op, size: current)
            sizes.append(current)
        }
        
        return sizes
    }

    private func applySpatialOpToSize(_ op: PipelineOperation, size: SpatialSize) -> SpatialSize {
        switch op.type {
        case .rotation:
            guard let angle = op.rotationAngle else { return size }
            if angle.quarterTurns % 2 == 1 {
                return SpatialSize(width: size.height, height: size.width)
            }
            return size
        case .resize:
            guard let params = op.resizeParameters else { return size }
            let targetWidth = params.targetWidth
            let targetHeight = params.targetHeight
            guard targetWidth > 0, targetHeight > 0 else { return size }
            return SpatialSize(width: targetWidth, height: targetHeight)
        case .spatialCrop:
            guard var params = op.cropParameters else { return size }
            params.clamp(maxWidth: size.width, maxHeight: size.height)
            guard params.width > 0, params.height > 0 else { return size }
            return SpatialSize(width: params.width, height: params.height)
        default:
            return size
        }
    }

    private func transformPoint(
        x: Int,
        y: Int,
        fromOps: [PipelineOperation],
        fromBaseSize: SpatialSize,
        toOps: [PipelineOperation],
        toBaseSize: SpatialSize
    ) -> SpatialPoint? {
        guard let original = applySpatialOpsToPoint(
            SpatialPoint(x: x, y: y),
            base: fromBaseSize,
            ops: fromOps,
            direction: .inverse
        ) else { return nil }
        
        return applySpatialOpsToPoint(
            original,
            base: toBaseSize,
            ops: toOps,
            direction: .forward
        )
    }

    private func transformRect(
        _ rect: SpectrumROIRect,
        fromOps: [PipelineOperation],
        fromBaseSize: SpatialSize,
        toOps: [PipelineOperation],
        toBaseSize: SpatialSize
    ) -> SpectrumROIRect? {
        guard let original = applySpatialOpsToRect(
            rect,
            base: fromBaseSize,
            ops: fromOps,
            direction: .inverse
        ) else { return nil }
        
        return applySpatialOpsToRect(
            original,
            base: toBaseSize,
            ops: toOps,
            direction: .forward
        )
    }

    private func applySpatialOpsToPoint(
        _ point: SpatialPoint,
        base: SpatialSize,
        ops: [PipelineOperation],
        direction: SpatialTransformDirection
    ) -> SpatialPoint? {
        let sizes = spatialSizes(from: base, ops: ops)
        var current = point
        
        switch direction {
        case .forward:
            for (index, op) in ops.enumerated() {
                let srcSize = sizes[index]
                let dstSize = sizes[index + 1]
                guard let mapped = applySpatialOpToPoint(
                    current,
                    op: op,
                    srcSize: srcSize,
                    dstSize: dstSize,
                    direction: .forward
                ) else { return nil }
                current = mapped
            }
        case .inverse:
            for index in (0..<ops.count).reversed() {
                let op = ops[index]
                let srcSize = sizes[index]
                let dstSize = sizes[index + 1]
                guard let mapped = applySpatialOpToPoint(
                    current,
                    op: op,
                    srcSize: srcSize,
                    dstSize: dstSize,
                    direction: .inverse
                ) else { return nil }
                current = mapped
            }
        }
        
        return current
    }

    private func applySpatialOpToPoint(
        _ point: SpatialPoint,
        op: PipelineOperation,
        srcSize: SpatialSize,
        dstSize: SpatialSize,
        direction: SpatialTransformDirection
    ) -> SpatialPoint? {
        switch op.type {
        case .rotation:
            guard let angle = op.rotationAngle else { return point }
            let turns = angle.quarterTurns
            let size = direction == .forward ? srcSize : dstSize
            let rotated = rotatePoint(
                x: point.x,
                y: point.y,
                turns: direction == .forward ? turns : -turns,
                size: (width: size.width, height: size.height)
            )
            return SpatialPoint(x: rotated.x, y: rotated.y)
        case .resize:
            guard srcSize.width > 0, srcSize.height > 0, dstSize.width > 0, dstSize.height > 0 else {
                return point
            }
            let fromSize = direction == .forward ? srcSize : dstSize
            let toSize = direction == .forward ? dstSize : srcSize
            let mappedX = mapCoordinate(point.x, from: fromSize.width, to: toSize.width)
            let mappedY = mapCoordinate(point.y, from: fromSize.height, to: toSize.height)
            return SpatialPoint(x: mappedX, y: mappedY)
        case .spatialCrop:
            guard var params = op.cropParameters else { return point }
            params.clamp(maxWidth: srcSize.width, maxHeight: srcSize.height)
            if direction == .forward {
                guard point.x >= params.left,
                      point.x <= params.right,
                      point.y >= params.top,
                      point.y <= params.bottom else {
                    return nil
                }
                return SpatialPoint(x: point.x - params.left, y: point.y - params.top)
            }
            let x = point.x + params.left
            let y = point.y + params.top
            let clampedX = max(0, min(x, max(srcSize.width - 1, 0)))
            let clampedY = max(0, min(y, max(srcSize.height - 1, 0)))
            return SpatialPoint(x: clampedX, y: clampedY)
        default:
            return point
        }
    }

    private func applySpatialOpsToRect(
        _ rect: SpectrumROIRect,
        base: SpatialSize,
        ops: [PipelineOperation],
        direction: SpatialTransformDirection
    ) -> SpectrumROIRect? {
        let sizes = spatialSizes(from: base, ops: ops)
        var current = rect
        
        switch direction {
        case .forward:
            for (index, op) in ops.enumerated() {
                let srcSize = sizes[index]
                let dstSize = sizes[index + 1]
                guard let mapped = applySpatialOpToRect(
                    current,
                    op: op,
                    srcSize: srcSize,
                    dstSize: dstSize,
                    direction: .forward
                ) else { return nil }
                current = mapped
            }
        case .inverse:
            for index in (0..<ops.count).reversed() {
                let op = ops[index]
                let srcSize = sizes[index]
                let dstSize = sizes[index + 1]
                guard let mapped = applySpatialOpToRect(
                    current,
                    op: op,
                    srcSize: srcSize,
                    dstSize: dstSize,
                    direction: .inverse
                ) else { return nil }
                current = mapped
            }
        }
        
        return current
    }

    private func applySpatialOpToRect(
        _ rect: SpectrumROIRect,
        op: PipelineOperation,
        srcSize: SpatialSize,
        dstSize: SpatialSize,
        direction: SpatialTransformDirection
    ) -> SpectrumROIRect? {
        switch op.type {
        case .rotation:
            guard let angle = op.rotationAngle else { return rect }
            let turns = angle.quarterTurns
            let size = direction == .forward ? srcSize : dstSize
            return rotateRect(
                rect,
                turns: direction == .forward ? turns : -turns,
                size: (width: size.width, height: size.height)
            )
        case .resize:
            guard srcSize.width > 0, srcSize.height > 0, dstSize.width > 0, dstSize.height > 0 else {
                return rect
            }
            let fromSize = direction == .forward ? srcSize : dstSize
            let toSize = direction == .forward ? dstSize : srcSize
            let minX = mapCoordinate(rect.minX, from: fromSize.width, to: toSize.width)
            let maxX = mapCoordinate(rect.maxX, from: fromSize.width, to: toSize.width)
            let minY = mapCoordinate(rect.minY, from: fromSize.height, to: toSize.height)
            let maxY = mapCoordinate(rect.maxY, from: fromSize.height, to: toSize.height)
            let lowerX = min(minX, maxX)
            let upperX = max(minX, maxX)
            let lowerY = min(minY, maxY)
            let upperY = max(minY, maxY)
            return SpectrumROIRect(
                minX: lowerX,
                minY: lowerY,
                width: upperX - lowerX + 1,
                height: upperY - lowerY + 1
            ).clamped(maxWidth: toSize.width, maxHeight: toSize.height)
        case .spatialCrop:
            guard var params = op.cropParameters else { return rect }
            params.clamp(maxWidth: srcSize.width, maxHeight: srcSize.height)
            if direction == .forward {
                let cropRect = SpectrumROIRect(
                    minX: params.left,
                    minY: params.top,
                    width: params.width,
                    height: params.height
                )
                guard let intersected = intersectRect(rect, with: cropRect) else { return nil }
                let shifted = SpectrumROIRect(
                    minX: intersected.minX - params.left,
                    minY: intersected.minY - params.top,
                    width: intersected.width,
                    height: intersected.height
                )
                return shifted.clamped(maxWidth: dstSize.width, maxHeight: dstSize.height)
            }
            let shifted = SpectrumROIRect(
                minX: rect.minX + params.left,
                minY: rect.minY + params.top,
                width: rect.width,
                height: rect.height
            )
            return shifted.clamped(maxWidth: srcSize.width, maxHeight: srcSize.height)
        default:
            return rect
        }
    }

    private func mapCoordinate(_ value: Int, from srcSize: Int, to dstSize: Int) -> Int {
        guard srcSize > 0, dstSize > 0 else { return value }
        let scaled = (Double(value) + 0.5) * Double(dstSize) / Double(srcSize) - 0.5
        let rounded = Int(round(scaled))
        return max(0, min(rounded, max(dstSize - 1, 0)))
    }

    private func intersectRect(_ lhs: SpectrumROIRect, with rhs: SpectrumROIRect) -> SpectrumROIRect? {
        let minX = max(lhs.minX, rhs.minX)
        let minY = max(lhs.minY, rhs.minY)
        let maxX = min(lhs.maxX, rhs.maxX)
        let maxY = min(lhs.maxY, rhs.maxY)
        guard maxX >= minX, maxY >= minY else { return nil }
        return SpectrumROIRect(
            minX: minX,
            minY: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
    
    private func cubeSpatialSize(for cube: HyperCube) -> (width: Int, height: Int)? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return nil }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        return (width, height)
    }
    
    private func cubeSpatialSize(for cube: HyperCube, layout: CubeLayout) -> (width: Int, height: Int)? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: layout) else { return nil }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        return (width, height)
    }
    
    private func rotateSpectrumSamples(by turns: Int, previousSize: (width: Int, height: Int)) {
        guard turns % 4 != 0 else { return }
        
        spectrumSamples = spectrumSamples.map { sample in
            let rotated = rotatePoint(x: sample.pixelX, y: sample.pixelY, turns: turns, size: previousSize)
            return SpectrumSample(
                id: sample.id,
                pixelX: rotated.x,
                pixelY: rotated.y,
                values: sample.values,
                wavelengths: sample.wavelengths,
                colorIndex: sample.colorIndex,
                displayName: sample.displayName
            )
        }
        
        if let pending = pendingSpectrumSample {
            let rotated = rotatePoint(x: pending.pixelX, y: pending.pixelY, turns: turns, size: previousSize)
            pendingSpectrumSample = SpectrumSample(
                id: pending.id,
                pixelX: rotated.x,
                pixelY: rotated.y,
                values: pending.values,
                wavelengths: pending.wavelengths,
                colorIndex: pending.colorIndex,
                displayName: pending.displayName
            )
        }
    }
    
    private func rotateROISamples(by turns: Int, previousSize: (width: Int, height: Int)) {
        guard turns % 4 != 0 else { return }
        
        roiSamples = roiSamples.map { sample in
            let rotatedRect = rotateRect(sample.rect, turns: turns, size: previousSize)
            return SpectrumROISample(
                id: sample.id,
                rect: rotatedRect,
                values: sample.values,
                wavelengths: sample.wavelengths,
                colorIndex: sample.colorIndex
            )
        }
        
        if let pending = pendingROISample {
            let rotatedRect = rotateRect(pending.rect, turns: turns, size: previousSize)
            pendingROISample = SpectrumROISample(
                id: pending.id,
                rect: rotatedRect,
                values: pending.values,
                wavelengths: pending.wavelengths,
                colorIndex: pending.colorIndex
            )
        }
    }
    
    private func rotateRect(
        _ rect: SpectrumROIRect,
        turns: Int,
        size: (width: Int, height: Int)
    ) -> SpectrumROIRect {
        guard size.width > 0, size.height > 0 else { return rect }
        
        let normalized = normalizedTurns(turns)
        if normalized == 0 { return rect }
        
        var currentRect = rect
        var width = size.width
        var height = size.height
        
        for _ in 0..<normalized {
            let corners = [
                (x: currentRect.minX, y: currentRect.minY),
                (x: currentRect.maxX, y: currentRect.minY),
                (x: currentRect.minX, y: currentRect.maxY),
                (x: currentRect.maxX, y: currentRect.maxY)
            ]
            
            let transformed = corners.map { point -> (x: Int, y: Int) in
                let newX = height - 1 - point.y
                let newY = point.x
                return (newX, newY)
            }
            
            let minX = transformed.map { $0.x }.min() ?? 0
            let maxX = transformed.map { $0.x }.max() ?? 0
            let minY = transformed.map { $0.y }.min() ?? 0
            let maxY = transformed.map { $0.y }.max() ?? 0
            
            currentRect = SpectrumROIRect(
                minX: minX,
                minY: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
            (width, height) = (height, width)
        }
        
        let clampedMinX = max(0, min(currentRect.minX, max(width - 1, 0)))
        let clampedMinY = max(0, min(currentRect.minY, max(height - 1, 0)))
        let maxWidth = max(width - clampedMinX, 1)
        let maxHeight = max(height - clampedMinY, 1)
        let clampedWidth = max(1, min(currentRect.width, maxWidth))
        let clampedHeight = max(1, min(currentRect.height, maxHeight))
        
        return SpectrumROIRect(
            minX: clampedMinX,
            minY: clampedMinY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
    
    private func rotatePoint(
        x: Int,
        y: Int,
        turns: Int,
        size: (width: Int, height: Int)
    ) -> (x: Int, y: Int) {
        guard size.width > 0, size.height > 0 else {
            return (0, 0)
        }
        var currentX = x
        var currentY = y
        var width = size.width
        var height = size.height
        
        let normalized = normalizedTurns(turns)
        for _ in 0..<normalized {
            let newX = height - 1 - currentY
            let newY = currentX
            currentX = newX
            currentY = newY
            (width, height) = (height, width)
        }
        
        currentX = max(0, min(currentX, max(width - 1, 0)))
        currentY = max(0, min(currentY, max(height - 1, 0)))
        return (currentX, currentY)
    }
    
    private func normalizedTurns(_ value: Int) -> Int {
        var result = value % 4
        if result < 0 { result += 4 }
        return result
    }
    
    private func pipelineRotationTurns() -> Int {
        var turns = 0
        for operation in pipelineOperations {
            if operation.type == .rotation, let angle = operation.rotationAngle {
                turns = (turns + angle.quarterTurns) % 4
            }
        }
        return turns
    }
    
    private func restoreSpectrumSamples(from descriptors: [SpectrumSampleDescriptor]) {
        guard cube != nil else {
            spectrumSamples.removeAll()
            pendingSpectrumSample = nil
            spectrumColorCounter = 0
            return
        }
        
        var restored: [SpectrumSample] = []
        var nextColorIndex = 0
        
        for descriptor in descriptors {
            if let sample = makeSpectrumSample(
                pixelX: descriptor.pixelX,
                pixelY: descriptor.pixelY,
                colorIndex: descriptor.colorIndex,
                id: descriptor.id,
                displayName: descriptor.displayName
            ) {
                restored.append(sample)
                nextColorIndex = max(nextColorIndex, descriptor.colorIndex + 1)
            }
        }
        
        spectrumSamples = restored
        pendingSpectrumSample = nil
        spectrumColorCounter = max(nextColorIndex, restored.count)
    }
    
    private func restoreROISamples(from descriptors: [SpectrumROISampleDescriptor]) {
        guard cube != nil else {
            roiSamples.removeAll()
            pendingROISample = nil
            roiColorCounter = 0
            return
        }
        
        var restored: [SpectrumROISample] = []
        var nextColorIndex = 0
        
        for descriptor in descriptors {
            let rect = SpectrumROIRect(
                minX: descriptor.minX,
                minY: descriptor.minY,
                width: descriptor.width,
                height: descriptor.height
            )
            if let sample = makeROISample(
                rect: rect,
                colorIndex: descriptor.colorIndex,
                id: descriptor.id,
                displayName: descriptor.displayName
            ) {
                restored.append(sample)
                nextColorIndex = max(nextColorIndex, descriptor.colorIndex + 1)
            }
        }
        
        roiSamples = restored
        pendingROISample = nil
        roiColorCounter = max(nextColorIndex, restored.count)
    }
    
    private func resetSpectrumSelections() {
        spectrumSamples.removeAll()
        pendingSpectrumSample = nil
        spectrumColorCounter = 0
        roiSamples.removeAll()
        pendingROISample = nil
        roiColorCounter = 0
    }
}

struct LibraryExportProgressState: Equatable {
    enum Phase: Equatable {
        case running
        case success
        case failure
    }
    
    var phase: Phase
    var completed: Int
    var total: Int
    var message: String?
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completed) / Double(total)))
    }
}

enum AnalysisTool: String, CaseIterable, Identifiable {
    case none
    case spectrumGraph
    case spectrumGraphROI
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return ""
        case .spectrumGraph: return "График спектра"
        case .spectrumGraphROI: return "График спектра ROI"
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return ""
        case .spectrumGraph: return "chart.xyaxis.line"
        case .spectrumGraphROI: return "square.dashed.inset.filled"
        }
    }
}

struct SpectrumSample: Identifiable, Equatable {
    let id: UUID
    let pixelX: Int
    let pixelY: Int
    let values: [Double]
    let wavelengths: [Double]?
    let colorIndex: Int
    var displayName: String?
    
    init(
        id: UUID = UUID(),
        pixelX: Int,
        pixelY: Int,
        values: [Double],
        wavelengths: [Double]?,
        colorIndex: Int,
        displayName: String? = nil
    ) {
        self.id = id
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.values = values
        self.wavelengths = wavelengths
        self.colorIndex = colorIndex
        self.displayName = displayName
    }
    
    var nsColor: NSColor {
        let palette = SpectrumColorPalette.colors
        guard !palette.isEmpty else { return .systemPink }
        return palette[colorIndex % palette.count]
    }
}

enum SpectrumColorPalette {
    static let colors: [NSColor] = [
        .systemPink,
        .systemBlue,
        .systemGreen,
        .systemOrange,
        .systemPurple,
        .systemRed,
        .systemTeal,
        .systemYellow
    ]
}

struct SpectrumROIRect: Equatable {
    var minX: Int
    var minY: Int
    var width: Int
    var height: Int
    
    var maxX: Int { minX + width - 1 }
    var maxY: Int { minY + height - 1 }
    var area: Int { max(width, 0) * max(height, 0) }
    
    func clamped(maxWidth: Int, maxHeight: Int) -> SpectrumROIRect? {
        guard maxWidth > 0, maxHeight > 0 else { return nil }
        let lowerX = max(0, min(minX, maxWidth - 1))
        let lowerY = max(0, min(minY, maxHeight - 1))
        let upperX = max(0, min(maxX, maxWidth - 1))
        let upperY = max(0, min(maxY, maxHeight - 1))
        guard upperX >= lowerX, upperY >= lowerY else { return nil }
        return SpectrumROIRect(
            minX: lowerX,
            minY: lowerY,
            width: upperX - lowerX + 1,
            height: upperY - lowerY + 1
        )
    }
}

struct SpectrumROISample: Identifiable, Equatable {
    let id: UUID
    let rect: SpectrumROIRect
    let values: [Double]
    let wavelengths: [Double]?
    let colorIndex: Int
    var displayName: String?
    
    init(
        id: UUID = UUID(),
        rect: SpectrumROIRect,
        values: [Double],
        wavelengths: [Double]?,
        colorIndex: Int,
        displayName: String? = nil
    ) {
        self.id = id
        self.rect = rect
        self.values = values
        self.wavelengths = wavelengths
        self.colorIndex = colorIndex
        self.displayName = displayName
    }
    
    var nsColor: NSColor {
        let palette = SpectrumColorPalette.colors
        guard !palette.isEmpty else { return .systemPink }
        return palette[colorIndex % palette.count]
    }
    
    func trimmed(to range: ClosedRange<Int>) -> SpectrumROISample? {
        guard !values.isEmpty else { return nil }
        let maxIndex = values.count - 1
        guard range.lowerBound <= maxIndex else { return nil }
        let lower = max(0, min(range.lowerBound, maxIndex))
        let upper = max(lower, min(range.upperBound, maxIndex))
        guard lower <= upper else { return nil }
        
        let trimmedValues = Array(values[lower...upper])
        let trimmedWavelengths: [Double]? = {
            guard let wavelengths else { return nil }
            guard wavelengths.count > upper else { return nil }
            return Array(wavelengths[lower...upper])
        }()
        
        return SpectrumROISample(
            id: id,
            rect: rect,
            values: trimmedValues,
            wavelengths: trimmedWavelengths,
            colorIndex: colorIndex
        )
    }
}

enum WDVIAutoRegressionMethod: String, CaseIterable, Identifiable {
    case ols = "OLS (линейная регрессия)"
    case huber = "Huber (робастная)"
    
    var id: String { rawValue }
}

struct WDVIAutoEstimationConfig {
    var selectedROIIDs: Set<UUID>
    var lowerPercentile: Double
    var upperPercentile: Double
    var zScoreThreshold: Double
    var method: WDVIAutoRegressionMethod
}

enum WDVIEstimationError: Error {
    case message(String)
    
    var localizedDescription: String {
        switch self {
        case .message(let text): return text
        }
    }
}

enum SpectrumROIAggregationMode: String, CaseIterable, Identifiable {
    case mean
    case median
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .mean: return "Среднее"
        case .median: return "Медиана"
        }
    }
}
