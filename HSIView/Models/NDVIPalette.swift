import Foundation

enum NDIndexPreset: String, CaseIterable, Identifiable {
    case ndvi = "NDVI"
    case ndsi = "NDSI"
    case wdvi = "WDVI"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ndvi: return "NDVI (растительность)"
        case .ndsi: return "NDSI (снег)"
        case .wdvi: return "WDVI (почвенная линия)"
        }
    }
}

enum NDPalette: String, CaseIterable, Identifiable {
    case classic = "Классическая"
    case grayscale = "Градации серого"
    case binaryVegetation = "Бинарная"
    
    var id: String { rawValue }
}
