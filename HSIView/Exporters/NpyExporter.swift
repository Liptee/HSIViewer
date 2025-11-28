import Foundation

enum ExportError: Error, LocalizedError {
    case unsupportedDataType
    case writeError(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .unsupportedDataType:
            return "Неподдерживаемый тип данных для экспорта"
        case .writeError(let msg):
            return "Ошибка записи: \(msg)"
        case .invalidData:
            return "Некорректные данные для экспорта"
        }
    }
}

class NpyExporter {
    static func export(cube: HyperCube, to url: URL, exportWavelengths: Bool) -> Result<Void, Error> {
        do {
            let npyData = try createNpyData(from: cube)
            try npyData.write(to: url, options: .atomic)
            
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
    
    private static func createNpyData(from cube: HyperCube) throws -> Data {
        let (d0, d1, d2) = cube.dims
        
        var header = "{'descr': '\(npyDescriptor(for: cube))', 'fortran_order': \(cube.isFortranOrder ? "True" : "False"), 'shape': (\(d0), \(d1), \(d2)), }"
        
        let majorVersion: UInt8 = 1
        let minorVersion: UInt8 = 0
        
        let headerBytesNeeded = header.utf8.count
        let totalHeaderSize = (10 + headerBytesNeeded + 1 + 15) & ~15
        let paddingSize = totalHeaderSize - (10 + headerBytesNeeded + 1)
        
        for _ in 0..<paddingSize {
            header.append(" ")
        }
        header.append("\n")
        
        let headerLength = UInt16(header.utf8.count)
        
        var data = Data()
        
        data.append(0x93)
        data.append(contentsOf: "NUMPY".utf8)
        data.append(majorVersion)
        data.append(minorVersion)
        
        var headerLenLE = headerLength.littleEndian
        data.append(Data(bytes: &headerLenLE, count: 2))
        
        data.append(contentsOf: header.utf8)
        
        let arrayData = try createArrayData(from: cube)
        data.append(arrayData)
        
        return data
    }
    
    private static func npyDescriptor(for cube: HyperCube) -> String {
        let endianness = "<"
        
        switch cube.originalDataType {
        case .float64:
            return endianness + "f8"
        case .float32:
            return endianness + "f4"
        case .int8:
            return "|i1"
        case .int16:
            return endianness + "i2"
        case .int32:
            return endianness + "i4"
        case .uint8:
            return "|u1"
        case .uint16:
            return endianness + "u2"
        case .unknown:
            return endianness + "f8"
        }
    }
    
    private static func createArrayData(from cube: HyperCube) throws -> Data {
        var data = Data()
        let totalElements = cube.totalElements
        
        switch cube.storage {
        case .float64(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 8))
            }
            
        case .float32(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 4))
            }
            
        case .int8(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 1))
            }
            
        case .int16(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 2))
            }
            
        case .int32(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 4))
            }
            
        case .uint8(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 1))
            }
            
        case .uint16(let arr):
            for i in 0..<totalElements {
                var value = arr[i]
                data.append(Data(bytes: &value, count: 2))
            }
        }
        
        return data
    }
}

