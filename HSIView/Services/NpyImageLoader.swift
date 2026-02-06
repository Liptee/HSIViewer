import Foundation

class NpyImageLoader: ImageLoader {
    static let supportedExtensions = ["npy"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.fileNotFound)
        }
        
        guard let header = parseNpyHeader(data: data) else {
            return .failure(.corruptedData)
        }
        
        guard header.shape.count == 3 || (header.shape.count == 2) else {
            return .failure(.notA3DCube)
        }
        
        guard let storage = parseNpyData(data: data, header: header) else {
            return .failure(.corruptedData)
        }
        
        let dims: (Int, Int, Int)
        if header.shape.count == 2 {
            dims = (header.shape[0], header.shape[1], 1)
        } else {
            dims = (header.shape[0], header.shape[1], header.shape[2])
        }

        let channelCount = header.shape.count == 2 ? 1 : dims.2
        let wavelengths = loadWavelengths(for: url, expectedCount: channelCount)
        
        // Передаем флаг Fortran-order для правильной индексации
        return .success(HyperCube(
            dims: dims,
            storage: storage,
            sourceFormat: "NumPy (.npy)",
            isFortranOrder: header.fortranOrder,
            wavelengths: wavelengths
        ))
    }
    
    private struct NpyHeader {
        let dtype: String
        let shape: [Int]
        let fortranOrder: Bool
        let headerLength: Int
        let dataOffset: Int
    }
    
    private static func parseNpyHeader(data: Data) -> NpyHeader? {
        guard data.count >= 10 else { return nil }
        
        let magic = data[0..<6]
        guard magic == Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]) else {
            return nil
        }
        
        let majorVersion = data[6]
        let minorVersion = data[7]
        
        guard majorVersion >= 1 && majorVersion <= 3 else {
            return nil
        }
        
        var headerLen: Int
        var headerStart: Int
        
        if majorVersion == 1 {
            headerLen = Int(data[8]) | (Int(data[9]) << 8)
            headerStart = 10
        } else {
            guard data.count >= 12 else { return nil }
            headerLen = Int(data[8]) | (Int(data[9]) << 8) |
                       (Int(data[10]) << 16) | (Int(data[11]) << 24)
            headerStart = 12
        }
        
        let headerEnd = headerStart + headerLen
        guard data.count >= headerEnd else { return nil }
        
        let headerBytes = data[headerStart..<headerEnd]
        guard let headerString = String(data: headerBytes, encoding: .utf8) else {
            return nil
        }
        
        guard let shape = extractShape(from: headerString),
              let dtype = extractDtype(from: headerString) else {
            return nil
        }
        
        let fortranOrder = extractFortranOrder(from: headerString)
        
        return NpyHeader(
            dtype: dtype,
            shape: shape,
            fortranOrder: fortranOrder,
            headerLength: headerLen,
            dataOffset: headerEnd
        )
    }
    
    private static func extractShape(from header: String) -> [Int]? {
        guard let shapeStart = header.range(of: "'shape'"),
              let colonIdx = header.range(of: ":", range: shapeStart.upperBound..<header.endIndex),
              let openParen = header.range(of: "(", range: colonIdx.upperBound..<header.endIndex) else {
            return nil
        }
        
        var closeParen = openParen.upperBound
        var depth = 1
        
        while closeParen < header.endIndex && depth > 0 {
            let char = header[closeParen]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
            }
            closeParen = header.index(after: closeParen)
        }
        
        guard depth == 0 else { return nil }
        
        let tupleContent = String(header[header.index(after: openParen.lowerBound)..<header.index(before: closeParen)])
        let components = tupleContent.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        var shape: [Int] = []
        for comp in components {
            let cleaned = comp.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            if let num = Int(cleaned), num > 0 {
                shape.append(num)
            }
        }
        
        return shape.isEmpty ? nil : shape
    }
    
    private static func extractDtype(from header: String) -> String? {
        guard let descrStart = header.range(of: "'descr'"),
              let colonIdx = header.range(of: ":", range: descrStart.upperBound..<header.endIndex),
              let firstQuote = header.range(of: "'", range: colonIdx.upperBound..<header.endIndex) else {
            return nil
        }
        
        guard let secondQuote = header.range(of: "'", range: firstQuote.upperBound..<header.endIndex) else {
            return nil
        }
        
        let dtype = String(header[firstQuote.upperBound..<secondQuote.lowerBound])
        return dtype.isEmpty ? nil : dtype
    }
    
    private static func extractFortranOrder(from header: String) -> Bool {
        return header.contains("'fortran_order': True")
    }
    
    private static func parseNpyData(data: Data, header: NpyHeader) -> DataStorage? {
        let dataStart = header.dataOffset
        guard data.count > dataStart else { return nil }
        
        let totalElements = header.shape.reduce(1, *)
        let dataBytes = Data(data[dataStart...])
        
        let dtype = header.dtype.trimmingCharacters(in: .whitespaces)
        
        // Возвращаем DataStorage в оригинальном типе (экономия памяти!)
        if dtype.hasSuffix("f8") || dtype.hasSuffix("f64") {
            guard dataBytes.count >= totalElements * 8 else { return nil }
            
            var values = [Double]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Double.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .float64(values)
            
        } else if dtype.hasSuffix("f4") || dtype.hasSuffix("f32") {
            guard dataBytes.count >= totalElements * 4 else { return nil }
            
            var values = [Float]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Float.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .float32(values)
        } else if dtype.hasSuffix("i8") {
            guard dataBytes.count >= totalElements * 8 else { return nil }
            
            var values = [Int32]()  // Используем Int32 вместо Int64 для экономии
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int64.self)
                for i in 0..<totalElements {
                    values.append(Int32(clamping: buffer[i]))
                }
            }
            return .int32(values)
            
        } else if dtype.hasSuffix("i4") {
            guard dataBytes.count >= totalElements * 4 else { return nil }
            
            var values = [Int32]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int32.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .int32(values)
            
        } else if dtype.hasSuffix("i2") {
            guard dataBytes.count >= totalElements * 2 else { return nil }
            
            var values = [Int16]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int16.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .int16(values)
            
        } else if dtype.hasSuffix("i1") {
            guard dataBytes.count >= totalElements else { return nil }
            
            var values = [Int8]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int8.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .int8(values)
            
        } else if dtype.hasSuffix("u1") {
            guard dataBytes.count >= totalElements else { return nil }
            
            var values = [UInt8]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt8.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .uint8(values)
            
        } else if dtype.hasSuffix("u2") {
            guard dataBytes.count >= totalElements * 2 else { return nil }
            
            var values = [UInt16]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt16.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
            return .uint16(values)
            
        } else if dtype.hasSuffix("u4") || dtype.hasSuffix("u8") {
            // uint32 и uint64 конвертируем в uint16 для экономии памяти
            let bytesPerElement = dtype.hasSuffix("u4") ? 4 : 8
            guard dataBytes.count >= totalElements * bytesPerElement else { return nil }
            
            var values = [UInt16]()
            values.reserveCapacity(totalElements)
            dataBytes.withUnsafeBytes { bytes in
                if dtype.hasSuffix("u4") {
                    let buffer = bytes.bindMemory(to: UInt32.self)
                    for i in 0..<totalElements {
                        values.append(UInt16(clamping: buffer[i]))
                    }
                } else {
                    let buffer = bytes.bindMemory(to: UInt64.self)
                    for i in 0..<totalElements {
                        values.append(UInt16(clamping: buffer[i]))
                    }
                }
            }
            return .uint16(values)
            
        } else {
            return nil
        }
    }

    private static func loadWavelengths(for npyURL: URL, expectedCount: Int) -> [Double]? {
        guard expectedCount > 0 else { return nil }

        let base = npyURL.deletingPathExtension()
        let candidateURLs: [URL] = [
            base.appendingPathExtension("wavelengths.txt"),
            npyURL.deletingPathExtension().deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)_wavelengths.txt")
        ]

        for candidate in candidateURLs {
            guard let text = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            let lines = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard lines.count == expectedCount else { continue }

            var values: [Double] = []
            values.reserveCapacity(lines.count)
            var isValid = true

            for line in lines {
                let normalized = line.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized), value.isFinite else {
                    isValid = false
                    break
                }
                values.append(value)
            }

            if isValid {
                return values
            }
        }

        return nil
    }
    
    // Больше не используется - DataStorage хранит originalDataType
    private static func npyDtypeToDataType(_ dtype: String) -> DataType {
        let dt = dtype.trimmingCharacters(in: .whitespaces)
        
        if dt.hasSuffix("f8") || dt.hasSuffix("f64") {
            return .float64
        } else if dt.hasSuffix("f4") || dt.hasSuffix("f32") {
            return .float32
        } else if dt.hasSuffix("i8") {
            return .int32
        } else if dt.hasSuffix("i4") {
            return .int32
        } else if dt.hasSuffix("i2") {
            return .int16
        } else if dt.hasSuffix("i1") {
            return .int8
        } else if dt.hasSuffix("u1") {
            return .uint8
        } else if dt.hasSuffix("u2") {
            return .uint16
        }
        
        return .unknown
    }
}
