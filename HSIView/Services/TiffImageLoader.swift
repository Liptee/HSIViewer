import Foundation

class TiffImageLoader: ImageLoader {
    static let supportedExtensions = ["tif", "tiff"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        var cCube = TiffCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0
        )
        
        let loaded: Bool = url.path.withCString { cPath in
            load_tiff_cube(cPath, &cCube)
        }
        
        defer {
            free_tiff_cube(&cCube)
        }
        
        guard loaded else {
            return .failure(.readError("Не удалось открыть TIFF файл"))
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
        
        return .success(HyperCube(
            dims: (d0, d1, d2),
            data: arr,
            originalDataType: .uint8,
            sourceFormat: "TIFF (.tiff)"
        ))
    }
}

