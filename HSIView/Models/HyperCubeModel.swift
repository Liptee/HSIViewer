import Foundation

struct MapCoordinate: Equatable {
    let x: Double
    let y: Double
}

private struct MapVector2D {
    var x: Double
    var y: Double
}

struct MapGeoReference: Equatable {
    let projectionName: String
    let referencePixelX: Double
    let referencePixelY: Double
    let tiePointX: Double
    let tiePointY: Double
    let pixelSizeX: Double
    let pixelSizeY: Double
    let zone: Int?
    let hemisphere: String?
    let datum: String?
    let units: String?
    let rotationDegrees: Double
    let xStart: Int
    let yStart: Int

    private var sampleVector: MapVector2D {
        let angle = rotationDegrees * .pi / 180.0
        let cosA = cos(angle)
        let sinA = sin(angle)
        return MapVector2D(x: pixelSizeX * cosA, y: pixelSizeX * sinA)
    }

    private var lineVector: MapVector2D {
        let angle = rotationDegrees * .pi / 180.0
        let cosA = cos(angle)
        let sinA = sin(angle)
        return MapVector2D(x: pixelSizeY * sinA, y: -pixelSizeY * cosA)
    }

    private var pixelOrigin: MapCoordinate {
        mapCoordinate(forPixelX: 0, pixelY: 0)
    }

    var crsDisplayName: String {
        var parts: [String] = [projectionName]

        if let zone {
            let hemiSuffix: String
            if let hemisphere, !hemisphere.isEmpty {
                hemiSuffix = hemisphere.prefix(1).uppercased()
            } else {
                hemiSuffix = ""
            }
            parts.append("zone \(zone)\(hemiSuffix)")
        }

        if let datum, !datum.isEmpty {
            parts.append(datum)
        }

        return parts.joined(separator: ", ")
    }

    var isGeographic: Bool {
        let projectionLower = projectionName.lowercased()
        let unitsLower = (units ?? "").lowercased()
        return projectionLower.contains("geographic")
            || projectionLower.contains("lon")
            || projectionLower.contains("lat")
            || unitsLower.contains("degree")
    }

    func mapCoordinate(forPixelX pixelX: Int, pixelY: Int) -> MapCoordinate {
        let sample = Double(pixelX + xStart)
        let line = Double(pixelY + yStart)
        let deltaSample = sample - referencePixelX
        let deltaLine = line - referencePixelY

        let sampleVector = self.sampleVector
        let lineVector = self.lineVector

        let x = tiePointX + deltaSample * sampleVector.x + deltaLine * lineVector.x
        let y = tiePointY + deltaSample * sampleVector.y + deltaLine * lineVector.y

        return MapCoordinate(x: x, y: y)
    }

    func cropped(left: Int, top: Int) -> MapGeoReference {
        let s = sampleVector
        let l = lineVector
        let base = pixelOrigin
        let origin = MapCoordinate(
            x: base.x + Double(left) * s.x + Double(top) * l.x,
            y: base.y + Double(left) * s.y + Double(top) * l.y
        )
        return rebuilt(origin: origin, sampleVector: s, lineVector: l)
    }

    func resized(sourceWidth: Int, sourceHeight: Int, targetWidth: Int, targetHeight: Int) -> MapGeoReference {
        guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else { return self }

        let scaleX = Double(sourceWidth) / Double(targetWidth)
        let scaleY = Double(sourceHeight) / Double(targetHeight)
        let offsetX = 0.5 * scaleX - 0.5
        let offsetY = 0.5 * scaleY - 0.5

        let s = sampleVector
        let l = lineVector
        let base = pixelOrigin
        let origin = MapCoordinate(
            x: base.x + offsetX * s.x + offsetY * l.x,
            y: base.y + offsetX * s.y + offsetY * l.y
        )
        let newS = MapVector2D(x: s.x * scaleX, y: s.y * scaleX)
        let newL = MapVector2D(x: l.x * scaleY, y: l.y * scaleY)
        return rebuilt(origin: origin, sampleVector: newS, lineVector: newL)
    }

    func rotatedClockwise(quarterTurns: Int, oldWidth: Int, oldHeight: Int) -> MapGeoReference {
        guard oldWidth > 0, oldHeight > 0 else { return self }
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return self }

        let s = sampleVector
        let l = lineVector
        let base = pixelOrigin

        switch turns {
        case 1:
            let origin = MapCoordinate(
                x: base.x + Double(oldHeight - 1) * l.x,
                y: base.y + Double(oldHeight - 1) * l.y
            )
            let newS = MapVector2D(x: -l.x, y: -l.y)
            let newL = MapVector2D(x: s.x, y: s.y)
            return rebuilt(origin: origin, sampleVector: newS, lineVector: newL)
        case 2:
            let origin = MapCoordinate(
                x: base.x + Double(oldWidth - 1) * s.x + Double(oldHeight - 1) * l.x,
                y: base.y + Double(oldWidth - 1) * s.y + Double(oldHeight - 1) * l.y
            )
            let newS = MapVector2D(x: -s.x, y: -s.y)
            let newL = MapVector2D(x: -l.x, y: -l.y)
            return rebuilt(origin: origin, sampleVector: newS, lineVector: newL)
        case 3:
            let origin = MapCoordinate(
                x: base.x + Double(oldWidth - 1) * s.x,
                y: base.y + Double(oldWidth - 1) * s.y
            )
            let newS = MapVector2D(x: l.x, y: l.y)
            let newL = MapVector2D(x: -s.x, y: -s.y)
            return rebuilt(origin: origin, sampleVector: newS, lineVector: newL)
        default:
            return self
        }
    }

    private func rebuilt(origin: MapCoordinate, sampleVector: MapVector2D, lineVector: MapVector2D) -> MapGeoReference {
        let newPixelSizeX = hypot(sampleVector.x, sampleVector.y)
        let newPixelSizeY = hypot(lineVector.x, lineVector.y)
        let newRotation = atan2(sampleVector.y, sampleVector.x) * 180.0 / .pi

        return MapGeoReference(
            projectionName: projectionName,
            referencePixelX: 1.0,
            referencePixelY: 1.0,
            tiePointX: origin.x,
            tiePointY: origin.y,
            pixelSizeX: newPixelSizeX,
            pixelSizeY: newPixelSizeY,
            zone: zone,
            hemisphere: hemisphere,
            datum: datum,
            units: units,
            rotationDegrees: newRotation,
            xStart: 1,
            yStart: 1
        )
    }
}

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
    let geoReference: MapGeoReference?
    
    init(
        dims: (Int, Int, Int),
        storage: DataStorage,
        sourceFormat: String,
        isFortranOrder: Bool,
        wavelengths: [Double]? = nil,
        geoReference: MapGeoReference? = nil
    ) {
        self.id = UUID()
        self.dims = dims
        self.storage = storage
        self.sourceFormat = sourceFormat
        self.isFortranOrder = isFortranOrder
        self.wavelengths = wavelengths
        self.geoReference = geoReference
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
        case .cwh:
            return d0
        case .hcw:
            return d1
        case .hwc:
            return d2
        case .wch:
            return d1
        case .whc:
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
            
        case .cwh:
            return (0, 2, 1)
            
        case .hcw:
            return (1, 0, 2)
            
        case .hwc:
            return (2, 0, 1)
            
        case .wch:
            return (1, 2, 0)
            
        case .whc:
            return (2, 1, 0)
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
    case cwh  = "CWH"
    case hcw  = "HCW"
    case hwc  = "HWC"
    case wch  = "WCH"
    case whc  = "WHC"
    
    var id: String { rawValue }
}

extension CubeLayout {
    static var explicitCases: [CubeLayout] {
        allCases.filter { $0 != .auto }
    }
    
    static func parseHWCOrder(_ rawOrder: String) -> CubeLayout? {
        let order = normalizeHWCOrder(rawOrder)
        guard order.count == 3 else { return nil }
        return CubeLayout.explicitCases.first(where: { $0.rawValue == order })
    }
    
    static func normalizeHWCOrder(_ rawOrder: String) -> String {
        rawOrder
            .uppercased()
            .filter { $0 == "H" || $0 == "W" || $0 == "C" }
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case rgb  = "RGB"
    case nd   = "ND"
    case mask = "Mask"
    
    var id: String { rawValue }
}
