import Foundation
import AppKit

struct ImportedMaskPayload {
    let width: Int
    let height: Int
    let classMap: [UInt8]
}

enum MaskMetadataImportError: LocalizedError {
    case unsupportedFormat(String)
    case readFailure(String)
    case invalidJSON
    case noClasses
    case invalidClassValue(String)
    case matListFailed
    case matNoMetadataFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return LF("mask.metadata.import.error.unsupported_format", ext)
        case .readFailure(let details):
            return LF("mask.metadata.import.error.read_details", details)
        case .invalidJSON:
            return L("mask.metadata.import.error.invalid_json")
        case .noClasses:
            return L("mask.metadata.import.error.no_classes")
        case .invalidClassValue(let details):
            return LF("mask.metadata.import.error.invalid_class_value", details)
        case .matListFailed:
            return L("mask.metadata.import.error.mat.list_failed")
        case .matNoMetadataFound:
            return L("mask.metadata.import.error.mat.not_found")
        }
    }
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
    static func importMaskMetadata(from url: URL) -> Result<[MaskClassMetadata], MaskMetadataImportError> {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return importJSONMaskMetadata(from: url)
        case "mat":
            return importMATMaskMetadata(from: url)
        default:
            return .failure(.unsupportedFormat(ext))
        }
    }

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

    private struct MatMetadataVariableInfo {
        let name: String
        let rows: Int
        let cols: Int
        let dataType: MatDataType
    }

    private struct LoadedMatVariable {
        let rows: Int
        let cols: Int
        let values: [Double] // Column-major order from MAT payload.
    }

    private struct MetadataCandidate {
        let metadata: [MaskClassMetadata]
        let score: Int
    }

    private static func importJSONMaskMetadata(from url: URL) -> Result<[MaskClassMetadata], MaskMetadataImportError> {
        do {
            let data = try Data(contentsOf: url)
            let metadata = try decodeMetadataDocument(from: data)
            return .success(metadata)
        } catch let error as MaskMetadataImportError {
            return .failure(error)
        } catch {
            return .failure(.readFailure(error.localizedDescription))
        }
    }

    private static func importMATMaskMetadata(from url: URL) -> Result<[MaskClassMetadata], MaskMetadataImportError> {
        var listPointer: UnsafeMutablePointer<MatCubeInfo>?
        var rawCount: Int = 0

        let listSuccess = url.path.withCString { cPath in
            list_mat_2d_variables(cPath, &listPointer, &rawCount)
        }

        guard listSuccess else {
            return .failure(.matListFailed)
        }

        defer {
            if let ptr = listPointer {
                free_mat_cube_info(ptr)
            }
        }

        guard let ptr = listPointer, rawCount > 0 else {
            return .failure(.matNoMetadataFound)
        }

        var variables: [MatMetadataVariableInfo] = []
        variables.reserveCapacity(rawCount)
        for index in 0..<rawCount {
            let info = ptr[index]
            variables.append(
                MatMetadataVariableInfo(
                    name: stringFromNameBuffer(info.name),
                    rows: Int(info.dims.0),
                    cols: Int(info.dims.1),
                    dataType: info.data_type
                )
            )
        }

        if let metadata = loadMetadataFromJSONVariables(in: variables, fileURL: url) {
            return .success(metadata)
        }

        if let metadata = loadMetadataFromStructuredMATVariables(in: variables, fileURL: url) {
            return .success(metadata)
        }

        if let metadata = loadMetadataByStructuralSimilarity(in: variables, fileURL: url) {
            return .success(metadata)
        }

        return .failure(.matNoMetadataFound)
    }

    private static func loadMetadataFromJSONVariables(
        in variables: [MatMetadataVariableInfo],
        fileURL: URL
    ) -> [MaskClassMetadata]? {
        var bestCandidate: MetadataCandidate?

        let sorted = variables.sorted { lhs, rhs in
            scoreForMetadataVariable(name: lhs.name) > scoreForMetadataVariable(name: rhs.name)
        }

        for variable in sorted {
            guard let loaded = loadMATVariable(from: fileURL, variableName: variable.name) else { continue }
            guard let data = try? bytesFromNumericVariable(loaded) else { continue }
            guard let metadata = try? decodeMetadataDocument(from: data) else { continue }

            let candidate = MetadataCandidate(
                metadata: metadata,
                score: scoreForMetadataVariable(name: variable.name)
            )
            if let current = bestCandidate {
                if candidate.score > current.score {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate?.metadata
    }

    private static func loadMetadataFromStructuredMATVariables(
        in variables: [MatMetadataVariableInfo],
        fileURL: URL
    ) -> [MaskClassMetadata]? {
        var byName: [String: MatMetadataVariableInfo] = [:]
        for variable in variables {
            byName[variable.name] = variable
        }
        let prefixes = Set(
            variables
                .map(\.name)
                .filter { $0.hasSuffix("_ids") }
                .map { String($0.dropLast(4)) }
        )

        var bestCandidate: MetadataCandidate?

        for prefix in prefixes {
            let idsName = "\(prefix)_ids"
            let namesName = "\(prefix)_names"
            let colorsName = "\(prefix)_colors"
            guard byName[idsName] != nil, byName[namesName] != nil, byName[colorsName] != nil else { continue }

            guard let idsVar = loadMATVariable(from: fileURL, variableName: idsName),
                  let namesVar = loadMATVariable(from: fileURL, variableName: namesName),
                  let colorsVar = loadMATVariable(from: fileURL, variableName: colorsName) else {
                continue
            }

            guard let classIDs = try? parseClassIDs(from: idsVar),
                  !classIDs.isEmpty else { continue }
            guard let classNames = try? parseClassNames(from: namesVar, expectedCount: classIDs.count),
                  !classNames.isEmpty else { continue }
            guard let classColors = try? parseClassColors(from: colorsVar, classCount: classIDs.count),
                  !classColors.isEmpty else { continue }

            var metadata = [MaskClassMetadata]()
            metadata.reserveCapacity(classIDs.count)

            for index in 0..<classIDs.count {
                let name = index < classNames.count && !classNames[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? classNames[index]
                    : LF("mask.class_name_numbered", classIDs[index])
                let color = classColors[index]
                metadata.append(
                    MaskClassMetadata(
                        id: classIDs[index],
                        name: name,
                        colorR: color.r,
                        colorG: color.g,
                        colorB: color.b
                    )
                )
            }

            guard let normalized = try? normalizeMetadata(metadata) else { continue }
            let candidate = MetadataCandidate(
                metadata: normalized,
                score: scoreForMetadataPrefix(prefix)
            )
            if let current = bestCandidate {
                if candidate.score > current.score {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate?.metadata
    }

    private static func loadMetadataByStructuralSimilarity(
        in variables: [MatMetadataVariableInfo],
        fileURL: URL
    ) -> [MaskClassMetadata]? {
        var loadedByName: [String: LoadedMatVariable] = [:]
        for info in variables {
            guard let loaded = loadMATVariable(from: fileURL, variableName: info.name) else { continue }
            loadedByName[info.name] = loaded
        }
        if loadedByName.isEmpty {
            return nil
        }

        struct Candidate {
            let metadata: [MaskClassMetadata]
            let score: Int
        }

        var best: Candidate?
        for (idVarName, idVariable) in loadedByName {
            guard let ids = try? parseClassIDs(from: idVariable), !ids.isEmpty else { continue }

            let expectedCount = ids.count
            let idPrefix = normalizedPrefix(for: idVarName)

            var bestNames: (names: [String], score: Int)?
            var bestColors: (colors: [(r: Double, g: Double, b: Double)], score: Int)?

            for (candidateName, variable) in loadedByName {
                if candidateName == idVarName { continue }

                if let names = try? parseClassNames(from: variable, expectedCount: expectedCount) {
                    let score = scoreNameCandidate(name: candidateName, idPrefix: idPrefix, expectedCount: expectedCount, actualCount: names.count)
                    if bestNames == nil || score > bestNames!.score {
                        bestNames = (names: names, score: score)
                    }
                }

                if let colors = try? parseClassColors(from: variable, classCount: expectedCount) {
                    let score = scoreColorCandidate(name: candidateName, idPrefix: idPrefix)
                    if bestColors == nil || score > bestColors!.score {
                        bestColors = (colors: colors, score: score)
                    }
                }
            }

            guard let colors = bestColors?.colors else { continue }

            let names = bestNames?.names ?? []
            var metadata = [MaskClassMetadata]()
            metadata.reserveCapacity(expectedCount)
            for index in 0..<expectedCount {
                let resolvedName = index < names.count && !names[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? names[index]
                    : LF("mask.class_name_numbered", ids[index])
                let color = colors[index]
                metadata.append(
                    MaskClassMetadata(
                        id: ids[index],
                        name: resolvedName,
                        colorR: color.r,
                        colorG: color.g,
                        colorB: color.b
                    )
                )
            }

            guard let normalized = try? normalizeMetadata(metadata) else { continue }
            let score = scoreIDCandidate(name: idVarName)
                + (bestNames?.score ?? 20)
                + (bestColors?.score ?? 60)
            let candidate = Candidate(metadata: normalized, score: score)
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }

        return best?.metadata
    }

    private static func normalizedPrefix(for variableName: String) -> String {
        let lower = variableName.lowercased()
        let suffixes = ["_ids", "_id", "_classes", "_class", "_labels", "_label", "_idx", "_index"]
        for suffix in suffixes where lower.hasSuffix(suffix) {
            return String(variableName.dropLast(suffix.count))
        }
        return variableName
    }

    private static func scoreIDCandidate(name: String) -> Int {
        let lower = name.lowercased()
        var score = 0
        if lower.contains("id") { score += 35 }
        if lower.contains("class") { score += 30 }
        if lower.contains("label") { score += 25 }
        if lower.contains("mask") { score += 15 }
        if lower.hasSuffix("_ids") || lower.hasSuffix("_id") { score += 20 }
        return score
    }

    private static func scoreNameCandidate(name: String, idPrefix: String, expectedCount: Int, actualCount: Int) -> Int {
        let lower = name.lowercased()
        var score = 0
        if lower.contains("name") { score += 40 }
        if lower.contains("label") { score += 30 }
        if lower.contains("class") { score += 20 }
        if lower.contains("mask") { score += 10 }

        if !idPrefix.isEmpty {
            let prefix = idPrefix.lowercased()
            if lower.hasPrefix(prefix) || prefix.hasPrefix(lower) {
                score += 25
            }
        }

        if actualCount == expectedCount {
            score += 20
        } else if actualCount > expectedCount {
            score += 8
        }

        return score
    }

    private static func scoreColorCandidate(name: String, idPrefix: String) -> Int {
        let lower = name.lowercased()
        var score = 0
        if lower.contains("color") || lower.contains("colour") { score += 50 }
        if lower.contains("palette") || lower.contains("cmap") || lower.contains("colormap") { score += 30 }
        if lower.contains("class") { score += 20 }
        if lower.contains("mask") { score += 10 }

        if !idPrefix.isEmpty {
            let prefix = idPrefix.lowercased()
            if lower.hasPrefix(prefix) || prefix.hasPrefix(lower) {
                score += 25
            }
        }

        return score
    }

    private static func loadMATVariable(from fileURL: URL, variableName: String) -> LoadedMatVariable? {
        var cube = MatCube3D(
            data: nil,
            dims: (0, 0, 0),
            rank: 0,
            data_type: MAT_DATA_FLOAT64
        )
        var nameBuf = [CChar](repeating: 0, count: 256)

        let loaded = fileURL.path.withCString { cPath in
            variableName.withCString { cVar in
                load_2d_array_by_name(cPath, cVar, &cube, &nameBuf, nameBuf.count)
            }
        }

        defer { free_cube(&cube) }

        guard loaded,
              cube.rank == 2,
              cube.dims.0 > 0,
              cube.dims.1 > 0,
              let pointer = cube.data else {
            return nil
        }

        let rows = Int(cube.dims.0)
        let cols = Int(cube.dims.1)
        let count = rows * cols

        var values = [Double]()
        values.reserveCapacity(count)

        switch cube.data_type {
        case MAT_DATA_FLOAT64:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: Double.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer)
        case MAT_DATA_FLOAT32:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: Float.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer.map(Double.init))
        case MAT_DATA_UINT8:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: UInt8.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer.map(Double.init))
        case MAT_DATA_UINT16:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: UInt16.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer.map(Double.init))
        case MAT_DATA_INT8:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: Int8.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer.map(Double.init))
        case MAT_DATA_INT16:
            let buffer = UnsafeBufferPointer(
                start: pointer.bindMemory(to: Int16.self, capacity: count),
                count: count
            )
            values.append(contentsOf: buffer.map(Double.init))
        default:
            return nil
        }

        return LoadedMatVariable(rows: rows, cols: cols, values: values)
    }

    private static func bytesFromNumericVariable(_ variable: LoadedMatVariable) throws -> Data {
        try Data(rawByteValues(from: variable, allowSignedByteReinterpret: true))
    }

    private static func rawByteValues(
        from variable: LoadedMatVariable,
        allowSignedByteReinterpret: Bool
    ) throws -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(variable.values.count)
        for value in variable.values {
            guard value.isFinite else {
                throw MaskMetadataImportError.invalidClassValue("NaN/Inf")
            }
            let rounded = value.rounded()
            if abs(value - rounded) > 0.000001 {
                throw MaskMetadataImportError.invalidClassValue(String(format: "%.6f", value))
            }
            let intValue = Int(rounded)
            if intValue >= 0 && intValue <= 255 {
                bytes.append(UInt8(intValue))
                continue
            }
            if allowSignedByteReinterpret, intValue >= -128 && intValue <= 127 {
                bytes.append(UInt8(bitPattern: Int8(intValue)))
                continue
            }
            throw MaskMetadataImportError.invalidClassValue("\(intValue)")
        }
        return bytes
    }

    private static func decodeMetadataDocument(from data: Data) throws -> [MaskClassMetadata] {
        let decoder = JSONDecoder()

        if let document = try? decoder.decode(MaskMetadataJSONDocument.self, from: data) {
            return try normalizeMetadata(document.classes)
        }

        if let direct = try? decoder.decode([MaskClassMetadata].self, from: data) {
            return try normalizeMetadata(direct)
        }

        throw MaskMetadataImportError.invalidJSON
    }

    private static func normalizeMetadata(_ metadata: [MaskClassMetadata]) throws -> [MaskClassMetadata] {
        var byID: [Int: MaskClassMetadata] = [:]

        for item in metadata {
            guard item.id > 0 && item.id <= 255 else {
                throw MaskMetadataImportError.invalidClassValue("\(item.id)")
            }

            let sanitizedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = sanitizedName.isEmpty ? LF("mask.class_name_numbered", item.id) : item.name
            byID[item.id] = MaskClassMetadata(
                id: item.id,
                name: resolvedName,
                colorR: max(0, min(1, item.colorR)),
                colorG: max(0, min(1, item.colorG)),
                colorB: max(0, min(1, item.colorB))
            )
        }

        let normalized = byID.values.sorted { $0.id < $1.id }
        guard !normalized.isEmpty else {
            throw MaskMetadataImportError.noClasses
        }
        return normalized
    }

    private static func parseClassIDs(from variable: LoadedMatVariable) throws -> [Int] {
        guard variable.rows == 1 || variable.cols == 1 else {
            throw MaskMetadataImportError.invalidJSON
        }

        var ids = [Int]()
        ids.reserveCapacity(variable.values.count)
        for value in variable.values {
            guard value.isFinite else {
                throw MaskMetadataImportError.invalidClassValue("NaN/Inf")
            }
            let rounded = value.rounded()
            if abs(value - rounded) > 0.000001 {
                throw MaskMetadataImportError.invalidClassValue(String(format: "%.6f", value))
            }
            let intValue = Int(rounded)
            guard intValue > 0 && intValue <= 255 else {
                throw MaskMetadataImportError.invalidClassValue("\(intValue)")
            }
            ids.append(intValue)
        }
        return ids
    }

    private static func parseClassNames(from variable: LoadedMatVariable, expectedCount: Int?) throws -> [String] {
        let bytes = try bytesFromNumericVariable(variable)
        let decoder = JSONDecoder()

        if let names = try? decoder.decode([String].self, from: bytes), !names.isEmpty {
            return trimNames(names, expectedCount: expectedCount)
        }

        if let document = try? decoder.decode(MaskMetadataJSONDocument.self, from: bytes), !document.classes.isEmpty {
            let names = document.classes
                .sorted { $0.id < $1.id }
                .map(\.name)
            return trimNames(names, expectedCount: expectedCount)
        }

        if let plainText = String(data: bytes, encoding: .utf8) {
            let parsed = parseNamesFromPlainText(plainText)
            if !parsed.isEmpty {
                return trimNames(parsed, expectedCount: expectedCount)
            }
        }

        let matrixParsed = parseNamesFromByteMatrix(variable: variable)
        if !matrixParsed.isEmpty {
            return trimNames(matrixParsed, expectedCount: expectedCount)
        }

        throw MaskMetadataImportError.invalidJSON
    }

    private static func parseClassColors(
        from variable: LoadedMatVariable,
        classCount: Int
    ) throws -> [(r: Double, g: Double, b: Double)] {
        guard classCount > 0 else { return [] }

        let rows = variable.rows
        let cols = variable.cols
        guard (rows == classCount && cols == 3) || (rows == 3 && cols == classCount) else {
            throw MaskMetadataImportError.invalidJSON
        }

        func matrixValue(row: Int, col: Int) -> Double {
            variable.values[row + rows * col]
        }

        var maxValue = 0.0
        for value in variable.values where value.isFinite {
            maxValue = max(maxValue, value)
        }
        let scale = maxValue > 1.0 ? 255.0 : 1.0

        var result = [(r: Double, g: Double, b: Double)]()
        result.reserveCapacity(classCount)

        for index in 0..<classCount {
            let rRaw: Double
            let gRaw: Double
            let bRaw: Double

            if rows == classCount && cols == 3 {
                rRaw = matrixValue(row: index, col: 0)
                gRaw = matrixValue(row: index, col: 1)
                bRaw = matrixValue(row: index, col: 2)
            } else {
                rRaw = matrixValue(row: 0, col: index)
                gRaw = matrixValue(row: 1, col: index)
                bRaw = matrixValue(row: 2, col: index)
            }

            guard rRaw.isFinite, gRaw.isFinite, bRaw.isFinite else {
                throw MaskMetadataImportError.invalidClassValue("NaN/Inf")
            }

            result.append((
                r: max(0, min(1, rRaw / scale)),
                g: max(0, min(1, gRaw / scale)),
                b: max(0, min(1, bRaw / scale))
            ))
        }

        return result
    }

    private static func parseNamesFromPlainText(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        if trimmed.contains("\n") {
            return trimmed
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if trimmed.contains(";") {
            return trimmed
                .split(separator: ";")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if trimmed.contains(",") {
            return trimmed
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return [trimmed]
    }

    private static func parseNamesFromByteMatrix(variable: LoadedMatVariable) -> [String] {
        let rows = variable.rows
        let cols = variable.cols
        guard rows > 0, cols > 0 else { return [] }

        let byteValues = variable.values.compactMap { value -> UInt8? in
            guard value.isFinite else { return nil }
            let rounded = value.rounded()
            if abs(value - rounded) > 0.000001 { return nil }
            let intValue = Int(rounded)
            if intValue >= 0 && intValue <= 255 {
                return UInt8(intValue)
            }
            if intValue >= -128 && intValue <= 127 {
                return UInt8(bitPattern: Int8(intValue))
            }
            return nil
        }
        guard byteValues.count == variable.values.count else { return [] }

        func columnMajorValue(row: Int, col: Int) -> UInt8 {
            byteValues[row + rows * col]
        }

        var namesByRows = [String]()
        namesByRows.reserveCapacity(rows)
        for row in 0..<rows {
            var buffer = [UInt8]()
            for col in 0..<cols {
                let value = columnMajorValue(row: row, col: col)
                if value == 0 { break }
                buffer.append(value)
            }
            if let string = String(bytes: buffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !string.isEmpty {
                namesByRows.append(string)
            }
        }

        var namesByCols = [String]()
        namesByCols.reserveCapacity(cols)
        for col in 0..<cols {
            var buffer = [UInt8]()
            for row in 0..<rows {
                let value = columnMajorValue(row: row, col: col)
                if value == 0 { break }
                buffer.append(value)
            }
            if let string = String(bytes: buffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !string.isEmpty {
                namesByCols.append(string)
            }
        }

        if namesByRows.count >= 2 || (namesByRows.count == 1 && rows == 1) {
            return namesByRows
        }
        if namesByCols.count >= 2 || (namesByCols.count == 1 && cols == 1) {
            return namesByCols
        }
        return namesByRows.count >= namesByCols.count ? namesByRows : namesByCols
    }

    private static func trimNames(_ names: [String], expectedCount: Int?) -> [String] {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let expectedCount, expectedCount > 0 else { return normalized }
        if normalized.count <= expectedCount { return normalized }
        return Array(normalized.prefix(expectedCount))
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

    private static func scoreForMetadataVariable(name: String) -> Int {
        let lower = name.lowercased()
        if lower == "mask_classes" {
            return 120
        }
        if lower.contains("mask_classes") {
            return 110
        }
        if lower.contains("metadata") {
            return 95
        }
        if lower.contains("class") {
            return 80
        }
        if lower.contains("label") {
            return 65
        }
        return 0
    }

    private static func scoreForMetadataPrefix(_ prefix: String) -> Int {
        scoreForMetadataVariable(name: prefix)
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
