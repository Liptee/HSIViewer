import Foundation

enum CubeNormalizationType: String, CaseIterable, Identifiable {
    case none = "Без нормализации"
    case minMax = "Min-Max (0-1)"
    case minMaxCustom = "Min-Max (custom)"
    case percentile = "Percentile"
    case zScore = "Z-Score"
    case log = "Log"
    case sqrt = "Sqrt"
    
    var id: String { rawValue }
    
    var hasParameters: Bool {
        switch self {
        case .none, .minMax, .zScore, .log, .sqrt:
            return false
        case .minMaxCustom, .percentile:
            return true
        }
    }
    
    var description: String {
        switch self {
        case .none:
            return "Исходные данные без преобразований"
        case .minMax:
            return "Линейная нормализация в диапазон [0, 1]"
        case .minMaxCustom:
            return "Линейная нормализация в заданный диапазон [min, max]"
        case .percentile:
            return "Обрезка выбросов по процентилям"
        case .zScore:
            return "Стандартизация: (x - mean) / std"
        case .log:
            return "Логарифмическая: log(x + 1)"
        case .sqrt:
            return "Квадратный корень: sqrt(x)"
        }
    }
}

struct CubeNormalizationParameters {
    var minValue: Double = 0.0
    var maxValue: Double = 1.0
    var lowerPercentile: Double = 2.0
    var upperPercentile: Double = 98.0
    
    static let `default` = CubeNormalizationParameters()
}

class CubeNormalizer {
    static func apply(
        _ type: CubeNormalizationType,
        to cube: HyperCube,
        parameters: CubeNormalizationParameters,
        preserveDataType: Bool = false
    ) -> HyperCube? {
        let totalElements = cube.totalElements
        guard totalElements > 0 else { return nil }
        
        switch type {
        case .none:
            return cube
            
        case .minMax:
            return applyMinMax(cube, targetMin: 0.0, targetMax: 1.0, preserveDataType: preserveDataType)
            
        case .minMaxCustom:
            return applyMinMax(cube, targetMin: parameters.minValue, targetMax: parameters.maxValue, preserveDataType: preserveDataType)
            
        case .percentile:
            return applyPercentile(cube, lower: parameters.lowerPercentile, upper: parameters.upperPercentile)
            
        case .zScore:
            return applyZScore(cube)
            
        case .log:
            return applyLog(cube)
            
        case .sqrt:
            return applySqrt(cube)
        }
    }
    
    private static func applyMinMax(_ cube: HyperCube, targetMin: Double, targetMax: Double, preserveDataType: Bool = false) -> HyperCube? {
        let stats = cube.statistics()
        let dataMin = stats.min
        let dataMax = stats.max
        
        guard dataMax > dataMin else { return cube }
        
        let range = dataMax - dataMin
        let targetRange = targetMax - targetMin
        
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            let normalized = (value - dataMin) / range
            return targetMin + normalized * targetRange
        }
        
        let preserveType = preserveDataType ? shouldPreserveType(cube: cube, normalizedData: normalizedData, targetMin: targetMin, targetMax: targetMax) : nil
        guard let storage = wrapInStorage(normalizedData, preserveType: preserveType) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [MinMax]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func applyPercentile(_ cube: HyperCube, lower: Double, upper: Double) -> HyperCube? {
        var allValues = [Double]()
        allValues.reserveCapacity(cube.totalElements)
        
        for idx in 0..<cube.totalElements {
            allValues.append(cube.storage.getValue(at: idx))
        }
        
        allValues.sort()
        
        guard allValues.count > 0 else { return cube }
        
        let lowerIdx = max(0, min(allValues.count - 1, Int(Double(allValues.count - 1) * lower / 100.0)))
        let upperIdx = max(0, min(allValues.count - 1, Int(Double(allValues.count - 1) * upper / 100.0)))
        
        let lowerValue = allValues[lowerIdx]
        let upperValue = allValues[upperIdx]
        
        guard upperValue > lowerValue else { return cube }
        
        let range = upperValue - lowerValue
        
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            let clamped = max(lowerValue, min(upperValue, value))
            return (clamped - lowerValue) / range
        }
        
        guard let storage = wrapInStorage(normalizedData) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Percentile]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func applyZScore(_ cube: HyperCube) -> HyperCube? {
        let stats = cube.statistics()
        let mean = stats.mean
        let std = stats.stdDev
        
        guard std > 0 else { return cube }
        
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            return (value - mean) / std
        }
        
        guard let storage = wrapInStorage(normalizedData) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Z-Score]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func applyLog(_ cube: HyperCube) -> HyperCube? {
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            return log(max(0, value) + 1.0)
        }
        
        guard let storage = wrapInStorage(normalizedData) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Log]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func applySqrt(_ cube: HyperCube) -> HyperCube? {
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            return sqrt(max(0, value))
        }
        
        guard let storage = wrapInStorage(normalizedData) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Sqrt]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func shouldPreserveType(cube: HyperCube, normalizedData: [Double], targetMin: Double, targetMax: Double) -> DataType? {
        let originalType = cube.originalDataType
        
        switch originalType {
        case .uint8:
            if targetMin >= 0 && targetMax <= 255 {
                return .uint8
            }
        case .uint16:
            if targetMin >= 0 && targetMax <= 65535 {
                return .uint16
            }
        case .int8:
            if targetMin >= -128 && targetMax <= 127 {
                return .int8
            }
        case .int16:
            if targetMin >= -32768 && targetMax <= 32767 {
                return .int16
            }
        case .int32:
            if targetMin >= Double(Int32.min) && targetMax <= Double(Int32.max) {
                return .int32
            }
        case .float32:
            return .float32
        case .float64:
            return .float64
        case .unknown:
            return nil
        }
        
        return nil
    }
    
    private static func wrapInStorage(_ data: [Double], preserveType: DataType? = nil) -> DataStorage? {
        guard let targetType = preserveType else {
            return .float64(data)
        }
        
        switch targetType {
        case .float64:
            return .float64(data)
            
        case .float32:
            return .float32(data.map { Float($0) })
            
        case .int8:
            return .int8(data.map { Int8(clamping: Int($0.rounded())) })
            
        case .int16:
            return .int16(data.map { Int16(clamping: Int($0.rounded())) })
            
        case .int32:
            return .int32(data.map { Int32(clamping: Int($0.rounded())) })
            
        case .uint8:
            return .uint8(data.map { UInt8(clamping: Int($0.rounded())) })
            
        case .uint16:
            return .uint16(data.map { UInt16(clamping: Int($0.rounded())) })
            
        case .unknown:
            return .float64(data)
        }
    }
}


