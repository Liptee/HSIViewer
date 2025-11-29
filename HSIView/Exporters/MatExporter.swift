import Foundation

class MatExporter {
    enum ExportError: LocalizedError {
        case unsupportedDataType
        case exportFailed(String)
        case memoryAllocationFailed
        
        var errorDescription: String? {
            switch self {
            case .unsupportedDataType:
                return "Неподдерживаемый тип данных для экспорта в MAT."
            case .exportFailed(let message):
                return "Ошибка экспорта в MAT: \(message)"
            case .memoryAllocationFailed:
                return "Не удалось выделить память для экспорта."
            }
        }
    }
    
    static func export(cube: HyperCube, to url: URL, variableName: String, wavelengths: [Double]?, wavelengthsAsVariable: Bool) -> Result<Void, Error> {
        let (d0, d1, d2) = cube.dims
        let count = d0 * d1 * d2
        
        var cCube = MatCube3D(
            data: nil,
            dims: (size_t(d0), size_t(d1), size_t(d2)),
            rank: 3,
            data_type: MAT_DATA_FLOAT64
        )
        
        let matDataType: MatDataType
        
        switch cube.storage {
        case .float64(let arr):
            matDataType = MAT_DATA_FLOAT64
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .float32(let arr):
            matDataType = MAT_DATA_FLOAT32
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .uint8(let arr):
            matDataType = MAT_DATA_UINT8
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .uint16(let arr):
            matDataType = MAT_DATA_UINT16
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .int8(let arr):
            matDataType = MAT_DATA_INT8
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .int16(let arr):
            matDataType = MAT_DATA_INT16
            let reordered = reorderIfNeeded(arr, cube: cube)
            cCube.data = allocateAndCopy(reordered)
            
        case .int32:
            return .failure(ExportError.unsupportedDataType)
        }
        
        cCube.data_type = matDataType
        
        guard cCube.data != nil else {
            return .failure(ExportError.memoryAllocationFailed)
        }
        
        defer {
            if let data = cCube.data {
                data.deallocate()
            }
        }
        
        let success = url.path.withCString { cPath in
            variableName.withCString { cVarName in
                save_3d_cube(cPath, cVarName, &cCube)
            }
        }
        
        guard success else {
            return .failure(ExportError.exportFailed("Не удалось записать MAT файл"))
        }
        
        if let wavelengths = wavelengths, !wavelengths.isEmpty {
            if wavelengthsAsVariable {
                let wavelengthsVarName = "\(variableName)_wavelengths"
                let waveSuccess = url.path.withCString { cPath in
                    wavelengthsVarName.withCString { cVarName in
                        wavelengths.withUnsafeBufferPointer { bufferPtr in
                            save_wavelengths(cPath, cVarName, bufferPtr.baseAddress!, wavelengths.count)
                        }
                    }
                }
                
                guard waveSuccess else {
                    return .failure(ExportError.exportFailed("Не удалось записать wavelengths в MAT файл"))
                }
            } else {
                let wavelengthsURL = url.deletingPathExtension()
                    .appendingPathExtension("wavelengths")
                    .appendingPathExtension("txt")
                let wavelengthString = wavelengths.map { String($0) }.joined(separator: "\n")
                do {
                    try wavelengthString.write(to: wavelengthsURL, atomically: true, encoding: .utf8)
                } catch {
                    return .failure(ExportError.exportFailed("Не удалось записать файл длин волн: \(error.localizedDescription)"))
                }
            }
        }
        
        return .success(())
    }
    
    private static func reorderIfNeeded<T>(_ arr: [T], cube: HyperCube) -> [T] {
        if cube.isFortranOrder {
            return arr
        }
        
        return reorderCToFortran(arr, dims: cube.dims)
    }
    
    private static func reorderCToFortran<T>(_ arr: [T], dims: (Int, Int, Int)) -> [T] {
        let (d0, d1, d2) = dims
        var result = arr
        
        for i0 in 0..<d0 {
            for i1 in 0..<d1 {
                for i2 in 0..<d2 {
                    let cIndex = i0 * (d1 * d2) + i1 * d2 + i2
                    let fortranIndex = i0 + d0 * (i1 + d1 * i2)
                    result[fortranIndex] = arr[cIndex]
                }
            }
        }
        
        return result
    }
    
    private static func allocateAndCopy<T>(_ arr: [T]) -> UnsafeMutableRawPointer? {
        let size = arr.count * MemoryLayout<T>.size
        let alignment = MemoryLayout<T>.alignment
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
        ptr.copyMemory(from: arr, byteCount: size)
        return ptr
    }
}
