import Foundation

enum ColorSynthesisMode: String, CaseIterable, Identifiable, Equatable {
    case trueColorRGB = "True Color RGB"
    case pcaVisualization = "PCA visualization"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .trueColorRGB:
            return "R=630нм, G=530нм, B=450нм"
        case .pcaVisualization:
            return "Информативная псевдо-цветность через PCA"
        }
    }
    
    var iconName: String {
        switch self {
        case .trueColorRGB:
            return "paintpalette"
        case .pcaVisualization:
            return "point.3.filled.trianglepath"
        }
    }
}

enum PCAComputeScope: String, CaseIterable, Identifiable {
    case fullImage = "Полный кадр"
    case roi = "ROI"
    case masked = "Маска"
    
    var id: String { rawValue }
}

enum PCAPreprocess: String, CaseIterable, Identifiable {
    case none = "Без предобработки"
    case meanCenter = "Mean-center"
    case standardize = "Standardize"
    case log = "Log(x+1)"
    
    var id: String { rawValue }
}

struct PCAComponentMapping: Equatable {
    var red: Int
    var green: Int
    var blue: Int
    
    func clamped(maxComponents: Int) -> PCAComponentMapping {
        guard maxComponents > 0 else { return self }
        let maxIndex = maxComponents - 1
        return PCAComponentMapping(
            red: max(0, min(red, maxIndex)),
            green: max(0, min(green, maxIndex)),
            blue: max(0, min(blue, maxIndex))
        )
    }
}

struct PCAVisualizationConfig: Equatable {
    var computeScope: PCAComputeScope
    var preprocess: PCAPreprocess
    var mapping: PCAComponentMapping
    var lockBasis: Bool
    var clipTopPercent: Double
    var selectedROI: UUID?
    
    // Кэш вычисленной базы
    var basis: [[Double]]?  // каждая компонента размера C
    var mean: [Double]?
    var std: [Double]?
    var explainedVariance: [Double]?
    var sourceCubeID: UUID?
    var clipUpper: [Double]?
    
    static func `default`() -> PCAVisualizationConfig {
        PCAVisualizationConfig(
            computeScope: .fullImage,
            preprocess: .meanCenter,
            mapping: PCAComponentMapping(red: 0, green: 1, blue: 2),
            lockBasis: false,
            clipTopPercent: 0.5,
            selectedROI: nil,
            basis: nil,
            mean: nil,
            std: nil,
            explainedVariance: nil,
            sourceCubeID: nil,
            clipUpper: nil
        )
    }
}

struct RGBChannelMapping: Equatable {
    var red: Int
    var green: Int
    var blue: Int
    
    static func defaultMapping(channelCount: Int, wavelengths: [Double]?) -> RGBChannelMapping {
        let maxIndex = max(channelCount - 1, 0)
        guard channelCount > 0 else {
            return RGBChannelMapping(red: 0, green: 0, blue: 0)
        }
        
        if let wavelengths, wavelengths.count >= channelCount {
            return RGBChannelMapping(
                red: closestIndex(in: wavelengths, to: 630.0, limit: channelCount, fallback: min(2, maxIndex)),
                green: closestIndex(in: wavelengths, to: 530.0, limit: channelCount, fallback: min(1, maxIndex)),
                blue: closestIndex(in: wavelengths, to: 450.0, limit: channelCount, fallback: min(0, maxIndex))
            )
        }
        
        return RGBChannelMapping(
            red: min(2, maxIndex),
            green: min(1, maxIndex),
            blue: min(0, maxIndex)
        )
    }
    
    func clamped(maxChannelCount: Int) -> RGBChannelMapping {
        guard maxChannelCount > 0 else {
            return self
        }
        let maxIndex = maxChannelCount - 1
        return RGBChannelMapping(
            red: max(0, min(red, maxIndex)),
            green: max(0, min(green, maxIndex)),
            blue: max(0, min(blue, maxIndex))
        )
    }
    
    func isValid(maxChannelCount: Int) -> Bool {
        guard maxChannelCount > 0 else { return false }
        let maxIndex = maxChannelCount - 1
        return (0...maxIndex).contains(red)
            && (0...maxIndex).contains(green)
            && (0...maxIndex).contains(blue)
    }
    
    private static func closestIndex(in wavelengths: [Double], to target: Double, limit: Int, fallback: Int) -> Int {
        var bestIdx = fallback
        var bestDist = Double.greatestFiniteMagnitude
        
        for i in 0..<limit {
            let d = abs(wavelengths[i] - target)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        
        return bestIdx
    }
}

struct ColorSynthesisConfig: Equatable {
    var mode: ColorSynthesisMode
    var mapping: RGBChannelMapping
    var pcaConfig: PCAVisualizationConfig
    
    static func `default`(channelCount: Int, wavelengths: [Double]?) -> ColorSynthesisConfig {
        ColorSynthesisConfig(
            mode: .trueColorRGB,
            mapping: .defaultMapping(channelCount: channelCount, wavelengths: wavelengths),
            pcaConfig: .default()
        )
    }
}
