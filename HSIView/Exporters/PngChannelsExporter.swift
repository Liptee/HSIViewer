import Foundation
import CoreGraphics
import ImageIO

class PngChannelsExporter {
    static func export(cube: HyperCube, to url: URL, wavelengths: [Double]?, layout: CubeLayout = .auto) -> Result<Void, Error> {
        print("PngChannelsExporter: Starting export to \(url.path)")
        print("PngChannelsExporter: Cube dims: \(cube.dims), dataType: \(cube.originalDataType), layout: \(layout)")
        
        guard let preparedCube = ensureExportableCube(cube) else {
            print("PngChannelsExporter: Failed to prepare cube for export")
            return .failure(ExportError.unsupportedDataType)
        }
        
        print("PngChannelsExporter: Cube prepared, storage type: \(type(of: preparedCube.storage))")
        
        do {
            try exportAsPNG(cube: preparedCube, to: url, layout: layout)
            print("PngChannelsExporter: Export completed successfully")
            
            if let wavelengths = wavelengths, !wavelengths.isEmpty {
                let baseName = url.deletingPathExtension().lastPathComponent
                let directory = url.deletingLastPathComponent()
                let wavelengthsURL = directory.appendingPathComponent("\(baseName)_wavelengths.txt")
                let wavelengthsText = wavelengths.map { String($0) }.joined(separator: "\n")
                try wavelengthsText.write(to: wavelengthsURL, atomically: true, encoding: .utf8)
            }
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Подготавливает куб к экспорту: если тип данных не UInt8/UInt16, выполняет масштабирование в UInt16.
    private static func ensureExportableCube(_ cube: HyperCube) -> HyperCube? {
        switch cube.originalDataType {
        case .uint8, .uint16:
            return cube
        default:
            return convertToUInt16(cube: cube)
        }
    }
    
    private static func convertToUInt16(cube: HyperCube) -> HyperCube? {
        let total = cube.totalElements
        guard total > 0 else { return nil }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        for idx in 0..<total {
            let value = cube.storage.getValue(at: idx)
            minVal = min(minVal, value)
            maxVal = max(maxVal, value)
        }
        
        guard maxVal > minVal else {
            let zeros = [UInt16](repeating: 0, count: total)
            return HyperCube(
                dims: cube.dims,
                storage: .uint16(zeros),
                sourceFormat: cube.sourceFormat + " [UInt16 PNG]",
                isFortranOrder: cube.isFortranOrder,
                wavelengths: cube.wavelengths
            )
        }
        
        let range = maxVal - minVal
        var scaled = [UInt16](repeating: 0, count: total)
        for idx in 0..<total {
            let value = cube.storage.getValue(at: idx)
            let normalized = (value - minVal) / range
            let scaledValue = UInt16(clamping: Int((normalized * 65535.0).rounded()))
            scaled[idx] = scaledValue
        }
        
        return HyperCube(
            dims: cube.dims,
            storage: .uint16(scaled),
            sourceFormat: cube.sourceFormat + " [UInt16 PNG]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func exportAsPNG(cube: HyperCube, to url: URL, layout: CubeLayout) throws {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: layout) else {
            print("PngChannelsExporter: Failed to get axes for layout \(layout)")
            throw ExportError.invalidData
        }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        print("PngChannelsExporter: Exporting \(channels) channels, size: \(width)x\(height)")
        print("PngChannelsExporter: Axes - width: \(axes.width), height: \(axes.height), channel: \(axes.channel)")
        
        var allImages: [Data] = []
        
        for channel in 0..<channels {
            var channelData: [UInt8] = []
            channelData.reserveCapacity(height * width)
            
            for row in 0..<height {
                for col in 0..<width {
                    var indices = [0, 0, 0]
                    indices[axes.channel] = channel
                    indices[axes.height] = row
                    indices[axes.width] = col
                    
                    let value: UInt8
                    switch cube.storage {
                    case .uint8(let arr):
                        let idx = cube.linearIndex(i0: indices[0], i1: indices[1], i2: indices[2])
                        value = arr[idx]
                    case .uint16(let arr):
                        let idx = cube.linearIndex(i0: indices[0], i1: indices[1], i2: indices[2])
                        value = UInt8(clamping: arr[idx] / 256)
                    default:
                        let val = cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
                        value = UInt8(clamping: Int(val.rounded()))
                    }
                    
                    channelData.append(value)
                }
            }
            
            guard let cgImage = createCGImage(data: channelData, width: width, height: height) else {
                throw ExportError.invalidData
            }
            
            guard let pngData = cgImageToPNG(cgImage) else {
                throw ExportError.writeError("Не удалось создать PNG")
            }
            
            allImages.append(pngData)
        }
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        
        print("PngChannelsExporter: Writing \(allImages.count) PNG files to \(directory.path)")
        print("PngChannelsExporter: Base name: \(baseName)")
        
        for (index, imageData) in allImages.enumerated() {
            let channelName = String(format: "%@_channel_%03d.png", baseName, index)
            let channelURL = directory.appendingPathComponent(channelName)
            try imageData.write(to: channelURL)
            print("PngChannelsExporter: Written channel \(index) to \(channelURL.lastPathComponent)")
        }
    }
    
    private static func createCGImage(data: [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            print("PngChannelsExporter: Failed to create CGDataProvider")
            return nil
        }
            
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            print("PngChannelsExporter: Failed to create CGImage")
            return nil
        }
        
        return cgImage
    }
    
    private static func cgImageToPNG(_ cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
}
