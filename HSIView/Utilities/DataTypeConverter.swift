import Foundation

class DataTypeConverter {
    static func convert(_ cube: HyperCube, to targetType: DataType, autoScale: Bool) -> HyperCube? {
        guard targetType != .unknown else { return nil }
        guard cube.originalDataType != targetType else { return cube }
        
        let totalElements = cube.totalElements
        guard totalElements > 0 else { return nil }
        
        let convertedData: DataStorage?
        
        if autoScale {
            convertedData = convertWithScaling(cube, to: targetType)
        } else {
            convertedData = convertWithClamping(cube, to: targetType)
        }
        
        guard let storage = convertedData else { return nil }
        
        return HyperCube(
            dims: cube.dims,
            storage: storage,
            sourceFormat: cube.sourceFormat + " [\(targetType.rawValue)]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func convertWithScaling(_ cube: HyperCube, to targetType: DataType) -> DataStorage? {
        let stats = cube.statistics()
        let dataMin = stats.min
        let dataMax = stats.max
        
        let (targetMin, targetMax) = getTypeRange(targetType)
        
        let range = dataMax - dataMin
        guard range > 0 else {
            return convertWithClamping(cube, to: targetType)
        }
        
        let targetRange = targetMax - targetMin
        
        let scaledData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            let normalized = (value - dataMin) / range
            return targetMin + normalized * targetRange
        }
        
        return wrapInTargetStorage(scaledData, targetType: targetType)
    }
    
    private static func convertWithClamping(_ cube: HyperCube, to targetType: DataType) -> DataStorage? {
        let (targetMin, targetMax) = getTypeRange(targetType)
        
        let clampedData = (0..<cube.totalElements).map { idx -> Double in
            let value = cube.storage.getValue(at: idx)
            return max(targetMin, min(targetMax, value))
        }
        
        return wrapInTargetStorage(clampedData, targetType: targetType)
    }
    
    private static func getTypeRange(_ type: DataType) -> (min: Double, max: Double) {
        switch type {
        case .float64:
            return (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        case .float32:
            return (-Double(Float.greatestFiniteMagnitude), Double(Float.greatestFiniteMagnitude))
        case .int8:
            return (Double(Int8.min), Double(Int8.max))
        case .int16:
            return (Double(Int16.min), Double(Int16.max))
        case .int32:
            return (Double(Int32.min), Double(Int32.max))
        case .uint8:
            return (0.0, 255.0)
        case .uint16:
            return (0.0, 65535.0)
        case .unknown:
            return (0.0, 1.0)
        }
    }
    
    private static func wrapInTargetStorage(_ data: [Double], targetType: DataType) -> DataStorage? {
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
            return nil
        }
    }
}


