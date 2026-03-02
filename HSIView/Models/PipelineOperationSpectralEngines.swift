import Foundation

class CubeClipper {
    static func clip(cube: HyperCube, parameters: ClippingParameters, layout: CubeLayout) -> HyperCube? {
        let lower = min(parameters.lower, parameters.upper)
        let upper = max(parameters.lower, parameters.upper)
        guard lower != -Double.infinity || upper != Double.infinity else { return cube }
        
        switch cube.storage {
        case .float64(let arr):
            let output = arr.map { min(upper, max(lower, $0)) }
            return HyperCube(dims: cube.dims, storage: .float64(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .float32(let arr):
            let lowerF = Float(lower)
            let upperF = Float(upper)
            let output = arr.map { min(upperF, max(lowerF, $0)) }
            return HyperCube(dims: cube.dims, storage: .float32(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint16(let arr):
            let bounds = intBounds(minValue: UInt16.min, maxValue: UInt16.max, lower: lower, upper: upper)
            let output = arr.map { UInt16(clamping: Int64(clampInt(Double($0), bounds))) }
            return HyperCube(dims: cube.dims, storage: .uint16(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint8(let arr):
            let bounds = intBounds(minValue: UInt8.min, maxValue: UInt8.max, lower: lower, upper: upper)
            let output = arr.map { UInt8(clamping: Int64(clampInt(Double($0), bounds))) }
            return HyperCube(dims: cube.dims, storage: .uint8(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int16(let arr):
            let bounds = intBounds(minValue: Int16.min, maxValue: Int16.max, lower: lower, upper: upper)
            let output = arr.map { Int16(clamping: Int64(clampInt(Double($0), bounds))) }
            return HyperCube(dims: cube.dims, storage: .int16(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int32(let arr):
            let bounds = intBounds(minValue: Int32.min, maxValue: Int32.max, lower: lower, upper: upper)
            let output = arr.map { Int32(clamping: Int64(clampInt(Double($0), bounds))) }
            return HyperCube(dims: cube.dims, storage: .int32(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int8(let arr):
            let bounds = intBounds(minValue: Int8.min, maxValue: Int8.max, lower: lower, upper: upper)
            let output = arr.map { Int8(clamping: Int64(clampInt(Double($0), bounds))) }
            return HyperCube(dims: cube.dims, storage: .int8(output), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        }
    }
    
    private static func intBounds<T: FixedWidthInteger>(
        minValue: T,
        maxValue: T,
        lower: Double,
        upper: Double
    ) -> (Double, Double) {
        let lowerBound = Swift.max(lower, Double(minValue))
        let upperBound = Swift.min(upper, Double(maxValue))
        return (lowerBound, upperBound)
    }
    
    private static func clampInt(_ value: Double, _ bounds: (Double, Double)) -> Double {
        let (lower, upper) = bounds
        return min(upper, max(lower, value))
    }
}

class CubeSpectralTrimmer {
    static func trim(cube: HyperCube, parameters: SpectralTrimParameters, layout: CubeLayout) -> HyperCube? {
        let start = max(0, parameters.startChannel)
        let end = max(start, parameters.endChannel)
        guard let axes = cube.axes(for: layout) else { return cube }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let channelCount = dims[axes.channel]
        guard channelCount > 0 else { return cube }
        let clampedEnd = min(end, channelCount - 1)
        guard start <= clampedEnd else { return cube }
        
        let height = dims[axes.height]
        let width = dims[axes.width]
        let newChannelCount = clampedEnd - start + 1
        var newDims = dims
        newDims[axes.channel] = newChannelCount
        let totalNewElements = newDims[0] * newDims[1] * newDims[2]
        
        func buildIndices(ch: Int, h: Int, w: Int) -> (Int, Int, Int) {
            var i0 = 0, i1 = 0, i2 = 0
            
            if axes.channel == 0 { i0 = ch }
            else if axes.channel == 1 { i1 = ch }
            else { i2 = ch }
            
            if axes.height == 0 { i0 = h }
            else if axes.height == 1 { i1 = h }
            else { i2 = h }
            
            if axes.width == 0 { i0 = w }
            else if axes.width == 1 { i1 = w }
            else { i2 = w }
            
            return (i0, i1, i2)
        }

        func outputIndex(ch: Int, h: Int, w: Int) -> Int {
            let (o0, o1, o2) = buildIndices(ch: ch, h: h, w: w)
            return linearIndex(dims: newDims, fortran: cube.isFortranOrder, i0: o0, i1: o1, i2: o2)
        }
        
        let newWavelengths: [Double]? = {
            guard let wavelengths = cube.wavelengths, wavelengths.count == channelCount else { return nil }
            return Array(wavelengths[start...clampedEnd])
        }()
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .float64(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .float32(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .uint16(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .uint8(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int16(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int32(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
            
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalNewElements)
            for ch in start...clampedEnd {
                for h in 0..<height {
                    for w in 0..<width {
                        let (i0, i1, i2) = buildIndices(ch: ch, h: h, w: w)
                        let idx = cube.linearIndex(i0: i0, i1: i1, i2: i2)
                        let outIdx = outputIndex(ch: ch - start, h: h, w: w)
                        newData[outIdx] = arr[idx]
                    }
                }
            }
            return HyperCube(
                dims: (newDims[0], newDims[1], newDims[2]),
                storage: .int8(newData),
                sourceFormat: cube.sourceFormat + " [Trim]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: newWavelengths, geoReference: cube.geoReference)
        }
    }

    private static func linearIndex(dims: [Int], fortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if fortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        }
        return i2 + dims[2] * (i1 + dims[1] * i0)
    }
}

class CubeSpectralInterpolator {
    static func interpolate(cube: HyperCube, parameters: SpectralInterpolationParameters, layout: CubeLayout) -> HyperCube? {
        guard let wavelengths = cube.wavelengths, !wavelengths.isEmpty else { return cube }
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        let channelCount = dimsArray[axes.channel]
        guard channelCount > 0, wavelengths.count == channelCount else { return cube }
        
        let targetWavelengths: [Double]
        if let explicitTargets = sanitizedTargetWavelengths(parameters.targetWavelengths) {
            targetWavelengths = explicitTargets
        } else {
            let targetCount = parameters.targetChannelCount
            guard targetCount > 0 else { return cube }
            let targetMin = parameters.targetMinLambda
            let targetMax = parameters.targetMaxLambda
            targetWavelengths = buildTargetWavelengths(min: targetMin, max: targetMax, count: targetCount)
        }
        
        let (sortedWavelengths, indexMap) = sortedWavelengthsIfNeeded(wavelengths)
        let outputChannels = targetWavelengths.count
        
        dimsArray[axes.channel] = outputChannels
        let totalElements = dimsArray[0] * dimsArray[1] * dimsArray[2]
        
        switch parameters.dataType {
        case .float64:
            var output = [Double](repeating: 0, count: totalElements)
            fillOutput(
                cube: cube,
                axes: axes,
                dims: dimsArray,
                sortedWavelengths: sortedWavelengths,
                indexMap: indexMap,
                targetWavelengths: targetWavelengths,
                method: parameters.method,
                extrapolation: parameters.extrapolation,
                into: &output
            )
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: .float64(output),
                sourceFormat: cube.sourceFormat + " [Spectral]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: targetWavelengths, geoReference: cube.geoReference)
        case .float32:
            var output = [Float](repeating: 0, count: totalElements)
            fillOutput(
                cube: cube,
                axes: axes,
                dims: dimsArray,
                sortedWavelengths: sortedWavelengths,
                indexMap: indexMap,
                targetWavelengths: targetWavelengths,
                method: parameters.method,
                extrapolation: parameters.extrapolation,
                into: &output
            )
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: .float32(output),
                sourceFormat: cube.sourceFormat + " [Spectral]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: targetWavelengths, geoReference: cube.geoReference)
        }
    }
    
    private static func buildTargetWavelengths(min: Double, max: Double, count: Int) -> [Double] {
        guard count > 1 else { return [min] }
        let step = (max - min) / Double(count - 1)
        return (0..<count).map { min + Double($0) * step }
    }

    private static func sanitizedTargetWavelengths(_ wavelengths: [Double]?) -> [Double]? {
        guard let wavelengths, !wavelengths.isEmpty else { return nil }
        guard wavelengths.allSatisfy({ $0.isFinite }) else { return nil }
        return wavelengths
    }
    
    private static func sortedWavelengthsIfNeeded(_ wavelengths: [Double]) -> ([Double], [Int]) {
        let isSorted = zip(wavelengths, wavelengths.dropFirst()).allSatisfy { $0 < $1 }
        if isSorted {
            return (wavelengths, Array(0..<wavelengths.count))
        }
        let indices = wavelengths.indices.sorted { wavelengths[$0] < wavelengths[$1] }
        let sorted = indices.map { wavelengths[$0] }
        return (sorted, indices)
    }
    
    private static func fillOutput(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        dims: [Int],
        sortedWavelengths: [Double],
        indexMap: [Int],
        targetWavelengths: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode,
        into output: inout [Double]
    ) {
        let height = dims[axes.height]
        let width = dims[axes.width]
        let outputChannels = targetWavelengths.count
        let inputChannels = sortedWavelengths.count
        
        var spectrum = [Double](repeating: 0, count: inputChannels)
        
        for y in 0..<height {
            for x in 0..<width {
                for (sortedIdx, originalIdx) in indexMap.enumerated() {
                    var idx3 = [0, 0, 0]
                    idx3[axes.channel] = originalIdx
                    idx3[axes.height] = y
                    idx3[axes.width] = x
                    let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                    spectrum[sortedIdx] = cube.getValue(at: lin)
                }
                
                for c in 0..<outputChannels {
                    let lambda = targetWavelengths[c]
                    let value = interpolate(
                        x: lambda,
                        xs: sortedWavelengths,
                        ys: spectrum,
                        method: method,
                        extrapolation: extrapolation
                    )
                    
                    var outIdx3 = [0, 0, 0]
                    outIdx3[axes.channel] = c
                    outIdx3[axes.height] = y
                    outIdx3[axes.width] = x
                    let outLin = linearIndex(dims: dims, fortran: cube.isFortranOrder, i0: outIdx3[0], i1: outIdx3[1], i2: outIdx3[2])
                    output[outLin] = value
                }
            }
        }
    }
    
    private static func fillOutput(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        dims: [Int],
        sortedWavelengths: [Double],
        indexMap: [Int],
        targetWavelengths: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode,
        into output: inout [Float]
    ) {
        let height = dims[axes.height]
        let width = dims[axes.width]
        let outputChannels = targetWavelengths.count
        let inputChannels = sortedWavelengths.count
        
        let xs = sortedWavelengths.map { Float($0) }
        let targets = targetWavelengths.map { Float($0) }
        var spectrum = [Float](repeating: 0, count: inputChannels)
        
        for y in 0..<height {
            for x in 0..<width {
                for (sortedIdx, originalIdx) in indexMap.enumerated() {
                    var idx3 = [0, 0, 0]
                    idx3[axes.channel] = originalIdx
                    idx3[axes.height] = y
                    idx3[axes.width] = x
                    let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                    spectrum[sortedIdx] = Float(cube.getValue(at: lin))
                }
                
                for c in 0..<outputChannels {
                    let lambda = targets[c]
                    let value = interpolate(
                        x: lambda,
                        xs: xs,
                        ys: spectrum,
                        method: method,
                        extrapolation: extrapolation
                    )
                    
                    var outIdx3 = [0, 0, 0]
                    outIdx3[axes.channel] = c
                    outIdx3[axes.height] = y
                    outIdx3[axes.width] = x
                    let outLin = linearIndex(dims: dims, fortran: cube.isFortranOrder, i0: outIdx3[0], i1: outIdx3[1], i2: outIdx3[2])
                    output[outLin] = value
                }
            }
        }
    }
    
    private static func linearIndex(dims: [Int], fortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if fortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        }
        return i2 + dims[2] * (i1 + dims[1] * i0)
    }
    
    private static func interpolate(
        x: Double,
        xs: [Double],
        ys: [Double],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode
    ) -> Double {
        guard xs.count == ys.count, !xs.isEmpty else { return 0 }
        if xs.count == 1 { return ys[0] }
        
        switch method {
        case .nearest:
            return nearest(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .linear:
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .cubic:
            return cubic(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
    }
    
    private static func interpolate(
        x: Float,
        xs: [Float],
        ys: [Float],
        method: SpectralInterpolationMethod,
        extrapolation: SpectralExtrapolationMode
    ) -> Float {
        guard xs.count == ys.count, !xs.isEmpty else { return 0 }
        if xs.count == 1 { return ys[0] }
        
        switch method {
        case .nearest:
            return nearest(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .linear:
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        case .cubic:
            return cubic(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
    }
    
    private static func nearest(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        let i = lowerBound(x: x, xs: xs)
        let left = max(0, min(i - 1, n - 1))
        let right = max(0, min(i, n - 1))
        return abs(xs[left] - x) <= abs(xs[right] - x) ? ys[left] : ys[right]
    }
    
    private static func linear(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if x <= xs[0] {
            return extrapolation == .clamp ? ys[0] : linearSegment(x: x, x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
        }
        if x >= xs[n - 1] {
            return extrapolation == .clamp ? ys[n - 1] : linearSegment(x: x, x0: xs[n - 2], x1: xs[n - 1], y0: ys[n - 2], y1: ys[n - 1])
        }
        let i = lowerBound(x: x, xs: xs)
        let i0 = max(0, i - 1)
        let i1 = min(n - 1, i)
        return linearSegment(x: x, x0: xs[i0], x1: xs[i1], y0: ys[i0], y1: ys[i1])
    }
    
    private static func cubic(x: Double, xs: [Double], ys: [Double], extrapolation: SpectralExtrapolationMode) -> Double {
        let n = xs.count
        if n < 4 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        
        if x <= xs[0] {
            if extrapolation == .clamp { return ys[0] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: 0, i1: 1, i2: 2, i3: 3)
        }
        if x >= xs[n - 1] {
            if extrapolation == .clamp { return ys[n - 1] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: n - 4, i1: n - 3, i2: n - 2, i3: n - 1)
        }
        
        let i = lowerBound(x: x, xs: xs)
        let i1 = max(1, min(i, n - 2))
        let i0 = max(0, i1 - 1)
        let i2 = min(n - 1, i1 + 1)
        let i3 = min(n - 1, i1 + 2)
        if i0 == i1 || i2 == i3 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        return cubicLagrange(x: x, xs: xs, ys: ys, i0: i0, i1: i1, i2: i2, i3: i3)
    }
    
    private static func lowerBound(x: Double, xs: [Double]) -> Int {
        var low = 0
        var high = xs.count
        while low < high {
            let mid = (low + high) / 2
            if xs[mid] < x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    
    private static func linearSegment(x: Double, x0: Double, x1: Double, y0: Double, y1: Double) -> Double {
        let denom = x1 - x0
        guard abs(denom) > 1e-12 else { return y0 }
        let t = (x - x0) / denom
        return y0 + t * (y1 - y0)
    }
    
    private static func cubicLagrange(x: Double, xs: [Double], ys: [Double], i0: Int, i1: Int, i2: Int, i3: Int) -> Double {
        let x0 = xs[i0], x1 = xs[i1], x2 = xs[i2], x3 = xs[i3]
        let y0 = ys[i0], y1 = ys[i1], y2 = ys[i2], y3 = ys[i3]
        let l0 = ((x - x1) * (x - x2) * (x - x3)) / ((x0 - x1) * (x0 - x2) * (x0 - x3))
        let l1 = ((x - x0) * (x - x2) * (x - x3)) / ((x1 - x0) * (x1 - x2) * (x1 - x3))
        let l2 = ((x - x0) * (x - x1) * (x - x3)) / ((x2 - x0) * (x2 - x1) * (x2 - x3))
        let l3 = ((x - x0) * (x - x1) * (x - x2)) / ((x3 - x0) * (x3 - x1) * (x3 - x2))
        return y0 * l0 + y1 * l1 + y2 * l2 + y3 * l3
    }
    
    private static func nearest(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        let i = lowerBound(x: x, xs: xs)
        let left = max(0, min(i - 1, n - 1))
        let right = max(0, min(i, n - 1))
        return abs(xs[left] - x) <= abs(xs[right] - x) ? ys[left] : ys[right]
    }
    
    private static func linear(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if x <= xs[0] {
            return extrapolation == .clamp ? ys[0] : linearSegment(x: x, x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
        }
        if x >= xs[n - 1] {
            return extrapolation == .clamp ? ys[n - 1] : linearSegment(x: x, x0: xs[n - 2], x1: xs[n - 1], y0: ys[n - 2], y1: ys[n - 1])
        }
        let i = lowerBound(x: x, xs: xs)
        let i0 = max(0, i - 1)
        let i1 = min(n - 1, i)
        return linearSegment(x: x, x0: xs[i0], x1: xs[i1], y0: ys[i0], y1: ys[i1])
    }
    
    private static func cubic(x: Float, xs: [Float], ys: [Float], extrapolation: SpectralExtrapolationMode) -> Float {
        let n = xs.count
        if n < 4 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        if x <= xs[0] {
            if extrapolation == .clamp { return ys[0] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: 0, i1: 1, i2: 2, i3: 3)
        }
        if x >= xs[n - 1] {
            if extrapolation == .clamp { return ys[n - 1] }
            return cubicLagrange(x: x, xs: xs, ys: ys, i0: n - 4, i1: n - 3, i2: n - 2, i3: n - 1)
        }
        let i = lowerBound(x: x, xs: xs)
        let i1 = max(1, min(i, n - 2))
        let i0 = max(0, i1 - 1)
        let i2 = min(n - 1, i1 + 1)
        let i3 = min(n - 1, i1 + 2)
        if i0 == i1 || i2 == i3 {
            return linear(x: x, xs: xs, ys: ys, extrapolation: extrapolation)
        }
        return cubicLagrange(x: x, xs: xs, ys: ys, i0: i0, i1: i1, i2: i2, i3: i3)
    }
    
    private static func lowerBound(x: Float, xs: [Float]) -> Int {
        var low = 0
        var high = xs.count
        while low < high {
            let mid = (low + high) / 2
            if xs[mid] < x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    
    private static func linearSegment(x: Float, x0: Float, x1: Float, y0: Float, y1: Float) -> Float {
        let denom = x1 - x0
        if abs(denom) < 1e-7 { return y0 }
        let t = (x - x0) / denom
        return y0 + t * (y1 - y0)
    }
    
    private static func cubicLagrange(x: Float, xs: [Float], ys: [Float], i0: Int, i1: Int, i2: Int, i3: Int) -> Float {
        let x0 = xs[i0], x1 = xs[i1], x2 = xs[i2], x3 = xs[i3]
        let y0 = ys[i0], y1 = ys[i1], y2 = ys[i2], y3 = ys[i3]
        let l0 = ((x - x1) * (x - x2) * (x - x3)) / ((x0 - x1) * (x0 - x2) * (x0 - x3))
        let l1 = ((x - x0) * (x - x2) * (x - x3)) / ((x1 - x0) * (x1 - x2) * (x1 - x3))
        let l2 = ((x - x0) * (x - x1) * (x - x3)) / ((x2 - x0) * (x2 - x1) * (x2 - x3))
        let l3 = ((x - x0) * (x - x1) * (x - x2)) / ((x3 - x0) * (x3 - x1) * (x3 - x2))
        return y0 * l0 + y1 * l1 + y2 * l2 + y3 * l3
    }
}

struct AlignmentProgressInfo {
    var progress: Double
    var message: String
    var currentChannel: Int
    var totalChannels: Int
    var stage: String
}

class CubeSpectralAligner {
    
    static func align(cube: HyperCube, parameters: inout SpectralAlignmentParameters, layout: CubeLayout, progressCallback: ((Double, String) -> Void)?) -> HyperCube? {
        
        let detailedCallback: ((AlignmentProgressInfo) -> Void)? = progressCallback != nil ? { info in
            progressCallback?(info.progress, info.message)
        } : nil
        
        return alignWithDetailedProgress(cube: cube, parameters: &parameters, layout: layout, progressCallback: detailedCallback)
    }
    
    static func alignWithDetailedProgress(cube: HyperCube, parameters: inout SpectralAlignmentParameters, layout: CubeLayout, progressCallback: ((AlignmentProgressInfo) -> Void)?) -> HyperCube? {
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        let channels = dimsArray[axes.channel]
        
        guard channels > 1, height > 0, width > 0 else { return cube }
        guard parameters.referenceChannel >= 0, parameters.referenceChannel < channels else { return cube }
        
        if let cached = parameters.cachedHomographies, cached.count == channels, parameters.isComputed {
            progressCallback?(AlignmentProgressInfo(progress: 1.0, message: L("Применение сохранённых параметров…"), currentChannel: 0, totalChannels: channels, stage: "apply"))
            return applyHomographies(cube: cube, homographies: cached, axes: axes, layout: layout)
        }
        
        progressCallback?(AlignmentProgressInfo(progress: 0.0, message: LF("pipeline.alignment.progress.extract_reference_channel", parameters.referenceChannel + 1), currentChannel: 0, totalChannels: channels, stage: "extract_ref"))
        
        let refChannel = extractChannel(cube: cube, channelIndex: parameters.referenceChannel, axes: axes)
        var homographies: [[Double]] = []
        var channelScores: [Double] = []
        var channelOffsets: [(dx: Int, dy: Int)] = []
        
        let channelsToProcess = channels - 1
        var processedChannels = 0
        
        for ch in 0..<channels {
            if ch == parameters.referenceChannel {
                homographies.append([1, 0, 0, 0, 1, 0, 0, 0, 1])
                channelScores.append(1.0)
                channelOffsets.append((dx: 0, dy: 0))
                continue
            }
            
            let progress = Double(processedChannels) / Double(channelsToProcess) * 0.9
            progressCallback?(AlignmentProgressInfo(
                progress: progress,
                message: LF("pipeline.alignment.progress.channel_extract_data", ch + 1, channels),
                currentChannel: ch + 1,
                totalChannels: channels,
                stage: "extract"
            ))
            
            let channelData = extractChannel(cube: cube, channelIndex: ch, axes: axes)
            
            progressCallback?(AlignmentProgressInfo(
                progress: progress + 0.02,
                message: LF("pipeline.alignment.progress.channel_search_homography", ch + 1, channels),
                currentChannel: ch + 1,
                totalChannels: channels,
                stage: "homography"
            ))
            
            let (H, score) = findBestHomographyWithScore(
                channelData: channelData,
                refData: refChannel,
                width: width,
                height: height,
                offsetMin: parameters.offsetMin,
                offsetMax: parameters.offsetMax,
                step: parameters.step,
                metric: parameters.metric,
                method: parameters.method,
                iterations: parameters.iterations,
                useRefinement: parameters.enableSubpixel,
                useMultiscale: parameters.enableMultiscale
            )
            homographies.append(H)
            channelScores.append(score)
            
            let avgDx = (H[2] + H[0] * Double(width) / 2 + H[1] * Double(height) / 2) / H[8] - Double(width) / 2
            let avgDy = (H[5] + H[3] * Double(width) / 2 + H[4] * Double(height) / 2) / H[8] - Double(height) / 2
            channelOffsets.append((dx: Int(round(avgDx)), dy: Int(round(avgDy))))
            
            processedChannels += 1
            
            let scoreStr = String(format: "%.4f", score)
            progressCallback?(AlignmentProgressInfo(
                progress: Double(processedChannels) / Double(channelsToProcess) * 0.9,
                message: LF("pipeline.alignment.progress.channel_metric_score", ch + 1, channels, L(parameters.metric.rawValue), scoreStr),
                currentChannel: ch + 1,
                totalChannels: channels,
                stage: "done"
            ))
        }
        
        let validScores = channelScores.filter { $0 > 0 && $0.isFinite }
        let avgScore = validScores.isEmpty ? 0.0 : validScores.reduce(0, +) / Double(validScores.count)
        
        parameters.cachedHomographies = homographies
        parameters.alignmentResult = SpectralAlignmentResult(
            channelScores: channelScores,
            channelOffsets: channelOffsets,
            averageScore: avgScore,
            referenceChannel: parameters.referenceChannel,
            metricName: parameters.metric.rawValue
        )
        parameters.isComputed = true
        
        progressCallback?(AlignmentProgressInfo(progress: 0.95, message: LF("pipeline.alignment.progress.apply_homographies_to_channels", channels), currentChannel: channels, totalChannels: channels, stage: "apply"))
        let result = applyHomographies(cube: cube, homographies: homographies, axes: axes, layout: layout)
        progressCallback?(AlignmentProgressInfo(progress: 1.0, message: LF("pipeline.alignment.progress.completed_average", L(parameters.metric.rawValue), String(format: "%.4f", avgScore)), currentChannel: channels, totalChannels: channels, stage: "complete"))
        
        return result
    }
    
    private static func extractChannel(cube: HyperCube, channelIndex: Int, axes: (channel: Int, height: Int, width: Int)) -> [Double] {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        
        var result = [Double](repeating: 0, count: height * width)
        
        for y in 0..<height {
            for x in 0..<width {
                var idx = [0, 0, 0]
                idx[axes.channel] = channelIndex
                idx[axes.height] = y
                idx[axes.width] = x
                let linearIdx = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                result[y * width + x] = cube.getValue(at: linearIdx)
            }
        }
        
        return result
    }
    
    private static func findBestHomographyWithScore(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric,
        method: SpectralAlignmentMethod,
        iterations: Int = 2,
        useRefinement: Bool = true,
        useMultiscale: Bool = true
    ) -> ([Double], Double) {
        
        switch method {
        case .coordinateDescent:
            return fourPointHomographyOptimization(
                channelData: channelData,
                refData: refData,
                width: width,
                height: height,
                offsetMin: offsetMin,
                offsetMax: offsetMax,
                step: step,
                metric: metric,
                iterations: iterations,
                useRefinement: false,
                useMultiscale: useMultiscale
            )
            
        case .differentialEvolution:
            return fourPointHomographyOptimization(
                channelData: channelData,
                refData: refData,
                width: width,
                height: height,
                offsetMin: offsetMin,
                offsetMax: offsetMax,
                step: 1,
                metric: metric,
                iterations: iterations + 1,
                useRefinement: useRefinement,
                useMultiscale: useMultiscale
            )
            
        case .hybrid:
            return fourPointHomographyOptimization(
                channelData: channelData,
                refData: refData,
                width: width,
                height: height,
                offsetMin: offsetMin,
                offsetMax: offsetMax,
                step: step,
                metric: metric,
                iterations: iterations,
                useRefinement: useRefinement,
                useMultiscale: useMultiscale
            )
        }
    }
    
    private static func fourPointHomographyOptimization(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric,
        iterations: Int,
        useRefinement: Bool,
        useMultiscale: Bool
    ) -> ([Double], Double) {
        let margin = 0.15
        let w = Double(width)
        let h = Double(height)
        
        let refPoints = [
            Point2D(x: w * margin, y: h * margin),
            Point2D(x: w * (1 - margin), y: h * margin),
            Point2D(x: w * (1 - margin), y: h * (1 - margin)),
            Point2D(x: w * margin, y: h * (1 - margin))
        ]
        
        var srcPoints = refPoints
        
        var workingChannel = channelData
        var workingRef = refData
        var workingWidth = width
        var workingHeight = height
        var scale = 1
        
        if useMultiscale && width > 200 && height > 200 {
            scale = 2
            workingWidth = width / scale
            workingHeight = height / scale
            workingChannel = downsample(channelData, width: width, height: height, factor: scale)
            workingRef = downsample(refData, width: width, height: height, factor: scale)
        }
        
        let scaledRefPoints = refPoints.map { Point2D(x: $0.x / Double(scale), y: $0.y / Double(scale)) }
        var scaledSrcPoints = scaledRefPoints
        
        for iteration in 0..<iterations {
            let currentStep = iteration == 0 ? max(1, step / scale) : max(1, step / scale / 2)
            let scaledOffsetMin = offsetMin / scale
            let scaledOffsetMax = offsetMax / scale
            
            for pointIdx in 0..<4 {
                let (bestDx, bestDy) = optimizeSinglePoint(
                    channelData: workingChannel,
                    refData: workingRef,
                    width: workingWidth,
                    height: workingHeight,
                    basePoints: scaledSrcPoints,
                    refPoints: scaledRefPoints,
                    pointIndex: pointIdx,
                    offsetMin: scaledOffsetMin,
                    offsetMax: scaledOffsetMax,
                    step: currentStep,
                    metric: metric
                )
                scaledSrcPoints[pointIdx].x += Double(bestDx)
                scaledSrcPoints[pointIdx].y += Double(bestDy)
            }
        }
        
        srcPoints = scaledSrcPoints.map { Point2D(x: $0.x * Double(scale), y: $0.y * Double(scale)) }
        
        if useRefinement {
            for pointIdx in 0..<4 {
                let (bestDx, bestDy) = optimizeSinglePoint(
                    channelData: channelData,
                    refData: refData,
                    width: width,
                    height: height,
                    basePoints: srcPoints,
                    refPoints: refPoints,
                    pointIndex: pointIdx,
                    offsetMin: -3,
                    offsetMax: 3,
                    step: 1,
                    metric: metric
                )
                srcPoints[pointIdx].x += Double(bestDx)
                srcPoints[pointIdx].y += Double(bestDy)
            }
        }
        
        let orderedSrc = orderPoints(srcPoints)
        let orderedRef = orderPoints(refPoints)
        
        guard let H = computeHomographyDLT(src: orderedSrc, dst: orderedRef) else {
            return ([1, 0, 0, 0, 1, 0, 0, 0, 1], 0.0)
        }
        
        let warped = warpPerspective(channelData, width: width, height: height, H: H)
        let score = computeMetricForWarped(warped: warped, refData: refData, width: width, height: height, metric: metric)
        
        return (H, score)
    }
    
    private static func optimizeSinglePoint(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        basePoints: [Point2D],
        refPoints: [Point2D],
        pointIndex: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric
    ) -> (Int, Int) {
        var bestDx = 0
        var bestDy = 0
        var bestScore = -Double.infinity
        
        for dx in stride(from: offsetMin, through: offsetMax, by: step) {
            for dy in stride(from: offsetMin, through: offsetMax, by: step) {
                var testPoints = basePoints
                testPoints[pointIndex].x += Double(dx)
                testPoints[pointIndex].y += Double(dy)
                
                let orderedSrc = orderPoints(testPoints)
                let orderedRef = orderPoints(refPoints)
                
                guard let H = computeHomographyDLT(src: orderedSrc, dst: orderedRef) else { continue }
                
                let warped = warpPerspective(channelData, width: width, height: height, H: H)
                let score = computeMetricForWarped(warped: warped, refData: refData, width: width, height: height, metric: metric)
                
                if score > bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        return (bestDx, bestDy)
    }
    
    private static func computeMetricForWarped(
        warped: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        metric: SpectralAlignmentMetric
    ) -> Double {
        let margin = 10
        let xStart = margin
        let xEnd = width - margin
        let yStart = margin
        let yEnd = height - margin
        
        guard xEnd > xStart, yEnd > yStart else { return -1.0 }
        
        let regionWidth = xEnd - xStart
        let regionHeight = yEnd - yStart
        
        var refRegion = [Double](repeating: 0, count: regionWidth * regionHeight)
        var warpedRegion = [Double](repeating: 0, count: regionWidth * regionHeight)
        
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let srcIdx = y * width + x
                let dstIdx = (y - yStart) * regionWidth + (x - xStart)
                refRegion[dstIdx] = refData[srcIdx]
                warpedRegion[dstIdx] = warped[srcIdx]
            }
        }
        
        let (normRef, _, _) = normalizeData(refRegion)
        let (normWarped, _, _) = normalizeData(warpedRegion)
        
        switch metric {
        case .ssim:
            return computeWindowedSSIM(
                img1: normRef,
                img2: normWarped,
                width: regionWidth,
                height: regionHeight,
                windowSize: 7,
                useGaussian: true,
                sigma: 1.5
            )
        case .psnr:
            return computePSNRDirect(normRef, normWarped)
        }
    }
    
    private static func multiScaleAlignment(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric,
        useSubpixel: Bool
    ) -> ([Double], Double) {
        let scales = [4, 2, 1]
        var bestDx = 0.0
        var bestDy = 0.0
        
        for scale in scales {
            if scale > 1 {
                let scaledWidth = width / scale
                let scaledHeight = height / scale
                guard scaledWidth > 10, scaledHeight > 10 else { continue }
                
                let scaledChannel = downsample(channelData, width: width, height: height, factor: scale)
                let scaledRef = downsample(refData, width: width, height: height, factor: scale)
                
                let scaledOffsetMin = offsetMin / scale
                let scaledOffsetMax = offsetMax / scale
                let scaledStep = max(1, step / scale)
                
                let searchCenterX = Int(bestDx) / scale
                let searchCenterY = Int(bestDy) / scale
                let searchRange = max(scaledOffsetMax - scaledOffsetMin, 4)
                
                let (dx, dy, _) = gridSearchAround(
                    channelData: scaledChannel,
                    refData: scaledRef,
                    width: scaledWidth,
                    height: scaledHeight,
                    centerX: searchCenterX,
                    centerY: searchCenterY,
                    range: searchRange,
                    step: scaledStep,
                    metric: metric
                )
                
                bestDx = Double(dx * scale)
                bestDy = Double(dy * scale)
            } else {
                let searchRange = max(step * 2, 3)
                let (dx, dy, _) = gridSearchAround(
                    channelData: channelData,
                    refData: refData,
                    width: width,
                    height: height,
                    centerX: Int(bestDx),
                    centerY: Int(bestDy),
                    range: searchRange,
                    step: 1,
                    metric: metric
                )
                bestDx = Double(dx)
                bestDy = Double(dy)
            }
        }
        
        if useSubpixel {
            let (subDx, subDy) = subpixelRefinement(
                channelData: channelData,
                refData: refData,
                width: width,
                height: height,
                intDx: Int(bestDx),
                intDy: Int(bestDy),
                metric: metric
            )
            bestDx = subDx
            bestDy = subDy
        }
        
        let finalScore = computeMetricSubpixel(
            channelData: channelData,
            refData: refData,
            dx: bestDx,
            dy: bestDy,
            width: width,
            height: height,
            metric: metric
        )
        
        return ([1, 0, bestDx, 0, 1, bestDy, 0, 0, 1], finalScore)
    }
    
    private static func fullGridSearchWithSubpixel(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric
    ) -> ([Double], Double) {
        var bestDx = 0
        var bestDy = 0
        var bestScore = -Double.infinity
        
        for dx in stride(from: offsetMin, through: offsetMax, by: step) {
            for dy in stride(from: offsetMin, through: offsetMax, by: step) {
                let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height, metric: metric)
                if score > bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        if step > 1 {
            let fineRange = step
            for dx in stride(from: bestDx - fineRange, through: bestDx + fineRange, by: 1) {
                for dy in stride(from: bestDy - fineRange, through: bestDy + fineRange, by: 1) {
                    let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height, metric: metric)
                    if score > bestScore {
                        bestScore = score
                        bestDx = dx
                        bestDy = dy
                    }
                }
            }
        }
        
        let (subDx, subDy) = subpixelRefinement(
            channelData: channelData,
            refData: refData,
            width: width,
            height: height,
            intDx: bestDx,
            intDy: bestDy,
            metric: metric
        )
        
        let finalScore = computeMetricSubpixel(
            channelData: channelData,
            refData: refData,
            dx: subDx,
            dy: subDy,
            width: width,
            height: height,
            metric: metric
        )
        
        return ([1, 0, subDx, 0, 1, subDy, 0, 0, 1], finalScore)
    }
    
    private static func downsample(_ data: [Double], width: Int, height: Int, factor: Int) -> [Double] {
        let newWidth = width / factor
        let newHeight = height / factor
        var result = [Double](repeating: 0, count: newWidth * newHeight)
        
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                var sum = 0.0
                var count = 0.0
                for fy in 0..<factor {
                    for fx in 0..<factor {
                        let srcX = x * factor + fx
                        let srcY = y * factor + fy
                        if srcX < width && srcY < height {
                            sum += data[srcY * width + srcX]
                            count += 1.0
                        }
                    }
                }
                result[y * newWidth + x] = count > 0 ? sum / count : 0
            }
        }
        
        return result
    }
    
    private static func gridSearchAround(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        centerX: Int,
        centerY: Int,
        range: Int,
        step: Int,
        metric: SpectralAlignmentMetric
    ) -> (Int, Int, Double) {
        var bestDx = centerX
        var bestDy = centerY
        var bestScore = -Double.infinity
        
        for dx in stride(from: centerX - range, through: centerX + range, by: step) {
            for dy in stride(from: centerY - range, through: centerY + range, by: step) {
                let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height, metric: metric)
                if score > bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        return (bestDx, bestDy, bestScore)
    }
    
    private static func subpixelRefinement(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        intDx: Int,
        intDy: Int,
        metric: SpectralAlignmentMetric
    ) -> (Double, Double) {
        let s00 = computeMetric(channelData: channelData, refData: refData, dx: intDx - 1, dy: intDy - 1, width: width, height: height, metric: metric)
        let s10 = computeMetric(channelData: channelData, refData: refData, dx: intDx,     dy: intDy - 1, width: width, height: height, metric: metric)
        let s20 = computeMetric(channelData: channelData, refData: refData, dx: intDx + 1, dy: intDy - 1, width: width, height: height, metric: metric)
        let s01 = computeMetric(channelData: channelData, refData: refData, dx: intDx - 1, dy: intDy,     width: width, height: height, metric: metric)
        let s11 = computeMetric(channelData: channelData, refData: refData, dx: intDx,     dy: intDy,     width: width, height: height, metric: metric)
        let s21 = computeMetric(channelData: channelData, refData: refData, dx: intDx + 1, dy: intDy,     width: width, height: height, metric: metric)
        let s02 = computeMetric(channelData: channelData, refData: refData, dx: intDx - 1, dy: intDy + 1, width: width, height: height, metric: metric)
        let s12 = computeMetric(channelData: channelData, refData: refData, dx: intDx,     dy: intDy + 1, width: width, height: height, metric: metric)
        let s22 = computeMetric(channelData: channelData, refData: refData, dx: intDx + 1, dy: intDy + 1, width: width, height: height, metric: metric)
        
        let dxNum = (s21 - s01 + s20 - s00 + s22 - s02)
        let dxDen = 2.0 * (s01 - 2.0 * s11 + s21)
        let dyNum = (s12 - s10 + s02 - s00 + s22 - s20)
        let dyDen = 2.0 * (s10 - 2.0 * s11 + s12)
        
        var subDx = Double(intDx)
        var subDy = Double(intDy)
        
        if abs(dxDen) > 1e-6 {
            let offset = -dxNum / dxDen
            if abs(offset) < 1.0 {
                subDx += offset
            }
        }
        
        if abs(dyDen) > 1e-6 {
            let offset = -dyNum / dyDen
            if abs(offset) < 1.0 {
                subDy += offset
            }
        }
        
        return (subDx, subDy)
    }
    
    private static func computeMetricSubpixel(
        channelData: [Double],
        refData: [Double],
        dx: Double,
        dy: Double,
        width: Int,
        height: Int,
        metric: SpectralAlignmentMetric
    ) -> Double {
        let shiftedChannel = bilinearShift(channelData, width: width, height: height, dx: dx, dy: dy)
        return computeMetricDirect(shiftedData: shiftedChannel, refData: refData, width: width, height: height, metric: metric)
    }
    
    private static func bilinearShift(_ data: [Double], width: Int, height: Int, dx: Double, dy: Double) -> [Double] {
        var result = [Double](repeating: 0, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcX = Double(x) + dx
                let srcY = Double(y) + dy
                
                let x0 = Int(floor(srcX))
                let y0 = Int(floor(srcY))
                let x1 = x0 + 1
                let y1 = y0 + 1
                
                let fx = srcX - Double(x0)
                let fy = srcY - Double(y0)
                
                func getValue(_ px: Int, _ py: Int) -> Double {
                    let cx = max(0, min(width - 1, px))
                    let cy = max(0, min(height - 1, py))
                    return data[cy * width + cx]
                }
                
                let v00 = getValue(x0, y0)
                let v10 = getValue(x1, y0)
                let v01 = getValue(x0, y1)
                let v11 = getValue(x1, y1)
                
                let v = v00 * (1 - fx) * (1 - fy) +
                        v10 * fx * (1 - fy) +
                        v01 * (1 - fx) * fy +
                        v11 * fx * fy
                
                result[y * width + x] = v
            }
        }
        
        return result
    }
    
    private static func computeMetricDirect(
        shiftedData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        metric: SpectralAlignmentMetric
    ) -> Double {
        let margin = 5
        let xStart = margin
        let xEnd = width - margin
        let yStart = margin
        let yEnd = height - margin
        
        guard xEnd > xStart, yEnd > yStart else { return -1.0 }
        
        let regionWidth = xEnd - xStart
        let regionHeight = yEnd - yStart
        
        var refRegion = [Double](repeating: 0, count: regionWidth * regionHeight)
        var shiftedRegion = [Double](repeating: 0, count: regionWidth * regionHeight)
        
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let srcIdx = y * width + x
                let dstIdx = (y - yStart) * regionWidth + (x - xStart)
                refRegion[dstIdx] = refData[srcIdx]
                shiftedRegion[dstIdx] = shiftedData[srcIdx]
            }
        }
        
        let (normRef, _, _) = normalizeData(refRegion)
        let (normShifted, _, _) = normalizeData(shiftedRegion)
        
        switch metric {
        case .ssim:
            return computeWindowedSSIM(
                img1: normRef,
                img2: normShifted,
                width: regionWidth,
                height: regionHeight,
                windowSize: 7,
                useGaussian: true,
                sigma: 1.5
            )
        case .psnr:
            return computePSNRDirect(normRef, normShifted)
        }
    }
    
    private static func computeSSIMDirect(_ img1: [Double], _ img2: [Double]) -> Double {
        guard !img1.isEmpty, img1.count == img2.count else { return -1.0 }
        
        let count = Double(img1.count)
        var sum1 = 0.0, sum2 = 0.0
        var sumSq1 = 0.0, sumSq2 = 0.0
        var sumProd = 0.0
        
        for i in 0..<img1.count {
            let v1 = img1[i]
            let v2 = img2[i]
            sum1 += v1
            sum2 += v2
            sumSq1 += v1 * v1
            sumSq2 += v2 * v2
            sumProd += v1 * v2
        }
        
        let mu1 = sum1 / count
        let mu2 = sum2 / count
        let sigma1Sq = max(0, sumSq1 / count - mu1 * mu1)
        let sigma2Sq = max(0, sumSq2 / count - mu2 * mu2)
        let sigma12 = sumProd / count - mu1 * mu2
        
        let c1 = 0.0001
        let c2 = 0.0009
        
        let numerator = (2.0 * mu1 * mu2 + c1) * (2.0 * sigma12 + c2)
        let denominator = (mu1 * mu1 + mu2 * mu2 + c1) * (sigma1Sq + sigma2Sq + c2)
        
        guard denominator > 1e-10 else { return 0.0 }
        return numerator / denominator
    }
    
    private static func computeWindowedSSIM(
        img1: [Double],
        img2: [Double],
        width: Int,
        height: Int,
        windowSize: Int = 7,
        useGaussian: Bool = true,
        sigma: Double = 1.5
    ) -> Double {
        guard width > windowSize, height > windowSize else {
            return computeSSIMDirect(img1, img2)
        }
        
        let kernel = useGaussian ? makeGaussianKernel(size: windowSize, sigma: sigma) : makeUniformKernel(size: windowSize)
        
        let mu1 = convolve2D(img1, width: width, height: height, kernel: kernel, kernelSize: windowSize)
        let mu2 = convolve2D(img2, width: width, height: height, kernel: kernel, kernelSize: windowSize)
        
        var img1Sq = [Double](repeating: 0, count: img1.count)
        var img2Sq = [Double](repeating: 0, count: img2.count)
        var img12 = [Double](repeating: 0, count: img1.count)
        for i in 0..<img1.count {
            img1Sq[i] = img1[i] * img1[i]
            img2Sq[i] = img2[i] * img2[i]
            img12[i] = img1[i] * img2[i]
        }
        
        let sigma1Sq = convolve2D(img1Sq, width: width, height: height, kernel: kernel, kernelSize: windowSize)
        let sigma2Sq = convolve2D(img2Sq, width: width, height: height, kernel: kernel, kernelSize: windowSize)
        let sigma12 = convolve2D(img12, width: width, height: height, kernel: kernel, kernelSize: windowSize)
        
        let c1 = 0.0001
        let c2 = 0.0009
        
        let pad = windowSize / 2
        var ssimSum = 0.0
        var count = 0
        
        for y in pad..<(height - pad) {
            for x in pad..<(width - pad) {
                let idx = y * width + x
                let m1 = mu1[idx]
                let m2 = mu2[idx]
                let s1 = max(0, sigma1Sq[idx] - m1 * m1)
                let s2 = max(0, sigma2Sq[idx] - m2 * m2)
                let s12 = sigma12[idx] - m1 * m2
                
                let num = (2.0 * m1 * m2 + c1) * (2.0 * s12 + c2)
                let den = (m1 * m1 + m2 * m2 + c1) * (s1 + s2 + c2)
                
                if den > 1e-10 {
                    ssimSum += num / den
                    count += 1
                }
            }
        }
        
        return count > 0 ? ssimSum / Double(count) : 0.0
    }
    
    private static func makeGaussianKernel(size: Int, sigma: Double) -> [Double] {
        var kernel = [Double](repeating: 0, count: size * size)
        let center = size / 2
        var sum = 0.0
        
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x - center)
                let dy = Double(y - center)
                let val = exp(-(dx * dx + dy * dy) / (2.0 * sigma * sigma))
                kernel[y * size + x] = val
                sum += val
            }
        }
        
        for i in 0..<kernel.count {
            kernel[i] /= sum
        }
        
        return kernel
    }
    
    private static func makeUniformKernel(size: Int) -> [Double] {
        let val = 1.0 / Double(size * size)
        return [Double](repeating: val, count: size * size)
    }
    
    private static func convolve2D(_ data: [Double], width: Int, height: Int, kernel: [Double], kernelSize: Int) -> [Double] {
        var result = [Double](repeating: 0, count: data.count)
        let pad = kernelSize / 2
        
        for y in 0..<height {
            for x in 0..<width {
                var sum = 0.0
                for ky in 0..<kernelSize {
                    for kx in 0..<kernelSize {
                        let srcY = min(max(y + ky - pad, 0), height - 1)
                        let srcX = min(max(x + kx - pad, 0), width - 1)
                        sum += data[srcY * width + srcX] * kernel[ky * kernelSize + kx]
                    }
                }
                result[y * width + x] = sum
            }
        }
        
        return result
    }
    
    private static func computePSNRDirect(_ img1: [Double], _ img2: [Double]) -> Double {
        guard !img1.isEmpty, img1.count == img2.count else { return -Double.infinity }
        
        var mse = 0.0
        for i in 0..<img1.count {
            let diff = img1[i] - img2[i]
            mse += diff * diff
        }
        mse /= Double(img1.count)
        
        guard mse > 1e-10 else { return 100.0 }
        return 10.0 * log10(1.0 / mse)
    }
    
    private static func coordinateDescent(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric
    ) -> (Int, Int) {
        var bestDx = 0
        var bestDy = 0
        var bestScore = computeMetric(channelData: channelData, refData: refData, dx: 0, dy: 0, width: width, height: height, metric: metric)
        
        for iteration in 0..<2 {
            var improved = true
            while improved {
                improved = false
                
                for dx in stride(from: offsetMin, through: offsetMax, by: step) {
                    let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: bestDy, width: width, height: height, metric: metric)
                    if score > bestScore + 1e-6 {
                        bestScore = score
                        bestDx = dx
                        improved = true
                    }
                }
                
                for dy in stride(from: offsetMin, through: offsetMax, by: step) {
                    let score = computeMetric(channelData: channelData, refData: refData, dx: bestDx, dy: dy, width: width, height: height, metric: metric)
                    if score > bestScore + 1e-6 {
                        bestScore = score
                        bestDy = dy
                        improved = true
                    }
                }
            }
            
            if iteration == 0 && step > 1 {
                let fineStep = max(1, step / 2)
                let fineMin = -fineStep * 2
                let fineMax = fineStep * 2
                
                for dx in stride(from: bestDx + fineMin, through: bestDx + fineMax, by: fineStep) {
                    for dy in stride(from: bestDy + fineMin, through: bestDy + fineMax, by: fineStep) {
                        let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height, metric: metric)
                        if score > bestScore + 1e-6 {
                            bestScore = score
                            bestDx = dx
                            bestDy = dy
                        }
                    }
                }
            }
        }
        
        return (bestDx, bestDy)
    }
    
    private static func gridSearch(
        channelData: [Double],
        refData: [Double],
        width: Int,
        height: Int,
        offsetMin: Int,
        offsetMax: Int,
        step: Int,
        metric: SpectralAlignmentMetric
    ) -> (Int, Int) {
        var bestDx = 0
        var bestDy = 0
        var bestScore = -Double.infinity
        
        for dx in stride(from: offsetMin, through: offsetMax, by: step) {
            for dy in stride(from: offsetMin, through: offsetMax, by: step) {
                let score = computeMetric(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height, metric: metric)
                if score > bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        return (bestDx, bestDy)
    }
    
    private static func computeMetric(
        channelData: [Double],
        refData: [Double],
        dx: Int,
        dy: Int,
        width: Int,
        height: Int,
        metric: SpectralAlignmentMetric
    ) -> Double {
        switch metric {
        case .ssim:
            return computeSSIM(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height)
        case .psnr:
            return computePSNR(channelData: channelData, refData: refData, dx: dx, dy: dy, width: width, height: height)
        }
    }
    
    private static func normalizeData(_ data: [Double]) -> (normalized: [Double], min: Double, max: Double) {
        guard !data.isEmpty else { return ([], 0, 0) }
        var minVal = Double.infinity
        var maxVal = -Double.infinity
        for v in data {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
        let range = maxVal - minVal
        if range < 1e-10 {
            return (Array(repeating: 0.0, count: data.count), minVal, maxVal)
        }
        var normalized = [Double](repeating: 0, count: data.count)
        for i in 0..<data.count {
            normalized[i] = (data[i] - minVal) / range
        }
        return (normalized, minVal, maxVal)
    }
    
    private static func computeSSIM(
        channelData: [Double],
        refData: [Double],
        dx: Int,
        dy: Int,
        width: Int,
        height: Int
    ) -> Double {
        let xStart = max(0, -dx)
        let xEnd = min(width, width - dx)
        let yStart = max(0, -dy)
        let yEnd = min(height, height - dy)
        
        guard xEnd > xStart, yEnd > yStart else { return -1.0 }
        
        var refRegion = [Double]()
        var chRegion = [Double]()
        refRegion.reserveCapacity((yEnd - yStart) * (xEnd - xStart))
        chRegion.reserveCapacity((yEnd - yStart) * (xEnd - xStart))
        
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let refIdx = y * width + x
                let chIdx = (y + dy) * width + (x + dx)
                
                guard refIdx >= 0, refIdx < refData.count,
                      chIdx >= 0, chIdx < channelData.count else { continue }
                
                refRegion.append(refData[refIdx])
                chRegion.append(channelData[chIdx])
            }
        }
        
        guard !refRegion.isEmpty else { return -1.0 }
        
        let (normRef, _, _) = normalizeData(refRegion)
        let (normCh, _, _) = normalizeData(chRegion)
        
        var sum1 = 0.0, sum2 = 0.0
        var sumSq1 = 0.0, sumSq2 = 0.0
        var sumProd = 0.0
        let count = Double(normRef.count)
        
        for i in 0..<normRef.count {
            let v1 = normRef[i]
            let v2 = normCh[i]
            sum1 += v1
            sum2 += v2
            sumSq1 += v1 * v1
            sumSq2 += v2 * v2
            sumProd += v1 * v2
        }
        
        let mu1 = sum1 / count
        let mu2 = sum2 / count
        let sigma1Sq = max(0, sumSq1 / count - mu1 * mu1)
        let sigma2Sq = max(0, sumSq2 / count - mu2 * mu2)
        let sigma12 = sumProd / count - mu1 * mu2
        
        let c1 = 0.0001  // (0.01 * 1.0)^2 for data_range=1.0
        let c2 = 0.0009  // (0.03 * 1.0)^2 for data_range=1.0
        
        let numerator = (2.0 * mu1 * mu2 + c1) * (2.0 * sigma12 + c2)
        let denominator = (mu1 * mu1 + mu2 * mu2 + c1) * (sigma1Sq + sigma2Sq + c2)
        
        guard denominator > 1e-10 else { return 0.0 }
        
        return numerator / denominator
    }
    
    private static func computePSNR(
        channelData: [Double],
        refData: [Double],
        dx: Int,
        dy: Int,
        width: Int,
        height: Int
    ) -> Double {
        let xStart = max(0, -dx)
        let xEnd = min(width, width - dx)
        let yStart = max(0, -dy)
        let yEnd = min(height, height - dy)
        
        guard xEnd > xStart, yEnd > yStart else { return -Double.infinity }
        
        var refRegion = [Double]()
        var chRegion = [Double]()
        refRegion.reserveCapacity((yEnd - yStart) * (xEnd - xStart))
        chRegion.reserveCapacity((yEnd - yStart) * (xEnd - xStart))
        
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let refIdx = y * width + x
                let chIdx = (y + dy) * width + (x + dx)
                
                guard refIdx >= 0, refIdx < refData.count,
                      chIdx >= 0, chIdx < channelData.count else { continue }
                
                refRegion.append(refData[refIdx])
                chRegion.append(channelData[chIdx])
            }
        }
        
        guard !refRegion.isEmpty else { return -Double.infinity }
        
        let (normRef, _, _) = normalizeData(refRegion)
        let (normCh, _, _) = normalizeData(chRegion)
        
        var mse = 0.0
        for i in 0..<normRef.count {
            let diff = normRef[i] - normCh[i]
            mse += diff * diff
        }
        
        mse /= Double(normRef.count)
        
        guard mse > 1e-10 else { return 100.0 }
        
        let psnr = 10.0 * log10(1.0 / mse)
        return psnr
    }
    
    private static func applyHomographies(
        cube: HyperCube,
        homographies: [[Double]],
        axes: (channel: Int, height: Int, width: Int),
        layout: CubeLayout
    ) -> HyperCube? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        let channels = dimsArray[axes.channel]
        
        let totalElements = dims.0 * dims.1 * dims.2
        
        func bilinearSample<T: BinaryFloatingPoint>(source: [T], x: Double, y: Double, ch: Int) -> T {
            let x0 = Int(floor(x))
            let y0 = Int(floor(y))
            let x1 = x0 + 1
            let y1 = y0 + 1
            
            let fx = T(x - Double(x0))
            let fy = T(y - Double(y0))
            
            func getVal(_ px: Int, _ py: Int) -> T {
                let cx = max(0, min(width - 1, px))
                let cy = max(0, min(height - 1, py))
                var idx = [0, 0, 0]
                idx[axes.channel] = ch
                idx[axes.height] = cy
                idx[axes.width] = cx
                let linear = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                return source[linear]
            }
            
            let v00 = getVal(x0, y0)
            let v10 = getVal(x1, y0)
            let v01 = getVal(x0, y1)
            let v11 = getVal(x1, y1)
            
            let w00: T = (1 - fx) * (1 - fy)
            let w10: T = fx * (1 - fy)
            let w01: T = (1 - fx) * fy
            let w11: T = fx * fy
            
            return v00 * w00 + v10 * w10 + v01 * w01 + v11 * w11
        }
        
        func applyTransform<T: BinaryFloatingPoint>(source: [T], into output: inout [T]) {
            for ch in 0..<channels {
                let H = homographies[ch]
                let Hinv = invertHomographyArray(H)
                let isPerspective = abs(H[6]) > 1e-9 || abs(H[7]) > 1e-9
                
                for y in 0..<height {
                    for x in 0..<width {
                        var dstIdx = [0, 0, 0]
                        dstIdx[axes.channel] = ch
                        dstIdx[axes.height] = y
                        dstIdx[axes.width] = x
                        let dstLinear = linearIndex(dims: dimsArray, fortran: cube.isFortranOrder, i0: dstIdx[0], i1: dstIdx[1], i2: dstIdx[2])
                        
                        let dx = Double(x)
                        let dy = Double(y)
                        var srcX: Double
                        var srcY: Double
                        
                        if isPerspective {
                            let w = Hinv[6]*dx + Hinv[7]*dy + Hinv[8]
                            guard abs(w) > 1e-12 else { output[dstLinear] = 0; continue }
                            srcX = (Hinv[0]*dx + Hinv[1]*dy + Hinv[2]) / w
                            srcY = (Hinv[3]*dx + Hinv[4]*dy + Hinv[5]) / w
                        } else {
                            srcX = dx - H[2]
                            srcY = dy - H[5]
                        }
                        
                        if srcX >= -0.5, srcX < Double(width) - 0.5, srcY >= -0.5, srcY < Double(height) - 0.5 {
                            output[dstLinear] = bilinearSample(source: source, x: srcX, y: srcY, ch: ch)
                        } else {
                            output[dstLinear] = 0
                        }
                    }
                }
            }
        }
        
        func applyTransformInt<T: FixedWidthInteger>(source: [T], into output: inout [T]) {
            for ch in 0..<channels {
                let H = homographies[ch]
                let Hinv = invertHomographyArray(H)
                let isPerspective = abs(H[6]) > 1e-9 || abs(H[7]) > 1e-9
                
                for y in 0..<height {
                    for x in 0..<width {
                        var dstIdx = [0, 0, 0]
                        dstIdx[axes.channel] = ch
                        dstIdx[axes.height] = y
                        dstIdx[axes.width] = x
                        let dstLinear = linearIndex(dims: dimsArray, fortran: cube.isFortranOrder, i0: dstIdx[0], i1: dstIdx[1], i2: dstIdx[2])
                        
                        let dx = Double(x)
                        let dy = Double(y)
                        var srcX: Double
                        var srcY: Double
                        
                        if isPerspective {
                            let w = Hinv[6]*dx + Hinv[7]*dy + Hinv[8]
                            guard abs(w) > 1e-12 else { output[dstLinear] = 0; continue }
                            srcX = (Hinv[0]*dx + Hinv[1]*dy + Hinv[2]) / w
                            srcY = (Hinv[3]*dx + Hinv[4]*dy + Hinv[5]) / w
                        } else {
                            srcX = dx - H[2]
                            srcY = dy - H[5]
                        }
                        
                        if srcX >= -0.5, srcX < Double(width) - 0.5, srcY >= -0.5, srcY < Double(height) - 0.5 {
                            let x0 = Int(floor(srcX))
                            let y0 = Int(floor(srcY))
                            let x1 = min(x0 + 1, width - 1)
                            let y1 = min(y0 + 1, height - 1)
                            let cx0 = max(0, x0)
                            let cy0 = max(0, y0)
                            
                            let fx = srcX - Double(x0)
                            let fy = srcY - Double(y0)
                            
                            func getVal(_ px: Int, _ py: Int) -> Double {
                                var idx = [0, 0, 0]
                                idx[axes.channel] = ch
                                idx[axes.height] = py
                                idx[axes.width] = px
                                let linear = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                                return Double(source[linear])
                            }
                            
                            let v00 = getVal(cx0, cy0)
                            let v10 = getVal(x1, cy0)
                            let v01 = getVal(cx0, y1)
                            let v11 = getVal(x1, y1)
                            
                            let w00 = (1 - fx) * (1 - fy)
                            let w10 = fx * (1 - fy)
                            let w01 = (1 - fx) * fy
                            let w11 = fx * fy
                            let interpolated = v00*w00 + v10*w10 + v01*w01 + v11*w11
                            
                            output[dstLinear] = T(clamping: Int64(round(interpolated)))
                        } else {
                            output[dstLinear] = 0
                        }
                    }
                }
            }
        }
        
        func invertHomographyArray(_ H: [Double]) -> [Double] {
            guard H.count == 9 else { return [1,0,0, 0,1,0, 0,0,1] }
            let m: [[Double]] = [[H[0], H[1], H[2]], [H[3], H[4], H[5]], [H[6], H[7], H[8]]]
            let det = m[0][0]*(m[1][1]*m[2][2] - m[1][2]*m[2][1]) - m[0][1]*(m[1][0]*m[2][2] - m[1][2]*m[2][0]) + m[0][2]*(m[1][0]*m[2][1] - m[1][1]*m[2][0])
            guard abs(det) > 1e-12 else { return [1,0,0, 0,1,0, 0,0,1] }
            let invDet = 1.0 / det
            return [(m[1][1]*m[2][2] - m[1][2]*m[2][1])*invDet, (m[0][2]*m[2][1] - m[0][1]*m[2][2])*invDet, (m[0][1]*m[1][2] - m[0][2]*m[1][1])*invDet,
                    (m[1][2]*m[2][0] - m[1][0]*m[2][2])*invDet, (m[0][0]*m[2][2] - m[0][2]*m[2][0])*invDet, (m[0][2]*m[1][0] - m[0][0]*m[1][2])*invDet,
                    (m[1][0]*m[2][1] - m[1][1]*m[2][0])*invDet, (m[0][1]*m[2][0] - m[0][0]*m[2][1])*invDet, (m[0][0]*m[1][1] - m[0][1]*m[1][0])*invDet]
        }
        
        switch cube.storage {
        case .float64(let arr):
            var output = [Double](repeating: 0, count: totalElements)
            applyTransform(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .float64(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .float32(let arr):
            var output = [Float](repeating: 0, count: totalElements)
            applyTransform(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .float32(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint16(let arr):
            var output = [UInt16](repeating: 0, count: totalElements)
            applyTransformInt(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .uint16(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint8(let arr):
            var output = [UInt8](repeating: 0, count: totalElements)
            applyTransformInt(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .uint8(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int16(let arr):
            var output = [Int16](repeating: 0, count: totalElements)
            applyTransformInt(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .int16(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int32(let arr):
            var output = [Int32](repeating: 0, count: totalElements)
            applyTransformInt(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .int32(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int8(let arr):
            var output = [Int8](repeating: 0, count: totalElements)
            applyTransformInt(source: arr, into: &output)
            return HyperCube(dims: dims, storage: .int8(output), sourceFormat: cube.sourceFormat + " [Align]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        }
    }
    
    private static func linearIndex(dims: [Int], fortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if fortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        }
        return i2 + dims[2] * (i1 + dims[1] * i0)
    }
    
    // MARK: - Homography Functions
    
    struct Point2D {
        var x: Double
        var y: Double
    }
    
    static func orderPoints(_ pts: [Point2D]) -> [Point2D] {
        guard pts.count == 4 else { return pts }
        let sums = pts.map { $0.x + $0.y }
        let diffs = pts.map { $0.x - $0.y }
        let tlIdx = sums.enumerated().min(by: { $0.1 < $1.1 })!.0
        let brIdx = sums.enumerated().max(by: { $0.1 < $1.1 })!.0
        let trIdx = diffs.enumerated().max(by: { $0.1 < $1.1 })!.0
        let blIdx = diffs.enumerated().min(by: { $0.1 < $1.1 })!.0
        return [pts[tlIdx], pts[trIdx], pts[brIdx], pts[blIdx]]
    }
    
    static func computeHomographyDLT(src: [Point2D], dst: [Point2D]) -> [Double]? {
        guard src.count >= 4, dst.count >= 4 else { return nil }
        let srcNorm = normalizePointsForDLT(src)
        let dstNorm = normalizePointsForDLT(dst)
        var A = [[Double]](repeating: [Double](repeating: 0, count: 9), count: src.count * 2)
        for i in 0..<min(src.count, dst.count) {
            let x = srcNorm.points[i].x, y = srcNorm.points[i].y
            let u = dstNorm.points[i].x, v = dstNorm.points[i].y
            A[2*i] = [-x, -y, -1, 0, 0, 0, u*x, u*y, u]
            A[2*i+1] = [0, 0, 0, -x, -y, -1, v*x, v*y, v]
        }
        guard let h = solveSVDForHomography(A) else { return nil }
        let Hn = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], h[8]]]
        let TdInv = invertMatrix3x3ForDLT(dstNorm.T)
        let H = multiplyMatrix3x3ForDLT(multiplyMatrix3x3ForDLT(TdInv, Hn), srcNorm.T)
        let scale = H[2][2]
        if abs(scale) < 1e-12 { return nil }
        return [H[0][0]/scale, H[0][1]/scale, H[0][2]/scale,
                H[1][0]/scale, H[1][1]/scale, H[1][2]/scale,
                H[2][0]/scale, H[2][1]/scale, H[2][2]/scale]
    }
    
    private static func normalizePointsForDLT(_ pts: [Point2D]) -> (points: [Point2D], T: [[Double]]) {
        var cx = 0.0, cy = 0.0
        for p in pts { cx += p.x; cy += p.y }
        cx /= Double(pts.count); cy /= Double(pts.count)
        var meanDist = 0.0
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            meanDist += sqrt(dx*dx + dy*dy)
        }
        meanDist /= Double(pts.count)
        let s = meanDist > 1e-12 ? sqrt(2.0) / meanDist : 1.0
        let T: [[Double]] = [[s, 0, -s*cx], [0, s, -s*cy], [0, 0, 1]]
        var normalized = [Point2D]()
        for p in pts { normalized.append(Point2D(x: s*(p.x - cx), y: s*(p.y - cy))) }
        return (normalized, T)
    }
    
    private static func solveSVDForHomography(_ A: [[Double]]) -> [Double]? {
        let m = A.count
        guard m >= 8 else { return nil }
        var AtA = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 9)
        for i in 0..<9 { for j in 0..<9 { var sum = 0.0; for k in 0..<m { sum += A[k][i] * A[k][j] }; AtA[i][j] = sum } }
        var eigenvector = [Double](repeating: 0, count: 9)
        for i in 0..<9 { eigenvector[i] = Double.random(in: -1...1) }
        for _ in 0..<200 {
            var newVec = [Double](repeating: 0, count: 9)
            for i in 0..<9 { for j in 0..<9 { newVec[i] += AtA[i][j] * eigenvector[j] } }
            var norm = 0.0; for v in newVec { norm += v * v }; norm = sqrt(norm)
            if norm < 1e-15 { break }
            for i in 0..<9 { newVec[i] /= norm }; eigenvector = newVec
        }
        var maxEig = 0.0; var tempVec = [Double](repeating: 0, count: 9)
        for i in 0..<9 { for j in 0..<9 { tempVec[i] += AtA[i][j] * eigenvector[j] } }
        for i in 0..<9 { maxEig += eigenvector[i] * tempVec[i] }
        for i in 0..<9 { AtA[i][i] -= maxEig * 1.001 }
        var minVec = [Double](repeating: 0, count: 9)
        for i in 0..<9 { minVec[i] = Double.random(in: -1...1) }
        for _ in 0..<200 {
            var newVec = [Double](repeating: 0, count: 9)
            for i in 0..<9 { for j in 0..<9 { newVec[i] += AtA[i][j] * minVec[j] } }
            var norm = 0.0; for v in newVec { norm += v * v }; norm = sqrt(norm)
            if norm < 1e-15 { break }
            for i in 0..<9 { newVec[i] /= norm }; minVec = newVec
        }
        return minVec
    }
    
    private static func multiplyMatrix3x3ForDLT(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        var C = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { C[i][j] += A[i][k] * B[k][j] } } }
        return C
    }
    
    private static func invertMatrix3x3ForDLT(_ m: [[Double]]) -> [[Double]] {
        let det = m[0][0]*(m[1][1]*m[2][2] - m[1][2]*m[2][1]) - m[0][1]*(m[1][0]*m[2][2] - m[1][2]*m[2][0]) + m[0][2]*(m[1][0]*m[2][1] - m[1][1]*m[2][0])
        guard abs(det) > 1e-12 else { return [[1,0,0],[0,1,0],[0,0,1]] }
        let invDet = 1.0 / det
        return [[(m[1][1]*m[2][2] - m[1][2]*m[2][1])*invDet, (m[0][2]*m[2][1] - m[0][1]*m[2][2])*invDet, (m[0][1]*m[1][2] - m[0][2]*m[1][1])*invDet],
                [(m[1][2]*m[2][0] - m[1][0]*m[2][2])*invDet, (m[0][0]*m[2][2] - m[0][2]*m[2][0])*invDet, (m[0][2]*m[1][0] - m[0][0]*m[1][2])*invDet],
                [(m[1][0]*m[2][1] - m[1][1]*m[2][0])*invDet, (m[0][1]*m[2][0] - m[0][0]*m[2][1])*invDet, (m[0][0]*m[1][1] - m[0][1]*m[1][0])*invDet]]
    }
    
    static func warpPerspective(_ data: [Double], width: Int, height: Int, H: [Double]) -> [Double] {
        guard H.count == 9 else { return data }
        let Hinv = invertHomography(H)
        var result = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x), dy = Double(y)
                let w = Hinv[6]*dx + Hinv[7]*dy + Hinv[8]
                guard abs(w) > 1e-12 else { continue }
                let srcX = (Hinv[0]*dx + Hinv[1]*dy + Hinv[2]) / w
                let srcY = (Hinv[3]*dx + Hinv[4]*dy + Hinv[5]) / w
                if srcX >= 0 && srcX < Double(width - 1) && srcY >= 0 && srcY < Double(height - 1) {
                    let x0 = Int(floor(srcX)), y0 = Int(floor(srcY))
                    let x1 = x0 + 1, y1 = y0 + 1
                    let fx = srcX - Double(x0), fy = srcY - Double(y0)
                    let v00 = data[y0 * width + x0], v10 = data[y0 * width + x1]
                    let v01 = data[y1 * width + x0], v11 = data[y1 * width + x1]
                    let w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy)
                    let w01 = (1 - fx) * fy, w11 = fx * fy
                    result[y * width + x] = v00*w00 + v10*w10 + v01*w01 + v11*w11
                } else {
                    let cx = max(0, min(width - 1, Int(round(srcX))))
                    let cy = max(0, min(height - 1, Int(round(srcY))))
                    result[y * width + x] = data[cy * width + cx]
                }
            }
        }
        return result
    }
    
    private static func invertHomography(_ H: [Double]) -> [Double] {
        let m: [[Double]] = [[H[0], H[1], H[2]], [H[3], H[4], H[5]], [H[6], H[7], H[8]]]
        let inv = invertMatrix3x3ForDLT(m)
        return [inv[0][0], inv[0][1], inv[0][2], inv[1][0], inv[1][1], inv[1][2], inv[2][0], inv[2][1], inv[2][2]]
    }
}
