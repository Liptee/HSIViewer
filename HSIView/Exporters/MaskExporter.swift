import Foundation
import AppKit

struct MaskMetadataJSONDocument: Codable {
    let version: Int
    let classes: [MaskClassMetadata]
}

struct MaskMATMetadataKeySet: Equatable {
    static let defaultPrefix = "mask_classes"

    let prefix: String
    var idsKey: String { "\(prefix)_ids" }
    var namesKey: String { "\(prefix)_names" }
    var colorsKey: String { "\(prefix)_colors" }

    init(prefix: String) {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefix = trimmed.isEmpty ? Self.defaultPrefix : trimmed
    }
}

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

    static func exportMetadataAsJSON(
        metadata: [MaskClassMetadata],
        to url: URL
    ) -> Result<Void, Error> {
        let normalized = normalizedMetadata(metadata)
        guard !normalized.isEmpty else {
            return .failure(ExportError.invalidData)
        }

        do {
            let document = MaskMetadataJSONDocument(version: 1, classes: normalized)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
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
        metadataKeys: MaskMATMetadataKeySet = MaskMATMetadataKeySet(prefix: MaskMATMetadataKeySet.defaultPrefix),
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

            writeMATHeader(to: fileHandle)
            writeMaskArray(to: fileHandle, name: maskVariableName, mask: mask, width: width, height: height)

            if let metadata, !metadata.isEmpty {
                let normalized = normalizedMetadata(metadata)
                if !normalized.isEmpty {
                    writeMetadataJSONVariable(to: fileHandle, name: metadataKeys.prefix, metadata: normalized)
                    writeMetadataIDsVariable(to: fileHandle, name: metadataKeys.idsKey, metadata: normalized)
                    writeMetadataNamesVariable(to: fileHandle, name: metadataKeys.namesKey, metadata: normalized)
                    writeMetadataColorsVariable(to: fileHandle, name: metadataKeys.colorsKey, metadata: normalized)
                }
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

    private static func normalizedMetadata(_ metadata: [MaskClassMetadata]) -> [MaskClassMetadata] {
        var byID: [Int: MaskClassMetadata] = [:]
        for item in metadata {
            guard item.id > 0 && item.id <= 255 else { continue }
            byID[item.id] = item.clamped()
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private static func writeMATHeader(to file: FileHandle) {
        var header = [UInt8](repeating: 0x20, count: 116)
        let headerText = "MATLAB 5.0 MAT-file, Platform: macOS, Created by HSIView"
        let headerBytes = Array(headerText.utf8)
        for (i, byte) in headerBytes.prefix(116).enumerated() {
            header[i] = byte
        }

        file.write(Data(header))
        file.write(Data(repeating: 0, count: 8))

        var version: UInt16 = 0x0100
        file.write(Data(bytes: &version, count: 2))

        var endian: UInt16 = 0x4D49
        file.write(Data(bytes: &endian, count: 2))
    }

    private static func writeMaskArray(to file: FileHandle, name: String, mask: [UInt8], width: Int, height: Int) {
        let matOrderedMask = reorderRowMajorToColumnMajor(mask, width: width, height: height)
        writeMatrixElement(
            to: file,
            name: name,
            rows: height,
            cols: width,
            arrayClass: 9,
            dataTypeTag: 2,
            payload: Data(matOrderedMask)
        )
    }

    private static func writeMetadataJSONVariable(to file: FileHandle, name: String, metadata: [MaskClassMetadata]) {
        guard let payload = metadataJSONBytes(from: MaskMetadataJSONDocument(version: 1, classes: metadata)) else { return }
        writeMatrixElement(
            to: file,
            name: name,
            rows: 1,
            cols: payload.count,
            arrayClass: 9,
            dataTypeTag: 2,
            payload: payload
        )
    }

    private static func writeMetadataIDsVariable(to file: FileHandle, name: String, metadata: [MaskClassMetadata]) {
        let values = metadata.map { UInt16($0.id) }
        writeMatrixElement(
            to: file,
            name: name,
            rows: 1,
            cols: values.count,
            arrayClass: 11,
            dataTypeTag: 4,
            payload: uint16Data(values)
        )
    }

    private static func writeMetadataNamesVariable(to file: FileHandle, name: String, metadata: [MaskClassMetadata]) {
        let names = metadata.map(\.name)
        guard let payload = metadataJSONBytes(from: names) else { return }
        writeMatrixElement(
            to: file,
            name: name,
            rows: 1,
            cols: payload.count,
            arrayClass: 9,
            dataTypeTag: 2,
            payload: payload
        )
    }

    private static func writeMetadataColorsVariable(to file: FileHandle, name: String, metadata: [MaskClassMetadata]) {
        var rowMajor = [Double]()
        rowMajor.reserveCapacity(metadata.count * 3)
        for item in metadata {
            rowMajor.append(item.colorR)
            rowMajor.append(item.colorG)
            rowMajor.append(item.colorB)
        }

        let columnMajor = reorderRowMajorToColumnMajor(rowMajor, rows: metadata.count, cols: 3)
        writeMatrixElement(
            to: file,
            name: name,
            rows: metadata.count,
            cols: 3,
            arrayClass: 6,
            dataTypeTag: 9,
            payload: doubleData(columnMajor)
        )
    }

    private static func metadataJSONBytes<T: Encodable>(from value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    private static func writeMatrixElement(
        to file: FileHandle,
        name: String,
        rows: Int,
        cols: Int,
        arrayClass: UInt32,
        dataTypeTag: UInt32,
        payload: Data
    ) {
        guard rows > 0, cols > 0 else { return }
        guard let rowsU32 = UInt32(exactly: rows),
              let colsU32 = UInt32(exactly: cols),
              let payloadLenU32 = UInt32(exactly: payload.count) else { return }

        var miMatrix: UInt32 = 14
        file.write(Data(bytes: &miMatrix, count: 4))

        let nameBytes = Array(name.utf8)
        let namePadding = (8 - (nameBytes.count % 8)) % 8
        let dataPadding = (8 - (payload.count % 8)) % 8
        let totalPayload = 48 + nameBytes.count + namePadding + payload.count + dataPadding
        guard let totalPayloadU32 = UInt32(exactly: totalPayload) else { return }
        var totalSize = totalPayloadU32
        file.write(Data(bytes: &totalSize, count: 4))

        var flags: [UInt32] = [6, 8, 0x00FF0000 | arrayClass, 0]
        file.write(Data(bytes: &flags, count: 16))

        var dims: [UInt32] = [5, 8, rowsU32, colsU32]
        file.write(Data(bytes: &dims, count: 16))

        var nameTag: UInt32 = 1
        var nameLen: UInt32 = UInt32(nameBytes.count)
        file.write(Data(bytes: &nameTag, count: 4))
        file.write(Data(bytes: &nameLen, count: 4))
        file.write(Data(nameBytes))
        if namePadding > 0 {
            file.write(Data(repeating: 0, count: namePadding))
        }

        var dataTag = dataTypeTag
        var dataLen = payloadLenU32
        file.write(Data(bytes: &dataTag, count: 4))
        file.write(Data(bytes: &dataLen, count: 4))
        file.write(payload)
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

    private static func reorderRowMajorToColumnMajor(_ values: [Double], rows: Int, cols: Int) -> [Double] {
        guard rows > 0, cols > 0, values.count == rows * cols else { return values }

        var reordered = [Double](repeating: 0, count: values.count)
        for row in 0..<rows {
            let rowOffset = row * cols
            for col in 0..<cols {
                let rowMajorIndex = rowOffset + col
                let columnMajorIndex = row + rows * col
                reordered[columnMajorIndex] = values[rowMajorIndex]
            }
        }
        return reordered
    }

    private static func uint16Data(_ values: [UInt16]) -> Data {
        var result = Data(capacity: values.count * MemoryLayout<UInt16>.size)
        for var value in values.map(\.littleEndian) {
            result.append(Data(bytes: &value, count: MemoryLayout<UInt16>.size))
        }
        return result
    }

    private static func doubleData(_ values: [Double]) -> Data {
        var result = Data(capacity: values.count * MemoryLayout<Double>.size)
        for var value in values {
            result.append(Data(bytes: &value, count: MemoryLayout<Double>.size))
        }
        return result
    }
}
