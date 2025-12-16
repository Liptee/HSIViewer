import Foundation
import AppKit

final class AppState: ObservableObject {
    @Published var cube: HyperCube?
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
    
    @Published var wavelengths: [Double]?
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
    @Published var spectrumData: SpectrumData?
    
    private var originalCube: HyperCube?
    private let processingQueue = DispatchQueue(label: "com.hsiview.processing", qos: .userInitiated)
    private var resolvedAutoLayout: CubeLayout = .auto
    private var sessionSnapshots: [URL: CubeSessionSnapshot] = [:]
    private var pendingSessionRestore: CubeSessionSnapshot?
    private var spectralTrimRange: ClosedRange<Int>?
    private var libraryExportDismissWorkItem: DispatchWorkItem?
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
            return
        }
        
        channelCount = cube.channelCount(for: activeLayout)
        
        if channelCount <= 0 {
            currentChannel = 0
        } else if Int(currentChannel) >= channelCount {
            currentChannel = Double(channelCount - 1)
        }
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
            spectrumData = nil
        } else {
            activeAnalysisTool = tool
            if tool == .spectrumGraph {
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
        
        spectrumData = SpectrumData(
            pixelX: pixelX,
            pixelY: pixelY,
            values: spectrum,
            wavelengths: wavelengths
        )
        
        if !isGraphPanelExpanded {
            isGraphPanelExpanded = true
        }
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
                if let trimmedWavelengths {
                    self.wavelengths = trimmedWavelengths
                }
                self.currentChannel = 0
                self.cube = resultCube ?? trimmedCube
                self.updateChannelCount()
                self.isTrimMode = false
                self.spectralTrimRange = absoluteRange
                self.loadError = nil
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
            baseName: baseName
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
        layout = .auto
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
            imageOffset: imageOffset
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
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return ""
        case .spectrumGraph: return "График спектра"
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return ""
        case .spectrumGraph: return "chart.xyaxis.line"
        }
    }
}

struct SpectrumData: Equatable {
    let pixelX: Int
    let pixelY: Int
    let values: [Double]
    let wavelengths: [Double]?
}
