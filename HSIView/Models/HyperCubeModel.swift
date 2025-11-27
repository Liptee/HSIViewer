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

struct HyperCube {
    let dims: (Int, Int, Int)
    let data: [Double]
    let originalDataType: DataType
    let sourceFormat: String
    
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
        case .hwc:
            return d2
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
            
        case .hwc:
            return (2, 0, 1)
        }
    }
    
    func linearIndex(i0: Int, i1: Int, i2: Int) -> Int {
        let (d0, d1, _) = dims
        return i0 + d0 * (i1 + d1 * i2)
    }
}

enum CubeLayout: String, CaseIterable, Identifiable {
    case auto = "Auto (min dim = C)"
    case chw  = "CHW"
    case hwc  = "HWC"
    
    var id: String { rawValue }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case rgb  = "RGB"
    
    var id: String { rawValue }
}

