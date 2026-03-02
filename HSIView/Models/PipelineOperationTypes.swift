import Foundation

enum PipelineOperationType: String, CaseIterable, Identifiable {
    case normalization = "Нормализация"
    case channelwiseNormalization = "Поканальная нормализация"
    case dataTypeConversion = "Тип данных"
    case clipping = "Клиппинг"
    case rotation = "Поворот"
    case transpose = "Транспонирование"
    case resize = "Изменение размера"
    case spatialCrop = "Обрезка области"
    case spectralTrim = "Обрезка длин волн"
    case calibration = "Калибровка"
    case spectralInterpolation = "Спектральная интерполяция"
    case spectralAlignment = "Спектральное выравнивание"
    case customPython = "Кастомная обработка"
    
    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }
    
    var iconName: String {
        switch self {
        case .normalization:
            return "chart.line.uptrend.xyaxis"
        case .channelwiseNormalization:
            return "chart.bar.xaxis"
        case .dataTypeConversion:
            return "arrow.triangle.2.circlepath"
        case .clipping:
            return "arrow.up.and.down"
        case .rotation:
            return "rotate.right"
        case .transpose:
            return "arrow.left.and.right.righttriangle.left.righttriangle.right"
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
        case .spectralAlignment:
            return "camera.metering.center.weighted"
        case .customPython:
            return "terminal"
        }
    }
    
    var description: String {
        switch self {
        case .normalization:
            return L("Применить нормализацию к данным")
        case .channelwiseNormalization:
            return L("Применить нормализацию отдельно к каждому каналу")
        case .dataTypeConversion:
            return L("Изменить тип данных")
        case .clipping:
            return L("Ограничить значения диапазоном")
        case .rotation:
            return L("Повернуть изображение на 90°, 180° или 270°")
        case .transpose:
            return L("Переставить оси массива в выбранный порядок HWC")
        case .resize:
            return L("Изменить размер пространственных измерений")
        case .spatialCrop:
            return L("Обрезать изображение по пространственным границам")
        case .spectralTrim:
            return L("Обрезать спектральный диапазон по каналам")
        case .calibration:
            return L("Калибровка по белой и/или чёрной точке")
        case .spectralInterpolation:
            return L("Изменить спектральное разрешение по длинам волн")
        case .spectralAlignment:
            return L("Выровнять каналы по эталонному каналу")
        case .customPython:
            return L("Запустить пользовательский Python-код для обработки ГСИ")
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

struct ClippingParameters: Equatable {
    var lower: Double
    var upper: Double
    
    static let `default` = ClippingParameters(lower: 0.0, upper: 1.0)
}

enum ResizeAlgorithm: String, CaseIterable, Identifiable {
    case nearest = "По ближайшему соседу"
    case bilinear = "Билинейная"
    case bicubic = "Бикубическая"
    case bspline = "Сплайн"
    case lanczos = "Ланцош"
    
    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }
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
    var targetWavelengths: [Double]?
    var method: SpectralInterpolationMethod
    var extrapolation: SpectralExtrapolationMode
    var dataType: SpectralInterpolationDataType
    var isConfiguredByUser: Bool
    
    static let `default` = SpectralInterpolationParameters(
        targetChannelCount: 0,
        targetMinLambda: 0,
        targetMaxLambda: 0,
        targetWavelengths: nil,
        method: .linear,
        extrapolation: .clamp,
        dataType: .float64,
        isConfiguredByUser: false
    )
}

enum SpatialAutoCropMetric: String, CaseIterable, Identifiable {
    case ssim = "SSIM"
    case mse = "MSE"

    var id: String { rawValue }
}

struct SpatialAutoCropSettings: Equatable {
    var referenceLibraryID: String?
    var metric: SpatialAutoCropMetric
    var sourceChannels: [Int]
    var referenceChannels: [Int]
    var minWidth: Int?
    var maxWidth: Int?
    var minHeight: Int?
    var maxHeight: Int?
    var saveAspectRatio: Bool
    var aspectRatioTolerancePercent: Double
    var enableEarlyCandidatePruning: Bool
    var positionStep: Int
    var sizeStep: Int
    var useCoarseToFine: Bool
    var keepRefinementReserve: Bool
    var downsampleFactor: Int

    static let `default` = SpatialAutoCropSettings(
        referenceLibraryID: nil,
        metric: .ssim,
        sourceChannels: [0],
        referenceChannels: [0],
        minWidth: nil,
        maxWidth: nil,
        minHeight: nil,
        maxHeight: nil,
        saveAspectRatio: false,
        aspectRatioTolerancePercent: 5.0,
        enableEarlyCandidatePruning: true,
        positionStep: 4,
        sizeStep: 4,
        useCoarseToFine: true,
        keepRefinementReserve: true,
        downsampleFactor: 2
    )
}

struct SpatialAutoCropResult: Equatable {
    var metric: SpatialAutoCropMetric
    var bestScore: Double
    var evaluatedCandidates: Int
    var referenceLibraryID: String?
    var sourceChannels: [Int]
    var referenceChannels: [Int]
    var selectedWidth: Int
    var selectedHeight: Int
}

struct SpatialCropParameters: Equatable {
    var left: Int
    var right: Int
    var top: Int
    var bottom: Int
    var autoCropSettings: SpatialAutoCropSettings? = nil
    var autoCropResult: SpatialAutoCropResult? = nil
    
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

struct SpatialAutoCropProgressInfo {
    var progress: Double
    var message: String
    var evaluatedCandidates: Int
    var totalCandidates: Int
    var bestCrop: SpatialCropParameters?
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

struct TransposeParameters: Equatable {
    var order: String
    
    var normalizedOrder: String {
        CubeLayout.normalizeHWCOrder(order)
    }
    
    var targetLayout: CubeLayout? {
        CubeLayout.parseHWCOrder(order)
    }
    
    static let `default` = TransposeParameters(order: CubeLayout.hwc.rawValue)
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

enum CalibrationScanDirection: String, CaseIterable, Identifiable {
    case leftToRight = "Слева направо"
    case rightToLeft = "Справа налево"
    case bottomToTop = "Снизу вверх"
    case topToBottom = "Сверху вниз"
    
    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }
}

enum WhitePointSearchPreset: String, CaseIterable, Identifiable {
    case balanced = "Сбалансированный"
    case spectralonPriority = "Приоритет Spectralon"
    case lowLight = "Низкая освещённость"
    case harshLight = "Сильные засветки"

    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }

    var localizedDescription: String {
        switch self {
        case .balanced:
            return L("pipeline.calibration.auto_white.preset.desc.balanced")
        case .spectralonPriority:
            return L("pipeline.calibration.auto_white.preset.desc.spectralon")
        case .lowLight:
            return L("pipeline.calibration.auto_white.preset.desc.low_light")
        case .harshLight:
            return L("pipeline.calibration.auto_white.preset.desc.harsh_light")
        }
    }
}

enum WhitePointWindowPreset: String, CaseIterable, Identifiable {
    case balanced = "Сбалансированное окно"
    case smallTargets = "Мелкие цели"
    case largePanels = "Крупные панели"
    case denseScan = "Плотное сканирование"
    case fastScan = "Быстрое сканирование"

    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }

    var localizedDescription: String {
        switch self {
        case .balanced:
            return L("pipeline.calibration.auto_white.window_preset.desc.balanced")
        case .smallTargets:
            return L("pipeline.calibration.auto_white.window_preset.desc.small_targets")
        case .largePanels:
            return L("pipeline.calibration.auto_white.window_preset.desc.large_panels")
        case .denseScan:
            return L("pipeline.calibration.auto_white.window_preset.desc.dense_scan")
        case .fastScan:
            return L("pipeline.calibration.auto_white.window_preset.desc.fast_scan")
        }
    }
}

struct CalibrationRefData: Equatable {
    let values: [Double]
    let channels: Int
    let scanLength: Int
    let sourceName: String
    
    func value(channel: Int, scanIndex: Int) -> Double {
        values[scanIndex * channels + channel]
    }
    
    static func from(refCube: HyperCube, expectedChannels: Int, sourceName: String) -> Result<CalibrationRefData, CalibrationRefError> {
        let dims = [refCube.dims.0, refCube.dims.1, refCube.dims.2]
        guard expectedChannels > 0 else {
            return .failure(CalibrationRefError(L("Неизвестное число каналов")))
        }
        
        let channelAxes = dims.enumerated().compactMap { index, value in
            value == expectedChannels ? index : nil
        }
        
        guard let channelAxis = channelAxes.first else {
            return .failure(CalibrationRefError(LF("pipeline.calibration.ref_channels_mismatch", expectedChannels)))
        }
        
        let remainingAxes = [0, 1, 2].filter { $0 != channelAxis }
        let scanAxisCandidates = remainingAxes.filter { dims[$0] > 1 }
        
        guard scanAxisCandidates.count == 1 else {
            return .failure(CalibrationRefError(L("REF должен быть 2D (B×W). Проверьте размеры файла.")))
        }
        
        let scanAxis = scanAxisCandidates[0]
        let otherAxis = remainingAxes.first { $0 != scanAxis } ?? channelAxis
        
        if dims[otherAxis] != 1 {
            return .failure(CalibrationRefError(L("REF должен быть 2D (B×W) с третьей размерностью = 1")))
        }
        
        let scanLength = dims[scanAxis]
        guard scanLength > 0 else {
            return .failure(CalibrationRefError(L("REF имеет пустую ширину")))
        }
        
        var values = [Double](repeating: 0, count: expectedChannels * scanLength)
        
        for scan in 0..<scanLength {
            for ch in 0..<expectedChannels {
                var indices = [0, 0, 0]
                indices[channelAxis] = ch
                indices[scanAxis] = scan
                indices[otherAxis] = 0
                let idx = refCube.linearIndex(i0: indices[0], i1: indices[1], i2: indices[2])
                values[scan * expectedChannels + ch] = refCube.getValue(at: idx)
            }
        }
        
        return .success(
            CalibrationRefData(
                values: values,
                channels: expectedChannels,
                scanLength: scanLength,
                sourceName: sourceName
            )
        )
    }
}

struct CalibrationRefError: Error, LocalizedError {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var errorDescription: String? {
        message
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
        displayName ?? LF("pipeline.sample.point_name", pixelX, pixelY)
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
    var whiteRef: CalibrationRefData?
    var blackRef: CalibrationRefData?
    var autoWhiteSearchEnabled: Bool = false
    var autoWhiteSearchPreset: WhitePointSearchPreset = .balanced
    var autoWhiteWindowPreset: WhitePointWindowPreset = .balanced
    var useScanDirection: Bool = false
    var scanDirection: CalibrationScanDirection = .topToBottom
    var targetMin: Double = 0.0
    var targetMax: Double = 1.0
    var clampOutput: Bool = true
    
    var isConfigured: Bool {
        whiteSpectrum != nil || blackSpectrum != nil || whiteRef != nil || blackRef != nil
    }
    
    var summaryText: String {
        var parts: [String] = []
        if whiteRef != nil { parts.append(L("белая REF")) }
        if whiteRef == nil && whiteSpectrum != nil { parts.append(L("белая")) }
        if blackRef != nil { parts.append(L("чёрная REF")) }
        if blackRef == nil && blackSpectrum != nil { parts.append(L("чёрная")) }
        if parts.isEmpty { return L("Не настроено") }
        return parts.joined(separator: " + ")
    }
    
    static let `default` = CalibrationParameters()
}

struct SpectralTrimParameters: Equatable {
    var startChannel: Int
    var endChannel: Int
}

enum SpectralAlignmentMethod: String, CaseIterable, Identifiable {
    case coordinateDescent = "Координатный спуск"
    case differentialEvolution = "Дифф. эволюция"
    case hybrid = "Гибридный"
    
    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }
}

enum SpectralAlignmentMetric: String, CaseIterable, Identifiable {
    case ssim = "SSIM"
    case psnr = "PSNR"
    
    var id: String { rawValue }
}

struct AlignmentPoint: Equatable {
    var x: Double
    var y: Double
    
    static func defaultCorners() -> [AlignmentPoint] {
        return [
            AlignmentPoint(x: 0.15, y: 0.15),
            AlignmentPoint(x: 0.85, y: 0.15),
            AlignmentPoint(x: 0.85, y: 0.85),
            AlignmentPoint(x: 0.15, y: 0.85)
        ]
    }
}

struct SpectralAlignmentResult: Equatable {
    var channelScores: [Double]
    var channelOffsets: [(dx: Int, dy: Int)]
    var averageScore: Double
    var referenceChannel: Int
    var metricName: String
    
    static func == (lhs: SpectralAlignmentResult, rhs: SpectralAlignmentResult) -> Bool {
        return lhs.channelScores == rhs.channelScores &&
               lhs.averageScore == rhs.averageScore &&
               lhs.referenceChannel == rhs.referenceChannel &&
               lhs.metricName == rhs.metricName &&
               lhs.channelOffsets.count == rhs.channelOffsets.count &&
               zip(lhs.channelOffsets, rhs.channelOffsets).allSatisfy { $0.dx == $1.dx && $0.dy == $1.dy }
    }
}

struct SpectralAlignmentParameters: Equatable {
    var referenceChannel: Int
    var method: SpectralAlignmentMethod
    var offsetMin: Int
    var offsetMax: Int
    var step: Int
    var metric: SpectralAlignmentMetric
    var cachedHomographies: [[Double]]?
    var alignmentResult: SpectralAlignmentResult?
    var isComputed: Bool
    var referencePoints: [AlignmentPoint]
    var useManualPoints: Bool
    var shouldCompute: Bool
    var iterations: Int
    var enableSubpixel: Bool
    var enableMultiscale: Bool
    
    var canApply: Bool {
        return isComputed || shouldCompute
    }
    
    func estimatedTimeSeconds(channelCount: Int) -> Double {
        let channelsToProcess = channelCount - 1
        guard channelsToProcess > 0 else { return 0 }
        
        let offsetRange = offsetMax - offsetMin + 1
        let pointsPerAxis = offsetRange / max(step, 1)
        let totalSearchPoints = pointsPerAxis * pointsPerAxis
        
        var baseTimePerChannel: Double
        switch method {
        case .coordinateDescent:
            baseTimePerChannel = Double(iterations) * Double(pointsPerAxis) * 2 * 0.02
        case .differentialEvolution:
            baseTimePerChannel = Double(totalSearchPoints) * 0.015
        case .hybrid:
            baseTimePerChannel = Double(iterations) * Double(pointsPerAxis) * 2 * 0.02 + Double(step * 2 + 1) * Double(step * 2 + 1) * 0.01
        }
        
        if enableMultiscale {
            baseTimePerChannel *= 0.6
        }
        
        if enableSubpixel {
            baseTimePerChannel += 0.5
        }
        
        let totalTime = baseTimePerChannel * Double(channelsToProcess) * 4
        return totalTime
    }
    
    func formattedEstimatedTime(channelCount: Int) -> String {
        let seconds = estimatedTimeSeconds(channelCount: channelCount)
        if seconds < 60 {
            return LF("pipeline.time.about_seconds", Int(seconds))
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return LF("pipeline.time.about_minutes_seconds", minutes, secs)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return LF("pipeline.time.about_hours_minutes", hours, minutes)
        }
    }
    
    static let `default` = SpectralAlignmentParameters(
        referenceChannel: 0,
        method: .hybrid,
        offsetMin: -5,
        offsetMax: 5,
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
    
    static func == (lhs: SpectralAlignmentParameters, rhs: SpectralAlignmentParameters) -> Bool {
        return lhs.referenceChannel == rhs.referenceChannel &&
               lhs.method == rhs.method &&
               lhs.offsetMin == rhs.offsetMin &&
               lhs.offsetMax == rhs.offsetMax &&
               lhs.step == rhs.step &&
               lhs.metric == rhs.metric &&
               lhs.isComputed == rhs.isComputed &&
               lhs.cachedHomographies == rhs.cachedHomographies &&
               lhs.alignmentResult == rhs.alignmentResult &&
               lhs.referencePoints == rhs.referencePoints &&
               lhs.useManualPoints == rhs.useManualPoints
    }
}

