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
    
    func open(url: URL) {
        cubeURL = url
        loadError = nil
        cube = nil
        currentChannel = 0
        channelCount = 0
        
        let result = ImageLoaderFactory.load(from: url)
        
        switch result {
        case .success(let hyperCube):
            cube = hyperCube
            
            let ext = url.pathExtension.lowercased()
            if ext == "mat" {
                layout = .auto
            } else if ext == "tif" || ext == "tiff" {
                layout = .hwc
            } else {
                layout = .auto
            }
            
            updateChannelCount()
            
            if wavelengths == nil {
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
}
