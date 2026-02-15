import Foundation

enum NDIndexPreset: String, CaseIterable, Identifiable {
    case ndvi = "NDVI"
    case ndsi = "NDSI"
    case wdvi = "WDVI"
    
    var id: String { rawValue }
    
    var localizedTitle: String {
        switch self {
        case .ndvi: return L("NDVI (растительность)")
        case .ndsi: return L("NDSI (снег)")
        case .wdvi: return L("WDVI (почвенная линия)")
        }
    }

    var title: String { localizedTitle }
}

enum NDPalette: String, CaseIterable, Identifiable {
    case classic = "Классическая"
    case grayscale = "Градации серого"
    case binaryVegetation = "Бинарная"
    
    var id: String { rawValue }

    var localizedTitle: String {
        L(rawValue)
    }
}
