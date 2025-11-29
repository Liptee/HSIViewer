import Foundation
import CoreGraphics
import ImageIO

class TiffExporter {
    static func export(cube: HyperCube, to url: URL, wavelengths: [Double]?) -> Result<Void, Error> {
        if cube.originalDataType != .uint8 && cube.originalDataType != .uint16 {
            return .failure(ExportError.unsupportedDataType)
        }
        
        do {
            try exportAsPNG(cube: cube, to: url)
            
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
    
    private static func exportAsPNG(cube: HyperCube, to url: URL) throws {
        let (height, width, channels) = cube.dims
        
        var allImages: [Data] = []
        
        for channel in 0..<channels {
            var channelData: [UInt8] = []
            channelData.reserveCapacity(height * width)
            
            for row in 0..<height {
                for col in 0..<width {
                    let idx: Int
                    if cube.isFortranOrder {
                        idx = row + height * (col + width * channel)
                    } else {
                        idx = channel + channels * (col + width * row)
                    }
                    
                    let value: UInt8
                    switch cube.storage {
                    case .uint8(let arr):
                        value = arr[idx]
                    case .uint16(let arr):
                        value = UInt8(clamping: arr[idx] / 256)
                    default:
                        value = 0
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
        
        for (index, imageData) in allImages.enumerated() {
            let channelName = String(format: "%@_channel_%03d.png", baseName, index)
            let channelURL = directory.appendingPathComponent(channelName)
            try imageData.write(to: channelURL)
        }
    }
    
    private static func createCGImage(data: [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        return data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }
            
            context.data?.copyMemory(from: baseAddress, byteCount: data.count)
            
            return context.makeImage()
        }
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

