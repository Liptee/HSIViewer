import Foundation

enum ImageLoadError: LocalizedError {
    case fileNotFound
    case unsupportedFormat(String)
    case corruptedData
    case invalidDimensions
    case memoryAllocationFailed
    case readError(String)
    case notA3DCube
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return L("Файл не найден")
        case .unsupportedFormat(let format):
            return LF("image_load.error.unsupported_format", format)
        case .corruptedData:
            return L("Поврежденные данные")
        case .invalidDimensions:
            return L("Некорректные размеры")
        case .memoryAllocationFailed:
            return L("Ошибка выделения памяти")
        case .readError(let details):
            return LF("image_load.error.read_details", details)
        case .notA3DCube:
            return L("Файл не содержит 3D гиперкуб")
        }
    }
}

