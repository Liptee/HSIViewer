import Foundation

enum PipelineOperationType: String, CaseIterable, Identifiable {
    case normalization = "Нормализация"
    case dataTypeConversion = "Тип данных"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .normalization:
            return "chart.line.uptrend.xyaxis"
        case .dataTypeConversion:
            return "arrow.triangle.2.circlepath"
        }
    }
    
    var description: String {
        switch self {
        case .normalization:
            return "Применить нормализацию к данным"
        case .dataTypeConversion:
            return "Изменить тип данных"
        }
    }
}

struct PipelineOperation: Identifiable, Equatable {
    let id: UUID
    let type: PipelineOperationType
    var normalizationType: CubeNormalizationType?
    var normalizationParams: CubeNormalizationParameters?
    var targetDataType: DataType?
    var autoScale: Bool?
    
    init(id: UUID = UUID(), type: PipelineOperationType) {
        self.id = id
        self.type = type
        
        switch type {
        case .normalization:
            self.normalizationType = .none
            self.normalizationParams = .default
        case .dataTypeConversion:
            self.targetDataType = .float64
            self.autoScale = true
        }
    }
    
    var displayName: String {
        switch type {
        case .normalization:
            return normalizationType?.rawValue ?? "Нормализация"
        case .dataTypeConversion:
            return targetDataType?.rawValue ?? "Тип данных"
        }
    }
    
    var detailsText: String {
        switch type {
        case .normalization:
            guard let normType = normalizationType else { return "" }
            switch normType {
            case .none:
                return "Без нормализации"
            case .minMax:
                return "[0, 1]"
            case .minMaxCustom:
                if let params = normalizationParams {
                    return String(format: "[%.2f, %.2f]", params.minValue, params.maxValue)
                }
                return "Custom"
            case .percentile:
                if let params = normalizationParams {
                    return String(format: "%.0f%%-%.0f%%", params.lowerPercentile, params.upperPercentile)
                }
                return "Percentile"
            case .zScore:
                return "Z-Score"
            case .log:
                return "log(x+1)"
            case .sqrt:
                return "√x"
            }
        case .dataTypeConversion:
            var text = targetDataType?.rawValue ?? ""
            if let autoScale = autoScale, autoScale {
                text += " (auto)"
            } else {
                text += " (clamp)"
            }
            return text
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
            return CubeNormalizer.apply(normType, to: cube, parameters: params)
            
        case .dataTypeConversion:
            guard let targetType = targetDataType,
                  let autoScale = autoScale else { return cube }
            return DataTypeConverter.convert(cube, to: targetType, autoScale: autoScale)
        }
    }
}

