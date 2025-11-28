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
        
        guard var values = parseNpyData(data: data, header: header) else {
            return .failure(.corruptedData)
        }
        
        let dims: (Int, Int, Int)
        if header.shape.count == 2 {
            dims = (header.shape[0], header.shape[1], 1)
        } else {
            dims = (header.shape[0], header.shape[1], header.shape[2])
        }
        
        // Для Fortran-order нужно переупорядочить данные в C-order
        if header.fortranOrder && header.shape.count == 3 {
            values = reorderFromFortranToC(values: values, dims: dims)
        }
        
        let dataType = npyDtypeToDataType(header.dtype)
        
        return .success(HyperCube(
            dims: dims,
            data: values,
            originalDataType: dataType,
            sourceFormat: "NumPy (.npy)"
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
    
    private static func parseNpyData(data: Data, header: NpyHeader) -> [Double]? {
        let dataStart = header.dataOffset
        guard data.count > dataStart else { return nil }
        
        let totalElements = header.shape.reduce(1, *)
        let dataBytes = Data(data[dataStart...])
        
        let dtype = header.dtype.trimmingCharacters(in: .whitespaces)
        
        var values: [Double] = []
        values.reserveCapacity(totalElements)
        
        if dtype.hasSuffix("f8") || dtype.hasSuffix("f64") {
            guard dataBytes.count >= totalElements * 8 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Double.self)
                for i in 0..<totalElements {
                    values.append(buffer[i])
                }
            }
        } else if dtype.hasSuffix("f4") || dtype.hasSuffix("f32") {
            guard dataBytes.count >= totalElements * 4 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Float.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("i8") {
            guard dataBytes.count >= totalElements * 8 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int64.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("i4") {
            guard dataBytes.count >= totalElements * 4 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int32.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("i2") {
            guard dataBytes.count >= totalElements * 2 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: Int16.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("i1") || dtype.hasSuffix("u1") {
            guard dataBytes.count >= totalElements else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt8.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("u2") {
            guard dataBytes.count >= totalElements * 2 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt16.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("u4") {
            guard dataBytes.count >= totalElements * 4 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt32.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else if dtype.hasSuffix("u8") {
            guard dataBytes.count >= totalElements * 8 else { return nil }
            
            dataBytes.withUnsafeBytes { bytes in
                let buffer = bytes.bindMemory(to: UInt64.self)
                for i in 0..<totalElements {
                    values.append(Double(buffer[i]))
                }
            }
        } else {
            return nil
        }
        
        return values
    }
    
    /// Переупорядочивает данные из Fortran-order (column-major) в C-order (row-major)
    /// Для shape (H, W, C):
    /// - Fortran: индекс = h + H*(w + W*c), где h меняется быстрее всего
    /// - C-order: индекс = c + C*(w + W*h), где c меняется быстрее всего
    private static func reorderFromFortranToC(values: [Double], dims: (Int, Int, Int)) -> [Double] {
        let (H, W, C) = dims
        var reordered = [Double](repeating: 0.0, count: values.count)
        
        for h in 0..<H {
            for w in 0..<W {
                for c in 0..<C {
                    let fortranIndex = h + H * (w + W * c)
                    let cIndex = c + C * (w + W * h)
                    reordered[cIndex] = values[fortranIndex]
                }
            }
        }
        
        return reordered
    }
    
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

