import Foundation

// MARK: - CubeResizer

class CubeResizer {
    static func resize(cube: HyperCube, parameters: ResizeParameters, layout: CubeLayout = .auto) -> HyperCube? {
        guard parameters.targetWidth > 0, parameters.targetHeight > 0 else { return cube }
        
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        let srcDims = dimsArray
        guard let axes = cube.axes(for: layout) else { return cube }
        let srcWidth = dimsArray[axes.width]
        let srcHeight = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        guard srcWidth > 0, srcHeight > 0, channels > 0 else { return cube }
        
        let dstWidth = parameters.targetWidth
        let dstHeight = parameters.targetHeight
        dimsArray[axes.width] = dstWidth
        dimsArray[axes.height] = dstHeight
        let transformedGeo = cube.geoReference?.resized(
            sourceWidth: srcWidth,
            sourceHeight: srcHeight,
            targetWidth: dstWidth,
            targetHeight: dstHeight
        )
        
        let total = dstWidth * dstHeight * channels
        
        if parameters.algorithm == .nearest {
            let scaleX = Double(srcWidth) / Double(dstWidth)
            let scaleY = Double(srcHeight) / Double(dstHeight)
            
            switch cube.storage {
            case .float64(let arr):
                var output = [Double](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .float64(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .float32(let arr):
                var output = [Float](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .float32(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .uint16(let arr):
                var output = [UInt16](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .uint16(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .uint8(let arr):
                var output = [UInt8](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .uint8(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .int16(let arr):
                var output = [Int16](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int16(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .int32(let arr):
                var output = [Int32](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int32(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            case .int8(let arr):
                var output = [Int8](repeating: 0, count: total)
                fillNearest(from: arr, into: &output, cube: cube, axes: axes, srcDims: srcDims, dstWidth: dstWidth, dstHeight: dstHeight, scaleX: scaleX, scaleY: scaleY, dstDims: dimsArray)
                return HyperCube(dims: (dimsArray[0], dimsArray[1], dimsArray[2]), storage: .int8(output), sourceFormat: cube.sourceFormat + " [Resize]", isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            }
        }
        
        let useFloat32 = parameters.computePrecision == .float32
        if useFloat32 {
            var output = [Float](repeating: 0, count: total)
            let scaleX = Float(srcWidth) / Float(dstWidth)
            let scaleY = Float(srcHeight) / Float(dstHeight)
            
            for ch in 0..<channels {
                for y in 0..<dstHeight {
                    for x in 0..<dstWidth {
                        let srcX = (Float(x) + 0.5) * scaleX - 0.5
                        let srcY = (Float(y) + 0.5) * scaleY - 0.5
                        let value = sampleFloat(
                            cube: cube,
                            axes: axes,
                            channel: ch,
                            x: srcX,
                            y: srcY,
                            algorithm: parameters.algorithm,
                            bicubicA: Float(parameters.bicubicA),
                            lanczosA: parameters.lanczosA
                        )
                        
                        var outIndices = [0, 0, 0]
                        outIndices[axes.width] = x
                        outIndices[axes.height] = y
                        outIndices[axes.channel] = ch
                        
                        let idx = linearIndex(
                            dims: dimsArray,
                            isFortran: cube.isFortranOrder,
                            i0: outIndices[0],
                            i1: outIndices[1],
                            i2: outIndices[2]
                        )
                        output[idx] = value
                    }
                }
            }
            
            let storage = DataStorage.float32(output)
            return HyperCube(
                dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
                storage: storage,
                sourceFormat: cube.sourceFormat + " [Resize]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths,
                geoReference: transformedGeo
            )
        }
        
        var output = [Double](repeating: 0.0, count: total)
        
        let scaleX = Double(srcWidth) / Double(dstWidth)
        let scaleY = Double(srcHeight) / Double(dstHeight)
        
        for ch in 0..<channels {
            for y in 0..<dstHeight {
                for x in 0..<dstWidth {
                    let srcX = (Double(x) + 0.5) * scaleX - 0.5
                    let srcY = (Double(y) + 0.5) * scaleY - 0.5
                    let value = sample(
                        cube: cube,
                        axes: axes,
                        channel: ch,
                        x: srcX,
                        y: srcY,
                        algorithm: parameters.algorithm,
                        bicubicA: parameters.bicubicA,
                        lanczosA: parameters.lanczosA
                    )
                    
                    var outIndices = [0, 0, 0]
                    outIndices[axes.width] = x
                    outIndices[axes.height] = y
                    outIndices[axes.channel] = ch
                    
                    let idx = linearIndex(
                        dims: dimsArray,
                        isFortran: cube.isFortranOrder,
                        i0: outIndices[0],
                        i1: outIndices[1],
                        i2: outIndices[2]
                    )
                    output[idx] = value
                }
            }
        }
        
        let storage = DataStorage.float64(output)
        return HyperCube(
            dims: (dimsArray[0], dimsArray[1], dimsArray[2]),
            storage: storage,
            sourceFormat: cube.sourceFormat + " [Resize]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths,
            geoReference: transformedGeo
        )
    }
    
    private static func sample(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channel: Int,
        x: Double,
        y: Double,
        algorithm: ResizeAlgorithm,
        bicubicA: Double,
        lanczosA: Int
    ) -> Double {
        switch algorithm {
        case .nearest:
            let nx = Int(round(x))
            let ny = Int(round(y))
            return value(atX: nx, y: ny, channel: channel, cube: cube, axes: axes)
        case .bilinear:
            return bilinearSample(cube: cube, axes: axes, channel: channel, x: x, y: y)
        case .bicubic:
            return bicubicSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: bicubicA)
        case .bspline:
            return bicubicSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: -1.0)
        case .lanczos:
            return lanczosSample(cube: cube, axes: axes, channel: channel, x: x, y: y, a: max(1, lanczosA))
        }
    }
    
    private static func sampleFloat(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channel: Int,
        x: Float,
        y: Float,
        algorithm: ResizeAlgorithm,
        bicubicA: Float,
        lanczosA: Int
    ) -> Float {
        switch algorithm {
        case .nearest:
            let nx = Int(round(x))
            let ny = Int(round(y))
            return Float(value(atX: nx, y: ny, channel: channel, cube: cube, axes: axes))
        case .bilinear:
            return Float(bilinearSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y)))
        case .bicubic:
            return Float(bicubicSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: Double(bicubicA)))
        case .bspline:
            return Float(bicubicSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: -1.0))
        case .lanczos:
            return Float(lanczosSample(cube: cube, axes: axes, channel: channel, x: Double(x), y: Double(y), a: max(1, lanczosA)))
        }
    }

    private static func fillNearest<T>(
        from source: [T],
        into output: inout [T],
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        srcDims: [Int],
        dstWidth: Int,
        dstHeight: Int,
        scaleX: Double,
        scaleY: Double,
        dstDims: [Int]
    ) {
        let dstDimsArray = dstDims
        let channels = dstDimsArray[axes.channel]
        
        for ch in 0..<channels {
            for y in 0..<dstHeight {
                for x in 0..<dstWidth {
                    let srcX = Int(round((Double(x) + 0.5) * scaleX - 0.5))
                    let srcY = Int(round((Double(y) + 0.5) * scaleY - 0.5))
                    
                    var srcIndices = [0, 0, 0]
                    srcIndices[axes.channel] = ch
                    srcIndices[axes.height] = min(max(0, srcY), srcDims[axes.height] - 1)
                    srcIndices[axes.width] = min(max(0, srcX), srcDims[axes.width] - 1)
                    
                    let srcIdx = cube.linearIndex(i0: srcIndices[0], i1: srcIndices[1], i2: srcIndices[2])
                    
                    var dstIndices = [0, 0, 0]
                    dstIndices[axes.channel] = ch
                    dstIndices[axes.height] = y
                    dstIndices[axes.width] = x
                    
                    let dstIdx = linearIndex(
                        dims: dstDimsArray,
                        isFortran: cube.isFortranOrder,
                        i0: dstIndices[0],
                        i1: dstIndices[1],
                        i2: dstIndices[2]
                    )
                    
                    output[dstIdx] = source[srcIdx]
                }
            }
        }
    }
    
    private static func value(atX x: Int, y: Int, channel: Int, cube: HyperCube, axes: (channel: Int, height: Int, width: Int)) -> Double {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard x >= 0, y >= 0,
              x < dimsArray[axes.width],
              y < dimsArray[axes.height] else { return 0 }
        var indices = [0, 0, 0]
        indices[axes.channel] = channel
        indices[axes.height] = y
        indices[axes.width] = x
        return cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
    }
    
    private static func bilinearSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double) -> Double {
        let x0 = Int(floor(x))
        let x1 = x0 + 1
        let y0 = Int(floor(y))
        let y1 = y0 + 1
        let fx = x - Double(x0)
        let fy = y - Double(y0)
        
        let v00 = value(atX: x0, y: y0, channel: channel, cube: cube, axes: axes)
        let v10 = value(atX: x1, y: y0, channel: channel, cube: cube, axes: axes)
        let v01 = value(atX: x0, y: y1, channel: channel, cube: cube, axes: axes)
        let v11 = value(atX: x1, y: y1, channel: channel, cube: cube, axes: axes)
        
        let vx0 = v00 * (1 - fx) + v10 * fx
        let vx1 = v01 * (1 - fx) + v11 * fx
        return vx0 * (1 - fy) + vx1 * fy
    }
    
    private static func cubicWeight(_ t: Double, a: Double) -> Double {
        let at = abs(t)
        if at <= 1 {
            return (a + 2) * pow(at, 3) - (a + 3) * pow(at, 2) + 1
        } else if at < 2 {
            return a * pow(at, 3) - 5 * a * pow(at, 2) + 8 * a * at - 4 * a
        } else {
            return 0
        }
    }
    
    private static func bicubicSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double, a: Double) -> Double {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        
        var result = 0.0
        for m in -1...2 {
            let wy = cubicWeight(Double(m) - (y - Double(y0)), a: a)
            let sampleY = y0 + m
            for n in -1...2 {
                let wx = cubicWeight(Double(n) - (x - Double(x0)), a: a)
                let sampleX = x0 + n
                let v = value(atX: sampleX, y: sampleY, channel: channel, cube: cube, axes: axes)
                result += v * wx * wy
            }
        }
        return result
    }
    
    private static func sinc(_ x: Double) -> Double {
        if abs(x) < 1e-7 { return 1.0 }
        return sin(Double.pi * x) / (Double.pi * x)
    }
    
    private static func lanczosWeight(_ x: Double, a: Int) -> Double {
        let ax = abs(x)
        if ax >= Double(a) { return 0 }
        return sinc(ax) * sinc(ax / Double(a))
    }
    
    private static func lanczosSample(cube: HyperCube, axes: (channel: Int, height: Int, width: Int), channel: Int, x: Double, y: Double, a: Int) -> Double {
        let xInt = Int(floor(x))
        let yInt = Int(floor(y))
        var sum = 0.0
        var weightSum = 0.0
        
        for j in (yInt - a + 1)...(yInt + a) {
            let wy = lanczosWeight(Double(j) - y, a: a)
            if wy == 0 { continue }
            for i in (xInt - a + 1)...(xInt + a) {
                let wx = lanczosWeight(Double(i) - x, a: a)
                let w = wx * wy
                if w == 0 { continue }
                let v = value(atX: i, y: j, channel: channel, cube: cube, axes: axes)
                sum += v * w
                weightSum += w
            }
        }
        if weightSum == 0 { return 0 }
        return sum / weightSum
    }
    
    private static func linearIndex(dims: [Int], isFortran: Bool, i0: Int, i1: Int, i2: Int) -> Int {
        if isFortran {
            return i0 + dims[0] * (i1 + dims[1] * i2)
        } else {
            return i2 + dims[2] * (i1 + dims[1] * i0)
        }
    }
}

class CubeTransposer {
    static func transpose(cube: HyperCube, sourceLayout: CubeLayout, targetLayout: CubeLayout) -> HyperCube? {
        guard targetLayout != .auto else { return cube }
        guard let sourceAxes = cube.axes(for: sourceLayout),
              let targetAxes = cube.axes(for: targetLayout) else {
            return cube
        }
        
        if sourceAxes == targetAxes {
            return cube
        }
        
        let srcDims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let channels = srcDims[sourceAxes.channel]
        let height = srcDims[sourceAxes.height]
        let width = srcDims[sourceAxes.width]
        
        var dstDims = [0, 0, 0]
        dstDims[targetAxes.channel] = channels
        dstDims[targetAxes.height] = height
        dstDims[targetAxes.width] = width
        
        let totalElements = dstDims[0] * dstDims[1] * dstDims[2]
        guard totalElements == cube.storage.count else { return cube }
        
        let suffix = sourceLayout == .auto
            ? " [Transpose →\(targetLayout.rawValue)]"
            : " [Transpose \(sourceLayout.rawValue)→\(targetLayout.rawValue)]"
        
        switch cube.storage {
        case .float64(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .float64(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .float32(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .float32(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int8(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .int8(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int16(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .int16(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .int32(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .int32(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint8(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .uint8(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        case .uint16(let arr):
            var output = initializedBuffer(from: arr, count: totalElements)
            remap(
                source: arr,
                output: &output,
                srcDims: srcDims,
                dstDims: dstDims,
                sourceAxes: sourceAxes,
                targetAxes: targetAxes,
                isFortran: cube.isFortranOrder
            )
            return HyperCube(dims: (dstDims[0], dstDims[1], dstDims[2]), storage: .uint16(output), sourceFormat: cube.sourceFormat + suffix, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: cube.geoReference)
        }
    }
    
    private static func initializedBuffer<T>(from source: [T], count: Int) -> [T] {
        guard count > 0, let first = source.first else { return [] }
        return [T](repeating: first, count: count)
    }
    
    private static func remap<T>(
        source: [T],
        output: inout [T],
        srcDims: [Int],
        dstDims: [Int],
        sourceAxes: (channel: Int, height: Int, width: Int),
        targetAxes: (channel: Int, height: Int, width: Int),
        isFortran: Bool
    ) {
        let channelCount = srcDims[sourceAxes.channel]
        let height = srcDims[sourceAxes.height]
        let width = srcDims[sourceAxes.width]
        
        for c in 0..<channelCount {
            for y in 0..<height {
                for x in 0..<width {
                    var srcIdx = [0, 0, 0]
                    srcIdx[sourceAxes.channel] = c
                    srcIdx[sourceAxes.height] = y
                    srcIdx[sourceAxes.width] = x
                    
                    var dstIdx = [0, 0, 0]
                    dstIdx[targetAxes.channel] = c
                    dstIdx[targetAxes.height] = y
                    dstIdx[targetAxes.width] = x
                    
                    let srcLinear = linearIndex(
                        dims: srcDims,
                        fortran: isFortran,
                        i0: srcIdx[0],
                        i1: srcIdx[1],
                        i2: srcIdx[2]
                    )
                    let dstLinear = linearIndex(
                        dims: dstDims,
                        fortran: isFortran,
                        i0: dstIdx[0],
                        i1: dstIdx[1],
                        i2: dstIdx[2]
                    )
                    output[dstLinear] = source[srcLinear]
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
}

class CubeRotator {
    static func rotate(_ cube: HyperCube, angle: RotationAngle, layout: CubeLayout = .auto) -> HyperCube? {
        let dims = cube.dims
        var dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let channels = dimsArray[axes.channel]
        let oldHeight = dimsArray[axes.height]
        let oldWidth = dimsArray[axes.width]
        
        let newHeight: Int
        let newWidth: Int
        switch angle {
        case .degree90, .degree270:
            newHeight = oldWidth
            newWidth = oldHeight
        case .degree180:
            newHeight = oldHeight
            newWidth = oldWidth
        }
        
        var newDimsArray = dimsArray
        newDimsArray[axes.height] = newHeight
        newDimsArray[axes.width] = newWidth
        let resultingDims = (newDimsArray[0], newDimsArray[1], newDimsArray[2])
        let transformedGeo = cube.geoReference?.rotatedClockwise(
            quarterTurns: angle.quarterTurns,
            oldWidth: oldWidth,
            oldHeight: oldHeight
        )
        let totalElements = resultingDims.0 * resultingDims.1 * resultingDims.2
        if totalElements == 0 {
            return HyperCube(dims: resultingDims, storage: cube.storage, sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        }
        
        switch cube.storage {
        case .float64(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .float32(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .uint16(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .uint8(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .int16(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .int32(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
            
        case .int8(let arr):
            let newData = rotateBuffer(
                source: arr,
                axes: axes,
                angle: angle,
                channels: channels,
                oldHeight: oldHeight,
                oldWidth: oldWidth,
                newHeight: newHeight,
                newWidth: newWidth,
                oldDims: (dims.0, dims.1, dims.2),
                newDims: resultingDims,
                fortran: cube.isFortranOrder
            )
            return HyperCube(dims: resultingDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        }
    }
    
    private static func rotateBuffer<T>(
        source: [T],
        axes: (channel: Int, height: Int, width: Int),
        angle: RotationAngle,
        channels: Int,
        oldHeight: Int,
        oldWidth: Int,
        newHeight: Int,
        newWidth: Int,
        oldDims: (Int, Int, Int),
        newDims: (Int, Int, Int),
        fortran: Bool
    ) -> [T] {
        let totalElements = newDims.0 * newDims.1 * newDims.2
        if totalElements == 0 { return [] }
        guard let first = source.first else { return [] }
        var buffer = [T](repeating: first, count: totalElements)
        
        let oldStrides = strides(for: oldDims, fortran: fortran)
        let newStrides = strides(for: newDims, fortran: fortran)
        
        let channelStrideOld = oldStrides[axes.channel]
        let heightStrideOld = oldStrides[axes.height]
        let widthStrideOld = oldStrides[axes.width]
        
        let channelStrideNew = newStrides[axes.channel]
        let heightStrideNew = newStrides[axes.height]
        let widthStrideNew = newStrides[axes.width]
        
        source.withUnsafeBufferPointer { src in
            buffer.withUnsafeMutableBufferPointer { dst in
                switch angle {
                case .degree180:
                    for ch in 0..<channels {
                        let srcChannelBase = ch * channelStrideOld
                        let dstChannelBase = ch * channelStrideNew
                        for newY in 0..<newHeight {
                            let oldY = oldHeight - 1 - newY
                            let srcRowBase = srcChannelBase + oldY * heightStrideOld + (oldWidth - 1) * widthStrideOld
                            let dstRowBase = dstChannelBase + newY * heightStrideNew
                            var srcIndex = srcRowBase
                            var dstIndex = dstRowBase
                            for _ in 0..<newWidth {
                                dst[dstIndex] = src[srcIndex]
                                srcIndex -= widthStrideOld
                                dstIndex += widthStrideNew
                            }
                        }
                    }
                case .degree90:
                    for ch in 0..<channels {
                        let srcChannelBase = ch * channelStrideOld
                        let dstChannelBase = ch * channelStrideNew
                        for newY in 0..<newHeight {
                            let oldX = newY
                            let srcRowBase = srcChannelBase + oldX * widthStrideOld + (oldHeight - 1) * heightStrideOld
                            let dstRowBase = dstChannelBase + newY * heightStrideNew
                            var srcIndex = srcRowBase
                            var dstIndex = dstRowBase
                            for _ in 0..<newWidth {
                                dst[dstIndex] = src[srcIndex]
                                srcIndex -= heightStrideOld
                                dstIndex += widthStrideNew
                            }
                        }
                    }
                case .degree270:
                    for ch in 0..<channels {
                        let srcChannelBase = ch * channelStrideOld
                        let dstChannelBase = ch * channelStrideNew
                        for newY in 0..<newHeight {
                            let oldX = oldWidth - 1 - newY
                            let srcRowBase = srcChannelBase + oldX * widthStrideOld
                            let dstRowBase = dstChannelBase + newY * heightStrideNew
                            var srcIndex = srcRowBase
                            var dstIndex = dstRowBase
                            for _ in 0..<newWidth {
                                dst[dstIndex] = src[srcIndex]
                                srcIndex += heightStrideOld
                                dstIndex += widthStrideNew
                            }
                        }
                    }
                }
            }
        }
        
        return buffer
    }
    
    private static func strides(for dims: (Int, Int, Int), fortran: Bool) -> [Int] {
        if fortran {
            return [1, dims.0, dims.0 * dims.1]
        }
        return [dims.1 * dims.2, dims.2, 1]
    }
}

class CubeSpatialCropper {
    static func crop(cube: HyperCube, parameters: SpatialCropParameters, layout: CubeLayout) -> HyperCube? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        
        guard height > 0, width > 0 else { return cube }
        
        let clamped = parameters.clamped(maxWidth: width, maxHeight: height)
        guard clamped.width > 0, clamped.height > 0 else { return cube }
        
        var newDims = dimsArray
        newDims[axes.height] = clamped.height
        newDims[axes.width] = clamped.width
        let resultingDims = (newDims[0], newDims[1], newDims[2])
        let transformedGeo = cube.geoReference?.cropped(left: clamped.left, top: clamped.top)
        let totalElements = resultingDims.0 * resultingDims.1 * resultingDims.2
        
        switch cube.storage {
        case .float64(let arr):
            var newData = [Double](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .float64(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .float32(let arr):
            var newData = [Float](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .float32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .uint16(let arr):
            var newData = [UInt16](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .uint16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .uint8(let arr):
            var newData = [UInt8](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .uint8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .int16(let arr):
            var newData = [Int16](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int16(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .int32(let arr):
            var newData = [Int32](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int32(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        case .int8(let arr):
            var newData = [Int8](repeating: 0, count: totalElements)
            fillBuffer(cube: cube, source: arr, into: &newData, newDims: resultingDims, axes: axes, crop: clamped)
            return HyperCube(dims: resultingDims, storage: .int8(newData), sourceFormat: cube.sourceFormat, isFortranOrder: cube.isFortranOrder, wavelengths: cube.wavelengths, geoReference: transformedGeo)
        }
    }
    
    private static func fillBuffer<T>(
        cube: HyperCube,
        source: [T],
        into buffer: inout [T],
        newDims: (Int, Int, Int),
        axes: (channel: Int, height: Int, width: Int),
        crop: SpatialCropParameters
    ) {
        for i0 in 0..<newDims.0 {
            for i1 in 0..<newDims.1 {
                for i2 in 0..<newDims.2 {
                    var srcCoord = [i0, i1, i2]
                    srcCoord[axes.height] += crop.top
                    srcCoord[axes.width] += crop.left
                    
                    let srcIndex = cube.linearIndex(i0: srcCoord[0], i1: srcCoord[1], i2: srcCoord[2])
                    let dstIndex = linearIndex(i0: i0, i1: i1, i2: i2, dims: newDims, fortran: cube.isFortranOrder)
                    buffer[dstIndex] = source[srcIndex]
                }
            }
        }
    }
    
    private static func linearIndex(
        i0: Int,
        i1: Int,
        i2: Int,
        dims: (Int, Int, Int),
        fortran: Bool
    ) -> Int {
        if fortran {
            return i0 + dims.0 * (i1 + dims.1 * i2)
        } else {
            return i2 + dims.2 * (i1 + dims.1 * i0)
        }
    }
}

struct SpatialAutoCropComputationResult {
    var crop: SpatialCropParameters
    var score: Double
    var evaluatedCandidates: Int
}

struct WhitePointCandidate: Identifiable, Equatable {
    let id: UUID
    let rect: SpectrumROIRect
    let score: Double
    let brightnessScore: Double
    let spectralFlatnessScore: Double
    let spectralDispersionScore: Double
    let spectralHomogeneityScore: Double
    let contrastScore: Double
    let glarePenalty: Double
    let meanSpectrum: [Double]

    init(
        id: UUID = UUID(),
        rect: SpectrumROIRect,
        score: Double,
        brightnessScore: Double,
        spectralFlatnessScore: Double,
        spectralDispersionScore: Double,
        spectralHomogeneityScore: Double,
        contrastScore: Double,
        glarePenalty: Double,
        meanSpectrum: [Double]
    ) {
        self.id = id
        self.rect = rect
        self.score = score
        self.brightnessScore = brightnessScore
        self.spectralFlatnessScore = spectralFlatnessScore
        self.spectralDispersionScore = spectralDispersionScore
        self.spectralHomogeneityScore = spectralHomogeneityScore
        self.contrastScore = contrastScore
        self.glarePenalty = glarePenalty
        self.meanSpectrum = meanSpectrum
    }
}

struct WhitePointSearchProgressInfo {
    var progress: Double
    var message: String
    var evaluatedCandidates: Int
    var totalCandidates: Int
    var stage: String
}

struct WhitePointSearchResult {
    var candidates: [WhitePointCandidate]
    var evaluatedCandidates: Int
    var rejectedByGlare: Int
}

struct WhitePointSearchFactorWeights: Equatable {
    var brightness: Double = 1.0
    var localHomogeneity: Double = 1.0
    var spectralFlatness: Double = 1.0
    var spectralDispersion: Double = 1.0
    var spectralHomogeneity: Double = 1.0
    var contrast: Double = 1.0
    var neutrality: Double = 1.0
    var area: Double = 1.0
    var shape: Double = 1.0
    var glarePenalty: Double = 1.0

    static let identity = WhitePointSearchFactorWeights()
}

class CubeAutoSpatialCropper {
    private struct CropCandidate: Hashable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    private struct ScoredCandidate {
        var candidate: CropCandidate
        var score: Double
    }

    static func findBestCrop(
        sourceCube: HyperCube,
        sourceLayout: CubeLayout,
        referenceCube: HyperCube,
        referenceLayout: CubeLayout,
        settings: SpatialAutoCropSettings,
        progressCallback: ((SpatialAutoCropProgressInfo) -> Void)? = nil
    ) -> SpatialAutoCropComputationResult? {
        guard let sourceAxes = sourceCube.axes(for: sourceLayout),
              let referenceAxes = referenceCube.axes(for: referenceLayout) else {
            return nil
        }

        let sourceDims = [sourceCube.dims.0, sourceCube.dims.1, sourceCube.dims.2]
        let sourceWidth = sourceDims[sourceAxes.width]
        let sourceHeight = sourceDims[sourceAxes.height]
        let sourceChannels = sourceDims[sourceAxes.channel]

        let referenceDims = [referenceCube.dims.0, referenceCube.dims.1, referenceCube.dims.2]
        let referenceWidth = referenceDims[referenceAxes.width]
        let referenceHeight = referenceDims[referenceAxes.height]
        let referenceChannels = referenceDims[referenceAxes.channel]

        guard sourceWidth > 0, sourceHeight > 0, sourceChannels > 0 else { return nil }
        guard referenceWidth > 0, referenceHeight > 0, referenceChannels > 0 else { return nil }
        guard settings.sourceChannels.count == settings.referenceChannels.count else { return nil }
        guard !settings.sourceChannels.isEmpty else { return nil }
        guard settings.sourceChannels.allSatisfy({ $0 >= 0 && $0 < sourceChannels }) else { return nil }
        guard settings.referenceChannels.allSatisfy({ $0 >= 0 && $0 < referenceChannels }) else { return nil }

        let minWidthDefault = settings.saveAspectRatio
            ? 1
            : min(sourceWidth, max(1, referenceWidth))
        let minHeightDefault = settings.saveAspectRatio
            ? 1
            : min(sourceHeight, max(1, referenceHeight))

        let minWidth = bounded(settings.minWidth ?? minWidthDefault, min: 1, max: sourceWidth)
        let maxWidth = bounded(settings.maxWidth ?? sourceWidth, min: minWidth, max: sourceWidth)
        let minHeight = bounded(settings.minHeight ?? minHeightDefault, min: 1, max: sourceHeight)
        let maxHeight = bounded(settings.maxHeight ?? sourceHeight, min: minHeight, max: sourceHeight)
        func matchesReferenceAspectRatio(width: Int, height: Int) -> Bool {
            guard settings.saveAspectRatio else { return true }
            guard width > 0, height > 0, referenceWidth > 0, referenceHeight > 0 else { return false }
            let targetAspect = Double(referenceWidth) / Double(referenceHeight)
            let candidateAspect = Double(width) / Double(height)
            let tolerance = max(0.0, settings.aspectRatioTolerancePercent) / 100.0
            let relativeDeviation = abs(candidateAspect - targetAspect) / targetAspect
            return relativeDeviation <= tolerance + 1e-12
        }

        let positionStep = max(1, settings.positionStep)
        let sizeStep = max(1, settings.sizeStep)
        let downsampleFactor = max(1, settings.downsampleFactor)

        let uniqueSourceChannels = Array(Set(settings.sourceChannels)).sorted()
        let uniqueReferenceChannels = Array(Set(settings.referenceChannels)).sorted()
        var sourceChannelData: [Int: [Double]] = [:]
        var referenceChannelData: [Int: [Double]] = [:]

        for ch in uniqueSourceChannels {
            sourceChannelData[ch] = extractChannel(cube: sourceCube, channelIndex: ch, axes: sourceAxes)
        }
        for ch in uniqueReferenceChannels {
            referenceChannelData[ch] = extractChannel(cube: referenceCube, channelIndex: ch, axes: referenceAxes)
        }

        if sourceChannelData.count != uniqueSourceChannels.count || referenceChannelData.count != uniqueReferenceChannels.count {
            return nil
        }

        var referenceEvalData: [Int: [Double]] = [:]
        var evalReferenceWidth = referenceWidth
        var evalReferenceHeight = referenceHeight
        for ch in uniqueReferenceChannels {
            guard let channel = referenceChannelData[ch] else { return nil }
            if downsampleFactor > 1 {
                let downsampled = downsampleMean(channel, width: referenceWidth, height: referenceHeight, factor: downsampleFactor)
                referenceEvalData[ch] = downsampled.data
                evalReferenceWidth = downsampled.width
                evalReferenceHeight = downsampled.height
            } else {
                referenceEvalData[ch] = channel
            }
        }

        let coarsePositionStep = settings.useCoarseToFine ? max(positionStep * 2, positionStep) : positionStep
        let coarseSizeStep = settings.useCoarseToFine ? max(sizeStep * 2, sizeStep) : sizeStep
        let widthValues = steppedValues(min: minWidth, max: maxWidth, step: sizeStep)
        let heightValues = steppedValues(min: minHeight, max: maxHeight, step: sizeStep)
        let coarseWidthValues = settings.useCoarseToFine
            ? steppedValues(min: minWidth, max: maxWidth, step: coarseSizeStep)
            : widthValues
        let coarseHeightValues = settings.useCoarseToFine
            ? steppedValues(min: minHeight, max: maxHeight, step: coarseSizeStep)
            : heightValues

        let coarseCount = countCandidates(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            widthValues: coarseWidthValues,
            heightValues: coarseHeightValues,
            positionStep: coarsePositionStep,
            sizeFilter: matchesReferenceAspectRatio
        )
        let refinementReserve = (settings.useCoarseToFine && settings.keepRefinementReserve)
            ? max(sizeStep, positionStep)
            : 0
        let refinePositionStep = max(1, positionStep / 2)
        let refineSizeStep = max(1, sizeStep / 2)
        let topCandidateLimit = 8
        let sizeRefineRadius = sizeStep + refinementReserve
        let positionRefineRadius = positionStep + refinementReserve
        let refineEstimatePerSeed = max(1, (2 * sizeRefineRadius / refineSizeStep + 1) * (2 * sizeRefineRadius / refineSizeStep + 1))
            * max(1, (2 * positionRefineRadius / refinePositionStep + 1) * (2 * positionRefineRadius / refinePositionStep + 1))
        let estimatedTotalCandidates = settings.useCoarseToFine
            ? coarseCount + topCandidateLimit * refineEstimatePerSeed
            : coarseCount

        var evaluatedCandidates = 0
        var bestCandidate: CropCandidate?
        var bestScore: Double?
        var visited: Set<CropCandidate> = []
        let progressInterval = max(1, estimatedTotalCandidates / 200)

        func reportProgress(force: Bool = false) {
            guard force || evaluatedCandidates % progressInterval == 0 else { return }
            let progress = estimatedTotalCandidates > 0
                ? min(0.99, Double(evaluatedCandidates) / Double(estimatedTotalCandidates))
                : 0.0
            let label = settings.metric == .ssim ? "SSIM" : "MSE"
            let bestText: String
            if let bestScore {
                bestText = String(format: "%.6f", bestScore)
            } else {
                bestText = "—"
            }
            let bestCrop = bestCandidate.map {
                SpatialCropParameters(
                    left: $0.x,
                    right: $0.x + $0.width - 1,
                    top: $0.y,
                    bottom: $0.y + $0.height - 1
                )
            }
            progressCallback?(
                SpatialAutoCropProgressInfo(
                    progress: progress,
                    message: LF("pipeline.auto_crop.progress.iteration", label, bestText),
                    evaluatedCandidates: evaluatedCandidates,
                    totalCandidates: max(estimatedTotalCandidates, evaluatedCandidates),
                    bestCrop: bestCrop
                )
            )
        }

        func maybeUpdateBest(candidate: CropCandidate, score: Double) -> Bool {
            guard isFinite(score) else { return false }
            if isBetter(score: score, than: bestScore, metric: settings.metric) {
                bestScore = score
                bestCandidate = candidate
                return true
            }
            return false
        }

        func evaluateCandidate(_ candidate: CropCandidate) -> Double? {
            guard candidate.width > 0, candidate.height > 0 else { return nil }
            guard candidate.x >= 0, candidate.y >= 0 else { return nil }
            guard matchesReferenceAspectRatio(width: candidate.width, height: candidate.height) else { return nil }
            guard candidate.x + candidate.width <= sourceWidth,
                  candidate.y + candidate.height <= sourceHeight else {
                return nil
            }
            guard visited.insert(candidate).inserted else { return nil }

            evaluatedCandidates += 1

            var metricSum = 0.0
            let pairCount = settings.sourceChannels.count
            for idx in 0..<pairCount {
                let sourceChannelIndex = settings.sourceChannels[idx]
                let referenceChannelIndex = settings.referenceChannels[idx]
                guard let source = sourceChannelData[sourceChannelIndex],
                      let reference = referenceEvalData[referenceChannelIndex] else {
                    return nil
                }

                let cropped = cropChannel(
                    source,
                    sourceWidth: sourceWidth,
                    x: candidate.x,
                    y: candidate.y,
                    width: candidate.width,
                    height: candidate.height
                )
                let resized = resizeBilinear(
                    data: cropped,
                    srcWidth: candidate.width,
                    srcHeight: candidate.height,
                    dstWidth: referenceWidth,
                    dstHeight: referenceHeight
                )

                let evalData: [Double]
                if downsampleFactor > 1 {
                    evalData = downsampleMean(
                        resized,
                        width: referenceWidth,
                        height: referenceHeight,
                        factor: downsampleFactor
                    ).data
                } else {
                    evalData = resized
                }

                let score = computeMetric(
                    candidate: evalData,
                    reference: reference,
                    width: evalReferenceWidth,
                    height: evalReferenceHeight,
                    metric: settings.metric
                )
                metricSum += score

                if settings.metric == .mse,
                   settings.enableEarlyCandidatePruning,
                   let currentBest = bestScore {
                    let partial = metricSum / Double(idx + 1)
                    if partial > currentBest {
                        return nil
                    }
                }
            }

            let score = metricSum / Double(max(pairCount, 1))
            let didImprove = maybeUpdateBest(candidate: candidate, score: score)
            reportProgress(force: didImprove)
            return score
        }

        var topCandidates: [ScoredCandidate] = []
        func rememberTop(candidate: CropCandidate, score: Double) {
            topCandidates.append(ScoredCandidate(candidate: candidate, score: score))
            topCandidates.sort {
                settings.metric == .ssim ? $0.score > $1.score : $0.score < $1.score
            }
            if topCandidates.count > topCandidateLimit {
                topCandidates.removeLast(topCandidates.count - topCandidateLimit)
            }
        }

        progressCallback?(
            SpatialAutoCropProgressInfo(
                progress: 0.0,
                message: L("Подготовка данных для автоподбора…"),
                evaluatedCandidates: 0,
                totalCandidates: max(estimatedTotalCandidates, 1),
                bestCrop: nil
            )
        )

        enumerateCandidates(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            widthValues: coarseWidthValues,
            heightValues: coarseHeightValues,
            positionStep: coarsePositionStep,
            sizeFilter: matchesReferenceAspectRatio
        ) { candidate in
            guard let score = evaluateCandidate(candidate) else { return }
            if settings.useCoarseToFine {
                rememberTop(candidate: candidate, score: score)
            }
        }

        if settings.useCoarseToFine {
            let seeds = topCandidates.map { $0.candidate }
            for seed in seeds {
                let sizeRadius = sizeStep + refinementReserve
                let positionRadius = positionStep + refinementReserve
                let minLocalWidth = bounded(seed.width - sizeRadius, min: minWidth, max: maxWidth)
                let maxLocalWidth = bounded(seed.width + sizeRadius, min: minLocalWidth, max: maxWidth)
                let minLocalHeight = bounded(seed.height - sizeRadius, min: minHeight, max: maxHeight)
                let maxLocalHeight = bounded(seed.height + sizeRadius, min: minLocalHeight, max: maxHeight)

                let localWidths = steppedValues(min: minLocalWidth, max: maxLocalWidth, step: refineSizeStep)
                let localHeights = steppedValues(min: minLocalHeight, max: maxLocalHeight, step: refineSizeStep)
                let localSizes = enumerateSizePairs(
                    sourceWidth: sourceWidth,
                    sourceHeight: sourceHeight,
                    widthValues: localWidths,
                    heightValues: localHeights,
                    sizeFilter: matchesReferenceAspectRatio
                )

                for size in localSizes {
                    let width = size.width
                    let height = size.height
                    let maxX = max(0, sourceWidth - width)
                    let maxY = max(0, sourceHeight - height)
                    let minLocalX = bounded(seed.x - positionRadius, min: 0, max: maxX)
                    let maxLocalX = bounded(seed.x + positionRadius, min: minLocalX, max: maxX)
                    let minLocalY = bounded(seed.y - positionRadius, min: 0, max: maxY)
                    let maxLocalY = bounded(seed.y + positionRadius, min: minLocalY, max: maxY)

                    let xValues = steppedValues(min: minLocalX, max: maxLocalX, step: refinePositionStep)
                    let yValues = steppedValues(min: minLocalY, max: maxLocalY, step: refinePositionStep)
                    for y in yValues {
                        for x in xValues {
                            _ = evaluateCandidate(CropCandidate(x: x, y: y, width: width, height: height))
                        }
                    }
                }
            }
        }

        reportProgress(force: true)

        guard let bestCandidate, let bestScore else { return nil }
        let resultCrop = SpatialCropParameters(
            left: bestCandidate.x,
            right: bestCandidate.x + bestCandidate.width - 1,
            top: bestCandidate.y,
            bottom: bestCandidate.y + bestCandidate.height - 1,
            autoCropSettings: settings,
            autoCropResult: SpatialAutoCropResult(
                metric: settings.metric,
                bestScore: bestScore,
                evaluatedCandidates: evaluatedCandidates,
                referenceLibraryID: settings.referenceLibraryID,
                sourceChannels: settings.sourceChannels,
                referenceChannels: settings.referenceChannels,
                selectedWidth: bestCandidate.width,
                selectedHeight: bestCandidate.height
            )
        )

        progressCallback?(
            SpatialAutoCropProgressInfo(
                progress: 1.0,
                message: L("Автоподбор завершён"),
                evaluatedCandidates: evaluatedCandidates,
                totalCandidates: max(estimatedTotalCandidates, evaluatedCandidates),
                bestCrop: resultCrop
            )
        )

        return SpatialAutoCropComputationResult(
            crop: resultCrop,
            score: bestScore,
            evaluatedCandidates: evaluatedCandidates
        )
    }

    private static func enumerateCandidates(
        sourceWidth: Int,
        sourceHeight: Int,
        widthValues: [Int],
        heightValues: [Int],
        positionStep: Int,
        sizeFilter: ((Int, Int) -> Bool)? = nil,
        preferSmallerResolutions: Bool = false,
        body: (CropCandidate) -> Void
    ) {
        let sizePairs = enumerateSizePairs(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            widthValues: widthValues,
            heightValues: heightValues,
            sizeFilter: sizeFilter,
            preferSmallerResolutions: preferSmallerResolutions
        )
        for size in sizePairs {
            let width = size.width
            let height = size.height
            let maxY = sourceHeight - height
            let yValues = steppedValues(min: 0, max: maxY, step: positionStep)
            let maxX = sourceWidth - width
            let xValues = steppedValues(min: 0, max: maxX, step: positionStep)
            for y in yValues {
                for x in xValues {
                    body(CropCandidate(x: x, y: y, width: width, height: height))
                }
            }
        }
    }

    private static func countCandidates(
        sourceWidth: Int,
        sourceHeight: Int,
        widthValues: [Int],
        heightValues: [Int],
        positionStep: Int,
        sizeFilter: ((Int, Int) -> Bool)? = nil,
        preferSmallerResolutions: Bool = false
    ) -> Int {
        let sizePairs = enumerateSizePairs(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            widthValues: widthValues,
            heightValues: heightValues,
            sizeFilter: sizeFilter,
            preferSmallerResolutions: preferSmallerResolutions
        )
        var total = 0
        for size in sizePairs {
            let width = size.width
            let height = size.height
            let yCount = steppedValues(min: 0, max: sourceHeight - height, step: positionStep).count
            let xCount = steppedValues(min: 0, max: sourceWidth - width, step: positionStep).count
            total += xCount * yCount
        }
        return total
    }

    private static func enumerateSizePairs(
        sourceWidth: Int,
        sourceHeight: Int,
        widthValues: [Int],
        heightValues: [Int],
        sizeFilter: ((Int, Int) -> Bool)? = nil,
        preferSmallerResolutions: Bool = false
    ) -> [(width: Int, height: Int)] {
        var sizes: [(width: Int, height: Int)] = []
        sizes.reserveCapacity(widthValues.count * heightValues.count)
        for height in heightValues where height > 0 && height <= sourceHeight {
            for width in widthValues where width > 0 && width <= sourceWidth {
                if let sizeFilter, !sizeFilter(width, height) { continue }
                sizes.append((width: width, height: height))
            }
        }

        guard preferSmallerResolutions else { return sizes }
        sizes.sort { lhs, rhs in
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            if lhs.height != rhs.height {
                return lhs.height < rhs.height
            }
            return lhs.width < rhs.width
        }
        return sizes
    }

    private static func steppedValues(min: Int, max: Int, step: Int) -> [Int] {
        guard min <= max else { return [] }
        let safeStep = Swift.max(1, step)
        var values = Array(stride(from: min, through: max, by: safeStep))
        if values.last != max {
            values.append(max)
        }
        return values
    }

    private static func extractChannel(
        cube: HyperCube,
        channelIndex: Int,
        axes: (channel: Int, height: Int, width: Int)
    ) -> [Double] {
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let width = dims[axes.width]
        let height = dims[axes.height]
        var result = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var idx = [0, 0, 0]
                idx[axes.channel] = channelIndex
                idx[axes.height] = y
                idx[axes.width] = x
                let linear = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                result[y * width + x] = cube.getValue(at: linear)
            }
        }
        return result
    }

    private static func cropChannel(
        _ data: [Double],
        sourceWidth: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> [Double] {
        var cropped = [Double](repeating: 0, count: width * height)
        for row in 0..<height {
            let srcBase = (y + row) * sourceWidth + x
            let dstBase = row * width
            for col in 0..<width {
                cropped[dstBase + col] = data[srcBase + col]
            }
        }
        return cropped
    }

    private static func resizeBilinear(
        data: [Double],
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int
    ) -> [Double] {
        guard srcWidth > 0, srcHeight > 0, dstWidth > 0, dstHeight > 0 else { return [] }
        if srcWidth == dstWidth && srcHeight == dstHeight {
            return data
        }

        var resized = [Double](repeating: 0, count: dstWidth * dstHeight)
        let scaleX = Double(srcWidth) / Double(dstWidth)
        let scaleY = Double(srcHeight) / Double(dstHeight)

        for y in 0..<dstHeight {
            let srcY = (Double(y) + 0.5) * scaleY - 0.5
            let y0 = Int(floor(srcY))
            let y1 = y0 + 1
            let fy = srcY - Double(y0)

            for x in 0..<dstWidth {
                let srcX = (Double(x) + 0.5) * scaleX - 0.5
                let x0 = Int(floor(srcX))
                let x1 = x0 + 1
                let fx = srcX - Double(x0)

                let p00 = sample(data: data, width: srcWidth, height: srcHeight, x: x0, y: y0)
                let p10 = sample(data: data, width: srcWidth, height: srcHeight, x: x1, y: y0)
                let p01 = sample(data: data, width: srcWidth, height: srcHeight, x: x0, y: y1)
                let p11 = sample(data: data, width: srcWidth, height: srcHeight, x: x1, y: y1)

                let top = p00 * (1.0 - fx) + p10 * fx
                let bottom = p01 * (1.0 - fx) + p11 * fx
                resized[y * dstWidth + x] = top * (1.0 - fy) + bottom * fy
            }
        }

        return resized
    }

    private static func sample(
        data: [Double],
        width: Int,
        height: Int,
        x: Int,
        y: Int
    ) -> Double {
        let clampedX = bounded(x, min: 0, max: max(width - 1, 0))
        let clampedY = bounded(y, min: 0, max: max(height - 1, 0))
        return data[clampedY * width + clampedX]
    }

    private static func downsampleMean(
        _ data: [Double],
        width: Int,
        height: Int,
        factor: Int
    ) -> (data: [Double], width: Int, height: Int) {
        let safeFactor = max(1, factor)
        guard safeFactor > 1 else { return (data, width, height) }

        let newWidth = max(1, width / safeFactor)
        let newHeight = max(1, height / safeFactor)
        var result = [Double](repeating: 0, count: newWidth * newHeight)

        for y in 0..<newHeight {
            for x in 0..<newWidth {
                var sum = 0.0
                var count = 0.0
                for fy in 0..<safeFactor {
                    for fx in 0..<safeFactor {
                        let srcX = x * safeFactor + fx
                        let srcY = y * safeFactor + fy
                        if srcX < width && srcY < height {
                            sum += data[srcY * width + srcX]
                            count += 1.0
                        }
                    }
                }
                result[y * newWidth + x] = count > 0 ? sum / count : 0.0
            }
        }

        return (result, newWidth, newHeight)
    }

    private static func computeMetric(
        candidate: [Double],
        reference: [Double],
        width: Int,
        height: Int,
        metric: SpatialAutoCropMetric
    ) -> Double {
        guard !candidate.isEmpty,
              candidate.count == reference.count,
              width > 0, height > 0 else {
            return metric == .ssim ? -1.0 : Double.infinity
        }

        let normCandidate = normalizeData(candidate)
        let normReference = normalizeData(reference)
        switch metric {
        case .ssim:
            return computeSSIMDirect(normCandidate, normReference)
        case .mse:
            var mse = 0.0
            for i in 0..<normCandidate.count {
                let diff = normCandidate[i] - normReference[i]
                mse += diff * diff
            }
            return mse / Double(normCandidate.count)
        }
    }

    private static func normalizeData(_ data: [Double]) -> [Double] {
        guard !data.isEmpty else { return [] }
        var minValue = Double.infinity
        var maxValue = -Double.infinity
        for value in data {
            if value < minValue { minValue = value }
            if value > maxValue { maxValue = value }
        }
        let range = maxValue - minValue
        guard range > 1e-12 else {
            return [Double](repeating: 0.0, count: data.count)
        }
        var normalized = [Double](repeating: 0, count: data.count)
        for i in 0..<data.count {
            normalized[i] = (data[i] - minValue) / range
        }
        return normalized
    }

    private static func computeSSIMDirect(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1.0 }
        let count = Double(lhs.count)

        var sumL = 0.0
        var sumR = 0.0
        var sumSqL = 0.0
        var sumSqR = 0.0
        var sumProd = 0.0

        for i in 0..<lhs.count {
            let l = lhs[i]
            let r = rhs[i]
            sumL += l
            sumR += r
            sumSqL += l * l
            sumSqR += r * r
            sumProd += l * r
        }

        let muL = sumL / count
        let muR = sumR / count
        let sigmaLSq = max(0, sumSqL / count - muL * muL)
        let sigmaRSq = max(0, sumSqR / count - muR * muR)
        let sigmaLR = sumProd / count - muL * muR

        let c1 = 0.0001
        let c2 = 0.0009
        let numerator = (2.0 * muL * muR + c1) * (2.0 * sigmaLR + c2)
        let denominator = (muL * muL + muR * muR + c1) * (sigmaLSq + sigmaRSq + c2)
        guard denominator > 1e-12 else { return 0.0 }
        return numerator / denominator
    }

    private static func isBetter(score: Double, than currentBest: Double?, metric: SpatialAutoCropMetric) -> Bool {
        guard let currentBest else { return true }
        switch metric {
        case .ssim:
            return score > currentBest
        case .mse:
            return score < currentBest
        }
    }

    private static func bounded(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }

    private static func isFinite(_ value: Double) -> Bool {
        value.isFinite && !value.isNaN
    }

}

