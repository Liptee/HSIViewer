import Foundation

enum CubeNormalizationType: String, CaseIterable, Identifiable {
    case none = "Без нормализации"
    case minMax = "Min-Max (0-1)"
    case minMaxCustom = "Min-Max (custom)"
    case manualRange = "Диапазон (ручной)"
    case percentile = "Percentile"
    case zScore = "Z-Score"
    case log = "Log"
    case sqrt = "Sqrt"
    
    var id: String { rawValue }
    
    var hasParameters: Bool {
        switch self {
        case .none, .minMax, .zScore, .log, .sqrt:
            return false
        case .minMaxCustom, .percentile, .manualRange:
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
        case .manualRange:
            return "Линейное преобразование из указанного диапазона в новый диапазон"
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

enum NormalizationComputationPrecision: String, CaseIterable, Identifiable {
    case float32 = "Float32"
    case float64 = "Float64"
    
    var id: String { rawValue }
}

struct CubeNormalizationParameters {
    var minValue: Double = 0.0
    var maxValue: Double = 1.0
    var lowerPercentile: Double = 2.0
    var upperPercentile: Double = 98.0
    var sourceMin: Double = 0.0
    var sourceMax: Double = 1.0
    var targetMin: Double = 0.0
    var targetMax: Double = 1.0
    var computePrecision: NormalizationComputationPrecision = .float64
    
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
            return applyMinMax(
                cube,
                targetMin: 0.0,
                targetMax: 1.0,
                preserveDataType: preserveDataType,
                computePrecision: parameters.computePrecision
            )
            
        case .minMaxCustom:
            return applyMinMax(
                cube,
                targetMin: parameters.minValue,
                targetMax: parameters.maxValue,
                preserveDataType: preserveDataType,
                computePrecision: parameters.computePrecision
            )
            
        case .manualRange:
            return applyManualRange(
                cube,
                sourceMin: parameters.sourceMin,
                sourceMax: parameters.sourceMax,
                targetMin: parameters.targetMin,
                targetMax: parameters.targetMax,
                preserveDataType: preserveDataType,
                computePrecision: parameters.computePrecision
            )
            
        case .percentile:
            return applyPercentile(
                cube,
                lower: parameters.lowerPercentile,
                upper: parameters.upperPercentile,
                computePrecision: parameters.computePrecision
            )
            
        case .zScore:
            return applyZScore(cube, computePrecision: parameters.computePrecision)
            
        case .log:
            return applyLog(cube, computePrecision: parameters.computePrecision)
            
        case .sqrt:
            return applySqrt(cube, computePrecision: parameters.computePrecision)
        }
    }
    
    private static func applyMinMax(
        _ cube: HyperCube,
        targetMin: Double,
        targetMax: Double,
        preserveDataType: Bool = false,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        let useFloat32 = computePrecision == .float32
        if useFloat32 {
            var minVal = Float.greatestFiniteMagnitude
            var maxVal = -Float.greatestFiniteMagnitude
            
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                if value < minVal { minVal = value }
                if value > maxVal { maxVal = value }
            }
            
            guard maxVal > minVal else { return cube }
            
            let range = maxVal - minVal
            let targetMinF = Float(targetMin)
            let targetRange = Float(targetMax - targetMin)
            
            var output = [Float](repeating: 0, count: cube.totalElements)
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                let normalized = (value - minVal) / range
                output[idx] = targetMinF + normalized * targetRange
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [MinMax]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
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
    
    private static func applyManualRange(
        _ cube: HyperCube,
        sourceMin: Double,
        sourceMax: Double,
        targetMin: Double,
        targetMax: Double,
        preserveDataType: Bool = false,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        let useFloat32 = computePrecision == .float32
        if useFloat32 {
            guard sourceMax > sourceMin else { return cube }
            
            let sourceMinF = Float(sourceMin)
            let sourceMaxF = Float(sourceMax)
            let sourceRange = sourceMaxF - sourceMinF
            let targetMinF = Float(targetMin)
            let targetRange = Float(targetMax - targetMin)
            
            var output = [Float](repeating: 0, count: cube.totalElements)
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                let clamped = max(sourceMinF, min(sourceMaxF, value))
                let normalized = (clamped - sourceMinF) / sourceRange
                output[idx] = targetMinF + normalized * targetRange
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [ManualRange]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
        guard sourceMax > sourceMin else { return cube }
        
        let sourceRange = sourceMax - sourceMin
        let targetRange = targetMax - targetMin
        
        let normalizedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            let clamped = max(sourceMin, min(sourceMax, value))
            let normalized = (clamped - sourceMin) / sourceRange
            return targetMin + normalized * targetRange
        }
        
        let preserveType = preserveDataType ? shouldPreserveType(cube: cube, normalizedData: normalizedData, targetMin: targetMin, targetMax: targetMax) : nil
        guard let storage = wrapInStorage(normalizedData, preserveType: preserveType) else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [ManualRange]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func applyPercentile(
        _ cube: HyperCube,
        lower: Double,
        upper: Double,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        if computePrecision == .float32 {
            var allValues = [Float]()
            allValues.reserveCapacity(cube.totalElements)
            
            for idx in 0..<cube.totalElements {
                allValues.append(Float(cube.storage.getValue(at: idx)))
            }
            
            allValues.sort()
            
            guard !allValues.isEmpty else { return cube }
            
            let lowerIdx = max(0, min(allValues.count - 1, Int(Double(allValues.count - 1) * lower / 100.0)))
            let upperIdx = max(0, min(allValues.count - 1, Int(Double(allValues.count - 1) * upper / 100.0)))
            
            let lowerValue = allValues[lowerIdx]
            let upperValue = allValues[upperIdx]
            
            guard upperValue > lowerValue else { return cube }
            
            let range = upperValue - lowerValue
            var output = [Float](repeating: 0, count: cube.totalElements)
            
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                let clamped = max(lowerValue, min(upperValue, value))
                output[idx] = (clamped - lowerValue) / range
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Percentile]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
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
    
    private static func applyZScore(
        _ cube: HyperCube,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        if computePrecision == .float32 {
            let total = cube.totalElements
            guard total > 0 else { return cube }
            
            var sum: Float = 0
            for idx in 0..<total {
                sum += Float(cube.storage.getValue(at: idx))
            }
            
            let mean = sum / Float(total)
            var varianceSum: Float = 0
            for idx in 0..<total {
                let diff = Float(cube.storage.getValue(at: idx)) - mean
                varianceSum += diff * diff
            }
            let variance = varianceSum / Float(total)
            let std = sqrt(variance)
            
            guard std > 0 else { return cube }
            
            var output = [Float](repeating: 0, count: total)
            for idx in 0..<total {
                let value = Float(cube.storage.getValue(at: idx))
                output[idx] = (value - mean) / std
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Z-Score]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
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
    
    private static func applyLog(
        _ cube: HyperCube,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        if computePrecision == .float32 {
            var output = [Float](repeating: 0, count: cube.totalElements)
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                output[idx] = log(max(0, value) + 1.0)
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Log]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
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
    
    private static func applySqrt(
        _ cube: HyperCube,
        computePrecision: NormalizationComputationPrecision
    ) -> HyperCube? {
        if computePrecision == .float32 {
            var output = [Float](repeating: 0, count: cube.totalElements)
            for idx in 0..<cube.totalElements {
                let value = Float(cube.storage.getValue(at: idx))
                output[idx] = sqrt(max(0, value))
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Sqrt]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
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
    
    static func applyChannelwise(
        _ type: CubeNormalizationType,
        to cube: HyperCube,
        parameters: CubeNormalizationParameters,
        preserveDataType: Bool = false
    ) -> HyperCube? {
        guard type != .none else { return cube }
        
        let (height, width, channels) = cube.dims
        guard channels > 0 else { return nil }
        
        let totalElements = height * width * channels
        let useFloat32 = parameters.computePrecision == .float32
        if useFloat32 {
            var allData = [Float](repeating: 0.0, count: totalElements)
            
            for ch in 0..<channels {
                var channelData = [Float]()
                channelData.reserveCapacity(height * width)
                
                for h in 0..<height {
                    for w in 0..<width {
                        let idx = cube.linearIndex(i0: h, i1: w, i2: ch)
                        let value = Float(cube.getValue(at: idx))
                        channelData.append(value)
                    }
                }
                
                let normalizedChannel: [Float]
                switch type {
                case .none:
                    normalizedChannel = channelData
                    
                case .minMax:
                    normalizedChannel = normalizeChannelMinMax(channelData, targetMin: 0.0, targetMax: 1.0)
                    
                case .minMaxCustom:
                    normalizedChannel = normalizeChannelMinMax(channelData, targetMin: Float(parameters.minValue), targetMax: Float(parameters.maxValue))
                    
                case .percentile:
                    normalizedChannel = normalizeChannelPercentile(channelData, lower: Float(parameters.lowerPercentile), upper: Float(parameters.upperPercentile))
                    
                case .zScore:
                    normalizedChannel = normalizeChannelZScore(channelData)
                    
                case .log:
                    normalizedChannel = normalizeChannelLog(channelData)
                    
                case .sqrt:
                    normalizedChannel = normalizeChannelSqrt(channelData)
                    
                case .manualRange:
                    normalizedChannel = normalizeChannelManualRange(
                        channelData,
                        sourceMin: Float(parameters.sourceMin),
                        sourceMax: Float(parameters.sourceMax),
                        targetMin: Float(parameters.targetMin),
                        targetMax: Float(parameters.targetMax)
                    )
                }
                
                for h in 0..<height {
                    for w in 0..<width {
                        let idx = cube.linearIndex(i0: h, i1: w, i2: ch)
                        let channelIdx = h * width + w
                        allData[idx] = normalizedChannel[channelIdx]
                    }
                }
            }
            
            return HyperCube(
                dims: cube.dims,
                storage: .float32(allData),
                sourceFormat: cube.sourceFormat,
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
        var allData = [Double](repeating: 0.0, count: totalElements)
        
        for ch in 0..<channels {
            var channelData = [Double]()
            channelData.reserveCapacity(height * width)
            
            for h in 0..<height {
                for w in 0..<width {
                    let idx = cube.linearIndex(i0: h, i1: w, i2: ch)
                    let value = cube.getValue(at: idx)
                    channelData.append(value)
                }
            }
            
            let normalizedChannel: [Double]
            switch type {
            case .none:
                normalizedChannel = channelData
                
            case .minMax:
                normalizedChannel = normalizeChannelMinMax(channelData, targetMin: 0.0, targetMax: 1.0)
                
            case .minMaxCustom:
                normalizedChannel = normalizeChannelMinMax(channelData, targetMin: parameters.minValue, targetMax: parameters.maxValue)
                
            case .percentile:
                normalizedChannel = normalizeChannelPercentile(channelData, lower: parameters.lowerPercentile, upper: parameters.upperPercentile)
                
            case .zScore:
                normalizedChannel = normalizeChannelZScore(channelData)
                
            case .log:
                normalizedChannel = normalizeChannelLog(channelData)
                
            case .sqrt:
                normalizedChannel = normalizeChannelSqrt(channelData)
                
            case .manualRange:
                normalizedChannel = normalizeChannelManualRange(
                    channelData,
                    sourceMin: parameters.sourceMin,
                    sourceMax: parameters.sourceMax,
                    targetMin: parameters.targetMin,
                    targetMax: parameters.targetMax
                )
            }
            
            for h in 0..<height {
                for w in 0..<width {
                    let idx = cube.linearIndex(i0: h, i1: w, i2: ch)
                    let channelIdx = h * width + w
                    allData[idx] = normalizedChannel[channelIdx]
                }
            }
        }
        
        let storage: DataStorage
        if preserveDataType, let preserveType = shouldPreserveChannelwise(cube: cube, normalizedData: allData) {
            storage = wrapInStorage(allData, preserveType: preserveType) ?? .float64(allData)
        } else {
            storage = .float64(allData)
        }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat,
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func normalizeChannelMinMax(_ data: [Double], targetMin: Double, targetMax: Double) -> [Double] {
        guard !data.isEmpty else { return data }
        
        let channelMin = data.min() ?? 0.0
        let channelMax = data.max() ?? 1.0
        let range = channelMax - channelMin
        
        guard range > 1e-10 else {
            return data.map { _ in targetMin }
        }
        
        return data.map { value in
            let normalized = (value - channelMin) / range
            return targetMin + normalized * (targetMax - targetMin)
        }
    }

    private static func normalizeChannelMinMax(_ data: [Float], targetMin: Float, targetMax: Float) -> [Float] {
        guard !data.isEmpty else { return data }
        
        let channelMin = data.min() ?? 0.0
        let channelMax = data.max() ?? 1.0
        let range = channelMax - channelMin
        
        guard range > 1e-10 else {
            return data.map { _ in targetMin }
        }
        
        return data.map { value in
            let normalized = (value - channelMin) / range
            return targetMin + normalized * (targetMax - targetMin)
        }
    }
    
    private static func normalizeChannelPercentile(_ data: [Double], lower: Double, upper: Double) -> [Double] {
        guard !data.isEmpty else { return data }
        
        var sorted = data.sorted()
        let count = sorted.count
        
        let lowerIdx = max(0, min(count - 1, Int(Double(count - 1) * lower / 100.0)))
        let upperIdx = max(0, min(count - 1, Int(Double(count - 1) * upper / 100.0)))
        
        let lowerValue = sorted[lowerIdx]
        let upperValue = sorted[upperIdx]
        let range = upperValue - lowerValue
        
        guard range > 1e-10 else {
            return data.map { _ in 0.0 }
        }
        
        return data.map { value in
            let clamped = max(lowerValue, min(upperValue, value))
            return (clamped - lowerValue) / range
        }
    }

    private static func normalizeChannelPercentile(_ data: [Float], lower: Float, upper: Float) -> [Float] {
        guard !data.isEmpty else { return data }
        
        var sorted = data.sorted()
        let count = sorted.count
        
        let lowerIdx = max(0, min(count - 1, Int(Double(count - 1) * Double(lower) / 100.0)))
        let upperIdx = max(0, min(count - 1, Int(Double(count - 1) * Double(upper) / 100.0)))
        
        let lowerValue = sorted[lowerIdx]
        let upperValue = sorted[upperIdx]
        let range = upperValue - lowerValue
        
        guard range > 1e-10 else {
            return data.map { _ in 0.0 }
        }
        
        return data.map { value in
            let clamped = max(lowerValue, min(upperValue, value))
            return (clamped - lowerValue) / range
        }
    }
    
    private static func normalizeChannelManualRange(
        _ data: [Double],
        sourceMin: Double,
        sourceMax: Double,
        targetMin: Double,
        targetMax: Double
    ) -> [Double] {
        guard sourceMax > sourceMin else { return data }
        let sourceRange = sourceMax - sourceMin
        let targetRange = targetMax - targetMin
        
        return data.map { value in
            let clamped = max(sourceMin, min(sourceMax, value))
            let normalized = (clamped - sourceMin) / sourceRange
            return targetMin + normalized * targetRange
        }
    }

    private static func normalizeChannelManualRange(
        _ data: [Float],
        sourceMin: Float,
        sourceMax: Float,
        targetMin: Float,
        targetMax: Float
    ) -> [Float] {
        guard sourceMax > sourceMin else { return data }
        let sourceRange = sourceMax - sourceMin
        let targetRange = targetMax - targetMin
        
        return data.map { value in
            let clamped = max(sourceMin, min(sourceMax, value))
            let normalized = (clamped - sourceMin) / sourceRange
            return targetMin + normalized * targetRange
        }
    }
    
    private static func normalizeChannelZScore(_ data: [Double]) -> [Double] {
        guard !data.isEmpty else { return data }
        
        let mean = data.reduce(0.0, +) / Double(data.count)
        let variance = data.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(data.count)
        let std = sqrt(variance)
        
        guard std > 1e-10 else {
            return data.map { _ in 0.0 }
        }
        
        return data.map { ($0 - mean) / std }
    }

    private static func normalizeChannelZScore(_ data: [Float]) -> [Float] {
        guard !data.isEmpty else { return data }
        
        let mean = data.reduce(0.0, +) / Float(data.count)
        let variance = data.map { pow($0 - mean, 2) }.reduce(0.0, +) / Float(data.count)
        let std = sqrt(variance)
        
        guard std > 1e-10 else {
            return data.map { _ in 0.0 }
        }
        
        return data.map { ($0 - mean) / std }
    }
    
    private static func normalizeChannelLog(_ data: [Double]) -> [Double] {
        return data.map { log(max($0, 0.0) + 1.0) }
    }
    
    private static func normalizeChannelSqrt(_ data: [Double]) -> [Double] {
        return data.map { sqrt(max($0, 0.0)) }
    }

    private static func normalizeChannelLog(_ data: [Float]) -> [Float] {
        return data.map { log(max($0, 0.0) + 1.0) }
    }
    
    private static func normalizeChannelSqrt(_ data: [Float]) -> [Float] {
        return data.map { sqrt(max($0, 0.0)) }
    }
    
    private static func shouldPreserveChannelwise(cube: HyperCube, normalizedData: [Double]) -> DataType? {
        let originalType = cube.originalDataType
        
        guard let dataMin = normalizedData.min(),
              let dataMax = normalizedData.max() else {
            return nil
        }
        
        switch originalType {
        case .uint8:
            if dataMin >= 0 && dataMax <= 255 {
                return .uint8
            }
        case .uint16:
            if dataMin >= 0 && dataMax <= 65535 {
                return .uint16
            }
        case .int8:
            if dataMin >= -128 && dataMax <= 127 {
                return .int8
            }
        case .int16:
            if dataMin >= -32768 && dataMax <= 32767 {
                return .int16
            }
        case .float32:
            return .float32
        case .float64:
            return .float64
        default:
            break
        }
        
        return nil
    }
}
