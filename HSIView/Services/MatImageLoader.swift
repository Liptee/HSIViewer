import Foundation

struct MatVariableOption: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let dims: (Int, Int, Int)
    let dataType: MatDataType
    
    var formattedSize: String {
        "\(dims.0) × \(dims.1) × \(dims.2)"
    }
    
    var typeDescription: String {
        switch dataType {
        case MAT_DATA_FLOAT64: return "Float64"
        case MAT_DATA_FLOAT32: return "Float32"
        case MAT_DATA_UINT8: return "UInt8"
        case MAT_DATA_UINT16: return "UInt16"
        case MAT_DATA_INT8: return "Int8"
        case MAT_DATA_INT16: return "Int16"
        default: return "Unknown"
        }
    }
    
    static func == (lhs: MatVariableOption, rhs: MatVariableOption) -> Bool {
        return lhs.name == rhs.name &&
            lhs.dims.0 == rhs.dims.0 &&
            lhs.dims.1 == rhs.dims.1 &&
            lhs.dims.2 == rhs.dims.2 &&
            matDataTypeEquals(lhs.dataType, rhs.dataType)
    }
}

private func matDataTypeEquals(_ lhs: MatDataType, _ rhs: MatDataType) -> Bool {
    var l = lhs
    var r = rhs
    return withUnsafeBytes(of: &l) { lBytes in
        withUnsafeBytes(of: &r) { rBytes in
            lBytes.elementsEqual(rBytes)
        }
    }
}

class MatImageLoader: ImageLoader {
    static let supportedExtensions = ["mat"]
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        return load(from: url, variableName: nil)
    }
    
    static func load(from url: URL, variableName: String?) -> Result<HyperCube, ImageLoadError> {
        var cCube = MatCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0,
            data_type: MAT_DATA_FLOAT64
        )
        
        var nameBuf = [CChar](repeating: 0, count: 256)
        
        let loaded: Bool = url.path.withCString { cPath in
            if let variableName = variableName {
                return variableName.withCString { cVar in
                    load_cube_by_name(cPath, cVar, &cCube, &nameBuf, nameBuf.count)
                }
            } else {
                return load_first_3d_double_cube(cPath, &cCube, &nameBuf, nameBuf.count)
            }
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
    
    static func availableVariables(at url: URL) -> Result<[MatVariableOption], ImageLoadError> {
        var listPointer: UnsafeMutablePointer<MatCubeInfo>?
        var rawCount: Int = 0
        
        let success = url.path.withCString { cPath in
            list_mat_cube_variables(cPath, &listPointer, &rawCount)
        }
        
        guard success else {
            return .failure(.readError("Не удалось прочитать список переменных"))
        }
        
        defer {
            if let ptr = listPointer {
                free_mat_cube_info(ptr)
            }
        }
        
        guard let ptr = listPointer, rawCount > 0 else {
            return .success([])
        }
        
        var options: [MatVariableOption] = []
        options.reserveCapacity(rawCount)
        
        for index in 0..<rawCount {
            var info = ptr[index]
            let name = stringFromNameBuffer(info.name)
            let dims = (
                Int(info.dims.0),
                Int(info.dims.1),
                Int(info.dims.2)
            )
            options.append(
                MatVariableOption(
                    name: name,
                    dims: dims,
                    dataType: info.data_type
                )
            )
        }
        
        return .success(options)
    }
    
    private static func stringFromNameBuffer<T>(_ buffer: T) -> String {
        var mutableBuffer = buffer
        let capacity = MemoryLayout<T>.size / MemoryLayout<CChar>.size
        
        return withUnsafePointer(to: &mutableBuffer) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { charPtr in
                if let str = String(validatingUTF8: charPtr) {
                    return str
                }
                
                let buffer = UnsafeBufferPointer(start: charPtr, count: capacity)
                let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                return String(bytes: bytes, encoding: .utf8) ?? ""
            }
        }
    }
}
