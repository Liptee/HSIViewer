import Foundation

struct NormalizationResult {
    let normalized: [Double]
    let min: Double
    let max: Double
}

enum NormalizationType {
    case minMax
    case zScore
    case percentile(lower: Double, upper: Double)
}

class DataNormalizer {
    static func normalize(_ data: [Double], type: NormalizationType = .minMax) -> NormalizationResult {
        switch type {
        case .minMax:
            return normalizeMinMax(data)
        case .zScore:
            return normalizeZScore(data)
        case .percentile(let lower, let upper):
            return normalizePercentile(data, lower: lower, upper: upper)
        }
    }
    
    private static func normalizeMinMax(_ data: [Double]) -> NormalizationResult {
        guard !data.isEmpty else {
            return NormalizationResult(normalized: [], min: 0, max: 0)
        }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        
        for val in data {
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
        }
        
        if maxVal == minVal {
            maxVal = minVal + 1.0
        }
        
        let normalized = data.map { ($0 - minVal) / (maxVal - minVal) }
        return NormalizationResult(normalized: normalized, min: minVal, max: maxVal)
    }
    
    private static func normalizeZScore(_ data: [Double]) -> NormalizationResult {
        guard !data.isEmpty else {
            return NormalizationResult(normalized: [], min: 0, max: 0)
        }
        
        let mean = data.reduce(0, +) / Double(data.count)
        let variance = data.map { pow($0 - mean, 2) }.reduce(0, +) / Double(data.count)
        let stdDev = sqrt(variance)
        
        let normalized = data.map { stdDev > 0 ? ($0 - mean) / stdDev : 0 }
        
        let minVal = normalized.min() ?? 0
        let maxVal = normalized.max() ?? 1
        
        return NormalizationResult(normalized: normalized, min: minVal, max: maxVal)
    }
    
    private static func normalizePercentile(_ data: [Double], lower: Double, upper: Double) -> NormalizationResult {
        guard !data.isEmpty else {
            return NormalizationResult(normalized: [], min: 0, max: 0)
        }
        
        let sorted = data.sorted()
        let lowerIdx = Int(Double(sorted.count) * lower / 100.0)
        let upperIdx = Int(Double(sorted.count) * upper / 100.0)
        
        let minVal = sorted[max(0, min(lowerIdx, sorted.count - 1))]
        let maxVal = sorted[max(0, min(upperIdx, sorted.count - 1))]
        
        let range = maxVal - minVal
        let normalized = data.map { val in
            if range > 0 {
                return max(0, min(1, (val - minVal) / range))
            }
            return 0.5
        }
        
        return NormalizationResult(normalized: normalized, min: minVal, max: maxVal)
    }
    
    static func toUInt8(_ normalized: [Double]) -> [UInt8] {
        return normalized.map { val in
            let clamped = max(0.0, min(1.0, val))
            return UInt8((clamped * 255.0).rounded())
        }
    }
}

