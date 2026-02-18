import Foundation
import AppKit

class ImageRenderer {
    private struct SamplingPlan {
        let outputWidth: Int
        let outputHeight: Int
        let xMap: [Int]
        let yMap: [Int]
        let logicalSize: NSSize
    }

    private static let cacheVersion = "v2"
    private static let renderCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    static func renderGrayscale(
        cube: HyperCube,
        layout: CubeLayout,
        channelIndex: Int,
        targetPixels: CGSize? = nil
    ) -> NSImage? {
        if cube.is2D {
            return render2DImage(cube: cube, targetPixels: targetPixels)
        }

        guard let axes = cube.axes(for: layout) else { return nil }

        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]

        let cCount = dimsArr[axes.channel]
        guard cCount > 0 else { return nil }
        guard channelIndex >= 0 && channelIndex < cCount else { return nil }

        let sourceHeight = dimsArr[axes.height]
        let sourceWidth = dimsArr[axes.width]
        let plan = samplingPlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels
        )

        let cacheKey = makeCacheKey([
            "gray",
            cube.id.uuidString,
            layout.rawValue,
            channelIndex,
            plan.outputWidth,
            plan.outputHeight
        ])
        if let cached = renderCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let slice = extractChannel(
            cube: cube,
            axes: axes,
            channelIndex: channelIndex,
            plan: plan
        )
        let pixels = normalizeToUInt8(slice)

        guard let image = createGrayscaleImage(
            pixels: pixels,
            width: plan.outputWidth,
            height: plan.outputHeight,
            logicalSize: plan.logicalSize
        ) else {
            return nil
        }

        storeInCache(image: image, key: cacheKey, width: plan.outputWidth, height: plan.outputHeight)
        return image
    }

    static func renderRGB(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        mapping: RGBChannelMapping,
        targetPixels: CGSize? = nil
    ) -> NSImage? {
        _ = wavelengths
        if cube.is2D {
            return render2DImage(cube: cube, targetPixels: targetPixels)
        }

        guard let axes = cube.axes(for: layout) else { return nil }

        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]

        let cCount = dimsArr[axes.channel]
        guard cCount > 0 else { return nil }

        let sourceHeight = dimsArr[axes.height]
        let sourceWidth = dimsArr[axes.width]
        let plan = samplingPlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels
        )

        let mapped = mapping.clamped(maxChannelCount: cCount)
        let idxR = mapped.red
        let idxG = mapped.green
        let idxB = mapped.blue

        let cacheKey = makeCacheKey([
            "rgb",
            cube.id.uuidString,
            layout.rawValue,
            idxR,
            idxG,
            idxB,
            plan.outputWidth,
            plan.outputHeight
        ])
        if let cached = renderCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let sliceR = extractChannel(cube: cube, axes: axes, channelIndex: idxR, plan: plan)
        let sliceG = extractChannel(cube: cube, axes: axes, channelIndex: idxG, plan: plan)
        let sliceB = extractChannel(cube: cube, axes: axes, channelIndex: idxB, plan: plan)

        let pixelsR = normalizeToUInt8(sliceR)
        let pixelsG = normalizeToUInt8(sliceG)
        let pixelsB = normalizeToUInt8(sliceB)

        guard let image = createRGBImage(
            r: pixelsR,
            g: pixelsG,
            b: pixelsB,
            width: plan.outputWidth,
            height: plan.outputHeight,
            logicalSize: plan.logicalSize
        ) else {
            return nil
        }

        storeInCache(image: image, key: cacheKey, width: plan.outputWidth, height: plan.outputHeight)
        return image
    }

    static func renderRGBRange(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        rangeMapping: RGBChannelRangeMapping,
        targetPixels: CGSize? = nil
    ) -> NSImage? {
        _ = wavelengths
        if cube.is2D {
            return render2DImage(cube: cube, targetPixels: targetPixels)
        }

        guard let axes = cube.axes(for: layout) else { return nil }

        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]

        let cCount = dimsArr[axes.channel]
        guard cCount > 0 else { return nil }

        let sourceHeight = dimsArr[axes.height]
        let sourceWidth = dimsArr[axes.width]
        let plan = samplingPlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels
        )

        let clamped = rangeMapping.clamped(maxChannelCount: cCount)
        let rangeR = clamped.red.normalized
        let rangeG = clamped.green.normalized
        let rangeB = clamped.blue.normalized

        let cacheKey = makeCacheKey([
            "rgb-range",
            cube.id.uuidString,
            layout.rawValue,
            rangeR.start,
            rangeR.end,
            rangeG.start,
            rangeG.end,
            rangeB.start,
            rangeB.end,
            plan.outputWidth,
            plan.outputHeight
        ])
        if let cached = renderCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let sliceR = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeR, plan: plan)
        let sliceG = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeG, plan: plan)
        let sliceB = extractChannelRangeAverage(cube: cube, axes: axes, range: rangeB, plan: plan)

        let pixelsR = normalizeToUInt8(sliceR)
        let pixelsG = normalizeToUInt8(sliceG)
        let pixelsB = normalizeToUInt8(sliceB)

        guard let image = createRGBImage(
            r: pixelsR,
            g: pixelsG,
            b: pixelsB,
            width: plan.outputWidth,
            height: plan.outputHeight,
            logicalSize: plan.logicalSize
        ) else {
            return nil
        }

        storeInCache(image: image, key: cacheKey, width: plan.outputWidth, height: plan.outputHeight)
        return image
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
        wdviIntercept: Double,
        targetPixels: CGSize? = nil
    ) -> NSImage? {
        guard let axes = cube.axes(for: layout) else { return nil }

        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        let channels = dimsArr[axes.channel]
        let sourceHeight = dimsArr[axes.height]
        let sourceWidth = dimsArr[axes.width]

        guard channels > max(positiveIndex, negativeIndex), positiveIndex >= 0, negativeIndex >= 0 else { return nil }

        let plan = samplingPlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels
        )

        let cacheKey = makeCacheKey([
            "nd",
            cube.id.uuidString,
            layout.rawValue,
            positiveIndex,
            negativeIndex,
            preset.rawValue,
            palette.rawValue,
            String(format: "%.5f", threshold),
            String(format: "%.5f", wdviSlope),
            String(format: "%.5f", wdviIntercept),
            plan.outputWidth,
            plan.outputHeight
        ])
        if let cached = renderCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let positiveSlice = extractChannel(cube: cube, axes: axes, channelIndex: positiveIndex, plan: plan)
        let negativeSlice = extractChannel(cube: cube, axes: axes, channelIndex: negativeIndex, plan: plan)

        var pixels = [UInt8](repeating: 0, count: plan.outputWidth * plan.outputHeight * 4)
        var values = [Double](repeating: 0, count: plan.outputWidth * plan.outputHeight)
        let epsilon = 1e-9

        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude

        for i in 0..<values.count {
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
            if value < minValue { minValue = value }
            if value > maxValue { maxValue = value }
        }

        let span = maxValue - minValue

        for i in 0..<values.count {
            let raw = values[i]
            let normalized: Double
            switch preset {
            case .ndvi, .ndsi:
                normalized = raw
            case .wdvi:
                if span <= epsilon {
                    normalized = 0
                } else {
                    let t = (raw - minValue) / span
                    normalized = t * 2 - 1
                }
            }

            let (r, g, b) = colorForND(normalized, palette: palette, threshold: threshold)
            let base = i * 4
            pixels[base] = r
            pixels[base + 1] = g
            pixels[base + 2] = b
            pixels[base + 3] = 255
        }

        guard let image = createRGBAImage(
            rgba: pixels,
            width: plan.outputWidth,
            height: plan.outputHeight,
            logicalSize: plan.logicalSize
        ) else {
            return nil
        }

        storeInCache(image: image, key: cacheKey, width: plan.outputWidth, height: plan.outputHeight)
        return image
    }

    private static func makeCacheKey(_ components: [CustomStringConvertible]) -> String {
        ([cacheVersion] + components.map { "\($0)" }).joined(separator: "|")
    }

    private static func storeInCache(image: NSImage, key: String, width: Int, height: Int) {
        let cost = max(1, width * height * 4)
        renderCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private static func samplingPlan(
        sourceWidth: Int,
        sourceHeight: Int,
        targetPixels: CGSize?
    ) -> SamplingPlan {
        let logicalSize = NSSize(width: sourceWidth, height: sourceHeight)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return SamplingPlan(
                outputWidth: 1,
                outputHeight: 1,
                xMap: [0],
                yMap: [0],
                logicalSize: logicalSize
            )
        }

        guard let targetPixels else {
            return SamplingPlan(
                outputWidth: sourceWidth,
                outputHeight: sourceHeight,
                xMap: Array(0..<sourceWidth),
                yMap: Array(0..<sourceHeight),
                logicalSize: logicalSize
            )
        }

        let requestedWidth = max(1, Int(targetPixels.width.rounded()))
        let requestedHeight = max(1, Int(targetPixels.height.rounded()))

        let outputWidth = min(sourceWidth, requestedWidth)
        let outputHeight = min(sourceHeight, requestedHeight)

        return SamplingPlan(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            xMap: coordinateMap(sourceCount: sourceWidth, outputCount: outputWidth),
            yMap: coordinateMap(sourceCount: sourceHeight, outputCount: outputHeight),
            logicalSize: logicalSize
        )
    }

    private static func coordinateMap(sourceCount: Int, outputCount: Int) -> [Int] {
        guard sourceCount > 0, outputCount > 0 else { return [0] }
        if sourceCount == outputCount {
            return Array(0..<sourceCount)
        }

        let scale = Double(sourceCount) / Double(outputCount)
        var map = [Int](repeating: 0, count: outputCount)
        for dst in 0..<outputCount {
            let src = ((Double(dst) + 0.5) * scale - 0.5).rounded()
            map[dst] = max(0, min(Int(src), sourceCount - 1))
        }
        return map
    }

    private static func storageStrides(for cube: HyperCube) -> [Int] {
        let (d0, d1, d2) = cube.dims
        if cube.isFortranOrder {
            return [1, d0, d0 * d1]
        } else {
            return [d1 * d2, d2, 1]
        }
    }

    private static func extractChannel(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channelIndex: Int,
        plan: SamplingPlan
    ) -> [Double] {
        let strides = storageStrides(for: cube)
        let channelStride = strides[axes.channel]
        let heightStride = strides[axes.height]
        let widthStride = strides[axes.width]

        let base = channelIndex * channelStride
        var slice = [Double](repeating: 0.0, count: plan.outputWidth * plan.outputHeight)

        for outY in 0..<plan.outputHeight {
            let srcY = plan.yMap[outY]
            let rowBase = base + srcY * heightStride
            let dstRow = outY * plan.outputWidth

            for outX in 0..<plan.outputWidth {
                let srcX = plan.xMap[outX]
                let linearIndex = rowBase + srcX * widthStride
                slice[dstRow + outX] = cube.getValue(at: linearIndex)
            }
        }

        return slice
    }

    private static func extractChannelRangeAverage(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        range: RGBChannelRange,
        plan: SamplingPlan
    ) -> [Double] {
        let normalized = range.normalized
        let start = normalized.start
        let end = normalized.end
        let count = max(end - start + 1, 1)

        let strides = storageStrides(for: cube)
        let channelStride = strides[axes.channel]
        let heightStride = strides[axes.height]
        let widthStride = strides[axes.width]

        var slice = [Double](repeating: 0.0, count: plan.outputWidth * plan.outputHeight)

        for ch in start...end {
            let base = ch * channelStride
            for outY in 0..<plan.outputHeight {
                let srcY = plan.yMap[outY]
                let rowBase = base + srcY * heightStride
                let dstRow = outY * plan.outputWidth

                for outX in 0..<plan.outputWidth {
                    let srcX = plan.xMap[outX]
                    let linearIndex = rowBase + srcX * widthStride
                    slice[dstRow + outX] += cube.getValue(at: linearIndex)
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

    private static func normalizeToUInt8(_ data: [Double]) -> [UInt8] {
        guard !data.isEmpty else { return [] }

        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude

        for value in data {
            if value < minVal { minVal = value }
            if value > maxVal { maxVal = value }
        }

        let range = maxVal - minVal
        guard range > 0 else {
            return [UInt8](repeating: 0, count: data.count)
        }

        var output = [UInt8](repeating: 0, count: data.count)
        for i in 0..<data.count {
            let normalized = (data[i] - minVal) / range
            let clamped = max(0.0, min(1.0, normalized))
            output[i] = UInt8((clamped * 255.0).rounded())
        }
        return output
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

    private static func createGrayscaleImage(
        pixels: [UInt8],
        width: Int,
        height: Int,
        logicalSize: NSSize
    ) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width

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

        return NSImage(cgImage: cgImage, size: logicalSize)
    }

    private static func createRGBImage(
        r: [UInt8],
        g: [UInt8],
        b: [UInt8],
        width: Int,
        height: Int,
        logicalSize: NSSize
    ) -> NSImage? {
        let pixelCount = width * height
        guard r.count == pixelCount, g.count == pixelCount, b.count == pixelCount else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            let base = i * 4
            pixels[base] = r[i]
            pixels[base + 1] = g[i]
            pixels[base + 2] = b[i]
            pixels[base + 3] = 255
        }

        return createRGBAImage(rgba: pixels, width: width, height: height, logicalSize: logicalSize)
    }

    private static func createRGBAImage(
        rgba: [UInt8],
        width: Int,
        height: Int,
        logicalSize: NSSize
    ) -> NSImage? {
        let pixelCount = width * height
        guard rgba.count == pixelCount * 4 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else {
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

        return NSImage(cgImage: cgImage, size: logicalSize)
    }

    private static func render2DImage(cube: HyperCube, targetPixels: CGSize?) -> NSImage? {
        guard cube.is2D, let dims2D = cube.dims2D else { return nil }

        let sourceWidth = dims2D.width
        let sourceHeight = dims2D.height
        let plan = samplingPlan(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels
        )

        let (d0, d1, _) = cube.dims
        let axes2D: (channel: Int, height: Int, width: Int)
        if d0 == 1 {
            axes2D = (0, 1, 2)
        } else if d1 == 1 {
            axes2D = (1, 0, 2)
        } else {
            axes2D = (2, 0, 1)
        }

        let cacheKey = makeCacheKey([
            "2d",
            cube.id.uuidString,
            axes2D.channel,
            plan.outputWidth,
            plan.outputHeight
        ])
        if let cached = renderCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let slice = extractChannel(cube: cube, axes: axes2D, channelIndex: 0, plan: plan)
        let pixels = normalizeToUInt8(slice)

        guard let image = createGrayscaleImage(
            pixels: pixels,
            width: plan.outputWidth,
            height: plan.outputHeight,
            logicalSize: plan.logicalSize
        ) else {
            return nil
        }

        storeInCache(image: image, key: cacheKey, width: plan.outputWidth, height: plan.outputHeight)
        return image
    }
}
