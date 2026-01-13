import Foundation

enum PipelineOperationType: String, CaseIterable, Identifiable {
    case normalization = "Нормализация"
    case channelwiseNormalization = "Поканальная нормализация"
    case dataTypeConversion = "Тип данных"
    case rotation = "Поворот"
    case resize = "Изменение размера"
    case spatialCrop = "Обрезка области"
    case spectralTrim = "Обрезка длин волн"
    case calibration = "Калибровка"
    case spectralInterpolation = "Спектральная интерполяция"
    
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
        case .resize:
            return "arrow.up.left.and.down.right.magnifyingglass"
        case .spatialCrop:
            return "crop"
        case .spectralTrim:
            return "scissors"
        case .calibration:
            return "slider.horizontal.below.sun.max"
        case .spectralInterpolation:
            return "waveform.path.ecg"
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
        case .resize:
            return "Изменить размер пространственных измерений"
        case .spatialCrop:
            return "Обрезать изображение по пространственным границам"
        case .spectralTrim:
            return "Обрезать спектральный диапазон по каналам"
        case .calibration:
            return "Калибровка по белой и/или чёрной точке"
        case .spectralInterpolation:
            return "Изменить спектральное разрешение по длинам волн"
        }
    }
}

struct ResizeParameters: Equatable {
    var targetWidth: Int
    var targetHeight: Int
    var algorithm: ResizeAlgorithm
    var bicubicA: Double
    var lanczosA: Int
    var lockAspectRatio: Bool
    var computePrecision: ResizeComputationPrecision
    
    static let `default` = ResizeParameters(
        targetWidth: 0,
        targetHeight: 0,
        algorithm: .bilinear,
        bicubicA: -0.5,
        lanczosA: 3,
        lockAspectRatio: true,
        computePrecision: .float64
    )
}

enum ResizeAlgorithm: String, CaseIterable, Identifiable {
    case nearest = "По ближайшему соседу"
    case bilinear = "Билинейная"
    case bicubic = "Бикубическая"
    case bspline = "Сплайн"
    case lanczos = "Ланцош"
    
    var id: String { rawValue }
}

enum ResizeComputationPrecision: String, CaseIterable, Identifiable {
    case float32 = "Float32"
    case float64 = "Float64"
    
    var id: String { rawValue }
}

enum SpectralInterpolationMethod: String, CaseIterable, Identifiable {
    case nearest = "Nearest"
    case linear = "Linear"
    case cubic = "Cubic"
    
    var id: String { rawValue }
}

enum SpectralExtrapolationMode: String, CaseIterable, Identifiable {
    case clamp = "Clamp"
    case extrapolate = "Extrapolate"
    
    var id: String { rawValue }
}

enum SpectralInterpolationDataType: String, CaseIterable, Identifiable {
    case float32 = "Float32"
    case float64 = "Float64"
    
    var id: String { rawValue }
}

struct SpectralInterpolationParameters: Equatable {
    var targetChannelCount: Int
    var targetMinLambda: Double
    var targetMaxLambda: Double
    var method: SpectralInterpolationMethod
    var extrapolation: SpectralExtrapolationMode
    var dataType: SpectralInterpolationDataType
    
    static let `default` = SpectralInterpolationParameters(
        targetChannelCount: 0,
        targetMinLambda: 0,
        targetMaxLambda: 0,
        method: .linear,
        extrapolation: .clamp,
        dataType: .float64
    )
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
    
    var quarterTurns: Int {
        switch self {
        case .degree90: return 1
        case .degree180: return 2
        case .degree270: return 3
        }
    }
}

struct CalibrationSpectrum: Equatable, Identifiable {
    let id: UUID
    let values: [Double]
    let sourceName: String
    
    init(id: UUID = UUID(), values: [Double], sourceName: String) {
        self.id = id
        self.values = values
        self.sourceName = sourceName
    }
    
    static func from(sample: SpectrumSampleSnapshot) -> CalibrationSpectrum {
        CalibrationSpectrum(
            id: sample.id,
            values: sample.values,
            sourceName: sample.effectiveName
        )
    }
    
    static func from(roiSample: SpectrumROISampleSnapshot) -> CalibrationSpectrum {
        CalibrationSpectrum(
            id: roiSample.id,
            values: roiSample.values,
            sourceName: roiSample.effectiveName
        )
    }
}

struct SpectrumSampleSnapshot: Equatable, Identifiable {
    let id: UUID
    let pixelX: Int
    let pixelY: Int
    let values: [Double]
    let colorIndex: Int
    let displayName: String?
    
    var effectiveName: String {
        displayName ?? "Точка (\(pixelX), \(pixelY))"
    }
}

struct SpectrumROISampleSnapshot: Equatable, Identifiable {
    let id: UUID
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
    let values: [Double]
    let colorIndex: Int
    let displayName: String?
    
    var effectiveName: String {
        displayName ?? "ROI (\(minX),\(minY))–(\(minX + width),\(minY + height))"
    }
}

struct CalibrationParameters: Equatable {
    var whiteSpectrum: CalibrationSpectrum?
    var blackSpectrum: CalibrationSpectrum?
    var targetMin: Double = 0.0
    var targetMax: Double = 1.0
    
    var isConfigured: Bool {
        whiteSpectrum != nil || blackSpectrum != nil
    }
    
    var summaryText: String {
        var parts: [String] = []
        if whiteSpectrum != nil { parts.append("белая") }
        if blackSpectrum != nil { parts.append("чёрная") }
        if parts.isEmpty { return "Не настроено" }
        return parts.joined(separator: " + ")
    }
    
    static let `default` = CalibrationParameters()
}

struct SpectralTrimParameters: Equatable {
    var startChannel: Int
    var endChannel: Int
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
    var calibrationParams: CalibrationParameters?
    var resizeParameters: ResizeParameters?
    var spectralTrimParams: SpectralTrimParameters?
    var spectralInterpolationParams: SpectralInterpolationParameters?
    
    init(id: UUID = UUID(), type: PipelineOperationType) {
        self.id = id
        self.type = type
        
        switch type {
        case .normalization, .channelwiseNormalization:
            self.normalizationType = .none
            self.normalizationParams = .default
            self.preserveDataType = true
        case .dataTypeConversion:
            self.autoScale = true
        case .rotation:
            self.rotationAngle = .degree90
        case .resize:
            self.resizeParameters = .default
        case .spatialCrop:
            self.cropParameters = SpatialCropParameters(left: 0, right: 0, top: 0, bottom: 0)
        case .spectralTrim:
            self.spectralTrimParams = SpectralTrimParameters(startChannel: 0, endChannel: 0)
        case .calibration:
            self.calibrationParams = .default
        case .spectralInterpolation:
            self.spectralInterpolationParams = .default
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
        case .resize:
            let dims = cube.dims
            let dimsArray = [dims.0, dims.1, dims.2]
            if let axes = cube.axes(for: layout) {
                let width = dimsArray[axes.width]
                let height = dimsArray[axes.height]
                resizeParameters = ResizeParameters(
                    targetWidth: width,
                    targetHeight: height,
                    algorithm: .bilinear,
                    bicubicA: -0.5,
                    lanczosA: 3,
                    lockAspectRatio: true,
                    computePrecision: .float64
                )
            }
        case .spectralTrim:
            let channelCount = cube.channelCount(for: layout)
            spectralTrimParams = SpectralTrimParameters(
                startChannel: 0,
                endChannel: max(channelCount - 1, 0)
            )
        case .dataTypeConversion:
            targetDataType = cube.originalDataType
        case .spectralInterpolation:
            if let wavelengths = cube.wavelengths, !wavelengths.isEmpty {
                let minLambda = wavelengths.min() ?? 0
                let maxLambda = wavelengths.max() ?? 0
                let channelCount = cube.channelCount(for: layout)
                spectralInterpolationParams = SpectralInterpolationParameters(
                    targetChannelCount: channelCount,
                    targetMinLambda: minLambda,
                    targetMaxLambda: maxLambda,
                    method: .linear,
                    extrapolation: .clamp,
                    dataType: .float64
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
        case .resize:
            if let params = resizeParameters {
                return "Ресайз до \(params.targetWidth)×\(params.targetHeight) (\(params.algorithm.rawValue))"
            }
            return "Изменение размера"
        case .spatialCrop:
            return "Обрезка области"
        case .spectralTrim:
            return "Обрезка спектра"
        case .calibration:
            return "Калибровка"
        case .spectralInterpolation:
            return "Интерполяция спектра"
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
            case .manualRange:
                if let params = normalizationParams {
                    return prefix + String(format: "[%.2f, %.2f] → [%.2f, %.2f]", params.sourceMin, params.sourceMax, params.targetMin, params.targetMax)
                }
                return prefix + "Диапазон"
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
        case .resize:
            if let params = resizeParameters {
                return "До \(params.targetWidth)×\(params.targetHeight), \(params.algorithm.rawValue)"
            }
            return "Изменение размера"
        case .spatialCrop:
            if let params = cropParameters {
                return "x: \(params.left)–\(params.right) px, y: \(params.top)–\(params.bottom) px"
            }
            return "Настройте границы"
        case .spectralTrim:
            if let params = spectralTrimParams {
                let count = max(0, params.endChannel - params.startChannel + 1)
                return "каналы \(params.startChannel)–\(params.endChannel) (\(count))"
            }
            return "Настройте диапазон"
        case .calibration:
            return calibrationParams?.summaryText ?? "Не настроено"
        case .spectralInterpolation:
            if let params = spectralInterpolationParams {
                return "\(params.targetChannelCount) каналов, \(params.method.rawValue)"
            }
            return "Настройте параметры"
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
        case .resize:
            guard let params = resizeParameters else { return cube }
            return CubeResizer.resize(cube: cube, parameters: params, layout: layout)
        case .spatialCrop:
            guard let params = cropParameters else { return cube }
            return CubeSpatialCropper.crop(cube: cube, parameters: params, layout: layout)
        case .spectralTrim:
            guard let params = spectralTrimParams else { return cube }
            return CubeSpectralTrimmer.trim(cube: cube, parameters: params, layout: layout)
        case .calibration:
            guard let params = calibrationParams, params.isConfigured else { return cube }
            return CubeCalibrator.calibrate(cube: cube, parameters: params, layout: layout)
        case .spectralInterpolation:
            guard let params = spectralInterpolationParams else { return cube }
            return CubeSpectralInterpolator.interpolate(cube: cube, parameters: params, layout: layout)
        }
    }
}

extension PipelineOperation {
    func isNoOp(for cube: HyperCube?, layout: CubeLayout) -> Bool {
        guard let cube else { return false }
        guard let axes = cube.axes(for: layout) ?? cube.axes(for: .auto) else { return false }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let width = dims[axes.width]
        let height = dims[axes.height]
        let channelCount = dims[axes.channel]
        
        switch type {
        case .resize:
            guard let params = resizeParameters else { return true }
            return params.targetWidth == width && params.targetHeight == height
        case .spatialCrop:
            guard let params = cropParameters else { return true }
            return params.left == 0 && params.top == 0 && params.right == width - 1 && params.bottom == height - 1
        case .spectralTrim:
            guard let params = spectralTrimParams else { return true }
            return params.startChannel == 0 && params.endChannel == max(channelCount - 1, 0)
        case .dataTypeConversion:
            guard let targetType = targetDataType else { return true }
            return targetType == cube.originalDataType
        default:
            return false
        }
    }
}

// MARK: - CubeResizer

class CubeResizer {
    static func resize(cube: HyperCube, parameters: ResizeParameters, layout: CubeLayout = .auto) -> HyperCube? {
        guard parameters.targetWidth > 0, parameters.targetHeight > 0 else { return cube }
        
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        let srcDims = dimsArray
        guard let axes = cube.axes(for: layout) else { return cube }
        let srcWidth = dimsArray[axes.width]
        let srcHeight = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        guard srcWidth > 0, srcHeight > 0, channels > 0 else { return cube }
        
        let dstWidth = parameters.targetWidth
        let dstHeight = parameters.targetHeight
        dimsArray[axes.width] = dstWidth
        dimsArray[axes.height] = dstHeight
        
        let total = dstWidth * dstHeight * channels
        
        if parameters.algorithm == .nearest {
            let scaleX = Double(srcWidth) / Double(dstWidth)
            let scaleY = Double(srcHeight) / Double(dstHeight)
            
            switch cube.storage {
            case .float64(let arr):
                var output = [Double](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .float64(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .float32(let arr):
                var output = [Float](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .float32(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .uint16(let arr):
                var output = [UInt16](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .uint16(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .uint8(let arr):
                var output = [UInt8](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .uint8(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .int16(let arr):
                var output = [Int16](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int16(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .int32(let arr):
                var output = [Int32](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int32(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            case .int8(let arr):
                var output = [Int8](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int8(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            }
        }
        
        let useFloat32 = parameters.computePrecision == .float32
        if useFloat32 {
            var output = [Float](repeating: 0, count: total)
            let scaleX = Float(srcWidth) / Float(dstWidth)
            let scaleY = Float(srcHeight) / Float(dstHeight)
            
            for ch in 0..<channels {
                for y in 0..<dstHeight {
                    for x in 0..<dstWidth {
                        let srcX = (Float(x) + 0.5) * scaleX - 0.5
                        let srcY = (Float(y) + 0.5) * scaleY - 0.5
                        let value = sampleFloat(
                            cube: cube,
                            axes: axes,
                            channel: ch,
                            x: srcX,
                            y: srcY,
                            algorithm: parameters.algorithm,
                            bicubicA: Float(parameters.bicubicA),
                            lanczosA: parameters.lanczosA
                        )
                        
                        var outIndices = [0, 0, 0]
                        outIndices[axes.width] = x
                        outIndices[axes.height] = y
                        outIndices[axes.channel] = ch
                        
                        let idx = linearIndex(
                            dims: dimsArray,
                            isFortran: cube.isFortranOrder,
                            i0: outIndices[0],
                            i1: outIndices[1],
                            i2: outIndices[2]
                        )
                        output[idx] = value
                    }
                }
            }
            
            let storage = DataStorage.float32(output)
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: storage,
                sourceFormat: cube.sourceFormat + " [Resize]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
        var output = [Double](repeating: 0.0, count: total)
        
        let scaleX = Double(srcWidth) / Double(dstWidth)
        let scaleY = Double(srcHeight) / Double(dstHeight)
        
        for ch in 0..<channels {
            for y in 0..<dstHeight {
                for x in 0..<dstWidth {
                    let srcX = (Double(x) + 0.5) * scaleX - 0.5
                    let srcY = (Double(y) + 0.5) * scaleY - 0.5
                    let value = sample(
                        cube: cube,
                        axes: axes,
                        channel: ch,
                        x: srcX,
                        y: srcY,
                        algorithm: parameters.algorithm,
                        bicubicA: parameters.bicubicA,
                        lanczosA: parameters.lanczosA
                    )
                    
                    var outIndices = [0, 0, 0]
                    outIndices[axes.width] = x
                    outIndices[axes.height] = y
                    outIndices[axes.channel] = ch
                    
                    let idx = linearIndex(
                        dims: dimsArray,
                        isFortran: cube.isFortranOrder,
                        i0: outIndices[0],
                        i1: outIndices[1],
                        i2: outIndices[2]
                    )
                    output[idx] = value
                }
            }
        }
        
        let storage = DataStorage.float64(output)
        return HyperCube(
            dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Resize]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func sample(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channel: Int,
        x: Double,
        y: Double,
        algorithm: ResizeAlgorithm,
        bicubicA: Double,
        lanczosA: Int
    ) -> Double {
        switch algorithm {
        case .nearest:
            let nx = Int(round(x))
            let ny = Int(round(y))
            return value(atX: nx, y: ny, channel: channel, cube: cube, axes: axes)
        case .bilinear:
            return bilinearSample(cube: cube, axes: axes, channel: channel, x: x, y: y)
        case .bicubic:
            return bicubicSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: bicubicA)
        case .bspline:
            return bicubicSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: -1.0)
        case .lanczos:
            return lanczosSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: max(1, lanczosA))
        }
    }
    
    private static func sampleFloat(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channel: Int,
        x: Float,
        y: Float,
        algorithm: ResizeAlgorithm,
        bicubicA: Float,
        lanczosA: Int
    ) -> Float {
        switch algorithm {
        case .nearest:
            let nx = Int(round(x))
            let ny = Int(round(y))
            return Float(value(atX: nx, y: ny, channel: channel, cube: cube, axes: axes))
        case .bilinear:
            return Float(bilinearSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y)))
        case .bicubic:
            return Float(bicubicSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: Double(bicubicA)))
        case .bspline:
            return Float(bicubicSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: -1.0))
        case .lanczos:
            return Float(lanczosSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: max(1, lanczosA)))
        }
    }

    private static func fillNearest<T>(
        from source: [T],
        into output: inout [T],
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        srcDims: [Int],
        dstWidth: Int,
        dstHeight: Int,
        scaleX: Double,
        scaleY: Double,
        dstDims: [Int]
    ) {
        let dstDimsArray = dstDims
        let channels = dstDimsArray[axes.channel]
        
        for ch in 0..<channels {
            for y in 0..<dstHeight {
                for x in 0..<dstWidth {
                    let srcX = Int(round((Double(x) + 0.5) * scaleX - 0.5))
                    let srcY = Int(round((Double(y) + 0.5) * scaleY - 0.5))
                    
                    var srcIndices = [0, 0, 0]
                    srcIndices[axes.channel] = ch
                    srcIndices[axes.height] = min(max(0, srcY), srcDims[axes.height] - 1)
                    srcIndices[axes.width] = min(max(0, srcX), srcDims[axes.width] - 1)
                    
                    let srcIdx = cube.linearIndex(i0: srcIndices[0], i1: srcIndices[1], i2: srcIndices[2])
                    
                    var dstIndices = [0, 0, 0]
                    dstIndices[axes.channel] = ch
                    dstIndices[axes.height] = y
                    dstIndices[axes.width] = x
                    
                    let dstIdx = linearIndex(
                        dims: dstDimsArray,
                        isFortran: cube.isFortranOrder,
                        i0: dstIndices[0],
                        i1: dstIndices[1],
                        i2: dstIndices[2]
                    )
                    
                    output[dstIdx] = source[srcIdx]
                }
            }
        }
    }
    
    private static func value(atX x: Int, y: Int, channel: Int, cube: HyperCube, axes: (channel: Int, height: Int, width: Int)) -> Double {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard x >= 0, y >= 0,
              x < dimsArray[axes.width],
              y < dimsArray[axes.height] else { return 0 }
        var indices = [0, 0, 0]
        indices[axes.channel] = channel
        indices[axes.height] = y
        indices[axes.width] = x
        return cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
    }
    
    private static func bilinearSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double) -> Double {
        let x0 = Int(floor(x))
        let x1 = x0 + 1
        let y0 = Int(floor(y))
        let y1 = y0 + 1
        let fx = x - Double(x0)
        let fy = y - Double(y0)
        
        let v00 = value(atX: x0, y: y0, channel: channel, cube: cube, axes: axes)
        let v10 = value(atX: x1, y: y0, channel: channel, cube: cube, axes: axes)
        let v01 = value(atX: x0, y: y1, channel: channel, cube: cube, axes: axes)
        let v11 = value(atX: x1, y: y1, channel: channel, cube: cube, axes: axes)
        
        let vx0 = v00 * (1 - fx) + v10 * fx
        let vx1 = v01 * (1 - fx) + v11 * fx
        return vx0 * (1 - fy) + vx1 * fy
    }
    
    private static func cubicWeight(_ t: Double, a: Double) -> Double {
        let at = abs(t)
        if at <= 1 {
            return (a + 2) * pow(at, 3) - (a + 3) * pow(at, 2) + 1
        } else if at < 2 {
            return a * pow(at, 3) - 5 * a * pow(at, 2) + 8 * a * at - 4 * a
        } else {
            return 0
        }
    }
    
    private static func bicubicSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double, a: Double) -> Double {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        
        var result = 0.0
        for m in -1...2 {
            let wy = cubicWeight(Double(m) - (y - Double(y0)), a: a)
            let sampleY = y0 + m
            for n in -1...2 {
                let wx = cubicWeight(Double(n) - (x - Double(x0)), a: a)
                let sampleX = x0 + n
                let v = value(atX: sampleX, y: sampleY, channel: channel, cube: cube, axes: axes)
                result += v * wx * wy
            }
        }
        return result
    }
    
    private static func sinc(_ x: Double) -> Double {
        if abs(x) < 1e-7 { return 1.0 }
        return sin(Double.pi * x) / (Double.pi * x)
    }
    
    private static func lanczosWeight(_ x: Double, a: Int) -> Double {
        let ax = abs(x)
        if ax >= Double(a) { return 0 }
        return sinc(ax) * sinc(ax / Double(a))
    }
    
    private static func lanczosSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double, a: Int) -> Double {
        let xInt = Int(floor(x))
        let yInt = Int(floor(y))
        var sum = 0.0
        var weightSum = 0.0
        
        for j in (yInt - a + 1)...(yInt + a) {
            let wy = lanczosWeight(Double(j) - y, a: a)
            if wy == 0 { continue }
            for i in (xInt - a + 1)...(xInt + a) {
                let wx = lanczosWeight(Double(i) - x, a: a)
                let w = wx * wy
                if w == 0 { continue }
                let v = value(atX: i, y: j, channel: channel, cube: cube, axes: axes)
                sum += v * w
                weightSum += w
            }
        }
        if weightSum == 0 { return 0 }
        return sum / weightSum
    }
    
    private static func linearIndex(dims: [Int], isFortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if isFortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        } else {
            return i2 + dims[2] * (i1 + dims[1] * i0)
        }
    }
}

class CubeRotator {
    static func rotate(_ cube: HyperCube, angle: RotationAngle, layout: CubeLayout = .auto) -> HyperCube? {
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        
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
        
        var newDimsArray = dimsArray
        newDimsArray[axes.height] = newHeight
        newDimsArray[axes.width] = newWidth
        let resultingDims = (newDimsArray[0], newDimsArray[1], newDimsArray[2])
        let totalElements = resultingDims.0 * resultingDims.1 * resultingDims.2
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
            
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalElements)
            fillBuffer(
                cube: cube,
                source: arr,
                into: &newData,
                axes: axes,
                angle: angle,
                channels: channels,
                newDims: resultingDims,
                newHeight: newHeight,
                newWidth: newWidth,
                oldHeight: oldHeight,
                oldWidth: oldWidth
            )
            return HyperCube(dims: resultingDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths)
        }
    }
    
    private static func fillBuffer<T>(
        cube: HyperCube,
        source: [T],
        into buffer: inout [T],
        axes: (channel: Int, height: Int, width: Int),
        angle: RotationAngle,
        channels: Int,
        newDims: (Int, Int, Int),
        newHeight: Int,
        newWidth: Int,
        oldHeight: Int,
        oldWidth: Int
    ) {
        for ch in 0..<channels {
            for newY in 0..<newHeight {
                for newX in 0..<newWidth {
                    let (src0, src1, src2) = rotatedSourceCoords(
                        channel: ch,
                        newY: newY,
                        newX: newX,
                        axes: axes,
                        angle: angle,
                        oldHeight: oldHeight,
                        oldWidth: oldWidth
                    )
                    
                    var dstCoord = [0, 0, 0]
                    dstCoord[axes.channel] = ch
                    dstCoord[axes.height] = newY
                    dstCoord[axes.width] = newX
                    
                    let srcIndex = cube.linearIndex(i0: src0, i1: src1, i2: src2)
                    let dstIndex = linearIndex(
                        i0: dstCoord[0],
                        i1: dstCoord[1],
                        i2: dstCoord[2],
                        dims: newDims,
                        fortran: cube.isFortranOrder
                    )
                    
                    buffer[dstIndex] = source[srcIndex]
                }
            }
        }
    }
    
    private static func rotatedSourceCoords(
        channel: Int,
        newY: Int,
        newX: Int,
        axes: (channel: Int, height: Int, width: Int),
        angle: RotationAngle,
        oldHeight: Int,
        oldWidth: Int
    ) -> (Int, Int, Int) {
        let oldY: Int
        let oldX: Int
        
        switch angle {
        case .degree90:
            oldY = oldHeight - 1 - newX
            oldX = newY
        case .degree180:
            oldY = oldHeight - 1 - newY
            oldX = oldWidth - 1 - newX
        case .degree270:
            oldY = newX
            oldX = oldWidth - 1 - newY
        }
        
        var coord = [0, 0, 0]
        coord[axes.channel] = channel
        coord[axes.height] = oldY
        coord[axes.width] = oldX
        
        return (coord[0], coord[1], coord[2])
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

class CubeCalibrator {
    static func calibrate(cube: HyperCube, parameters: CalibrationParameters, layout: CubeLayout) -> HyperCube? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let channels = dimsArray[axes.channel]
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        
        guard channels > 0, height > 0, width > 0 else { return cube }
        
        let whiteSpectrum = parameters.whiteSpectrum?.values
        let blackSpectrum = parameters.blackSpectrum?.values
        
        guard whiteSpectrum != nil || blackSpectrum != nil else { return cube }
        
        if let white = whiteSpectrum, white.count != channels { return cube }
        if let black = blackSpectrum, black.count != channels { return cube }
        
        let targetMin = parameters.targetMin
        let targetMax = parameters.targetMax
        
        let totalElements = dims.0 * dims.1 * dims.2
        var resultData = [Double](repeating: 0, count: totalElements)
        
        for ch in 0..<channels {
            let whiteVal = whiteSpectrum?[ch] ?? 1.0
            let blackVal = blackSpectrum?[ch] ?? 0.0
            let range = whiteVal - blackVal
            let scale = range != 0 ? (targetMax - targetMin) / range : 1.0
            
            for h in 0..<height {
                for w in 0..<width {
                    var indices = [0, 0, 0]
                    indices[axes.channel] = ch
                    indices[axes.height] = h
                    indices[axes.width] = w
                    
                    let srcIndex = cube.linearIndex(i0: indices[0], i1: indices[1], i2: indices[2])
                    let value = cube.getValue(at: srcIndex)
                    
                    let calibrated: Double
                    if range != 0 {
                        calibrated = targetMin + (value - blackVal) * scale
                    } else {
                        calibrated = value
                    }
                    
                    let dstIndex = linearIndex(
                        i0: indices[0],
                        i1: indices[1],
                        i2: indices[2],
                        dims: dims,
                        fortran: cube.isFortranOrder
                    )
                    resultData[dstIndex] = calibrated
                }
            }
        }
        
        return HyperCube(
            dims: dims,
            storage: .float64(resultData),
            sourceFormat: cube.sourceFormat,
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
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

class CubeSpectralTrimmer {
    static func trim(cube: HyperCube, parameters: SpectralTrimParameters, layout: CubeLayout) -> HyperCube? {
        let start = max(0, parameters.startChannel)
        let end = max(start, parameters.endChannel)
        guard let axes = cube.axes(for: layout) else { return cube }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let channelCount = dims[axes.channel]
        guard channelCount > 0 else { return cube }
        let clampedEnd = min(end, channelCount - 1)
        guard start <= clampedEnd else { return cube }
        
        let height = dims[axes.height]
        let width = dims[axes.width]
        let newChannelCount = clampedEnd - start + 1
        var newDims = dims
        newDims[axes.channel] = newChannelCount
        let totalNewElements = newDims[0] * newDims[1] * newDims[2]
        
        func buildIndices(ch: Int, h: Int, w: Int) -> (Int, Int, Int) {
            var i0 = 0, i1 = 0, i2 = 0
            
            if axes.channel == 0 { i0 = ch }
            else if axes.channel == 1 { i1 = ch }
            else { i2 = ch }
            
            if axes.height == 0 { i0 = h }
            else if axes.height == 1 { i1 = h }
            else { i2 = h }
            
            if axes.width == 0 { i0 = w }
            else if axes.width == 1 { i1 = w }
            else { i2 = w }
            
            return (i0, i1, i2)
        }

        func outputIndex(ch: Int, h: Int, w: Int) -> Int {
            let (o0, o1, o2) = buildIndices(ch: ch, h: h, w: w)
            return linearIndex(dims: newDims, fortran: cube.isFortranOrder, i0: o0, i1: o1, i2: o2)
        }
        
        let newWavelengths: [Double]? = {
            guard let wavelengths = cube.wavelengths, wavelengths.count == channelCount else { return nil }
            return Array(wavelengths[start...clampedEnd])
        }()
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .float64(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .float32(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .uint16(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .uint8(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int16(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int32(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
            
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int8(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths
            )
        }
    }

    private static func linearIndex(dims: [Int], fortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if fortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        }
        return i2 + dims[2] * (i1 + dims[1] * i0)
    }
}

class CubeSpectralInterpolator {
    static func interpolate(cube: HyperCube, parameters: SpectralInterpolationParameters, layout: CubeLayout) -> HyperCube? {
        guard let wavelengths = cube.wavelengths, !wavelengths.isEmpty else { return cube }
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        let channelCount = dimsArray[axes.channel]
        guard channelCount > 0, wavelengths.count == channelCount else { return cube }
        
        let targetCount = parameters.targetChannelCount
        guard targetCount > 0 else { return cube }
        
        let targetMin = parameters.targetMinLambda
        let targetMax = parameters.targetMaxLambda
        let targetWavelengths = buildTargetWavelengths(min: targetMin, max: targetMax, count: targetCount)
        
        let (sortedWavelengths, indexMap) = sortedWavelengthsIfNeeded(wavelengths)
        let outputChannels = targetWavelengths.count
        
        dimsArray[axes.channel] = outputChannels
        let totalElements = dimsArray[0] * dimsArray[1] * dimsArray[2]
        
        switch parameters.dataType {
        case .float64:
            var output = [Double](repeating: 0, count: totalElements)
            fillOutput(
                cube: cube,
                axes: axes,
                dims: dimsArray,
                sortedWavelengths: sortedWavelengths,
                indexMap: indexMap,
                targetWavelengths: targetWavelengths,
                method: parameters.method,
                extrapolation: parameters.extrapolation,
                into: &output
            )
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: .float64(output),
                sourceFormat: cube.sourceFormat + " [Spectral]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: targetWavelengths
            )
        case .float32:
            var output = [Float](repeating: 0, count: totalElements)
            fillOutput(
                cube: cube,
                axes: axes,
                dims: dimsArray,
                sortedWavelengths: sortedWavelengths,
                indexMap: indexMap,
                targetWavelengths: targetWavelengths,
                method: parameters.method,
                extrapolation: parameters.extrapolation,
                into: &output
            )
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Spectral]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: targetWavelengths
            )
        }
    }
    
    private static func buildTargetWavelengths(min: Double, max: Double, count: Int) -> [Double] {
        guard count > 1 else { return [min] }
        let step = (max - min) / Double(count - 1)
        return (0..<count).map { min + Double($0) * step }
    }
    
    private static func sortedWavelengthsIfNeeded(_ wavelengths: [Double]) -> ([Double], [Int]) {
        let isSorted = zip(wavelengths, wavelengths.dropFirst()).allSatisfy { $0 < $1 }
        if isSorted {
            return (wavelengths, Array(0..<wavelengths.count))
        }
        let indices = wavelengths.indices.sorted { wavelengths[$0] < wavelengths[$1] }
        let sorted = indices.map { wavelengths[$0] }
        return (sorted, indices)
    }
    
    private static func fillOutput(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        dims: [Int],
        sortedWavelengths: [Double],
        indexMap: [Int],
        targetWavelengths: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode,
        into output: inout [Double]
    ) {
        let height = dims[axes.height]
        let width = dims[axes.width]
        let outputChannels = targetWavelengths.count
        let inputChannels = sortedWavelengths.count
        
        var spectrum = [Double](repeating: 0, count: inputChannels)
        
        for y in 0..<height {
            for x in 0..<width {
                for (sortedIdx, originalIdx) in indexMap.enumerated() {
                    var idx3 = [0, 0, 0]
                    idx3[axes.channel] = originalIdx
                    idx3[axes.height] = y
                    idx3[axes.width] = x
                    let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                    spectrum[sortedIdx] = cube.getValue(at: lin)
                }
                
                for c in 0..<outputChannels {
                    let lambda = targetWavelengths[c]
                    let value = interpolate(
                        x: lambda,
                        xs: sortedWavelengths,
                        ys: spectrum,
                        method: method,
                        extrapolation: extrapolation
                    )
                    
                    var outIdx3 = [0, 0, 0]
                    outIdx3[axes.channel] = c
                    outIdx3[axes.height] = y
                    outIdx3[axes.width] = x
                    let outLin = linearIndex(dims: dims, fortran: cube.isFortranOrder, i0: outIdx3[0], i1: outIdx3[1], i2: outIdx3[2])
                    output[outLin] = value
                }
            }
        }
    }
    
    private static func fillOutput(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        dims: [Int],
        sortedWavelengths: [Double],
        indexMap: [Int],
        targetWavelengths: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode,
        into output: inout [Float]
    ) {
        let height = dims[axes.height]
        let width = dims[axes.width]
        let outputChannels = targetWavelengths.count
        let inputChannels = sortedWavelengths.count
        
        let xs = sortedWavelengths.map { Float($0) }
        let targets = targetWavelengths.map { Float($0) }
        var spectrum = [Float](repeating: 0, count: inputChannels)
        
        for y in 0..<height {
            for x in 0..<width {
                for (sortedIdx, originalIdx) in indexMap.enumerated() {
                    var idx3 = [0, 0, 0]
                    idx3[axes.channel] = originalIdx
                    idx3[axes.height] = y
                    idx3[axes.width] = x
                    let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                    spectrum[sortedIdx] = Float(cube.getValue(at: lin))
                }
                
                for c in 0..<outputChannels {
                    let lambda = targets[c]
                    let value = interpolate(
                        x: lambda,
                        xs: xs,
                        ys: spectrum,
                        method: method,
                        extrapolation: extrapolation
                    )
                    
                    var outIdx3 = [0, 0, 0]
                    outIdx3[axes.channel] = c
                    outIdx3[axes.height] = y
                    outIdx3[axes.width] = x
                    let outLin = linearIndex(dims: dims, fortran: cube.isFortranOrder, i0: outIdx3[0], i1: outIdx3[1], i2: outIdx3[2])
                    output[outLin] = value
                }
            }
        }
    }
    
    private static func linearIndex(dims: [Int], fortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if fortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        }
        return i2 + dims[2] * (i1 + dims[1] * i0)
    }
    
    private static func interpolate(
        x: Double,
        xs: [Double],
        ys: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode
    ) -> Double {
        guard xs.count == ys.count, !xs.isEmpty else { return 0 }
        if xs.count == 1 { return ys[0] }
        
        switch method {
        case .nearest:
            return nearest(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .linear:
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .cubic:
            return cubic(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
    }
    
    private static func interpolate(
        x: Float,
        xs: [Float],
        ys: [Float],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode
    ) -> Float {
        guard xs.count == ys.count, !xs.isEmpty else { return 0 }
        if xs.count == 1 { return ys[0] }
        
        switch method {
        case .nearest:
            return nearest(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .linear:
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .cubic:
            return cubic(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
    }
    
    private static func nearest(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        let i = lowerBound(x: x, xs: xs)
        let left = max(0, min(i - 1, n - 1))
        let right = max(0, min(i, n - 1))
        return abs(xs[left] - x) <= abs(xs[right] - x) ? ys[left] : ys[right]
    }
    
    private static func linear(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if x <= xs[0] {
            return extrapolation == .clamp ? ys[0] : linearSegment(x: x, x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
        }
        if x >= xs[n - 1] {
            return extrapolation == .clamp ? ys[n - 1] : linearSegment(x: x, x0: xs[n - 2], x1: xs[n - 1], y0: ys[n - 2], y1: ys[n - 1])
        }
        let i = lowerBound(x: x, xs: xs)
        let i0 = max(0, i - 1)
        let i1 = min(n - 1, i)
        return linearSegment(x: x, x0: xs[i0], x1: xs[i1], y0: ys[i0], y1: ys[i1])
    }
    
    private static func cubic(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if n < 4 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        
        if x <= xs[0] {
            if extrapolation == .clamp { return ys[0] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: 0, i1: 1, i2: 2, i3: 3)
        }
        if x >= xs[n - 1] {
            if extrapolation == .clamp { return ys[n - 1] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: n - 4, i1: n - 3, i2: n - 2, i3: n - 1)
        }
        
        let i = lowerBound(x: x, xs: xs)
        let i1 = max(1, min(i, n - 2))
        let i0 = max(0, i1 - 1)
        let i2 = min(n - 1, i1 + 1)
        let i3 = min(n - 1, i1 + 2)
        if i0 == i1 || i2 == i3 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        return cubicLagrange(x: x, xs: xs, ys: ys, i0: i0, i1: i1, i2: i2, i3: i3)
    }
    
    private static func lowerBound(x: Double, xs: [Double]) -> Int {
        var low = 0
        var high = xs.count
        while low < high {
            let mid = (low + high) / 2
            if xs[mid] < x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    
    private static func linearSegment(x: Double, x0: Double, x1: Double, y0: Double, y1: Double) -> Double {
        let denom = x1 - x0
        guard abs(denom) > 1e-12 else { return y0 }
        let t = (x - x0) / denom
        return y0 + t * (y1 - y0)
    }
    
    private static func cubicLagrange(x: Double, xs: [Double], ys: [Double], i0: Int, i1: Int, i2: Int, i3: Int) -> Double {
        let x0 = xs[i0], x1 = xs[i1], x2 = xs[i2], x3 = xs[i3]
        let y0 = ys[i0], y1 = ys[i1], y2 = ys[i2], y3 = ys[i3]
        let l0 = ((x - x1) * (x - x2) * (x - x3)) / ((x0 - x1) * (x0 - x2) * (x0 - x3))
        let l1 = ((x - x0) * (x - x2) * (x - x3)) / ((x1 - x0) * (x1 - x2) * (x1 - x3))
        let l2 = ((x - x0) * (x - x1) * (x - x3)) / ((x2 - x0) * (x2 - x1) * (x2 - x3))
        let l3 = ((x - x0) * (x - x1) * (x - x2)) / ((x3 - x0) * (x3 - x1) * (x3 - x2))
        return y0 * l0 + y1 * l1 + y2 * l2 + y3 * l3
    }
    
    private static func nearest(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        let i = lowerBound(x: x, xs: xs)
        let left = max(0, min(i - 1, n - 1))
        let right = max(0, min(i, n - 1))
        return abs(xs[left] - x) <= abs(xs[right] - x) ? ys[left] : ys[right]
    }
    
    private static func linear(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if x <= xs[0] {
            return extrapolation == .clamp ? ys[0] : linearSegment(x: x, x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
        }
        if x >= xs[n - 1] {
            return extrapolation == .clamp ? ys[n - 1] : linearSegment(x: x, x0: xs[n - 2], x1: xs[n - 1], y0: ys[n - 2], y1: ys[n - 1])
        }
        let i = lowerBound(x: x, xs: xs)
        let i0 = max(0, i - 1)
        let i1 = min(n - 1, i)
        return linearSegment(x: x, x0: xs[i0], x1: xs[i1], y0: ys[i0], y1: ys[i1])
    }
    
    private static func cubic(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if n < 4 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        if x <= xs[0] {
            if extrapolation == .clamp { return ys[0] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: 0, i1: 1, i2: 2, i3: 3)
        }
        if x >= xs[n - 1] {
            if extrapolation == .clamp { return ys[n - 1] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: n - 4, i1: n - 3, i2: n - 2, i3: n - 1)
        }
        let i = lowerBound(x: x, xs: xs)
        let i1 = max(1, min(i, n - 2))
        let i0 = max(0, i1 - 1)
        let i2 = min(n - 1, i1 + 1)
        let i3 = min(n - 1, i1 + 2)
        if i0 == i1 || i2 == i3 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        return cubicLagrange(x: x, xs: xs, ys: ys, i0: i0, i1: i1, i2: i2, i3: i3)
    }
    
    private static func lowerBound(x: Float, xs: [Float]) -> Int {
        var low = 0
        var high = xs.count
        while low < high {
            let mid = (low + high) / 2
            if xs[mid] < x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    
    private static func linearSegment(x: Float, x0: Float, x1: Float, y0: Float, y1: Float) -> Float {
        let denom = x1 - x0
        if abs(denom) < 1e-7 { return y0 }
        let t = (x - x0) / denom
        return y0 + t * (y1 - y0)
    }
    
    private static func cubicLagrange(x: Float, xs: [Float], ys: [Float], i0: Int, i1: Int, i2: Int, i3: Int) -> Float {
        let x0 = xs[i0], x1 = xs[i1], x2 = xs[i2], x3 = xs[i3]
        let y0 = ys[i0], y1 = ys[i1], y2 = ys[i2], y3 = ys[i3]
        let l0 = ((x - x1) * (x - x2) * (x - x3)) / ((x0 - x1) * (x0 - x2) * (x0 - x3))
        let l1 = ((x - x0) * (x - x2) * (x - x3)) / ((x1 - x0) * (x1 - x2) * (x1 - x3))
        let l2 = ((x - x0) * (x - x1) * (x - x3)) / ((x2 - x0) * (x2 - x1) * (x2 - x3))
        let l3 = ((x - x0) * (x - x1) * (x - x2)) / ((x3 - x0) * (x3 - x1) * (x3 - x2))
        return y0 * l0 + y1 * l1 + y2 * l2 + y3 * l3
    }
}
