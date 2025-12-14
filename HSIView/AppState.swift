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
    
    @Published var isTrimMode: Bool = false
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    
    @Published var isBusy: Bool = false
    @Published var busyMessage: String?
    
    @Published var pendingMatSelection: MatSelectionRequest?
    
    private var originalCube: HyperCube?
    private let processingQueue = DispatchQueue(label: "com.hsiview.processing", qos: .userInitiated)
    private var resolvedAutoLayout: CubeLayout = .auto
    
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
        cubeURL = url
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0
        resetZoom()
        pipelineOperations.removeAll()
        isTrimMode = false
        pendingMatSelection = nil
        
        if handleMatOpenIfNeeded(for: url) {
            return
        }
        
        beginBusy(message: "Импорт гиперкуба…")
        
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = ImageLoaderFactory.load(from: url)
            DispatchQueue.main.async {
                self.handleLoadResult(result: result, url: url)
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
            
        case .failure(let error):
            loadError = error.localizedDescription
        }
        
        endBusy()
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
}
