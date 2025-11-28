import Foundation

class MatExporter {
    static func export(cube: HyperCube, to url: URL, exportWavelengths: Bool) -> Result<Void, Error> {
        do {
            let result = exportMatFile(cube: cube, url: url, exportWavelengths: exportWavelengths)
            
            if result {
                return .success(())
            } else {
                return .failure(ExportError.writeError("Не удалось записать MAT файл"))
            }
        } catch {
            return .failure(error)
        }
    }
    
    private static func exportMatFile(cube: HyperCube, url: URL, exportWavelengths: Bool) -> Bool {
        let path = url.path
        let mat = Mat_CreateVer(path, nil, MAT_FT_MAT5)
        guard let mat = mat else {
            return false
        }
        defer { Mat_Close(mat) }
        
        let (d0, d1, d2) = cube.dims
        var dims: [size_t] = [size_t(d0), size_t(d1), size_t(d2)]
        
        let rank: Int32 = 3
        let matDataType = matDataType(for: cube.originalDataType)
        let classType = matClassType(for: cube.originalDataType)
        
        let dataPtr = extractDataPointer(from: cube)
        guard let dataPtr = dataPtr else {
            return false
        }
        
        let matvar = Mat_VarCreate("cube", classType, matDataType, rank, &dims, dataPtr, 0)
        guard let matvar = matvar else {
            return false
        }
        
        let writeResult = Mat_VarWrite(mat, matvar, MAT_COMPRESSION_NONE)
        Mat_VarFree(matvar)
        
        if writeResult != 0 {
            return false
        }
        
        if exportWavelengths, let wavelengths = cube.wavelengths, !wavelengths.isEmpty {
            var wavelengthsArray = wavelengths
            var wavelengthsDims: [size_t] = [size_t(wavelengths.count), 1]
            
            let wavelengthsVar = Mat_VarCreate(
                "wavelengths",
                MAT_C_DOUBLE,
                MAT_T_DOUBLE,
                2,
                &wavelengthsDims,
                &wavelengthsArray,
                0
            )
            
            if let wavelengthsVar = wavelengthsVar {
                Mat_VarWrite(mat, wavelengthsVar, MAT_COMPRESSION_NONE)
                Mat_VarFree(wavelengthsVar)
            }
        }
        
        return true
    }
    
    private static func matDataType(for dataType: DataType) -> mat_types {
        switch dataType {
        case .float64:
            return MAT_T_DOUBLE
        case .float32:
            return MAT_T_SINGLE
        case .int8:
            return MAT_T_INT8
        case .int16:
            return MAT_T_INT16
        case .int32:
            return MAT_T_INT32
        case .uint8:
            return MAT_T_UINT8
        case .uint16:
            return MAT_T_UINT16
        case .unknown:
            return MAT_T_DOUBLE
        }
    }
    
    private static func matClassType(for dataType: DataType) -> matio_classes {
        switch dataType {
        case .float64:
            return MAT_C_DOUBLE
        case .float32:
            return MAT_C_SINGLE
        case .int8:
            return MAT_C_INT8
        case .int16:
            return MAT_C_INT16
        case .int32:
            return MAT_C_INT32
        case .uint8:
            return MAT_C_UINT8
        case .uint16:
            return MAT_C_UINT16
        case .unknown:
            return MAT_C_DOUBLE
        }
    }
    
    private static func extractDataPointer(from cube: HyperCube) -> UnsafeMutableRawPointer? {
        switch cube.storage {
        case .float64(let arr):
            let ptr = UnsafeMutablePointer<Double>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .float32(let arr):
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .int8(let arr):
            let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .int16(let arr):
            let ptr = UnsafeMutablePointer<Int16>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .int32(let arr):
            let ptr = UnsafeMutablePointer<Int32>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .uint8(let arr):
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
            
        case .uint16(let arr):
            let ptr = UnsafeMutablePointer<UInt16>.allocate(capacity: arr.count)
            for i in 0..<arr.count {
                ptr[i] = arr[i]
            }
            return UnsafeMutableRawPointer(ptr)
        }
    }
}

