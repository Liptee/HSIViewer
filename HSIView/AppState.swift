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
        }
    }
    @Published var currentChannel: Double = 0
    @Published var channelCount: Int = 0
    @Published var loadError: String?
    
    @Published var viewMode: ViewMode = .gray
    @Published var colorSynthesisConfig: ColorSynthesisConfig = .default(channelCount: 0, wavelengths: nil)
    @Published var ndviRedTarget: String = "660"
    @Published var ndviNIRTarget: String = "840"
    @Published var ndviPalette: NDVIPalette = .classic
    @Published var ndviThreshold: Double = 0.3
    
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
    
    @Published var showExportView: Bool = false
    @Published var pendingExport: PendingExportInfo? = nil
    @Published var exportEntireLibrary: Bool = false
    
    @Published var isTrimMode: Bool = false
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    
    @Published var isBusy: Bool = false
    @Published var busyMessage: String?
    
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
    @Published var pcaPendingConfig: PCAVisualizationConfig?
    @Published var pcaRenderedImage: NSImage?
    @Published var isPCAApplying: Bool = false
    @Published var pcaProgressMessage: String?
    private var hasCustomColorSynthesisMapping: Bool = false
    private var ndviFallbackIndices: (red: Int, nir: Int) = (0, 0)
    private var processingClipboard: ProcessingClipboard? {
        didSet {
            hasProcessingClipboard = processingClipboard != nil
        }
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

    var defaultExportBaseName: String {
        guard let url = cubeURL else { return "hypercube" }
        let rawName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawName.isEmpty ? "hypercube" : rawName
    }
    
    func open(url: URL) {
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
        colorSynthesisConfig.pcaConfig.mapping = PCAComponentMapping(red: 0, green: 1, blue: 2).clamped(maxComponents: max(channelCount, 1))
    }
    
    private func clampColorSynthesisMapping() {
        colorSynthesisConfig.mapping = colorSynthesisConfig.mapping.clamped(maxChannelCount: channelCount)
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
    
    func ndviChannelIndices() -> (red: Int, nir: Int)? {
        guard channelCount > 1 else { return nil }
        let count = channelCount
        let fallbackRed = min(max(0, count / 3), count - 1)
        let fallbackNIR = max(fallbackRed + 1, count - 1)
        
        let redTarget = Double(ndviRedTarget.replacingOccurrences(of: ",", with: ".")) ?? 660
        let nirTarget = Double(ndviNIRTarget.replacingOccurrences(of: ",", with: ".")) ?? 840
        
        if let wl = wavelengths, wl.count >= count {
            let redIndex = closestIndex(in: wl, to: redTarget, limit: count) ?? fallbackRed
            let nirIndex = closestIndex(in: wl, to: nirTarget, limit: count) ?? fallbackNIR
            ndviFallbackIndices = (red: redIndex, nir: nirIndex)
            return (redIndex, nirIndex)
        } else {
            if ndviFallbackIndices == (0, 0) {
                ndviFallbackIndices = (red: fallbackRed, nir: fallbackNIR)
            }
            return ndviFallbackIndices
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
            return
        }
        wavelengths = lambda
    }
    
    func loadWavelengthsFromTXT(url: URL) {
        let result = WavelengthManager.loadFromFile(url: url)
        
        switch result {
        case .success(let values):
            wavelengths = values
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
    
    func toggleGraphPanel() {
        isGraphPanelExpanded.toggle()
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
            applyPipeline()
        }
    }
    
    func removeOperation(at index: Int) {
        guard index >= 0 && index < pipelineOperations.count else { return }
        pipelineOperations.remove(at: index)
        if pipelineAutoApply {
            applyPipeline()
        }
    }
    
    func moveOperation(from source: Int, to destination: Int) {
        guard source >= 0 && source < pipelineOperations.count else { return }
        guard destination >= 0 && destination < pipelineOperations.count else { return }
        guard source != destination else { return }
        
        let operation = pipelineOperations[source]
        pipelineOperations.remove(at: source)
        pipelineOperations.insert(operation, at: destination)
        if pipelineAutoApply {
            applyPipeline()
        }
    }
    
    func clearPipeline() {
        pipelineOperations.removeAll()
        applyPipeline()
    }
    
    func applyPipeline() {
        guard let original = originalCube else { return }
        
        if pipelineOperations.isEmpty {
            cube = original
            return
        }
        
        let operations = pipelineOperations
        beginBusy(message: "Применение пайплайна…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.processPipeline(original: original, operations: operations)
            DispatchQueue.main.async {
                self.cube = result ?? original
                self.endBusy()
            }
        }
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
        guard let original = originalCube else { return }
        
        let startChannel = Int(trimStart)
        let endChannel = Int(trimEnd)
        let currentChannels = channelCount
        
        guard startChannel >= 0, endChannel < currentChannels, startChannel <= endChannel else {
            loadError = "Некорректный диапазон обрезки"
            return
        }
        
        let layoutSnapshot = activeLayout
        let wavelengthsSnapshot = wavelengths
        let operationsSnapshot = pipelineOperations.map { operation -> PipelineOperation in
            var updatedOperation = operation
            updatedOperation.layout = .chw
            return updatedOperation
        }
        
        let baseRange: ClosedRange<Int> = spectralTrimRange ?? 0...max(currentChannels - 1, 0)
        let absoluteRange = (baseRange.lowerBound + startChannel)...(baseRange.lowerBound + endChannel)
        
        beginBusy(message: "Обрезка каналов…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            
            guard let trimmedCube = self.trimChannels(cube: original, layout: layoutSnapshot, from: startChannel, to: endChannel) else {
                DispatchQueue.main.async {
                    self.loadError = "Ошибка при обрезке каналов"
                    self.endBusy()
                }
                return
            }
            
            let trimmedWavelengths: [Double]? = {
                guard let wl = wavelengthsSnapshot, wl.count == currentChannels else { return nil }
                return Array(wl[startChannel...endChannel])
            }()
            
            let resultCube = self.processPipeline(original: trimmedCube, operations: operationsSnapshot)
            
            DispatchQueue.main.async {
                self.originalCube = trimmedCube
                self.layout = .chw
                for index in self.pipelineOperations.indices {
                    self.pipelineOperations[index].layout = self.layout
                }
                self.currentChannel = 0
                self.cube = resultCube ?? trimmedCube
                self.updateChannelCount()
                self.isTrimMode = false
                self.spectralTrimRange = absoluteRange
                self.loadError = nil
                self.suppressSpectrumRefresh = true
                if let trimmedWavelengths {
                    self.wavelengths = trimmedWavelengths
                }
                self.suppressSpectrumRefresh = false
                self.refreshSpectrumSamples()
                self.refreshROISamples()
                self.endBusy()
            }
        }
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
    
    private func processPipeline(original: HyperCube, operations: [PipelineOperation]) -> HyperCube? {
        guard !operations.isEmpty else { return original }
        
        var result: HyperCube? = original
        
        for operation in operations {
            guard let current = result else { break }
            result = operation.apply(to: current)
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
            } else if ext == "dat" || ext == "hdr" {
                layout = .hwc
            } else {
                layout = .auto
            }
            updateResolvedLayout()
            
            updateChannelCount()
            spectralTrimRange = nil
            
            if let enviWavelengths = hyperCube.wavelengths, !enviWavelengths.isEmpty {
                wavelengths = enviWavelengths
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
        
        let baseName = entry.url.deletingPathExtension().lastPathComponent
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
        restoreSession(from: snapshot)
    }
    
    private func restoreSession(from snapshot: CubeSessionSnapshot) {
        if let range = snapshot.spectralTrimRange {
            restoreTrim(range: range, snapshot: snapshot)
        } else {
            applySnapshot(snapshot)
            endBusy()
        }
    }
    
    private func restoreTrim(range: ClosedRange<Int>, snapshot: CubeSessionSnapshot) {
        guard let sourceCube = originalCube else {
            applySnapshot(snapshot)
            endBusy()
            return
        }
        let layoutSnapshot = activeLayout
        let availableChannels = sourceCube.channelCount(for: layoutSnapshot)
        guard range.lowerBound >= 0, range.upperBound < availableChannels else {
            applySnapshotWithoutTrim(snapshot)
            endBusy()
            return
        }
        
        busyMessage = "Восстановление обрезки…"
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            guard let trimmed = self.trimChannels(
                cube: sourceCube,
                layout: layoutSnapshot,
                from: range.lowerBound,
                to: range.upperBound
            ) else {
                DispatchQueue.main.async {
                    self.applySnapshotWithoutTrim(snapshot)
                    self.endBusy()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.originalCube = trimmed
                self.cube = trimmed
                self.spectralTrimRange = range
                self.updateChannelCount()
                self.applySnapshot(snapshot)
                self.endBusy()
            }
        }
    }
    
    private func applySnapshot(_ snapshot: CubeSessionSnapshot) {
        wavelengths = snapshot.wavelengths
        lambdaStart = snapshot.lambdaStart
        lambdaEnd = snapshot.lambdaEnd
        lambdaStep = snapshot.lambdaStep
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
            pcaConfig: clampedPCAConfig(snapshot.colorSynthesisConfig.pcaConfig)
        )
        ndviRedTarget = snapshot.ndviRedTarget
        ndviNIRTarget = snapshot.ndviNIRTarget
        ndviPalette = NDVIPalette(rawValue: snapshot.ndviPaletteRaw) ?? .classic
        ndviThreshold = snapshot.ndviThreshold
        pcaPendingConfig = nil
        pcaRenderedImage = nil
        hasCustomColorSynthesisMapping = true
        restoreSpectrumSamples(from: snapshot.spectrumSamples)
        restoreROISamples(from: snapshot.roiSamples)
        
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
        
        if pipelineAutoApply && !pipelineOperations.isEmpty {
            applyPipeline()
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
        sessionSnapshots[canonicalURL(url)] = snapshot
    }
    
    private func resetSessionState() {
        pipelineOperations.removeAll()
        pipelineAutoApply = true
        wavelengths = nil
        lambdaStart = "400"
        lambdaEnd = "1000"
        lambdaStep = ""
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
        ndviRedTarget = "660"
        ndviNIRTarget = "840"
        ndviPalette = .classic
        pcaPendingConfig = nil
        pcaRenderedImage = nil
        isPCAApplying = false
        pcaProgressMessage = nil
        hasCustomColorSynthesisMapping = false
        layout = .auto
        resetSpectrumSelections()
        spectrumSpatialSize = nil
        spectrumRotationTurns = pipelineRotationTurns()
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
                displayName: $0.displayName
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
                displayName: $0.displayName
            )
        }
        
        let clampedConfig = ColorSynthesisConfig(
            mode: colorSynthesisConfig.mode,
            mapping: colorSynthesisConfig.mapping.clamped(maxChannelCount: channelCount),
            pcaConfig: clampedPCAConfig(colorSynthesisConfig.pcaConfig)
        )
        
        return CubeSessionSnapshot(
            pipelineOperations: pipelineOperations,
            pipelineAutoApply: pipelineAutoApply,
            wavelengths: wavelengths,
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
            ndviRedTarget: ndviRedTarget,
            ndviNIRTarget: ndviNIRTarget,
            ndviPaletteRaw: ndviPalette.rawValue,
            ndviThreshold: ndviThreshold
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
        
        if let trimRange = snapshot.spectralTrimRange {
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
            workingCube = processPipeline(original: workingCube, operations: snapshot.pipelineOperations) ?? workingCube
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
        
        guard let newCube else {
            spectrumSpatialSize = nil
            spectrumRotationTurns = currentTurns
            return
        }
        
        let newSize = cubeSpatialSize(for: newCube)
        
        if let previousSize = spectrumSpatialSize,
           previousCube != nil {
            let delta = normalizedTurns(currentTurns - spectrumRotationTurns)
            if delta != 0 {
                rotateSpectrumSamples(by: delta, previousSize: previousSize)
                rotateROISamples(by: delta, previousSize: previousSize)
            }
        }
        
        spectrumSpatialSize = newSize ?? spectrumSpatialSize
        spectrumRotationTurns = currentTurns
    }
    
    private func cubeSpatialSize(for cube: HyperCube) -> (width: Int, height: Int)? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: activeLayout) else { return nil }
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
