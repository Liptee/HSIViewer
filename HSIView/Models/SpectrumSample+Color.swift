import SwiftUI

extension SpectrumSample {
    var displayColor: Color {
        Color(nsColor)
    }
    
    func trimmed(to range: ClosedRange<Int>) -> SpectrumSample? {
        guard !values.isEmpty else { return nil }
        let maxIndex = values.count - 1
        guard range.lowerBound <= maxIndex else { return nil }
        let lower = max(0, min(range.lowerBound, maxIndex))
        let upper = max(lower, min(range.upperBound, maxIndex))
        guard lower <= upper else { return nil }
        
        let trimmedValues = Array(values[lower...upper])
        let trimmedWavelengths: [Double]? = {
            guard let wavelengths else { return nil }
            guard wavelengths.count > upper else { return nil }
            return Array(wavelengths[lower...upper])
        }()
        
        return SpectrumSample(
            id: id,
            pixelX: pixelX,
            pixelY: pixelY,
            values: trimmedValues,
            wavelengths: trimmedWavelengths,
            colorIndex: colorIndex
        )
    }
}

extension SpectrumROISample {
    var displayColor: Color {
        Color(nsColor)
    }
}
