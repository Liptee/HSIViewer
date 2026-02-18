import Foundation
import AppKit

struct ImportedMaskPayload {
    let width: Int
    let height: Int
    let classMap: [UInt8]
}

enum MaskImportError: LocalizedError {
    case unsupportedFormat(String)
    case readFailure(String)
    case sizeMismatch(actual: String, expectedWidth: Int, expectedHeight: Int)
    case matNoMatching2D(expectedWidth: Int, expectedHeight: Int)
    case matVariableLoadFailed(String)
    case invalidClassValue(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return LF("mask.import.error.unsupported_format", ext)
        case .readFailure(let details):
            return LF("mask.import.error.read_details", details)
        case .sizeMismatch(let actual, let expectedWidth, let expectedHeight):
            return LF("mask.import.error.size_mismatch", actual, expectedWidth, expectedHeight)
        case .matNoMatching2D(let expectedWidth, let expectedHeight):
            return LF("mask.import.error.mat.no_matching_2d", expectedWidth, expectedHeight)
        case .matVariableLoadFailed(let variableName):
            return LF("mask.import.error.mat.variable_load_failed", variableName)
        case .invalidClassValue(let details):
            return LF("mask.import.error.invalid_class_value", details)
        }
    }
}

enum MaskImportService {
    static func importMask(from url: URL, targetSize: (width: Int, height: Int)) -> Result<ImportedMaskPayload, MaskImportError> {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png":
            return importPNGMask(from: url, targetSize: targetSize)
        case "npy":
            return importNPYMask(from: url, targetSize: targetSize)
        case "mat":
            return importMATMask(from: url, targetSize: targetSize)
        default:
            return .failure(.unsupportedFormat(ext))
        }
    }

    private static func importPNGMask(from url: URL, targetSize: (width: Int, height: Int)) -> Result<ImportedMaskPayload, MaskImportError> {
        guard let image = NSImage(contentsOf: url) else {
            return .failure(.readFailure(L("mask.import.error.png_read")))
        }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return .failure(.readFailure(L("mask.import.error.png_read")))
        }

        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let expectedWidth = targetSize.width
        let expectedHeight = targetSize.height

        let isTransposed: Bool
        if sourceWidth == expectedWidth && sourceHeight == expectedHeight {
            isTransposed = false
        } else if sourceWidth == expectedHeight && sourceHeight == expectedWidth {
            isTransposed = true
        } else {
            return .failure(
                .sizeMismatch(
                    actual: "\(sourceWidth)x\(sourceHeight)",
                    expectedWidth: expectedWidth,
                    expectedHeight: expectedHeight
                )
            )
        }

        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return .failure(.readFailure(L("mask.import.error.png_read")))
        }

        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
        let colorOffset = firstColorComponentOffset(alphaInfo: cgImage.alphaInfo, bytesPerPixel: bytesPerPixel)

        var classMap = [UInt8](repeating: 0, count: expectedWidth * expectedHeight)
        for y in 0..<expectedHeight {
            for x in 0..<expectedWidth {
                let sourceX = isTransposed ? y : x
                let sourceY = isTransposed ? x : y
                let baseOffset = sourceY * bytesPerRow + sourceX * bytesPerPixel
                let value = bytes[baseOffset + colorOffset]
                classMap[y * expectedWidth + x] = value
            }
        }

        return .success(
            ImportedMaskPayload(
                width: expectedWidth,
                height: expectedHeight,
                classMap: classMap
            )
        )
    }

    private static func firstColorComponentOffset(alphaInfo: CGImageAlphaInfo, bytesPerPixel: Int) -> Int {
        guard bytesPerPixel > 1 else { return 0 }
        switch alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            return min(1, bytesPerPixel - 1)
        default:
            return 0
        }
    }

    private static func importNPYMask(from url: URL, targetSize: (width: Int, height: Int)) -> Result<ImportedMaskPayload, MaskImportError> {
        let cubeResult = NpyImageLoader.load(from: url)
        guard case .success(let cube) = cubeResult else {
            if case .failure(let error) = cubeResult {
                return .failure(.readFailure(error.localizedDescription))
            }
            return .failure(.readFailure(L("mask.import.error.npy_read")))
        }

        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let singletonAxes = (0..<3).filter { dims[$0] == 1 }

        struct Mapping {
            let fixedAxis: Int
            let yAxis: Int
            let xAxis: Int
            let isTransposed: Bool
        }

        var mapping: Mapping?
        for fixed in singletonAxes {
            let others = (0..<3).filter { $0 != fixed }
            let yAxis = others[0]
            let xAxis = others[1]

            if dims[yAxis] == targetSize.height && dims[xAxis] == targetSize.width {
                mapping = Mapping(fixedAxis: fixed, yAxis: yAxis, xAxis: xAxis, isTransposed: false)
                break
            }
            if dims[yAxis] == targetSize.width && dims[xAxis] == targetSize.height {
                mapping = Mapping(fixedAxis: fixed, yAxis: yAxis, xAxis: xAxis, isTransposed: true)
                break
            }
        }

        guard let resolvedMapping = mapping else {
            let actual = "\(dims[0])x\(dims[1])x\(dims[2])"
            return .failure(
                .sizeMismatch(
                    actual: actual,
                    expectedWidth: targetSize.width,
                    expectedHeight: targetSize.height
                )
            )
        }

        var classMap = [UInt8](repeating: 0, count: targetSize.width * targetSize.height)

        do {
            for y in 0..<targetSize.height {
                for x in 0..<targetSize.width {
                    let sourceY = resolvedMapping.isTransposed ? x : y
                    let sourceX = resolvedMapping.isTransposed ? y : x

                    var indices = [0, 0, 0]
                    indices[resolvedMapping.fixedAxis] = 0
                    indices[resolvedMapping.yAxis] = sourceY
                    indices[resolvedMapping.xAxis] = sourceX

                    let value = cube.getValue(i0: indices[0], i1: indices[1], i2: indices[2])
                    classMap[y * targetSize.width + x] = try classValue(fromFloatingPoint: value)
                }
            }
        } catch {
            if let importError = error as? MaskImportError {
                return .failure(importError)
            }
            return .failure(.readFailure(error.localizedDescription))
        }

        return .success(
            ImportedMaskPayload(
                width: targetSize.width,
                height: targetSize.height,
                classMap: classMap
            )
        )
    }

    private struct Mat2DMatch {
        let name: String
        let rows: Int
        let cols: Int
        let isTransposed: Bool
        let score: Int
    }

    private static func importMATMask(from url: URL, targetSize: (width: Int, height: Int)) -> Result<ImportedMaskPayload, MaskImportError> {
        var listPointer: UnsafeMutablePointer<MatCubeInfo>?
        var rawCount: Int = 0

        let listSuccess = url.path.withCString { cPath in
            list_mat_2d_variables(cPath, &listPointer, &rawCount)
        }

        guard listSuccess else {
            return .failure(.readFailure(L("mask.import.error.mat.list_failed")))
        }

        defer {
            if let ptr = listPointer {
                free_mat_cube_info(ptr)
            }
        }

        guard let ptr = listPointer, rawCount > 0 else {
            return .failure(.matNoMatching2D(expectedWidth: targetSize.width, expectedHeight: targetSize.height))
        }

        var matches: [Mat2DMatch] = []
        matches.reserveCapacity(rawCount)

        for index in 0..<rawCount {
            let info = ptr[index]
            let name = stringFromNameBuffer(info.name)
            let rows = Int(info.dims.0)
            let cols = Int(info.dims.1)

            if rows == targetSize.height && cols == targetSize.width {
                matches.append(
                    Mat2DMatch(
                        name: name,
                        rows: rows,
                        cols: cols,
                        isTransposed: false,
                        score: scoreForMaskVariable(name: name)
                    )
                )
            } else if rows == targetSize.width && cols == targetSize.height {
                matches.append(
                    Mat2DMatch(
                        name: name,
                        rows: rows,
                        cols: cols,
                        isTransposed: true,
                        score: scoreForMaskVariable(name: name)
                    )
                )
            }
        }

        guard !matches.isEmpty else {
            return .failure(.matNoMatching2D(expectedWidth: targetSize.width, expectedHeight: targetSize.height))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.isTransposed != rhs.isTransposed {
                return lhs.isTransposed == false
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        guard let selected = sorted.first else {
            return .failure(.matNoMatching2D(expectedWidth: targetSize.width, expectedHeight: targetSize.height))
        }

        var cube = MatCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0,
            data_type: MAT_DATA_FLOAT64
        )
        var nameBuf = [CChar](repeating: 0, count: 256)

        let loaded = url.path.withCString { cPath in
            selected.name.withCString { cVar in
                load_2d_array_by_name(cPath, cVar, &cube, &nameBuf, nameBuf.count)
            }
        }

        defer {
            free_cube(&cube)
        }

        guard loaded,
              cube.rank == 2,
              cube.dims.0 > 0,
              cube.dims.1 > 0,
              let dataPointer = cube.data else {
            return .failure(.matVariableLoadFailed(selected.name))
        }

        let rows = Int(cube.dims.0)
        let cols = Int(cube.dims.1)

        var classMap = [UInt8](repeating: 0, count: targetSize.width * targetSize.height)

        do {
            switch cube.data_type {
            case MAT_DATA_FLOAT64:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: Double.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    try classValue(fromFloatingPoint: buffer[index])
                }

            case MAT_DATA_FLOAT32:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: Float.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    try classValue(fromFloatingPoint: Double(buffer[index]))
                }

            case MAT_DATA_UINT8:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: UInt8.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    buffer[index]
                }

            case MAT_DATA_UINT16:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: UInt16.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    try classValue(fromUnsignedInteger: UInt64(buffer[index]))
                }

            case MAT_DATA_INT8:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: Int8.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    try classValue(fromSignedInteger: Int64(buffer[index]))
                }

            case MAT_DATA_INT16:
                let buffer = UnsafeBufferPointer(
                    start: dataPointer.bindMemory(to: Int16.self, capacity: rows * cols),
                    count: rows * cols
                )
                try fillClassMap(
                    into: &classMap,
                    sourceRows: rows,
                    sourceCols: cols,
                    targetWidth: targetSize.width,
                    targetHeight: targetSize.height,
                    isTransposed: selected.isTransposed
                ) { index in
                    try classValue(fromSignedInteger: Int64(buffer[index]))
                }

            default:
                return .failure(.readFailure(L("mask.import.error.mat.unsupported_type")))
            }
        } catch {
            if let importError = error as? MaskImportError {
                return .failure(importError)
            }
            return .failure(.readFailure(error.localizedDescription))
        }

        return .success(
            ImportedMaskPayload(
                width: targetSize.width,
                height: targetSize.height,
                classMap: classMap
            )
        )
    }

    private static func fillClassMap(
        into target: inout [UInt8],
        sourceRows: Int,
        sourceCols: Int,
        targetWidth: Int,
        targetHeight: Int,
        isTransposed: Bool,
        valueProvider: (Int) throws -> UInt8
    ) throws {
        guard target.count == targetWidth * targetHeight else { return }

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let sourceRow = isTransposed ? x : y
                let sourceCol = isTransposed ? y : x
                if sourceRow < 0 || sourceRow >= sourceRows || sourceCol < 0 || sourceCol >= sourceCols {
                    throw MaskImportError.readFailure("index out of bounds")
                }
                let sourceIndex = sourceRow + sourceRows * sourceCol
                let targetIndex = y * targetWidth + x
                target[targetIndex] = try valueProvider(sourceIndex)
            }
        }
    }

    private static func classValue(fromFloatingPoint value: Double) throws -> UInt8 {
        guard value.isFinite else {
            throw MaskImportError.invalidClassValue("NaN/Inf")
        }

        let rounded = value.rounded()
        if abs(value - rounded) > 0.000001 {
            throw MaskImportError.invalidClassValue(String(format: "%.6f", value))
        }

        return try classValue(fromSignedInteger: Int64(rounded))
    }

    private static func classValue(fromSignedInteger value: Int64) throws -> UInt8 {
        guard value >= 0 && value <= 255 else {
            throw MaskImportError.invalidClassValue("\(value)")
        }
        return UInt8(value)
    }

    private static func classValue(fromUnsignedInteger value: UInt64) throws -> UInt8 {
        guard value <= 255 else {
            throw MaskImportError.invalidClassValue("\(value)")
        }
        return UInt8(value)
    }

    private static func scoreForMaskVariable(name: String) -> Int {
        let lower = name.lowercased()
        if lower == "mask" {
            return 100
        }
        if lower.contains("mask") {
            return 90
        }
        if lower.contains("label") {
            return 80
        }
        if lower.contains("class") {
            return 75
        }
        if lower.contains("seg") {
            return 70
        }
        return 0
    }

    private static func stringFromNameBuffer<T>(_ buffer: T) -> String {
        var mutableBuffer = buffer
        let capacity = MemoryLayout<T>.size / MemoryLayout<CChar>.size

        return withUnsafePointer(to: &mutableBuffer) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { charPtr in
                if let str = String(validatingUTF8: charPtr) {
                    return str
                }

                let bytes = UnsafeBufferPointer(start: charPtr, count: capacity)
                    .prefix { $0 != 0 }
                    .map { UInt8(bitPattern: $0) }
                return String(bytes: bytes, encoding: .utf8) ?? ""
            }
        }
    }
}
