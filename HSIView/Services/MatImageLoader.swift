import Foundation

class MatImageLoader: ImageLoader {
    static let supportedExtensions = ["mat"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        var cCube = MatCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0
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
        let buffer = UnsafeBufferPointer(start: ptr, count: count)
        let arr = Array(buffer)
        
        let dataType: DataType
        if cCube.dims.0 == d0 {
            dataType = .float64
        } else {
            dataType = .float32
        }
        
        return .success(HyperCube(
            dims: (d0, d1, d2),
            data: arr,
            originalDataType: dataType,
            sourceFormat: "MATLAB (.mat)",
            isFortranOrder: true  // MATLAB всегда column-major
        ))
    }
}

