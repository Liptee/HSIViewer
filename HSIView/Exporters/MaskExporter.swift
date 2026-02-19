import Foundation
import AppKit

enum MaskExporter {
    static func exportAsPNG(
        mask: [UInt8],
        width: Int,
        height: Int,
        to url: URL,
        classColors: [(id: UInt8, color: NSColor)]? = nil
    ) -> Result<Void, Error> {
        guard width > 0, height > 0, mask.count == width * height else {
            return .failure(ExportError.invalidData)
        }
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let colorMap = buildColorMap(classColors: classColors)
        
        for i in 0..<mask.count {
            let classValue = mask[i]
            let rgba = colorMap[Int(classValue)] ?? (0, 0, 0, 0)
            let offset = i * 4
            pixelData[offset] = rgba.0
            pixelData[offset + 1] = rgba.1
            pixelData[offset + 2] = rgba.2
            pixelData[offset + 3] = rgba.3
        }
        
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return .failure(ExportError.writeError("Не удалось создать изображение"))
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure(ExportError.writeError("Не удалось конвертировать в PNG"))
        }
        
        do {
            try pngData.write(to: url)
            return .success(())
        } catch {
            return .failure(ExportError.writeError(error.localizedDescription))
        }
    }
    
    static func exportAsGrayscalePNG(
        mask: [UInt8],
        width: Int,
        height: Int,
        to url: URL
    ) -> Result<Void, Error> {
        guard width > 0, height > 0, mask.count == width * height else {
            return .failure(ExportError.invalidData)
        }
        
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return .failure(ExportError.writeError("Не удалось создать изображение"))
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure(ExportError.writeError("Не удалось конвертировать в PNG"))
        }
        
        do {
            try pngData.write(to: url)
            return .success(())
        } catch {
            return .failure(ExportError.writeError(error.localizedDescription))
        }
    }
    
    static func exportAsNumPy(
        mask: [UInt8],
        width: Int,
        height: Int,
        to url: URL
    ) -> Result<Void, Error> {
        guard width > 0, height > 0, mask.count == width * height else {
            return .failure(ExportError.invalidData)
        }
        
        var data = Data()
        
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]
        data.append(contentsOf: magic)
        
        data.append(0x01)
        data.append(0x00)
        
        let descr = "{'descr': '|u1', 'fortran_order': False, 'shape': (\(height), \(width)), }"
        var header = descr
        let alignment = 64
        let baseLen = magic.count + 2 + 2 + header.count + 1
        let padding = (alignment - (baseLen % alignment)) % alignment
        header += String(repeating: " ", count: padding) + "\n"
        
        var headerLen = UInt16(header.count).littleEndian
        data.append(Data(bytes: &headerLen, count: 2))
        data.append(header.data(using: .ascii)!)
        
        data.append(contentsOf: mask)
        
        do {
            try data.write(to: url)
            return .success(())
        } catch {
            return .failure(ExportError.writeError(error.localizedDescription))
        }
    }
    
    static func exportAsMAT(
        mask: [UInt8],
        width: Int,
        height: Int,
        to url: URL,
        maskVariableName: String,
        metadata: [MaskClassMetadata]?,
        hypercube: HyperCube? = nil,
        hypercubeVariableName: String? = nil
    ) -> Result<Void, Error> {
        guard width > 0, height > 0, mask.count == width * height else {
            return .failure(ExportError.invalidData)
        }
        
        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            let fileHandle = try FileHandle(forWritingTo: url)
            defer { try? fileHandle.close() }
            try fileHandle.truncate(atOffset: 0)
            try fileHandle.seek(toOffset: 0)
            
            var header = [UInt8](repeating: 0x20, count: 116)
            let headerText = "MATLAB 5.0 MAT-file, Platform: macOS, Created by HSIView"
            let headerBytes = Array(headerText.utf8)
            for (i, byte) in headerBytes.prefix(116).enumerated() {
                header[i] = byte
            }
            
            fileHandle.write(Data(header))
            
            let subsys = [UInt8](repeating: 0, count: 8)
            fileHandle.write(Data(subsys))
            
            var version: UInt16 = 0x0100
            fileHandle.write(Data(bytes: &version, count: 2))
            
            var endian: UInt16 = 0x4D49
            fileHandle.write(Data(bytes: &endian, count: 2))
            
            writeMaskArray(to: fileHandle, name: maskVariableName, mask: mask, width: width, height: height)
            
            if let metadata = metadata, !metadata.isEmpty {
                writeMetadataStruct(to: fileHandle, name: "mask_classes", metadata: metadata)
            }
            
            return .success(())
        } catch {
            return .failure(ExportError.writeError(error.localizedDescription))
        }
    }
    
    private static func buildColorMap(classColors: [(id: UInt8, color: NSColor)]?) -> [Int: (UInt8, UInt8, UInt8, UInt8)] {
        var map: [Int: (UInt8, UInt8, UInt8, UInt8)] = [0: (0, 0, 0, 0)]
        
        if let colors = classColors {
            for item in colors {
                let rgb = item.color.usingColorSpace(.sRGB) ?? item.color
                let r = UInt8(rgb.redComponent * 255)
                let g = UInt8(rgb.greenComponent * 255)
                let b = UInt8(rgb.blueComponent * 255)
                map[Int(item.id)] = (r, g, b, 255)
            }
        } else {
            let defaultPalette: [(UInt8, UInt8, UInt8)] = [
                (255, 50, 50),
                (50, 200, 50),
                (50, 100, 255),
                (255, 200, 0),
                (200, 50, 200),
                (0, 200, 200),
                (255, 128, 0),
                (150, 100, 50)
            ]
            for (idx, color) in defaultPalette.enumerated() {
                map[idx + 1] = (color.0, color.1, color.2, 255)
            }
        }
        
        return map
    }
    
    private static func writeMaskArray(to file: FileHandle, name: String, mask: [UInt8], width: Int, height: Int) {
        var dataType: UInt32 = 14
        file.write(Data(bytes: &dataType, count: 4))
        
        let numElements = width * height
        let matOrderedMask = reorderRowMajorToColumnMajor(mask, width: width, height: height)
        let nameBytes = Array(name.utf8)
        let namePadding = (8 - (nameBytes.count % 8)) % 8
        let dataPadding = (8 - (numElements % 8)) % 8
        
        // MI_MATRIX payload size (without outer 8-byte tag):
        // flags(16) + dims(16) + nameTagAndData(8 + name + pad) + dataTagAndData(8 + data + pad)
        var totalSize: UInt32 = UInt32(48 + nameBytes.count + namePadding + numElements + dataPadding)
        file.write(Data(bytes: &totalSize, count: 4))
        
        var flags: [UInt32] = [6, 8, 0x00FF0008, 0]
        file.write(Data(bytes: &flags, count: 16))
        
        var dims: [UInt32] = [5, 8, UInt32(height), UInt32(width)]
        file.write(Data(bytes: &dims, count: 16))
        
        var nameTag: UInt32 = 1
        var nameLen: UInt32 = UInt32(nameBytes.count)
        file.write(Data(bytes: &nameTag, count: 4))
        file.write(Data(bytes: &nameLen, count: 4))
        file.write(Data(nameBytes))
        if namePadding > 0 {
            file.write(Data(repeating: 0, count: namePadding))
        }
        
        var dataTag: UInt32 = 2
        var dataLen: UInt32 = UInt32(numElements)
        file.write(Data(bytes: &dataTag, count: 4))
        file.write(Data(bytes: &dataLen, count: 4))
        file.write(Data(matOrderedMask))
        if dataPadding > 0 {
            file.write(Data(repeating: 0, count: dataPadding))
        }
    }

    private static func reorderRowMajorToColumnMajor(_ values: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, values.count == width * height else { return values }

        var reordered = [UInt8](repeating: 0, count: values.count)
        for y in 0..<height {
            let rowOffset = y * width
            for x in 0..<width {
                let rowMajorIndex = rowOffset + x
                let columnMajorIndex = y + height * x
                reordered[columnMajorIndex] = values[rowMajorIndex]
            }
        }
        return reordered
    }
    
    private static func writeMetadataStruct(to file: FileHandle, name: String, metadata: [MaskClassMetadata]) {
        guard let jsonData = try? JSONEncoder().encode(metadata),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        var dataType: UInt32 = 14
        file.write(Data(bytes: &dataType, count: 4))
        
        let nameBytes = Array(name.utf8)
        let namePadding = (8 - (nameBytes.count % 8)) % 8
        let jsonBytes = Array(jsonString.utf8)
        let jsonPadding = (8 - (jsonBytes.count % 8)) % 8
        
        // Same MI_MATRIX payload layout as above.
        var totalSize: UInt32 = UInt32(48 + nameBytes.count + namePadding + jsonBytes.count + jsonPadding)
        file.write(Data(bytes: &totalSize, count: 4))
        
        // Store metadata as a numeric uint8 vector with UTF-8 JSON bytes.
        var flags: [UInt32] = [6, 8, 0x00FF0009, 0]
        file.write(Data(bytes: &flags, count: 16))
        
        var dims: [UInt32] = [5, 8, 1, UInt32(jsonBytes.count)]
        file.write(Data(bytes: &dims, count: 16))
        
        var nameTag: UInt32 = 1
        var nameLen: UInt32 = UInt32(nameBytes.count)
        file.write(Data(bytes: &nameTag, count: 4))
        file.write(Data(bytes: &nameLen, count: 4))
        file.write(Data(nameBytes))
        if namePadding > 0 {
            file.write(Data(repeating: 0, count: namePadding))
        }
        
        var dataTag: UInt32 = 2
        var dataLen: UInt32 = UInt32(jsonBytes.count)
        file.write(Data(bytes: &dataTag, count: 4))
        file.write(Data(bytes: &dataLen, count: 4))
        file.write(Data(jsonBytes))
        if jsonPadding > 0 {
            file.write(Data(repeating: 0, count: jsonPadding))
        }
    }
}
