import Foundation

extension HyperCube {
    struct Statistics {
        let min: Double
        let max: Double
        let mean: Double
        let stdDev: Double
    }
    
    func statistics() -> Statistics {
        let count = storage.count
        guard count > 0 else {
            return Statistics(min: 0, max: 0, mean: 0, stdDev: 0)
        }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        var sum = 0.0
        
        for i in 0..<count {
            let val = storage.getValue(at: i)
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
            sum += val
        }
        
        let mean = sum / Double(count)
        
        var sumSquaredDiff = 0.0
        for i in 0..<count {
            let val = storage.getValue(at: i)
            let diff = val - mean
            sumSquaredDiff += diff * diff
        }
        
        let variance = sumSquaredDiff / Double(count)
        let stdDev = sqrt(variance)
        
        return Statistics(min: minVal, max: maxVal, mean: mean, stdDev: stdDev)
    }
    
    func channelStatistics(layout: CubeLayout, channelIndex: Int) -> Statistics? {
        guard let axes = axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = dims
        let dimsArr = [d0, d1, d2]
        
        let cCount = dimsArr[axes.channel]
        guard channelIndex >= 0 && channelIndex < cCount else { return nil }
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        
        var values = [Double]()
        values.reserveCapacity(h * w)
        
        for y in 0..<h {
            for x in 0..<w {
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = channelIndex
                idx3[axes.height] = y
                idx3[axes.width] = x
                
                let lin = linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                values.append(getValue(at: lin))
            }
        }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        var sum = 0.0
        
        for val in values {
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
            sum += val
        }
        
        let mean = sum / Double(values.count)
        
        var sumSquaredDiff = 0.0
        for val in values {
            let diff = val - mean
            sumSquaredDiff += diff * diff
        }
        
        let variance = sumSquaredDiff / Double(values.count)
        let stdDev = sqrt(variance)
        
        return Statistics(min: minVal, max: maxVal, mean: mean, stdDev: stdDev)
    }
    
    func pixelSpectrum(layout: CubeLayout, x: Int, y: Int) -> [Double]? {
        guard let axes = axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = dims
        let dimsArr = [d0, d1, d2]
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        let cCount = dimsArr[axes.channel]
        
        guard x >= 0 && x < w && y >= 0 && y < h else { return nil }
        
        var spectrum = [Double]()
        spectrum.reserveCapacity(cCount)
        
        for c in 0..<cCount {
            var idx3 = [0, 0, 0]
            idx3[axes.channel] = c
            idx3[axes.height] = y
            idx3[axes.width] = x
            
            let lin = linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
            spectrum.append(getValue(at: lin))
        }
        
        return spectrum
    }
}


