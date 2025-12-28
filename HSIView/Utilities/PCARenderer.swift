import Foundation
import Accelerate
import AppKit

struct PCAImageResult {
    let image: NSImage?
    let updatedConfig: PCAVisualizationConfig
}

enum PCARenderError: Error {
    case invalidLayout
    case notEnoughChannels
}

final class PCARenderer {
    static func render(
        cube: HyperCube,
        layout: CubeLayout,
        config: PCAVisualizationConfig,
        roi: SpectrumROIRect? = nil,
        progress: ((String) -> Void)? = nil
    ) -> PCAImageResult {
        progress?("Сбор статистики…")
        guard let axes = cube.axes(for: layout) else {
            return PCAImageResult(image: nil, updatedConfig: config)
        }
        
        let dims = cube.dims
        let dimsArr = [dims.0, dims.1, dims.2]
        let channels = dimsArr[axes.channel]
        let fullHeight = dimsArr[axes.height]
        let fullWidth = dimsArr[axes.width]
        guard channels >= 1 else {
            return PCAImageResult(image: nil, updatedConfig: config)
        }
        
        let region: SpectrumROIRect = {
            if let roi {
                return roi
            }
            return SpectrumROIRect(minX: 0, minY: 0, width: fullWidth, height: fullHeight)
        }()
        
        let regionWidth = region.width
        let regionHeight = region.height
        guard regionWidth > 0, regionHeight > 0 else {
            return PCAImageResult(image: nil, updatedConfig: config)
        }
        
        let totalPixels = regionWidth * regionHeight
        if channels == 1 {
            // Одноканальный случай: просто нормализация в градации серого
            let slice = extractChannel(cube: cube, axes: axes, channelIndex: 0, region: region)
            let normalized = normalize(slice)
            let pixels = toUInt8(normalized)
            let image = createRGBImage(r: pixels, g: pixels, b: pixels, width: region.width, height: region.height)
            return PCAImageResult(image: image, updatedConfig: config)
        }
        
        // Проверяем, можем ли использовать зафиксированный базис
        if config.lockBasis,
           let basis = config.basis,
           basis.count >= 3,
           basis.first?.count == channels,
           let mean = config.mean,
           mean.count == channels {
            progress?("Используем сохранённый базис…")
            return projectWithExistingBasis(
                cube: cube,
                layoutAxes: axes,
                width: regionWidth,
                height: regionHeight,
                channels: channels,
                config: config,
                mean: mean,
                std: config.std ?? Array(repeating: 1.0, count: channels),
                basis: basis,
                region: region
            )
        }
        
        // Ограничиваем число пикселей для оценки ковариации, чтобы не перегружать CPU
        let maxSamples = 50_000
        let sampleStride = max(1, totalPixels / maxSamples)
        let statsStride = sampleStride
        
        // Первичный проход: собираем статистики (после выбранной предобработки)
        progress?("Оценка среднего и дисперсии…")
        var mean = Array(repeating: 0.0, count: channels)
        var m2 = Array(repeating: 0.0, count: channels)
        var sampleCount = 0
        var clipSamples: [[Double]] = Array(repeating: [], count: channels)
        let clipCapacity = min(maxSamples, max(10_000, channels * 100))
        clipSamples = clipSamples.map { _ in [] }
        
        for linear in stride(from: 0, to: totalPixels, by: statsStride) {
            let (hIdx, wIdx) = linearToHW(linear: linear, width: region.width)
            let srcY = region.minY + hIdx
            let srcX = region.minX + wIdx
            var vector = [Double](repeating: 0.0, count: channels)
            for c in 0..<channels {
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = c
                idx3[axes.height] = srcY
                idx3[axes.width] = srcX
                let idx = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                let raw = cube.getValue(at: idx)
                vector[c] = preprocessValue(raw, mode: config.preprocess)
            }
            
            sampleCount += 1
            // Welford для среднего и дисперсии
            for c in 0..<channels {
                let delta = vector[c] - mean[c]
                mean[c] += delta / Double(sampleCount)
                m2[c] += delta * (vector[c] - mean[c])
                if clipSamples[c].count < clipCapacity {
                    clipSamples[c].append(vector[c])
                }
            }
        }
        
        var std = Array(repeating: 1.0, count: channels)
        for c in 0..<channels {
            let variance = sampleCount > 1 ? m2[c] / Double(sampleCount - 1) : 0
            std[c] = variance > 1e-12 ? sqrt(variance) : 1.0
        }
        
        // Оценка порога отсечения выбросов
        var clipUpper: [Double] = Array(repeating: Double.greatestFiniteMagnitude, count: channels)
        if config.clipTopPercent > 0 {
            for c in 0..<channels {
                let values = clipSamples[c].sorted()
                if values.isEmpty { continue }
                let rank = Int(Double(values.count - 1) * (100.0 - config.clipTopPercent) / 100.0)
                clipUpper[c] = values[max(0, min(values.count - 1, rank))]
            }
        }
        
        // Строим ковариационную матрицу на подвыборке
        progress?("Расчёт ковариации…")
        var cov = Array(repeating: 0.0, count: channels * channels)
        var usedSamples = 0
        for linear in stride(from: 0, to: totalPixels, by: sampleStride) {
            let (hIdx, wIdx) = linearToHW(linear: linear, width: region.width)
            let srcY = region.minY + hIdx
            let srcX = region.minX + wIdx
            var centered = [Double](repeating: 0.0, count: channels)
            for c in 0..<channels {
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = c
                idx3[axes.height] = srcY
                idx3[axes.width] = srcX
                let idx = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                let raw = cube.getValue(at: idx)
                var val = preprocessValue(raw, mode: config.preprocess)
                val = min(val, clipUpper[c])
                val = (val - mean[c])
                if config.preprocess == .standardize {
                    val /= std[c]
                }
                centered[c] = val
            }
            usedSamples += 1
            
            for i in 0..<channels {
                let vi = centered[i]
                let rowBase = i * channels
                for j in i..<channels {
                    cov[rowBase + j] += vi * centered[j]
                }
            }
        }
        
        if usedSamples > 1 {
            let scale = 1.0 / Double(usedSamples - 1)
            for i in 0..<channels {
                for j in i..<channels {
                    cov[i * channels + j] *= scale
                    cov[j * channels + i] = cov[i * channels + j]
                }
            }
        }
        
        progress?("Собственные векторы…")
        let (basis, eigenValues) = topEigenVectors(fromCovariance: cov, channels: channels, components: 3)
        
        var updatedConfig = config
        updatedConfig.basis = basis
        updatedConfig.mean = mean
        updatedConfig.std = std
        updatedConfig.explainedVariance = eigenValues
        updatedConfig.sourceCubeID = cube.id
        updatedConfig.clipUpper = clipUpper
        
        progress?("Проекция и нормализация…")
        return projectWithExistingBasis(
            cube: cube,
            layoutAxes: axes,
            width: regionWidth,
            height: regionHeight,
            channels: channels,
            config: updatedConfig,
            mean: mean,
            std: std,
            basis: basis,
            region: region
        )
    }
    
    // MARK: - Projection
    
    private static func projectWithExistingBasis(
        cube: HyperCube,
        layoutAxes: (channel: Int, height: Int, width: Int),
        width: Int,
        height: Int,
        channels: Int,
        config: PCAVisualizationConfig,
        mean: [Double],
        std: [Double],
        basis: [[Double]],
        region: SpectrumROIRect
    ) -> PCAImageResult {
        let totalPixels = width * height
        let mapping = config.mapping
        let components = basis
        
        var pcMin = Array(repeating: Double.greatestFiniteMagnitude, count: components.count)
        var pcMax = Array(repeating: -Double.greatestFiniteMagnitude, count: components.count)
        
        var projections: [[Double]] = Array(repeating: [Double](repeating: 0.0, count: totalPixels), count: components.count)
        
        for linear in 0..<totalPixels {
            let (hIdx, wIdx) = linearToHW(linear: linear, width: region.width)
            let srcY = region.minY + hIdx
            let srcX = region.minX + wIdx
            var vector = [Double](repeating: 0.0, count: channels)
            for c in 0..<channels {
                var idx3 = [0, 0, 0]
                idx3[layoutAxes.channel] = c
                idx3[layoutAxes.height] = srcY
                idx3[layoutAxes.width] = srcX
                let idx = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                var val = cube.getValue(at: idx)
                val = preprocessValue(val, mode: config.preprocess)
                if let clip = config.clipUpper, clip.count > c {
                    val = min(val, clip[c])
                }
                val = val - mean[c]
                if config.preprocess == .standardize {
                    val /= std[c]
                }
                vector[c] = val
            }
            
            for compIndex in 0..<components.count {
                let dot = dotProduct(vector, components[compIndex])
                projections[compIndex][linear] = dot
                pcMin[compIndex] = min(pcMin[compIndex], dot)
                pcMax[compIndex] = max(pcMax[compIndex], dot)
            }
        }
        
        let mapped = mapping.clamped(maxComponents: components.count)
        let pixelsR = toUInt8(normalize(projections[mapped.red], minVal: pcMin[mapped.red], maxVal: pcMax[mapped.red]))
        let pixelsG = toUInt8(normalize(projections[mapped.green], minVal: pcMin[mapped.green], maxVal: pcMax[mapped.green]))
        let pixelsB = toUInt8(normalize(projections[mapped.blue], minVal: pcMin[mapped.blue], maxVal: pcMax[mapped.blue]))
        
        let image = createRGBImage(r: pixelsR, g: pixelsG, b: pixelsB, width: region.width, height: region.height)
        return PCAImageResult(image: image, updatedConfig: config)
    }
    
    // MARK: - Math helpers
    
    private static func preprocessValue(_ value: Double, mode: PCAPreprocess) -> Double {
        switch mode {
        case .none, .meanCenter, .standardize:
            return value
        case .log:
            return log(max(0, value) + 1.0)
        }
    }
    
    private static func linearToHW(linear: Int, width: Int) -> (Int, Int) {
        let h = linear / width
        let w = linear % width
        return (h, w)
    }
    
    private static func topEigenVectors(fromCovariance cov: [Double], channels: Int, components: Int) -> ([[Double]], [Double]) {
        guard channels > 0 else { return ([], []) }
        let comps = max(1, min(components, channels))
        var vectors: [[Double]] = []
        var eigenValues: [Double] = []
        
        for _ in 0..<comps {
            var v = randomUnitVector(length: channels)
            for _ in 0..<25 {
                // w = cov * v
                var w = [Double](repeating: 0.0, count: channels)
                for i in 0..<channels {
                    var sum = 0.0
                    let rowBase = i * channels
                    for j in 0..<channels {
                        sum += cov[rowBase + j] * v[j]
                    }
                    w[i] = sum
                }
                
                // ортогонализация к уже найденным векторам
                for prev in vectors {
                    let proj = dotProduct(w, prev)
                    for i in 0..<channels {
                        w[i] -= proj * prev[i]
                    }
                }
                
                let norm = sqrt(dotProduct(w, w))
                if norm > 1e-12 {
                    for i in 0..<channels { v[i] = w[i] / norm }
                }
            }
            
            // Собственное значение
            var lambda = 0.0
            for i in 0..<channels {
                var sum = 0.0
                let rowBase = i * channels
                for j in 0..<channels {
                    sum += cov[rowBase + j] * v[j]
                }
                lambda += v[i] * sum
            }
            
            vectors.append(v)
            eigenValues.append(lambda)
        }
        
        return (vectors, eigenValues)
    }
    
    private static func randomUnitVector(length: Int) -> [Double] {
        var v = (0..<length).map { _ in Double.random(in: -1...1) }
        let norm = sqrt(dotProduct(v, v))
        if norm > 1e-12 {
            for i in 0..<length { v[i] /= norm }
        }
        return v
    }
    
    private static func dotProduct(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        return zip(a, b).reduce(0.0) { partial, pair in
            partial + pair.0 * pair.1
        }
    }
    
    private static func extractChannel(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        channelIndex: Int,
        region: SpectrumROIRect
    ) -> [Double] {
        var slice = [Double](repeating: 0.0, count: region.width * region.height)
        
        for y in 0..<region.height {
            for x in 0..<region.width {
                let srcY = region.minY + y
                let srcX = region.minX + x
                var idx3 = [0, 0, 0]
                idx3[axes.channel] = channelIndex
                idx3[axes.height] = srcY
                idx3[axes.width] = srcX
                
                let lin = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                slice[y * region.width + x] = cube.getValue(at: lin)
            }
        }
        
        return slice
    }
    
    private static func normalize(_ data: [Double]) -> [Double] {
        guard !data.isEmpty else { return data }
        let minVal = data.min() ?? 0
        let maxVal = data.max() ?? 1
        return normalize(data, minVal: minVal, maxVal: maxVal)
    }
    
    private static func normalize(_ data: [Double], minVal: Double, maxVal: Double) -> [Double] {
        let range = maxVal - minVal
        guard range > 1e-10 else {
            return [Double](repeating: 0.5, count: data.count)
        }
        return data.map { ( $0 - minVal ) / range }
    }
    
    private static func toUInt8(_ data: [Double]) -> [UInt8] {
        return data.map { val in
            let clamped = max(0.0, min(1.0, val))
            return UInt8(clamping: Int((clamped * 255.0).rounded()))
        }
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
}
