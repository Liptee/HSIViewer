import Foundation

enum NDIndexPreset: String, CaseIterable, Identifiable {
    case ndvi = "NDVI"
    case ndsi = "NDSI"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ndvi: return "NDVI (растительность)"
        case .ndsi: return "NDSI (снег)"
        }
    }
}

enum NDPalette: String, CaseIterable, Identifiable {
    case classic = "Классическая"
    case grayscale = "Градации серого"
    case binaryVegetation = "Бинарная"
    
    var id: String { rawValue }
}
