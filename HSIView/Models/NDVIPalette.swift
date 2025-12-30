import Foundation

enum NDVIPalette: String, CaseIterable, Identifiable {
    case classic = "Классическая"
    case grayscale = "Градации серого"
    case binaryVegetation = "Бинарная"
    
    var id: String { rawValue }
}
