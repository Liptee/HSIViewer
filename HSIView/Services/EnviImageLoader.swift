import Foundation
import AppKit

class EnviImageLoader: ImageLoader {
    static let supportedExtensions = ["dat", "hdr", "img", "bsq", "bil", "bip", "raw"]
    
    private static func findDataFile(basePath: URL) -> URL? {
        let possibleExtensions = ["dat", "img", "bsq", "bil", "bip", "raw"]
        
        for ext in possibleExtensions {
            let url = basePath.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }
    
    private static func requestAccessToFile(_ fileURL: URL, description: String) -> URL? {
        guard !FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return fileURL
        }
        
        var result: URL? = nil
        
        let showPanel = {
            let panel = NSOpenPanel()
            panel.message = "ENVI формат требует доступ к парному файлу"
            panel.prompt = "Разрешить доступ"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.directoryURL = fileURL.deletingLastPathComponent()
            panel.nameFieldStringValue = fileURL.lastPathComponent
            
            if panel.runModal() == .OK, let selectedURL = panel.url {
                result = selectedURL
            }
        }
        
        if Thread.isMainThread {
            showPanel()
        } else {
            DispatchQueue.main.sync(execute: showPanel)
        }
        
        return result
    }
    
    static func load(from url: URL) -> Result<HyperCube, ImageLoadError> {
        let fileExt = url.pathExtension.lowercased()
        let basePath = url.deletingPathExtension()
        
        var hdrURL: URL
        var datURL: URL
        
        if fileExt == "hdr" {
            hdrURL = url
            let possibleDataURL = findDataFile(basePath: basePath) ?? basePath.appendingPathExtension("dat")
            
            if !FileManager.default.isReadableFile(atPath: possibleDataURL.path) {
                guard let accessibleURL = requestAccessToFile(possibleDataURL, description: "бинарный файл данных") else {
                    return .failure(.readError("Нет доступа к бинарному файлу: \(possibleDataURL.lastPathComponent)"))
                }
                datURL = accessibleURL
            } else {
                datURL = possibleDataURL
            }
        } else {
            datURL = url
            let possibleHdrURL = basePath.appendingPathExtension("hdr")
            
            if !FileManager.default.isReadableFile(atPath: possibleHdrURL.path) {
                guard let accessibleURL = requestAccessToFile(possibleHdrURL, description: "заголовочный файл") else {
                    return .failure(.readError("Нет доступа к .hdr файлу: \(possibleHdrURL.lastPathComponent)"))
                }
                hdrURL = accessibleURL
            } else {
                hdrURL = possibleHdrURL
            }
        }
        
        guard FileManager.default.fileExists(atPath: hdrURL.path) else {
            return .failure(.readError("Не найден .hdr файл: \(hdrURL.lastPathComponent)"))
        }
        
        guard FileManager.default.fileExists(atPath: datURL.path) else {
            return .failure(.readError("Не найден бинарный файл. Ожидается: \(datURL.lastPathComponent)"))
        }
        
        let header: EnviHeader
        do {
            header = try EnviHeaderParser.parse(from: hdrURL)
        } catch let error as ImageLoadError {
            return .failure(error)
        } catch {
            return .failure(.corruptedData)
        }
        
        guard let data = try? Data(contentsOf: datURL) else {
            return .failure(.readError("Не удалось прочитать .dat файл"))
        }
        
        let expectedSize = header.height * header.width * header.channels * header.bytesPerPixel + header.headerOffset
        guard data.count >= expectedSize - header.headerOffset else {
            return .failure(.readError("Размер файла не соответствует заголовку"))
        }
        
        let dataStart = header.headerOffset
        let dataBytes = Data(data[dataStart...])
        
        guard let storage = parseEnviData(data: dataBytes, header: header) else {
            return .failure(.corruptedData)
        }
        
        let cube = HyperCube(
            dims: (header.height, header.width, header.channels),
            storage: storage,
            sourceFormat: "ENVI (\(header.interleave.uppercased()))",
            isFortranOrder: false,
            wavelengths: header.wavelength
        )
        
        return .success(cube)
    }
    
    private static func parseEnviData(data: Data, header: EnviHeader) -> DataStorage? {
        let H = header.height
        let W = header.width
        let C = header.channels
        let totalElements = H * W * C
        
        let isLittleEndian = header.isLittleEndian
        
        switch header.dataType {
        case 1:
            return parseInt8(data: data, header: header, totalElements: totalElements)
        case 2:
            return parseInt16(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        case 3:
            return parseInt32(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        case 4:
            return parseFloat32(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        case 5:
            return parseFloat64(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        case 12:
            return parseUInt16(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        case 13:
            return parseUInt32(data: data, header: header, totalElements: totalElements, isLittleEndian: isLittleEndian)
        default:
            return nil
        }
    }
    
    private static func parseInt8(data: Data, header: EnviHeader, totalElements: Int) -> DataStorage? {
        guard data.count >= totalElements else { return nil }
        
        return data.withUnsafeBytes { bytes in
            let arr = Array(bytes.bindMemory(to: UInt8.self))
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseInt16(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 2 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: Int16.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { Int16(bigEndian: $0) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseInt32(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 4 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: Int32.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { Int32(bigEndian: $0) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseFloat32(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 4 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: Float.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { Float(bitPattern: UInt32(bigEndian: $0.bitPattern)) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseFloat64(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 8 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: Double.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { Double(bitPattern: UInt64(bigEndian: $0.bitPattern)) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseUInt16(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 2 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: UInt16.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { UInt16(bigEndian: $0) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func parseUInt32(data: Data, header: EnviHeader, totalElements: Int, isLittleEndian: Bool) -> DataStorage? {
        guard data.count >= totalElements * 4 else { return nil }
        
        return data.withUnsafeBytes { bytes in
            var arr = Array(bytes.bindMemory(to: UInt32.self))
            if isLittleEndian != (CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderLittleEndian.rawValue)) {
                arr = arr.map { UInt32(bigEndian: $0) }
            }
            return reorderENVI(arr, header: header)
        }
    }
    
    private static func reorderENVI<T>(_ arr: [T], header: EnviHeader) -> DataStorage? {
        guard !arr.isEmpty else { return nil }
        
        let H = header.height
        let W = header.width
        let C = header.channels
        
        switch header.interleave.lowercased() {
        case "bsq":
            let reordered = reorderBSQToHWC(arr, H: H, W: W, C: C)
            return wrapInStorage(reordered)
        case "bil":
            let reordered = reorderBILToHWC(arr, H: H, W: W, C: C)
            return wrapInStorage(reordered)
        case "bip":
            return wrapInStorage(arr)
        default:
            return wrapInStorage(arr)
        }
    }
    
    private static func reorderBSQToHWC<T>(_ arr: [T], H: Int, W: Int, C: Int) -> [T] {
        var result = [T]()
        result.reserveCapacity(H * W * C)
        
        for h in 0..<H {
            for w in 0..<W {
                for c in 0..<C {
                    let srcIdx = c * H * W + h * W + w
                    result.append(arr[srcIdx])
                }
            }
        }
        
        return result
    }
    
    private static func reorderBILToHWC<T>(_ arr: [T], H: Int, W: Int, C: Int) -> [T] {
        var result = [T]()
        result.reserveCapacity(H * W * C)
        
        for h in 0..<H {
            for w in 0..<W {
                for c in 0..<C {
                    let srcIdx = h * C * W + c * W + w
                    result.append(arr[srcIdx])
                }
            }
        }
        
        return result
    }
    
    private static func wrapInStorage<T>(_ arr: [T]) -> DataStorage? {
        if let arr = arr as? [Double] {
            return .float64(arr)
        } else if let arr = arr as? [Float] {
            return .float32(arr)
        } else if let arr = arr as? [UInt8] {
            return .uint8(arr)
        } else if let arr = arr as? [Int8] {
            return .int8(arr)
        } else if let arr = arr as? [Int16] {
            return .int16(arr)
        } else if let arr = arr as? [Int32] {
            return .int32(arr)
        } else if let arr = arr as? [UInt16] {
            return .uint16(arr)
        } else {
            return nil
        }
    }
}

