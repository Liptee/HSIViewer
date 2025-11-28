import Foundation
import AppKit

final class AppState: ObservableObject {
    @Published var cube: HyperCube?
    @Published var cubeURL: URL?
    @Published var layout: CubeLayout = .auto
    @Published var currentChannel: Double = 0
    @Published var channelCount: Int = 0
    @Published var loadError: String?
    
    @Published var viewMode: ViewMode = .gray
    
    @Published var wavelengths: [Double]?
    @Published var lambdaStart: String = "400"
    @Published var lambdaEnd: String = ""
    @Published var lambdaStep: String = "1"
    
    @Published var zoomScale: CGFloat = 1.0
    @Published var imageOffset: CGSize = .zero
    
    @Published var normalizationType: CubeNormalizationType = .none
    @Published var normalizationParams: CubeNormalizationParameters = .default
    
    @Published var autoScaleOnTypeConversion: Bool = true
    
    @Published var pipelineOperations: [PipelineOperation] = []
    @Published var pipelineAutoApply: Bool = true
    
    private var originalCube: HyperCube?
    
    var displayCube: HyperCube? {
        guard let original = originalCube else { return cube }
        return cube
    }
    
    func open(url: URL) {
        cubeURL = url
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0
        resetZoom()
        pipelineOperations.removeAll()
        
        let result = ImageLoaderFactory.load(from: url)
        
        switch result {
        case .success(let hyperCube):
            originalCube = hyperCube
            cube = hyperCube
            normalizationType = .none
            normalizationParams = .default
            
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
    }
    
    func updateChannelCount() {
        guard let cube = cube else {
            channelCount = 0
            currentChannel = 0
            return
        }
        
        channelCount = cube.channelCount(for: layout)
        
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
              let step = Double(lambdaStep.replacingOccurrences(of: ",", with: ".")),
              step > 0 else {
            loadError = "Некорректные параметры λ (start/step)"
            return
        }
        
        let end = WavelengthManager.calculateEnd(start: start, channels: channels, step: step)
        lambdaEnd = String(format: "%.4g", end)
        
        wavelengths = WavelengthManager.generate(start: start, channels: channels, step: step)
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
        let operation = PipelineOperation(type: type)
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
        if pipelineAutoApply {
            applyPipeline()
        }
    }
    
    func applyPipeline() {
        guard let original = originalCube else { return }
        
        if pipelineOperations.isEmpty {
            cube = original
            return
        }
        
        var result: HyperCube? = original
        
        for operation in pipelineOperations {
            guard let current = result else { break }
            result = operation.apply(to: current)
        }
        
        cube = result ?? original
    }
}
