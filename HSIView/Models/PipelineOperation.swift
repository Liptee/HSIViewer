import Foundation

struct PipelineOperation: Identifiable, Equatable {
    let id: UUID
    let type: PipelineOperationType
    var normalizationType: CubeNormalizationType?
    var normalizationParams: CubeNormalizationParameters?
    var preserveDataType: Bool?
    var targetDataType: DataType?
    var autoScale: Bool?
    var clippingParams: ClippingParameters?
    var rotationAngle: RotationAngle?
    var transposeParameters: TransposeParameters?
    var layout: CubeLayout = .auto
    var cropParameters: SpatialCropParameters?
    var calibrationParams: CalibrationParameters?
    var resizeParameters: ResizeParameters?
    var spectralTrimParams: SpectralTrimParameters?
    var spectralInterpolationParams: SpectralInterpolationParameters?
    var spectralAlignmentParams: SpectralAlignmentParameters?
    var customPythonConfig: CustomPythonOperationConfig?
    
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
        case .clipping:
            self.clippingParams = .default
        case .rotation:
            self.rotationAngle = .degree90
        case .transpose:
            self.transposeParameters = .default
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
        case .spectralAlignment:
            self.spectralAlignmentParams = .default
        case .customPython:
            self.customPythonConfig = .empty
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
        case .transpose:
            let sourceLayout = layout == .auto ? .hwc : layout
            let targetLayout: CubeLayout = sourceLayout == .hwc ? .chw : .hwc
            transposeParameters = TransposeParameters(order: targetLayout.rawValue)
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
                    targetWavelengths: nil,
                    method: .linear,
                    extrapolation: .clamp,
                    dataType: .float64,
                    isConfiguredByUser: false
                )
            }
        case .spectralAlignment:
            let channelCount = cube.channelCount(for: layout)
            spectralAlignmentParams = SpectralAlignmentParameters(
                referenceChannel: channelCount / 2,
                method: .hybrid,
                offsetMin: -8,
                offsetMax: 8,
                step: 1,
                metric: .ssim,
                cachedHomographies: nil,
                alignmentResult: nil,
                isComputed: false,
                referencePoints: AlignmentPoint.defaultCorners(),
                useManualPoints: false,
                shouldCompute: false,
                iterations: 2,
                enableSubpixel: true,
                enableMultiscale: true
            )
        case .customPython:
            if var config = customPythonConfig {
                if config.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    config.script = CustomPythonOperationTemplate.defaultScript(layout: layout)
                }
                if config.templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    config.templateName = L("custom.python.operation.default_name")
                }
                customPythonConfig = config
            } else {
                customPythonConfig = CustomPythonOperationConfig(
                    templateID: nil,
                    templateName: L("custom.python.operation.default_name"),
                    script: CustomPythonOperationTemplate.defaultScript(layout: layout)
                )
            }
        default:
            break
        }
    }
    
    var displayName: String {
        switch type {
        case .normalization, .channelwiseNormalization:
            return normalizationType?.localizedTitle ?? type.localizedTitle
        case .dataTypeConversion:
            return targetDataType?.rawValue ?? L("Тип данных")
        case .clipping:
            return L("Клиппинг")
        case .rotation:
            return LF("pipeline.operation.display.rotation", rotationAngle?.rawValue ?? "")
        case .transpose:
            if let params = transposeParameters {
                return LF("pipeline.operation.display.transpose_to", params.normalizedOrder)
            }
            return L("Транспонирование")
        case .resize:
            if let params = resizeParameters {
                return LF("pipeline.operation.display.resize_to", params.targetWidth, params.targetHeight, params.algorithm.localizedTitle)
            }
            return L("Изменение размера")
        case .spatialCrop:
            return L("Обрезка области")
        case .spectralTrim:
            return L("Обрезка спектра")
        case .calibration:
            return L("Калибровка")
        case .spectralInterpolation:
            return L("Интерполяция спектра")
        case .spectralAlignment:
            return L("Спектральное выравнивание")
        case .customPython:
            return customPythonConfig?.templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (customPythonConfig?.templateName ?? L("custom.python.operation.default_name"))
                : L("custom.python.operation.default_name")
        }
    }
    
    var detailsText: String {
        switch type {
        case .normalization, .channelwiseNormalization:
            guard let normType = normalizationType else { return "" }
            let prefix = type == .channelwiseNormalization ? L("По каналам: ") : ""
            switch normType {
            case .none:
                    return prefix + L("Без нормализации")
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
                return prefix + L("Диапазон")
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
        case .clipping:
            if let params = clippingParams {
                return String(format: "[%.3f, %.3f]", params.lower, params.upper)
            }
            return L("Настройте диапазон")
        case .rotation:
            return L("По часовой стрелке")
        case .transpose:
            guard let params = transposeParameters else { return L("Введите порядок HWC") }
            guard let target = params.targetLayout else {
                return LF("pipeline.operation.details.invalid_order", params.order)
            }
            return "\(layout.rawValue) → \(target.rawValue)"
        case .resize:
            if let params = resizeParameters {
                return LF("pipeline.operation.details.resize_to", params.targetWidth, params.targetHeight, params.algorithm.localizedTitle)
            }
            return L("Изменение размера")
        case .spatialCrop:
            if let params = cropParameters {
                var text = "x: \(params.left)–\(params.right) px, y: \(params.top)–\(params.bottom) px"
                if let auto = params.autoCropResult {
                    let scoreText = String(format: auto.metric == .ssim ? "%.4f" : "%.6f", auto.bestScore)
                    text += LF("pipeline.operation.details.auto_metric", L(auto.metric.rawValue), scoreText)
                }
                return text
            }
            return L("Настройте границы")
        case .spectralTrim:
            if let params = spectralTrimParams {
                let count = max(0, params.endChannel - params.startChannel + 1)
                return LF("pipeline.operation.details.channels_range_count", params.startChannel, params.endChannel, count)
            }
            return L("Настройте диапазон")
        case .calibration:
            return calibrationParams?.summaryText ?? L("Не настроено")
        case .spectralInterpolation:
            if let params = spectralInterpolationParams {
                if !params.isConfiguredByUser {
                    return L("Настройте параметры")
                }
                if let customWavelengths = params.targetWavelengths, !customWavelengths.isEmpty {
                    return LF("pipeline.operation.details.spectral_interp_file_channels", customWavelengths.count, params.method.rawValue)
                }
                return LF("pipeline.operation.details.spectral_interp_channels", params.targetChannelCount, params.method.rawValue)
            }
            return L("Настройте параметры")
        case .spectralAlignment:
            if let params = spectralAlignmentParams {
                let status = params.isComputed ? "✓" : "⏳"
                return LF("pipeline.operation.details.spectral_alignment_status", status, params.referenceChannel, L(params.metric.rawValue))
            }
            return L("Настройте параметры")
        case .customPython:
            let layoutLabel = layout == .auto ? "Auto" : layout.rawValue
            return LF("custom.python.operation.details", layoutLabel)
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
            
        case .clipping:
            guard let params = clippingParams else { return cube }
            return CubeClipper.clip(cube: cube, parameters: params, layout: layout)
            
        case .rotation:
            guard let angle = rotationAngle else { return cube }
            return CubeRotator.rotate(cube, angle: angle, layout: layout)
        case .transpose:
            guard let params = transposeParameters,
                  let targetLayout = params.targetLayout else { return cube }
            return CubeTransposer.transpose(cube: cube, sourceLayout: layout, targetLayout: targetLayout)
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
            guard let params = spectralInterpolationParams, params.isConfiguredByUser else { return cube }
            return CubeSpectralInterpolator.interpolate(cube: cube, parameters: params, layout: layout)
        case .spectralAlignment:
            guard let params = spectralAlignmentParams, params.canApply else { return cube }
            var mutableParams = params
            let result = CubeSpectralAligner.align(cube: cube, parameters: &mutableParams, layout: layout, progressCallback: nil)
            return result
        case .customPython:
            return cube
        }
    }
    
    mutating func applyWithUpdate(to cube: HyperCube, progressCallback: ((Double, String) -> Void)? = nil) -> HyperCube? {
        switch type {
        case .spectralAlignment:
            guard let params = spectralAlignmentParams, params.canApply else { return cube }
            var mutableParams = params
            let result = CubeSpectralAligner.align(cube: cube, parameters: &mutableParams, layout: layout, progressCallback: progressCallback)
            mutableParams.shouldCompute = false
            self.spectralAlignmentParams = mutableParams
            return result
        default:
            return apply(to: cube)
        }
    }
    
    mutating func applyWithUpdateDetailed(to cube: HyperCube, progressCallback: ((AlignmentProgressInfo) -> Void)? = nil) -> HyperCube? {
        switch type {
        case .spectralAlignment:
            guard let params = spectralAlignmentParams, params.canApply else { return cube }
            var mutableParams = params
            let result = CubeSpectralAligner.alignWithDetailedProgress(cube: cube, parameters: &mutableParams, layout: layout, progressCallback: progressCallback)
            mutableParams.shouldCompute = false
            self.spectralAlignmentParams = mutableParams
            return result
        default:
            return apply(to: cube)
        }
    }
}

extension PipelineOperation {
    func clonedWithNewID() -> PipelineOperation {
        var copy = PipelineOperation(type: type)
        copy.normalizationType = normalizationType
        copy.normalizationParams = normalizationParams
        copy.preserveDataType = preserveDataType
        copy.targetDataType = targetDataType
        copy.autoScale = autoScale
        copy.clippingParams = clippingParams
        copy.rotationAngle = rotationAngle
        copy.transposeParameters = transposeParameters
        copy.layout = layout
        copy.cropParameters = cropParameters
        copy.calibrationParams = calibrationParams
        copy.resizeParameters = resizeParameters
        copy.spectralTrimParams = spectralTrimParams
        copy.spectralInterpolationParams = spectralInterpolationParams
        copy.customPythonConfig = customPythonConfig
        if var alignment = spectralAlignmentParams {
            alignment.cachedHomographies = nil
            alignment.alignmentResult = nil
            alignment.isComputed = false
            if !alignment.shouldCompute {
                alignment.shouldCompute = true
            }
            copy.spectralAlignmentParams = alignment
        } else {
            copy.spectralAlignmentParams = nil
        }
        return copy
    }

    func isNoOp(for cube: HyperCube?, layout: CubeLayout) -> Bool {
        guard let cube else { return false }
        guard let axes = cube.axes(for: layout) ?? cube.axes(for: .auto) else { return false }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let width = dims[axes.width]
        let height = dims[axes.height]
        let channelCount = dims[axes.channel]
        
        switch type {
        case .transpose:
            guard let params = transposeParameters,
                  let targetLayout = params.targetLayout else { return true }
            let sourceLayout = self.layout == .auto ? layout : self.layout
            return sourceLayout == targetLayout
        case .resize:
            guard let params = resizeParameters else { return true }
            return params.targetWidth == width && params.targetHeight == height
        case .spatialCrop:
            guard let params = cropParameters else { return true }
            return params.left == 0 && params.top == 0 && params.right == width - 1 && params.bottom == height - 1
        case .spectralTrim:
            guard let params = spectralTrimParams else { return true }
            return params.startChannel == 0 && params.endChannel == max(channelCount - 1, 0)
        case .spectralInterpolation:
            guard let params = spectralInterpolationParams else { return true }
            return !params.isConfiguredByUser
        case .dataTypeConversion:
            guard let targetType = targetDataType else { return true }
            return targetType == cube.originalDataType
        case .customPython:
            return false
        default:
            return false
        }
    }
}

