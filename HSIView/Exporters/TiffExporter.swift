import Foundation
import CoreGraphics
import ImageIO

class TiffExporter {
    static func export(cube: HyperCube, to url: URL, wavelengths: [Double]?, layout: CubeLayout = .auto, enviCompatible: Bool = false) -> Result<Void, Error> {
        print("TiffExporter: Starting export to \(url.path)")
        print("TiffExporter: Cube dims: \(cube.dims), dataType: \(cube.originalDataType), layout: \(layout)")
        
        guard let preparedCube = ensureExportableCube(cube) else {
            print("TiffExporter: Failed to prepare cube for export")
            return .failure(ExportError.unsupportedDataType)
        }
        
        print("TiffExporter: Cube prepared, storage type: \(type(of: preparedCube.storage))")
        
        do {
            if enviCompatible {
                try exportAsENVICompatibleTIFF(cube: preparedCube, to: url, layout: layout)
            } else {
                try exportAsTIFF(cube: preparedCube, to: url, layout: layout)
            }
            print("TiffExporter: Export completed successfully")
            
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
                sourceFormat: cube.sourceFormat + " [UInt16 TIFF]",
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
            sourceFormat: cube.sourceFormat + " [UInt16 TIFF]",
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths
        )
    }
    
    private static func exportAsTIFF(cube: HyperCube, to url: URL, layout: CubeLayout) throws {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: layout) else {
            print("TiffExporter: Failed to get axes for layout \(layout)")
            throw ExportError.invalidData
        }
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        print("TiffExporter: Exporting \(channels) channels, size: \(width)x\(height)")
        print("TiffExporter: Axes - width: \(axes.width), height: \(axes.height), channel: \(axes.channel)")
        
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.tiff" as CFString,
            channels,
            nil
        ) else {
            throw ExportError.writeError("Не удалось создать TIFF")
        }
        
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
            
            CGImageDestinationAddImage(destination, cgImage, nil)
        }
        
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.writeError("Не удалось записать TIFF")
        }
    }

    private static func exportAsENVICompatibleTIFF(cube: HyperCube, to url: URL, layout: CubeLayout) throws {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        guard let axes = cube.axes(for: layout) else {
            print("TiffExporter: Failed to get axes for layout \(layout)")
            throw ExportError.invalidData
        }
        
        let width = dimsArray[axes.width]
        let height = dimsArray[axes.height]
        let channels = dimsArray[axes.channel]
        
        print("TiffExporter: ENVI export \(channels) channels, size: \(width)x\(height)")
        
        func linearIndex(channel: Int, row: Int, col: Int) -> Int {
            var i0 = 0
            var i1 = 0
            var i2 = 0
            
            switch axes.channel {
            case 0: i0 = channel
            case 1: i1 = channel
            default: i2 = channel
            }
            
            switch axes.height {
            case 0: i0 = row
            case 1: i1 = row
            default: i2 = row
            }
            
            switch axes.width {
            case 0: i0 = col
            case 1: i1 = col
            default: i2 = col
            }
            
            return cube.linearIndex(i0: i0, i1: i1, i2: i2)
        }
        
        switch cube.storage {
        case .uint8(let arr):
            var interleaved = [UInt8](repeating: 0, count: width * height * channels)
            for row in 0..<height {
                for col in 0..<width {
                    let base = (row * width + col) * channels
                    for channel in 0..<channels {
                        let idx = linearIndex(channel: channel, row: row, col: col)
                        interleaved[base + channel] = arr[idx]
                    }
                }
            }
            
            let ok = interleaved.withUnsafeBytes { rawBuffer -> Bool in
                guard let baseAddress = rawBuffer.baseAddress else { return false }
                return write_tiff_cube_contig(
                    url.path,
                    baseAddress,
                    width,
                    height,
                    channels,
                    Int32(8)
                )
            }
            
            if !ok {
                throw ExportError.writeError("Не удалось записать TIFF (ENVI)")
            }
        case .uint16(let arr):
            var interleaved = [UInt16](repeating: 0, count: width * height * channels)
            for row in 0..<height {
                for col in 0..<width {
                    let base = (row * width + col) * channels
                    for channel in 0..<channels {
                        let idx = linearIndex(channel: channel, row: row, col: col)
                        interleaved[base + channel] = arr[idx]
                    }
                }
            }
            
            let ok = interleaved.withUnsafeBytes { rawBuffer -> Bool in
                guard let baseAddress = rawBuffer.baseAddress else { return false }
                return write_tiff_cube_contig(
                    url.path,
                    baseAddress,
                    width,
                    height,
                    channels,
                    Int32(16)
                )
            }
            
            if !ok {
                throw ExportError.writeError("Не удалось записать TIFF (ENVI)")
            }
        default:
            throw ExportError.unsupportedDataType
        }
    }
    
    private static func createCGImage(data: [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            print("TiffExporter: Failed to create CGDataProvider")
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
            print("TiffExporter: Failed to create CGImage")
            return nil
        }
        
        return cgImage
    }
    
}
