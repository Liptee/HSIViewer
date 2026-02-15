import Foundation

enum EnviBinaryFileType: String, CaseIterable, Identifiable {
    case dat
    case raw

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var title: String {
        switch self {
        case .dat:
            return L("export.envi.binary_type.dat")
        case .raw:
            return L("export.envi.binary_type.raw")
        }
    }
}

enum EnviInterleave: String, CaseIterable, Identifiable {
    case bsq = "BSQ"
    case bil = "BIL"
    case bip = "BIP"

    var id: String { rawValue }

    var title: String {
        rawValue
    }

    var headerValue: String {
        rawValue.lowercased()
    }
}

enum EnviByteOrder: Int, CaseIterable, Identifiable {
    case littleEndian = 0
    case bigEndian = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .littleEndian:
            return L("export.envi.byte_order.little")
        case .bigEndian:
            return L("export.envi.byte_order.big")
        }
    }
}

enum EnviExportDataType: String, CaseIterable, Identifiable {
    case uint8
    case int16
    case int32
    case float32
    case float64
    case uint16

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uint8:
            return "UInt8 (ENVI 1)"
        case .int16:
            return "Int16 (ENVI 2)"
        case .int32:
            return "Int32 (ENVI 3)"
        case .float32:
            return "Float32 (ENVI 4)"
        case .float64:
            return "Float64 (ENVI 5)"
        case .uint16:
            return "UInt16 (ENVI 12)"
        }
    }

    var enviCode: Int {
        switch self {
        case .uint8: return 1
        case .int16: return 2
        case .int32: return 3
        case .float32: return 4
        case .float64: return 5
        case .uint16: return 12
        }
    }

    var bytesPerSample: Int {
        switch self {
        case .uint8: return 1
        case .int16: return 2
        case .int32, .float32: return 4
        case .float64: return 8
        case .uint16: return 2
        }
    }

    static func defaultFor(sourceDataType: DataType) -> EnviExportDataType {
        switch sourceDataType {
        case .uint8:
            return .uint8
        case .int16:
            return .int16
        case .int32:
            return .int32
        case .float32:
            return .float32
        case .float64:
            return .float64
        case .uint16:
            return .uint16
        case .int8, .unknown:
            return .float32
        }
    }
}

enum EnviDefaultBandsMode: String, CaseIterable, Identifiable {
    case colorSynthesis
    case specimPreset
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colorSynthesis:
            return L("export.envi.default_bands.mode.color_synthesis")
        case .specimPreset:
            return L("export.envi.default_bands.mode.specim")
        case .custom:
            return L("export.envi.default_bands.mode.custom")
        }
    }
}

struct EnviDefaultBands: Equatable {
    var red: Int
    var green: Int
    var blue: Int
}

struct EnviExportOptions: Equatable {
    var binaryFileType: EnviBinaryFileType
    var interleave: EnviInterleave
    var dataType: EnviExportDataType
    var byteOrder: EnviByteOrder
    var description: String
    var fileType: String
    var sensorType: String
    var includeDefaultBands: Bool
    var defaultBandsMode: EnviDefaultBandsMode
    var customDefaultBands: EnviDefaultBands
    var includeAcquisitionDate: Bool
    var acquisitionDate: Date
    var includeCoordinates: Bool
    var latitude: Double
    var longitude: Double
    var wavelengthUnits: String
    var additionalHeaderFields: String

    static func `default`(
        binaryFileType: EnviBinaryFileType = .dat,
        sourceDataType: DataType = .float32
    ) -> EnviExportOptions {
        EnviExportOptions(
            binaryFileType: binaryFileType,
            interleave: .bil,
            dataType: EnviExportDataType.defaultFor(sourceDataType: sourceDataType),
            byteOrder: .littleEndian,
            description: "Export via HSIView by Liptee",
            fileType: "ENVI",
            sensorType: "Unknown",
            includeDefaultBands: true,
            defaultBandsMode: .colorSynthesis,
            customDefaultBands: EnviDefaultBands(red: 70, green: 53, blue: 19),
            includeAcquisitionDate: false,
            acquisitionDate: Date(),
            includeCoordinates: false,
            latitude: 0.0,
            longitude: 0.0,
            wavelengthUnits: "nm",
            additionalHeaderFields: ""
        )
    }
}

private enum EnviExportError: Error, LocalizedError {
    case invalidLayout
    case failedToCreateFile(String)
    case invalidAdditionalHeaderField(line: Int)

    var errorDescription: String? {
        switch self {
        case .invalidLayout:
            return L("export.envi.error.invalid_layout")
        case .failedToCreateFile(let path):
            return LF("export.envi.error.failed_to_create_file", path)
        case .invalidAdditionalHeaderField(let line):
            return LF("export.envi.error.invalid_additional_field_line", line)
        }
    }
}

final class EnviExporter {
    private static let additionalReservedKeys: Set<String> = [
        "description",
        "samples",
        "lines",
        "bands",
        "header offset",
        "file type",
        "data type",
        "interleave",
        "byte order",
        "default bands",
        "wavelength",
        "wavelength units",
        "sensor type",
        "latitude",
        "longitude",
        "acquisition date"
    ]

    static func export(
        cube: HyperCube,
        to requestedURL: URL,
        wavelengths: [Double]?,
        layout: CubeLayout = .auto,
        options: EnviExportOptions,
        colorSynthesisConfig: ColorSynthesisConfig? = nil
    ) -> Result<Void, Error> {
        do {
            let baseURL = requestedURL.deletingPathExtension()
            let dataURL = baseURL.appendingPathExtension(options.binaryFileType.fileExtension)
            let hdrURL = baseURL.appendingPathExtension("hdr")

            if FileManager.default.fileExists(atPath: dataURL.path) {
                try FileManager.default.removeItem(at: dataURL)
            }
            if FileManager.default.fileExists(atPath: hdrURL.path) {
                try FileManager.default.removeItem(at: hdrURL)
            }

            let dims = cube.dims
            let dimsArray = [dims.0, dims.1, dims.2]
            guard let axes = cube.axes(for: layout) else {
                return .failure(EnviExportError.invalidLayout)
            }

            let width = dimsArray[axes.width]
            let height = dimsArray[axes.height]
            let channels = dimsArray[axes.channel]

            try writeBinary(
                cube: cube,
                dataURL: dataURL,
                axes: axes,
                width: width,
                height: height,
                channels: channels,
                options: options
            )

            let header = try buildHeaderText(
                width: width,
                height: height,
                channels: channels,
                wavelengths: wavelengths,
                options: options,
                colorSynthesisConfig: colorSynthesisConfig
            )
            try header.write(to: hdrURL, atomically: true, encoding: .utf8)

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func buildHeaderText(
        width: Int,
        height: Int,
        channels: Int,
        wavelengths: [Double]?,
        options: EnviExportOptions,
        colorSynthesisConfig: ColorSynthesisConfig?
    ) throws -> String {
        var lines: [String] = []
        lines.append("ENVI")
        lines.append("description = {")
        lines.append(options.description.isEmpty ? "Export via HSIView by Liptee" : options.description)
        lines.append("}")
        lines.append("samples = \(width)")
        lines.append("lines = \(height)")
        lines.append("bands = \(channels)")
        lines.append("header offset = 0")
        lines.append("file type = \(options.fileType)")
        lines.append("data type = \(options.dataType.enviCode)")
        lines.append("interleave = \(options.interleave.headerValue)")
        lines.append("byte order = \(options.byteOrder.rawValue)")

        let sensorType = options.sensorType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sensorType.isEmpty {
            lines.append("sensor type = \(sensorType)")
        }

        if options.includeAcquisitionDate {
            lines.append("acquisition date = \(formatAcquisitionDate(options.acquisitionDate))")
        }

        if options.includeCoordinates {
            lines.append(String(format: "latitude = %.8f", options.latitude))
            lines.append(String(format: "longitude = %.8f", options.longitude))
        }

        if options.includeDefaultBands, let defaultBands = resolvedDefaultBands(
            channels: channels,
            options: options,
            colorSynthesisConfig: colorSynthesisConfig
        ) {
            lines.append("default bands = {")
            lines.append("\(defaultBands[0]),")
            lines.append("\(defaultBands[1]),")
            lines.append("\(defaultBands[2])")
            lines.append("}")
        }

        if let wavelengths, !wavelengths.isEmpty {
            let units = options.wavelengthUnits.trimmingCharacters(in: .whitespacesAndNewlines)
            if !units.isEmpty {
                lines.append("wavelength units = \(units)")
            }
            lines.append("wavelength = {")
            for (index, lambda) in wavelengths.enumerated() {
                let suffix = index < wavelengths.count - 1 ? "," : ""
                lines.append("\(formatWavelength(lambda))\(suffix)")
            }
            lines.append("}")
        }

        let additionalFields = try parseAdditionalHeaderFields(options.additionalHeaderFields)
        lines.append(contentsOf: additionalFields)

        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseAdditionalHeaderFields(_ raw: String) throws -> [String] {
        let sourceLines = raw.components(separatedBy: .newlines)
        var output: [String] = []
        output.reserveCapacity(sourceLines.count)

        for (idx, sourceLine) in sourceLines.enumerated() {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw EnviExportError.invalidAdditionalHeaderField(line: idx + 1)
            }

            let key = line[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let keyLowercased = key.lowercased()
            if additionalReservedKeys.contains(keyLowercased) {
                continue
            }

            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            output.append("\(key) = \(value)")
        }

        return output
    }

    private static func resolvedDefaultBands(
        channels: Int,
        options: EnviExportOptions,
        colorSynthesisConfig: ColorSynthesisConfig?
    ) -> [Int]? {
        guard channels > 0 else { return nil }

        switch options.defaultBandsMode {
        case .colorSynthesis:
            if let config = colorSynthesisConfig {
                switch config.mode {
                case .trueColorRGB:
                    let mapping = config.mapping.clamped(maxChannelCount: channels)
                    return [
                        clampBand(index: mapping.red, channels: channels),
                        clampBand(index: mapping.green, channels: channels),
                        clampBand(index: mapping.blue, channels: channels)
                    ]
                case .rangeWideRGB:
                    let mapping = config.rangeMapping.clamped(maxChannelCount: channels)
                    return [
                        clampBand(index: (mapping.red.start + mapping.red.end) / 2, channels: channels),
                        clampBand(index: (mapping.green.start + mapping.green.end) / 2, channels: channels),
                        clampBand(index: (mapping.blue.start + mapping.blue.end) / 2, channels: channels)
                    ]
                case .pcaVisualization:
                    break
                }
            }
            return [
                clampBand(index: 69, channels: channels),
                clampBand(index: 52, channels: channels),
                clampBand(index: 18, channels: channels)
            ]
        case .specimPreset:
            return [
                clampBand(index: 69, channels: channels),
                clampBand(index: 52, channels: channels),
                clampBand(index: 18, channels: channels)
            ]
        case .custom:
            return [
                max(1, min(options.customDefaultBands.red, channels)),
                max(1, min(options.customDefaultBands.green, channels)),
                max(1, min(options.customDefaultBands.blue, channels))
            ]
        }
    }

    private static func clampBand(index: Int, channels: Int) -> Int {
        max(1, min(index + 1, channels))
    }

    private static func formatWavelength(_ value: Double) -> String {
        String(format: "%.8f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func formatAcquisitionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    private static func writeBinary(
        cube: HyperCube,
        dataURL: URL,
        axes: (channel: Int, height: Int, width: Int),
        width: Int,
        height: Int,
        channels: Int,
        options: EnviExportOptions
    ) throws {
        let path = dataURL.path
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw EnviExportError.failedToCreateFile(path)
        }
        let handle = try FileHandle(forWritingTo: dataURL)
        defer {
            try? handle.close()
        }

        let flushThreshold = 1 << 20
        var buffer = Data()
        buffer.reserveCapacity(flushThreshold)

        func flushBuffer() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }

        func appendByte(_ value: UInt8) throws {
            buffer.append(value)
            if buffer.count >= flushThreshold {
                try flushBuffer()
            }
        }

        func appendValue<T>(_ value: T) throws {
            var mutable = value
            withUnsafeBytes(of: &mutable) { ptr in
                buffer.append(ptr.bindMemory(to: UInt8.self))
            }
            if buffer.count >= flushThreshold {
                try flushBuffer()
            }
        }

        func linearIndex(channel: Int, row: Int, col: Int) -> Int {
            var i0 = 0
            var i1 = 0
            var i2 = 0

            switch axes.channel {
            case 0: i0 = channel
            case 1: i1 = channel
            default: i2 = channel
            }

            switch axes.height {
            case 0: i0 = row
            case 1: i1 = row
            default: i2 = row
            }

            switch axes.width {
            case 0: i0 = col
            case 1: i1 = col
            default: i2 = col
            }

            return cube.linearIndex(i0: i0, i1: i1, i2: i2)
        }

        func appendSample(_ value: Double) throws {
            let finiteValue = value.isFinite ? value : 0
            switch options.dataType {
            case .uint8:
                let converted = UInt8(clamping: Int(finiteValue.rounded()))
                try appendByte(converted)
            case .int16:
                let converted = Int16(clamping: Int(finiteValue.rounded()))
                let ordered = options.byteOrder == .littleEndian ? converted.littleEndian : converted.bigEndian
                try appendValue(ordered)
            case .int32:
                let converted = Int32(clamping: Int(finiteValue.rounded()))
                let ordered = options.byteOrder == .littleEndian ? converted.littleEndian : converted.bigEndian
                try appendValue(ordered)
            case .float32:
                let converted = Float(finiteValue)
                let bits = options.byteOrder == .littleEndian ? converted.bitPattern.littleEndian : converted.bitPattern.bigEndian
                try appendValue(bits)
            case .float64:
                let converted = finiteValue
                let bits = options.byteOrder == .littleEndian ? converted.bitPattern.littleEndian : converted.bitPattern.bigEndian
                try appendValue(bits)
            case .uint16:
                let converted = UInt16(clamping: Int(finiteValue.rounded()))
                let ordered = options.byteOrder == .littleEndian ? converted.littleEndian : converted.bigEndian
                try appendValue(ordered)
            }
        }

        switch options.interleave {
        case .bsq:
            for c in 0..<channels {
                for h in 0..<height {
                    for w in 0..<width {
                        let idx = linearIndex(channel: c, row: h, col: w)
                        try appendSample(cube.storage.getValue(at: idx))
                    }
                }
            }
        case .bil:
            for h in 0..<height {
                for c in 0..<channels {
                    for w in 0..<width {
                        let idx = linearIndex(channel: c, row: h, col: w)
                        try appendSample(cube.storage.getValue(at: idx))
                    }
                }
            }
        case .bip:
            for h in 0..<height {
                for w in 0..<width {
                    for c in 0..<channels {
                        let idx = linearIndex(channel: c, row: h, col: w)
                        try appendSample(cube.storage.getValue(at: idx))
                    }
                }
            }
        }

        try flushBuffer()
    }
}
