import Foundation
import AppKit

class TiffExporter {
    static func export(cube: HyperCube, to url: URL, exportWavelengths: Bool) -> Result<Void, Error> {
        do {
            let dataType = cube.originalDataType
            
            if dataType != .uint8 && dataType != .uint16 {
                return .failure(ExportError.unsupportedDataType)
            }
            
            let result = exportTiffFile(cube: cube, url: url)
            
            if !result {
                return .failure(ExportError.writeError("Не удалось записать TIFF файл"))
            }
            
            if exportWavelengths, let wavelengths = cube.wavelengths, !wavelengths.isEmpty {
                let wavelengthsURL = url.deletingPathExtension().appendingPathExtension("wavelengths.txt")
                let wavelengthsText = wavelengths.map { String($0) }.joined(separator: "\n")
                try wavelengthsText.write(to: wavelengthsURL, atomically: true, encoding: .utf8)
            }
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    private static func exportTiffFile(cube: HyperCube, url: URL) -> Bool {
        let path = url.path
        let cPath = (path as NSString).utf8String
        
        let tiff = TIFFOpen(cPath, "w")
        guard let tiff = tiff else {
            return false
        }
        defer { TIFFClose(tiff) }
        
        let (height, width, channels) = cube.dims
        
        for channel in 0..<channels {
            TIFFSetField(tiff, UInt32(TIFFTAG_IMAGEWIDTH), UInt32(width))
            TIFFSetField(tiff, UInt32(TIFFTAG_IMAGELENGTH), UInt32(height))
            
            switch cube.originalDataType {
            case .uint8:
                TIFFSetField(tiff, UInt32(TIFFTAG_BITSPERSAMPLE), UInt16(8))
            case .uint16:
                TIFFSetField(tiff, UInt32(TIFFTAG_BITSPERSAMPLE), UInt16(16))
            default:
                return false
            }
            
            TIFFSetField(tiff, UInt32(TIFFTAG_SAMPLESPERPIXEL), UInt16(1))
            TIFFSetField(tiff, UInt32(TIFFTAG_PLANARCONFIG), UInt16(PLANARCONFIG_SEPARATE))
            TIFFSetField(tiff, UInt32(TIFFTAG_PHOTOMETRIC), UInt16(PHOTOMETRIC_MINISBLACK))
            TIFFSetField(tiff, UInt32(TIFFTAG_COMPRESSION), UInt16(COMPRESSION_NONE))
            TIFFSetField(tiff, UInt32(TIFFTAG_ORIENTATION), UInt16(ORIENTATION_TOPLEFT))
            
            let rowsPerStrip = height
            TIFFSetField(tiff, UInt32(TIFFTAG_ROWSPERSTRIP), UInt32(rowsPerStrip))
            
            let success = writeChannel(tiff: tiff, cube: cube, channel: channel, height: height, width: width)
            
            if !success {
                return false
            }
            
            if channel < channels - 1 {
                TIFFWriteDirectory(tiff)
            }
        }
        
        return true
    }
    
    private static func writeChannel(tiff: OpaquePointer, cube: HyperCube, channel: Int, height: Int, width: Int) -> Bool {
        let bytesPerPixel: Int
        
        switch cube.originalDataType {
        case .uint8:
            bytesPerPixel = 1
        case .uint16:
            bytesPerPixel = 2
        default:
            return false
        }
        
        let scanlineSize = width * bytesPerPixel
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: scanlineSize)
        defer { buffer.deallocate() }
        
        for row in 0..<height {
            for col in 0..<width {
                let idx: Int
                if cube.isFortranOrder {
                    idx = row + height * (col + width * channel)
                } else {
                    idx = channel + cube.dims.2 * (col + width * row)
                }
                
                switch cube.storage {
                case .uint8(let arr):
                    buffer[col] = arr[idx]
                    
                case .uint16(let arr):
                    let value = arr[idx]
                    let ptr = buffer.advanced(by: col * 2).withMemoryRebound(to: UInt16.self, capacity: 1) { $0 }
                    ptr.pointee = value
                    
                default:
                    return false
                }
            }
            
            if TIFFWriteScanline(tiff, buffer, UInt32(row), 0) < 0 {
                return false
            }
        }
        
        return true
    }
}

