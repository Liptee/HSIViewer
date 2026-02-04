import Foundation
import AppKit

class ImageRenderer {
    static func renderGrayscale(
        cube: HyperCube,
        layout: CubeLayout,
        channelIndex: Int
    ) -> NSImage? {
        if cube.is2D {
            return render2DImage(cube: cube)
        }
        
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        
        let cCount = dimsArr[axes.channel]
        guard cCount > 0 else { return nil }
        guard channelIndex >= 0 && channelIndex < cCount else { return nil }
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        
        var slice = [Double](repeating: 0.0, count: h * w)
        
        for y in 0..<h {
            for x in 0..<w {
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = channelIndex
                idx3[axes.height] = y
                idx3[axes.width] = x
                
                let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                slice[y * w + x] = cube.getValue(at: lin)
            }
        }
        
        let normalized = DataNormalizer.normalize(slice)
        let pixels = DataNormalizer.toUInt8(normalized.normalized)
        
        return createGrayscaleImage(pixels: pixels, width: w, height: h)
    }
    
    static func renderRGB(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        mapping: RGBChannelMapping
    ) -> NSImage? {
        _ = wavelengths
        if cube.is2D {
            return render2DImage(cube: cube)
        }
        
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        
        let cCount = dimsArr[axes.channel]
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        
        let mapped = mapping.clamped(maxChannelCount: cCount)
        let idxR = mapped.red
        let idxG = mapped.green
        let idxB = mapped.blue
        
        let sliceR = extractChannel(cube: cube, axes: axes, channelIndex: idxR, h: h, w: w)
        let sliceG = extractChannel(cube: cube, axes: axes, channelIndex: idxG, h: h, w: w)
        let sliceB = extractChannel(cube: cube, axes: axes, channelIndex: idxB, h: h, w: w)
        
        let normR = DataNormalizer.normalize(sliceR)
        let normG = DataNormalizer.normalize(sliceG)
        let normB = DataNormalizer.normalize(sliceB)
        
        let pixelsR = DataNormalizer.toUInt8(normR.normalized)
        let pixelsG = DataNormalizer.toUInt8(normG.normalized)
        let pixelsB = DataNormalizer.toUInt8(normB.normalized)
        
        return createRGBImage(r: pixelsR, g: pixelsG, b: pixelsB, width: w, height: h)
    }

    static func renderRGBRange(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        rangeMapping: RGBChannelRangeMapping
    ) -> NSImage? {
        _ = wavelengths
        if cube.is2D {
            return render2DImage(cube: cube)
        }
        
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        
        let cCount = dimsArr[axes.channel]
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        
        let clamped = rangeMapping.clamped(maxChannelCount: cCount)
        let rangeR = clamped.red.normalized
        let rangeG = clamped.green.normalized
        let rangeB = clamped.blue.normalized
        
        let sliceR = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeR, h: h, w: w)
        let sliceG = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeG, h: h, w: w)
        let sliceB = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeB, h: h, w: w)
        
        let normR = DataNormalizer.normalize(sliceR)
        let normG = DataNormalizer.normalize(sliceG)
        let normB = DataNormalizer.normalize(sliceB)
        
        let pixelsR = DataNormalizer.toUInt8(normR.normalized)
        let pixelsG = DataNormalizer.toUInt8(normG.normalized)
        let pixelsB = DataNormalizer.toUInt8(normB.normalized)
        
        return createRGBImage(r: pixelsR, g: pixelsG, b: pixelsB, width: w, height: h)
    }
    
    private static func extractChannel(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channelIndex: Int,
        h: Int,
        w: Int
    ) -> [Double] {
        var slice = [Double](repeating: 0.0, count: h * w)
        
        for y in 0..<h {
            for x in 0..<w {
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = channelIndex
                idx3[axes.height] = y
                idx3[axes.width] = x
                
                let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                slice[y * w + x] = cube.getValue(at: lin)
            }
        }
        
        return slice
    }

    private static func extractChannelRangeAverage(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        range: RGBChannelRange,
        h: Int,
        w: Int
    ) -> [Double] {
        let normalized = range.normalized
        let start = normalized.start
        let end = normalized.end
        let count = max(end - start + 1, 1)
        var slice = [Double](repeating: 0.0, count: h * w)
        
        for ch in start...end {
            for y in 0..<h {
                for x in 0..<w {
                    var idx3 = [0, 0, 0]
                    idx3[axes.channel] = ch
                    idx3[axes.height] = y
                    idx3[axes.width] = x
                    
                    let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                    slice[y * w + x] += cube.getValue(at: lin)
                }
            }
        }
        
        let divisor = Double(count)
        if divisor > 1 {
            for i in 0..<slice.count {
                slice[i] /= divisor
            }
        }
        
        return slice
    }

    static func renderND(
        cube: HyperCube,
        layout: CubeLayout,
        positiveIndex: Int,
        negativeIndex: Int,
        palette: NDPalette,
        threshold: Double,
        preset: NDIndexPreset,
        wdviSlope: Double,
        wdviIntercept: Double
    ) -> NSImage? {
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        let channels = dimsArr[axes.channel]
        let height = dimsArr[axes.height]
        let width = dimsArr[axes.width]
        
        guard channels > max(positiveIndex, negativeIndex), positiveIndex >= 0, negativeIndex >= 0 else { return nil }
        
        let positiveSlice = extractChannel(cube: cube, axes: axes, channelIndex: positiveIndex, h: height, w: width)
        let negativeSlice = extractChannel(cube: cube, axes: axes, channelIndex: negativeIndex, h: height, w: width)
        
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var values = [Double](repeating: 0, count: width * height)
        let epsilon = 1e-9
        
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude
        
        for i in 0..<(width * height) {
            let positive = positiveSlice[i]
            let negative = negativeSlice[i]
            let value: Double
            switch preset {
            case .ndvi, .ndsi:
                let denom = positive + negative
                value = abs(denom) < epsilon ? 0.0 : (positive - negative) / denom
            case .wdvi:
                value = positive - (wdviSlope * negative + wdviIntercept)
            }
            values[i] = value
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }
        
        let span = maxValue - minValue
        
        for i in 0..<(width * height) {
            let raw = values[i]
            let normalized: Double
            switch preset {
            case .ndvi, .ndsi:
                normalized = raw // already in [-1,1] ideally
            case .wdvi:
                if span <= epsilon {
                    normalized = 0
                } else {
                    let t = (raw - minValue) / span // 0...1
                    normalized = t * 2 - 1 // -1...1 for palette reuse
                }
            }
            
            let (r, g, b) = colorForND(normalized, palette: palette, threshold: threshold)
            let base = i * 4
            pixels[base] = r
            pixels[base + 1] = g
            pixels[base + 2] = b
            pixels[base + 3] = 255
        }
        
        return createRGBImage(r: pixelsAt(pixels, channel: 0),
                              g: pixelsAt(pixels, channel: 1),
                              b: pixelsAt(pixels, channel: 2),
                              width: width,
                              height: height)
    }
    
    private static func pixelsAt(_ buffer: [UInt8], channel: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: buffer.count / 4)
        for i in 0..<result.count {
            result[i] = buffer[i * 4 + channel]
        }
        return result
    }
    
    private static func colorForND(_ value: Double, palette: NDPalette, threshold: Double) -> (UInt8, UInt8, UInt8) {
        let v = max(-1.0, min(1.0, value))
        switch palette {
        case .grayscale:
            let t = (v + 1.0) / 2.0
            let g = UInt8(clamping: Int(t * 255.0))
            return (g, g, g)
        case .binaryVegetation:
            let isVeg = v > threshold
            return isVeg ? (44, 160, 44) : (170, 85, 0)
        case .classic:
            return classicPaletteColor(v)
        }
    }
    
    private static func classicPaletteColor(_ v: Double) -> (UInt8, UInt8, UInt8) {
        let t = (v + 1.0) / 2.0
        // color stops (t, r, g, b)
        let stops: [(Double, Double, Double, Double)] = [
            (0.0, 0.5, 0.1, 0.1),
            (0.25, 0.75, 0.5, 0.2),
            (0.5, 0.95, 0.95, 0.4),
            (0.7, 0.4, 0.8, 0.4),
            (1.0, 0.0, 0.5, 0.0)
        ]
        
        let clamped = max(0.0, min(1.0, t))
        var lower = stops[0]
        var upper = stops.last!
        
        for i in 0..<(stops.count - 1) {
            if clamped >= stops[i].0 && clamped <= stops[i + 1].0 {
                lower = stops[i]
                upper = stops[i + 1]
                break
            }
        }
        
        let span = upper.0 - lower.0
        let localT = span > 0 ? (clamped - lower.0) / span : 0
        let r = interpolate(lower.1, upper.1, t: localT)
        let g = interpolate(lower.2, upper.2, t: localT)
        let b = interpolate(lower.3, upper.3, t: localT)
        return (toUInt8(r), toUInt8(g), toUInt8(b))
    }
    
    private static func interpolate(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }
    
    private static func toUInt8(_ value: Double) -> UInt8 {
        UInt8(clamping: Int(max(0.0, min(1.0, value)) * 255.0))
    }
    
    private static func createGrayscaleImage(pixels: [UInt8], width: Int, height: Int) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width * 1
        
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    private static func createRGBImage(
        r: [UInt8],
        g: [UInt8],
        b: [UInt8],
        width: Int,
        height: Int
    ) -> NSImage? {
        let pixelCount = width * height
        guard r.count == pixelCount, g.count == pixelCount, b.count == pixelCount else {
            return nil
        }
        
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        
        for i in 0..<pixelCount {
            let base = i * 4
            pixels[base + 0] = r[i]
            pixels[base + 1] = g[i]
            pixels[base + 2] = b[i]
            pixels[base + 3] = 255
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    private static func render2DImage(cube: HyperCube) -> NSImage? {
        guard cube.is2D, let dims2D = cube.dims2D else { return nil }
        
        let width = dims2D.width
        let height = dims2D.height
        
        var slice = [Double](repeating: 0.0, count: width * height)
        
        let (d0, d1, d2) = cube.dims
        
        if d0 == 1 {
            for y in 0..<height {
                for x in 0..<width {
                    let lin = cube.linearIndex(i0: 0, i1: y, i2: x)
                    slice[y * width + x] = cube.getValue(at: lin)
                }
            }
        } else if d1 == 1 {
            for y in 0..<height {
                for x in 0..<width {
                    let lin = cube.linearIndex(i0: y, i1: 0, i2: x)
                    slice[y * width + x] = cube.getValue(at: lin)
                }
            }
        } else {
            for y in 0..<height {
                for x in 0..<width {
                    let lin = cube.linearIndex(i0: y, i1: x, i2: 0)
                    slice[y * width + x] = cube.getValue(at: lin)
                }
            }
        }
        
        let normalized = DataNormalizer.normalize(slice)
        let pixels = DataNormalizer.toUInt8(normalized.normalized)
        
        return createGrayscaleImage(pixels: pixels, width: width, height: height)
    }
}
