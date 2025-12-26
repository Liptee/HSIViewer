import Foundation

enum ColorSynthesisMode: String, CaseIterable, Identifiable, Equatable {
    case trueColorRGB = "True Color RGB"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .trueColorRGB:
            return "R=630нм, G=530нм, B=450нм"
        }
    }
    
    var iconName: String {
        switch self {
        case .trueColorRGB:
            return "paintpalette"
        }
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
    
    static func `default`(channelCount: Int, wavelengths: [Double]?) -> ColorSynthesisConfig {
        ColorSynthesisConfig(
            mode: .trueColorRGB,
            mapping: .defaultMapping(channelCount: channelCount, wavelengths: wavelengths)
        )
    }
}
