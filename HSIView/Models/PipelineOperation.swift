import Foundation

enum PipelineOperationType: String, CaseIterable, Identifiable {
    case normalization = "Нормализация"
    case channelwiseNormalization = "Поканальная нормализация"
    case dataTypeConversion = "Тип данных"
    case rotation = "Поворот"
    case spatialCrop = "Обрезка области"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .normalization:
            return "chart.line.uptrend.xyaxis"
        case .channelwiseNormalization:
            return "chart.bar.xaxis"
        case .dataTypeConversion:
            return "arrow.triangle.2.circlepath"
        case .rotation:
            return "rotate.right"
        case .spatialCrop:
            return "crop"
        }
    }
    
    var description: String {
        switch self {
        case .normalization:
            return "Применить нормализацию к данным"
        case .channelwiseNormalization:
            return "Применить нормализацию отдельно к каждому каналу"
        case .dataTypeConversion:
            return "Изменить тип данных"
        case .rotation:
            return "Повернуть изображение на 90°, 180° или 270°"
        case .spatialCrop:
            return "Обрезать изображение по пространственным границам"
        }
    }
}

struct SpatialCropParameters: Equatable {
    var left: Int
    var right: Int
    var top: Int
    var bottom: Int
    
    var width: Int { max(0, right - left + 1) }
    var height: Int { max(0, bottom - top + 1) }
    
    mutating func clamp(maxWidth: Int, maxHeight: Int) {
        let widthLimit = max(1, maxWidth)
        let heightLimit = max(1, maxHeight)
        
        left = min(max(left, 0), widthLimit - 1)
        right = min(max(right, left), widthLimit - 1)
        top = min(max(top, 0), heightLimit - 1)
        bottom = min(max(bottom, top), heightLimit - 1)
    }
    
    func clamped(maxWidth: Int, maxHeight: Int) -> SpatialCropParameters {
        var copy = self
        copy.clamp(maxWidth: maxWidth, maxHeight: maxHeight)
        return copy
    }
}

enum RotationAngle: String, CaseIterable, Identifiable {
    case degree90 = "90°"
    case degree180 = "180°"
    case degree270 = "270°"
    
    var id: String { rawValue }
    
    var degrees: Int {
        switch self {
        case .degree90: return 90
        case .degree180: return 180
        case .degree270: return 270
        }
    }
}

struct PipelineOperation: Identifiable, Equatable {
    let id: UUID
    let type: PipelineOperationType
    var normalizationType: CubeNormalizationType?
    var normalizationParams: CubeNormalizationParameters?
    var preserveDataType: Bool?
    var targetDataType: DataType?
   var autoScale: Bool?
   var rotationAngle: RotationAngle?
   var layout: CubeLayout = .auto
    var cropParameters: SpatialCropParameters?
    
    init(id: UUID = UUID(), type: PipelineOperationType) {
        self.id = id
        self.type = type
        
        switch type {
        case .normalization, .channelwiseNormalization:
            self.normalizationType = .none
            self.normalizationParams = .default
            self.preserveDataType = true
        case .dataTypeConversion:
            self.targetDataType = .float64
            self.autoScale = true
        case .rotation:
            self.rotationAngle = .degree90
        case .spatialCrop:
            self.cropParameters = SpatialCropParameters(left: 0, right: 0, top: 0, bottom: 0)
        }
    }
    
    mutating func configureDefaults(with cube: HyperCube?, layout: CubeLayout) {
        guard let cube = cube else { return }
        
        switch type {
        case .spatialCrop:
            let dims = cube.dims
            let dimsArray = [dims.0, dims.1, dims.2]
            if let axes = cube.axes(for: layout) {
                let width = dimsArray[axes.width]
                let height = dimsArray[axes.height]
                cropParameters = SpatialCropParameters(
                    left: 0,
                    right: max(width - 1, 0),
                    top: 0,
                    bottom: max(height - 1, 0)
                )
            }
        default:
            break
        }
    }
    
    var displayName: String {
        switch type {
        case .normalization, .channelwiseNormalization:
            return normalizationType?.rawValue ?? type.rawValue
        case .dataTypeConversion:
            return targetDataType?.rawValue ?? "Тип данных"
        case .rotation:
            return "Поворот \(rotationAngle?.rawValue ?? "")"
        case .spatialCrop:
            return "Обрезка области"
        }
    }
    
    var detailsText: String {
        switch type {
        case .normalization, .channelwiseNormalization:
            guard let normType = normalizationType else { return "" }
            let prefix = type == .channelwiseNormalization ? "По каналам: " : ""
            switch normType {
            case .none:
                return prefix + "Без нормализации"
            case .minMax:
                return prefix + "[0, 1]"
            case .minMaxCustom:
                if let params = normalizationParams {
                    return prefix + String(format: "[%.2f, %.2f]", params.minValue, params.maxValue)
                }
                return prefix + "Custom"
            case .percentile:
                if let params = normalizationParams {
                    return prefix + String(format: "%.0f%%-%.0f%%", params.lowerPercentile, params.upperPercentile)
                }
                return prefix + "Percentile"
            case .zScore:
                return prefix + "Z-Score"
            case .log:
                return prefix + "log(x+1)"
            case .sqrt:
                return prefix + "√x"
            }
        case .dataTypeConversion:
            var text = targetDataType?.rawValue ?? ""
            if let autoScale = autoScale, autoScale {
                text += " (auto)"
            } else {
                text += " (clamp)"
            }
            return text
        case .rotation:
            return "По часовой стрелке"
        case .spatialCrop:
            if let params = cropParameters {
                return "x: \(params.left)–\(params.right) px, y: \(params.top)–\(params.bottom) px"
            }
            return "Настройте границы"
        }
    }
    
    static func == (lhs: PipelineOperation, rhs: PipelineOperation) -> Bool {
        return lhs.id == rhs.id
    }
    
    func apply(to cube: HyperCube) -> HyperCube? {
        switch type {
        case .normalization:
            guard let normType = normalizationType,
                  let params = normalizationParams else { return cube }
            let preserve = preserveDataType ?? true
            return CubeNormalizer.apply(normType, to: cube, parameters: params, preserveDataType: preserve)
            
        case .channelwiseNormalization:
            guard let normType = normalizationType,
                  let params = normalizationParams else { return cube }
            let preserve = preserveDataType ?? true
            return CubeNormalizer.applyChannelwise(normType, to: cube, parameters: params, preserveDataType: preserve)
            
        case .dataTypeConversion:
            guard let targetType = targetDataType,
                  let autoScale = autoScale else { return cube }
            return DataTypeConverter.convert(cube, to: targetType, autoScale: autoScale)
            
        case .rotation:
            guard let angle = rotationAngle else { return cube }
            return CubeRotator.rotate(cube, angle: angle, layout: layout)
        case .spatialCrop:
            guard let params = cropParameters else { return cube }
            return CubeSpatialCropper.crop(cube: cube, parameters: params, layout: layout)
        }
    }
}

class CubeRotator {
    static func rotate(_ cube: HyperCube, angle: RotationAngle, layout: CubeLayout = .auto) -> HyperCube? {
        let (d0, d1, d2) = cube.dims
        let dimsArray = [d0, d1, d2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let channels = dimsArray[axes.channel]
        let oldHeight = dimsArray[axes.height]
        let oldWidth = dimsArray[axes.width]
        
        let newHeight: Int
        let newWidth: Int
        switch angle {
        case .degree90, .degree270:
            newHeight = oldWidth
            newWidth = oldHeight
        case .degree180:
            newHeight = oldHeight
            newWidth = oldWidth
        }
        
        let newDims = (channels, newHeight, newWidth)
        let totalElements = newDims.0 * newDims.1 * newDims.2
        
        func getOldCoords(ch: Int, newY: Int, newX: Int) -> (Int, Int, Int) {
            let oldY: Int
            let oldX: Int
            
            switch angle {
            case .degree90:
                // 90° по часовой: new[y][x] = old[H-1-x][y]
                oldY = oldHeight - 1 - newX
                oldX = newY
            case .degree180:
                // 180°: new[y][x] = old[H-1-y][W-1-x]
                oldY = oldHeight - 1 - newY
                oldX = oldWidth - 1 - newX
            case .degree270:
                // 270° по часовой (90° против): new[y][x] = old[x][W-1-y]
                oldY = newX
                oldX = oldWidth - 1 - newY
            }
            
            var idx3 = [0, 0, 0]
            idx3[axes.channel] = ch
            idx3[axes.height] = oldY
            idx3[axes.width] = oldX
            return (idx3[0], idx3[1], idx3[2])
        }
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
            
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalElements)
            for ch in 0..<channels {
                for newY in 0..<newHeight {
                    for newX in 0..<newWidth {
                        let (i0, i1, i2) = getOldCoords(ch: ch, newY: newY, newX: newX)
                        let oldIdx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let newIdx = newX + newWidth * (newY + newHeight * ch)
                        newData[newIdx] = arr[oldIdx]
                    }
                }
            }
            return HyperCube(dims: newDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: false, wavelengths: cube.wavelengths)
        }
    }
}

class CubeSpatialCropper {
    static func crop(cube: HyperCube, parameters: SpatialCropParameters, layout: CubeLayout) -> HyperCube? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        
        guard height > 0, width > 0 else { return cube }
        
        let clamped = parameters.clamped(maxWidth: width, maxHeight: height)
        guard clamped.width > 0, clamped.height > 0 else { return cube }
        
        var newDims = dimsArray
        newDims[axes.height] = clamped.height
        newDims[axes.width] = clamped.width
        let resultingDims = (newDims[0], newDims[1], newDims[2])
        let totalElements = resultingDims.0 * resultingDims.1 * resultingDims.2
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        }
    }
    
    private static func fillBuffer<T>(
        cube: HyperCube,
        source: [T],
        into buffer: inout [T],
        newDims: (Int, Int, Int),
        axes: (channel: Int, height: Int, width: Int),
        crop: SpatialCropParameters
    ) {
        for i0 in 0..<newDims.0 {
            for i1 in 0..<newDims.1 {
                for i2 in 0..<newDims.2 {
                    var srcCoord = [i0, i1, i2]
                    srcCoord[axes.height] += crop.top
                    srcCoord[axes.width] += crop.left
                    
                    let srcIndex = cube.linearIndex(i0: srcCoord[0], i1: srcCoord[1], i2: srcCoord[2])
                    let dstIndex = linearIndex(i0: i0, i1: i1, i2: i2, dims: newDims, fortran: cube.isFortranOrder)
                    buffer[dstIndex] = source[srcIndex]
                }
            }
        }
    }
    
    private static func linearIndex(
        i0: Int,
        i1: Int,
        i2: Int,
        dims: (Int, Int, Int),
        fortran: Bool
    ) -> Int {
        if fortran {
            return i0 + dims.0 * (i1 + dims.1 * i2)
        } else {
            return i2 + dims.2 * (i1 + dims.1 * i0)
        }
    }
}
