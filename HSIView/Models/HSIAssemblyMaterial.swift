import Foundation
import AppKit
import UniformTypeIdentifiers

struct HSIAssemblyMaterial: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let fileName: String
    let width: Int
    let height: Int
    let colorPaletteDescription: String
    let dataTypeDescription: String
    let channelValues: [UInt8]
    var wavelengthText: String

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        fileName: String,
        width: Int,
        height: Int,
        colorPaletteDescription: String,
        dataTypeDescription: String,
        channelValues: [UInt8],
        wavelengthText: String = ""
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.width = width
        self.height = height
        self.colorPaletteDescription = colorPaletteDescription
        self.dataTypeDescription = dataTypeDescription
        self.channelValues = channelValues
        self.wavelengthText = wavelengthText
    }

    var resolutionDescription: String {
        "\(width) × \(height)"
    }

    var pixelCount: Int {
        width * height
    }

    var isGrayscale: Bool {
        colorPaletteDescription.lowercased().contains("gray")
    }
}

enum HSIAssemblyMaterialLoadError: LocalizedError {
    case unsupportedType
    case failedToReadImage
    case invalidResolution
    case failedToExtractPixels
    case failedToSplitChannels

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Поддерживаются только PNG, JPG и BMP файлы"
        case .failedToReadImage:
            return "Не удалось прочитать изображение"
        case .invalidResolution:
            return "Некорректное разрешение изображения"
        case .failedToExtractPixels:
            return "Не удалось извлечь пиксели изображения"
        case .failedToSplitChannels:
            return "Не удалось разбить изображение на каналы"
        }
    }
}

enum HSIAssemblyMaterialLoader {
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp"]

    static var supportedUTTypes: [UTType] {
        [UTType.png, UTType.jpeg, UTType.bmp]
    }

    static func load(from url: URL) -> Result<HSIAssemblyMaterial, HSIAssemblyMaterialLoadError> {
        let canonical = url.standardizedFileURL
        let ext = canonical.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return .failure(.unsupportedType)
        }

        guard let data = try? Data(contentsOf: canonical),
              let rep = NSBitmapImageRep(data: data) else {
            return .failure(.failedToReadImage)
        }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else {
            return .failure(.invalidResolution)
        }

        let palette = colorPaletteDescription(for: rep)
        let typeDescription = dataTypeDescription(for: rep)

        guard let channelValues = extractLumaChannel(from: rep) else {
            return .failure(.failedToExtractPixels)
        }

        let material = HSIAssemblyMaterial(
            sourceURL: canonical,
            fileName: canonical.lastPathComponent,
            width: width,
            height: height,
            colorPaletteDescription: palette,
            dataTypeDescription: typeDescription,
            channelValues: channelValues
        )
        return .success(material)
    }

    static func splitIntoChannels(from material: HSIAssemblyMaterial) -> Result<[HSIAssemblyMaterial], HSIAssemblyMaterialLoadError> {
        guard let data = try? Data(contentsOf: material.sourceURL),
              let rep = NSBitmapImageRep(data: data) else {
            return .failure(.failedToReadImage)
        }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else {
            return .failure(.invalidResolution)
        }

        if rep.colorSpace.colorSpaceModel == .gray {
            return .success([material])
        }

        let pixelCount = width * height
        var red = [UInt8](repeating: 0, count: pixelCount)
        var green = [UInt8](repeating: 0, count: pixelCount)
        var blue = [UInt8](repeating: 0, count: pixelCount)
        var alpha = [UInt8](repeating: 255, count: pixelCount)
        var hasAlpha = false

        for y in 0..<height {
            for x in 0..<width {
                guard let color = rep.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.deviceRGB) else {
                    return .failure(.failedToSplitChannels)
                }
                let idx = y * width + x
                red[idx] = UInt8(clamping: Int((rgb.redComponent * 255.0).rounded()))
                green[idx] = UInt8(clamping: Int((rgb.greenComponent * 255.0).rounded()))
                blue[idx] = UInt8(clamping: Int((rgb.blueComponent * 255.0).rounded()))
                alpha[idx] = UInt8(clamping: Int((rgb.alphaComponent * 255.0).rounded()))
                hasAlpha = hasAlpha || rgb.alphaComponent < 1.0
            }
        }

        let baseName = material.sourceURL.deletingPathExtension().lastPathComponent
        let ext = material.sourceURL.pathExtension
        let fileNameWithSuffix: (String) -> String = { suffix in
            if ext.isEmpty {
                return "\(baseName) [\(suffix)]"
            }
            return "\(baseName) [\(suffix)].\(ext)"
        }

        var materials: [HSIAssemblyMaterial] = [
            HSIAssemblyMaterial(
                sourceURL: material.sourceURL,
                fileName: fileNameWithSuffix("R"),
                width: width,
                height: height,
                colorPaletteDescription: "Grayscale",
                dataTypeDescription: "UInt8",
                channelValues: red,
                wavelengthText: ""
            ),
            HSIAssemblyMaterial(
                sourceURL: material.sourceURL,
                fileName: fileNameWithSuffix("G"),
                width: width,
                height: height,
                colorPaletteDescription: "Grayscale",
                dataTypeDescription: "UInt8",
                channelValues: green,
                wavelengthText: ""
            ),
            HSIAssemblyMaterial(
                sourceURL: material.sourceURL,
                fileName: fileNameWithSuffix("B"),
                width: width,
                height: height,
                colorPaletteDescription: "Grayscale",
                dataTypeDescription: "UInt8",
                channelValues: blue,
                wavelengthText: ""
            )
        ]

        if hasAlpha {
            materials.append(
                HSIAssemblyMaterial(
                    sourceURL: material.sourceURL,
                    fileName: fileNameWithSuffix("A"),
                    width: width,
                    height: height,
                    colorPaletteDescription: "Grayscale",
                    dataTypeDescription: "UInt8",
                    channelValues: alpha,
                    wavelengthText: ""
                )
            )
        }

        return .success(materials)
    }

    private static func colorPaletteDescription(for rep: NSBitmapImageRep) -> String {
        let colorSpace = rep.colorSpace
        switch colorSpace.colorSpaceModel {
        case .gray:
            return "Grayscale"
        case .rgb:
            return rep.samplesPerPixel >= 4 ? "RGBA" : "RGB"
        case .cmyk:
            return "CMYK"
        case .indexed:
            return "Indexed"
        default:
            return "Unknown"
        }
    }

    private static func dataTypeDescription(for rep: NSBitmapImageRep) -> String {
        let bits = rep.bitsPerSample
        if bits <= 8 {
            return "UInt8"
        }
        if bits <= 16 {
            return "UInt16"
        }
        return "Float32"
    }

    private static func extractLumaChannel(from rep: NSBitmapImageRep) -> [UInt8]? {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard let color = rep.colorAt(x: x, y: y) else { return nil }
                let luma: Double
                if let rgbColor = color.usingColorSpace(.deviceRGB) {
                    luma = 0.2126 * rgbColor.redComponent + 0.7152 * rgbColor.greenComponent + 0.0722 * rgbColor.blueComponent
                } else if let grayColor = color.usingColorSpace(.deviceGray) {
                    luma = grayColor.whiteComponent
                } else {
                    return nil
                }
                let idx = y * width + x
                values[idx] = UInt8(clamping: Int((luma * 255.0).rounded()))
            }
        }
        return values
    }
}
