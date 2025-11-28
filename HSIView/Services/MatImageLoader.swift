import Foundation

class MatImageLoader: ImageLoader {
    static let supportedExtensions = ["mat"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        var cCube = MatCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0,
            data_type: MAT_DATA_FLOAT64
        )
        
        var nameBuf = [CChar](repeating: 0, count: 256)
        
        let loaded: Bool = url.path.withCString { cPath in
            load_first_3d_double_cube(cPath, &cCube, &nameBuf, nameBuf.count)
        }
        
        defer {
            free_cube(&cCube)
        }
        
        guard loaded else {
            return .failure(.readError("Не удалось открыть .mat файл"))
        }
        
        guard cCube.rank == 3 else {
            return .failure(.notA3DCube)
        }
        
        guard let ptr = cCube.data else {
            return .failure(.corruptedData)
        }
        
        let d0 = Int(cCube.dims.0)
        let d1 = Int(cCube.dims.1)
        let d2 = Int(cCube.dims.2)
        
        guard d0 > 0 && d1 > 0 && d2 > 0 else {
            return .failure(.invalidDimensions)
        }
        
        let count = d0 * d1 * d2
        
        // Создаем DataStorage в зависимости от типа данных
        let storage: DataStorage
        
        switch cCube.data_type {
        case MAT_DATA_FLOAT64:
            let typedPtr = ptr.bindMemory(to: Double.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .float64(Array(buffer))
            
        case MAT_DATA_FLOAT32:
            let typedPtr = ptr.bindMemory(to: Float.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .float32(Array(buffer))
            
        case MAT_DATA_UINT8:
            let typedPtr = ptr.bindMemory(to: UInt8.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .uint8(Array(buffer))
            
        case MAT_DATA_UINT16:
            let typedPtr = ptr.bindMemory(to: UInt16.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .uint16(Array(buffer))
            
        case MAT_DATA_INT8:
            let typedPtr = ptr.bindMemory(to: Int8.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .int8(Array(buffer))
            
        case MAT_DATA_INT16:
            let typedPtr = ptr.bindMemory(to: Int16.self, capacity: count)
            let buffer = UnsafeBufferPointer(start: typedPtr, count: count)
            storage = .int16(Array(buffer))
            
        default:
            return .failure(.corruptedData)
        }
        
        return .success(HyperCube(
            dims: (d0, d1, d2),
            storage: storage,
            sourceFormat: "MATLAB (.mat)",
            isFortranOrder: true  // MATLAB всегда column-major
        ))
    }
}

