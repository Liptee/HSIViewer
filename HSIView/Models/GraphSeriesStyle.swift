import SwiftUI

enum SeriesLinePattern: String, CaseIterable, Identifiable {
    case solid
    case dotted
    case dashed
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .solid: return L("Сплошная")
        case .dotted: return L("Точечная")
        case .dashed: return L("Пунктирная")
        }
    }
    
    func strokeStyle(lineWidth: Double) -> StrokeStyle {
        switch self {
        case .solid:
            return StrokeStyle(lineWidth: lineWidth)
        case .dotted:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [1, 4])
        case .dashed:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 4])
        }
    }
}

struct SeriesStyleOverride: Equatable {
    var linePattern: SeriesLinePattern
    var lineWidth: Double
    var opacity: Double
    var showPoints: Bool
    
    init(
        linePattern: SeriesLinePattern = .solid,
        lineWidth: Double = 1.5,
        opacity: Double = 1.0,
        showPoints: Bool = false
    ) {
        self.linePattern = linePattern
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.showPoints = showPoints
    }
}
