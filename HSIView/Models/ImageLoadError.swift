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
            return "Файл не найден"
        case .unsupportedFormat(let format):
            return "Неподдерживаемый формат: \(format)"
        case .corruptedData:
            return "Поврежденные данные"
        case .invalidDimensions:
            return "Некорректные размеры"
        case .memoryAllocationFailed:
            return "Ошибка выделения памяти"
        case .readError(let details):
            return "Ошибка чтения: \(details)"
        case .notA3DCube:
            return "Файл не содержит 3D гиперкуб"
        }
    }
}


