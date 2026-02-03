import Foundation

enum DataType: String {
    case float64 = "Float64"
    case float32 = "Float32"
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case unknown = "Unknown"
}

/// Хранилище данных в оригинальном типе для экономии памяти
enum DataStorage {
    case float64([Double])
    case float32([Float])
    case int8([Int8])
    case int16([Int16])
    case int32([Int32])
    case uint8([UInt8])
    case uint16([UInt16])
    
    var dataType: DataType {
        switch self {
        case .float64: return .float64
        case .float32: return .float32
        case .int8: return .int8
        case .int16: return .int16
        case .int32: return .int32
        case .uint8: return .uint8
        case .uint16: return .uint16
        }
    }
    
    var count: Int {
        switch self {
        case .float64(let arr): return arr.count
        case .float32(let arr): return arr.count
        case .int8(let arr): return arr.count
        case .int16(let arr): return arr.count
        case .int32(let arr): return arr.count
        case .uint8(let arr): return arr.count
        case .uint16(let arr): return arr.count
        }
    }
    
    /// Размер одного элемента в байтах
    var bytesPerElement: Int {
        switch self {
        case .float64: return 8
        case .float32: return 4
        case .int8: return 1
        case .int16: return 2
        case .int32: return 4
        case .uint8: return 1
        case .uint16: return 2
        }
    }
    
    /// Общий размер в памяти (в байтах)
    var sizeInBytes: Int {
        return count * bytesPerElement
    }
    
    /// Получить значение как Double (для совместимости)
    func getValue(at index: Int) -> Double {
        switch self {
        case .float64(let arr): return arr[index]
        case .float32(let arr): return Double(arr[index])
        case .int8(let arr): return Double(arr[index])
        case .int16(let arr): return Double(arr[index])
        case .int32(let arr): return Double(arr[index])
        case .uint8(let arr): return Double(arr[index])
        case .uint16(let arr): return Double(arr[index])
        }
    }
    
    /// Получить срез данных как Double массив
    func getSlice(indices: [Int]) -> [Double] {
        return indices.map { getValue(at: $0) }
    }
}

struct HyperCube {
    let id: UUID
    let dims: (Int, Int, Int)
    let storage: DataStorage  // Изменено: хранение в оригинальном типе
    let sourceFormat: String
    let isFortranOrder: Bool  // Для правильной индексации
    let wavelengths: [Double]?  // Для ENVI и других форматов с длинами волн
    
    init(dims: (Int, Int, Int), storage: DataStorage, sourceFormat: String, isFortranOrder: Bool, wavelengths: [Double]? = nil) {
        self.id = UUID()
        self.dims = dims
        self.storage = storage
        self.sourceFormat = sourceFormat
        self.isFortranOrder = isFortranOrder
        self.wavelengths = wavelengths
    }
    
    var originalDataType: DataType {
        storage.dataType
    }
    
    var is2D: Bool {
        dims.0 == 1 || dims.1 == 1 || dims.2 == 1
    }
    
    var dims2D: (width: Int, height: Int)? {
        guard is2D else { return nil }
        
        if dims.0 == 1 {
            return (dims.2, dims.1)
        } else if dims.1 == 1 {
            return (dims.2, dims.0)
        } else {
            return (dims.1, dims.0)
        }
    }
    
    var totalChannelsAuto: Int {
        if is2D { return 1 }
        let arr = [dims.0, dims.1, dims.2]
        return arr.min() ?? dims.0
    }
    
    var totalElements: Int {
        dims.0 * dims.1 * dims.2
    }
    
    var resolution: String {
        if is2D, let dims2D = dims2D {
            return "\(dims2D.width) × \(dims2D.height) (2D)"
        }
        return "\(dims.0) × \(dims.1) × \(dims.2)"
    }
    
    func channelCount(for layout: CubeLayout) -> Int {
        if is2D { return 1 }
        
        let (d0, d1, d2) = dims
        let dimsArr = [d0, d1, d2]
        
        switch layout {
        case .auto:
            return dimsArr.min() ?? d0
        case .chw:
            return d0
        case .hcw:
            return d1
        case .hwc:
            return d2
        case .wch:
            return d1
        }
    }
    
    func axes(for layout: CubeLayout) -> (channel: Int, height: Int, width: Int)? {
        let (d0, d1, d2) = dims
        guard d0 > 0 && d1 > 0 && d2 > 0 else { return nil }
        
        switch layout {
        case .auto:
            let dimsArr = [d0, d1, d2]
            guard let minDim = dimsArr.min(),
                  let cAxis = dimsArr.firstIndex(of: minDim) else { return nil }
            let other = [0, 1, 2].filter { $0 != cAxis }
            return (cAxis, other[0], other[1])
            
        case .chw:
            return (0, 1, 2)
            
        case .hcw:
            return (1, 0, 2)
            
        case .hwc:
            return (2, 0, 1)
            
        case .wch:
            return (1, 2, 0)
        }
    }
    
    func linearIndex(i0: Int, i1: Int, i2: Int) -> Int {
        let (d0, d1, d2) = dims
        
        if isFortranOrder {
            // Fortran-order (column-major): первый индекс меняется быстрее
            // Элемент [i0, i1, i2] находится на позиции: i0 + d0*(i1 + d1*i2)
            return i0 + d0 * (i1 + d1 * i2)
        } else {
            // C-order (row-major): последний индекс меняется быстрее
            // Элемент [i0, i1, i2] находится на позиции: i2 + d2*(i1 + d1*i0)
            return i2 + d2 * (i1 + d1 * i0)
        }
    }
    
    /// Получить значение по линейному индексу
    func getValue(at linearIndex: Int) -> Double {
        return storage.getValue(at: linearIndex)
    }
    
    /// Получить значение по 3D координатам
    func getValue(i0: Int, i1: Int, i2: Int) -> Double {
        let index = linearIndex(i0: i0, i1: i1, i2: i2)
        return getValue(at: index)
    }
}

enum CubeLayout: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case chw  = "CHW"
    case hcw  = "HCW"
    case hwc  = "HWC"
    case wch  = "WCH"
    
    var id: String { rawValue }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case rgb  = "RGB"
    case nd   = "ND"
    case mask = "Mask"
    
    var id: String { rawValue }
}
