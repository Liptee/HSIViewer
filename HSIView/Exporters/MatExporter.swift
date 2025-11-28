import Foundation

class MatExporter {
    static func export(cube: HyperCube, to url: URL, exportWavelengths: Bool) -> Result<Void, Error> {
        return .failure(ExportError.unsupportedDataType)
    }
}

