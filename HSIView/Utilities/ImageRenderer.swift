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
        wavelengths: [Double]
    ) -> NSImage? {
        if cube.is2D {
            return render2DImage(cube: cube)
        }
        
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        
        let cCount = dimsArr[axes.channel]
        guard wavelengths.count >= cCount else { return nil }
        
        let h = dimsArr[axes.height]
        let w = dimsArr[axes.width]
        
        let targetR = 630.0
        let targetG = 530.0
        let targetB = 450.0
        
        let idxR = closestIndex(in: wavelengths, to: targetR, count: cCount)
        let idxG = closestIndex(in: wavelengths, to: targetG, count: cCount)
        let idxB = closestIndex(in: wavelengths, to: targetB, count: cCount)
        
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
    
    private static func closestIndex(in wavelengths: [Double], to target: Double, count: Int) -> Int {
        var bestIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        
        for i in 0..<count {
            let d = abs(wavelengths[i] - target)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        
        return bestIdx
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


