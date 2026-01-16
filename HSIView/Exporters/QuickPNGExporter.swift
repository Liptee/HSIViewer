import Foundation
import AppKit
import CoreGraphics
import ImageIO

class QuickPNGExporter {
    static func export(
        cube: HyperCube,
        to url: URL,
        layout: CubeLayout,
        wavelengths: [Double]?,
        config: ColorSynthesisConfig
    ) -> Result<Void, Error> {
        guard let image = renderImage(cube: cube, layout: layout, wavelengths: wavelengths, config: config) else {
            return .failure(ExportError.invalidData)
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure(ExportError.writeError("Не удалось создать PNG данные"))
        }
        
        do {
            try pngData.write(to: url)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    private static func renderImage(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        config: ColorSynthesisConfig
    ) -> NSImage? {
        switch config.mode {
        case .trueColorRGB:
            return renderTrueColorRGB(
                cube: cube,
                layout: layout,
                wavelengths: wavelengths,
                mapping: config.mapping
            )
        case .pcaVisualization:
            let result = PCARenderer.render(
                cube: cube,
                layout: layout,
                config: config.pcaConfig
            )
            return result.image
        }
    }
    
    private static func renderTrueColorRGB(
        cube: HyperCube,
        layout: CubeLayout,
        wavelengths: [Double]?,
        mapping: RGBChannelMapping
    ) -> NSImage? {
        _ = wavelengths
        guard let axes = cube.axes(for: layout) else { return nil }
        
        let (d0, d1, d2) = cube.dims
        let dimsArr = [d0, d1, d2]
        
        let channels = dimsArr[axes.channel]
        guard channels > 0 else { return nil }
        let height = dimsArr[axes.height]
        let width = dimsArr[axes.width]
        
        let clamped = mapping.clamped(maxChannelCount: channels)
        let idxR = clamped.red
        let idxG = clamped.green
        let idxB = clamped.blue
        
        let sliceR = extractChannel(cube: cube, axes: axes, channelIndex: idxR, h: height, w: width)
        let sliceG = extractChannel(cube: cube, axes: axes, channelIndex: idxG, h: height, w: width)
        let sliceB = extractChannel(cube: cube, axes: axes, channelIndex: idxB, h: height, w: width)
        
        let normR = normalize(sliceR)
        let normG = normalize(sliceG)
        let normB = normalize(sliceB)
        
        let pixelsR = toUInt8(normR)
        let pixelsG = toUInt8(normG)
        let pixelsB = toUInt8(normB)
        
        return createRGBImage(r: pixelsR, g: pixelsG, b: pixelsB, width: width, height: height)
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
    
    private static func normalize(_ data: [Double]) -> [Double] {
        guard !data.isEmpty else { return data }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        
        for value in data {
            if value < minVal { minVal = value }
            if value > maxVal { maxVal = value }
        }
        
        let range = maxVal - minVal
        guard range > 1e-10 else {
            return [Double](repeating: 0.5, count: data.count)
        }
        
        return data.map { ($0 - minVal) / range }
    }
    
    private static func toUInt8(_ data: [Double]) -> [UInt8] {
        return data.map { UInt8(clamping: Int($0 * 255.0)) }
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
















