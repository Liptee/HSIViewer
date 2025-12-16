import Foundation

struct CubeExportPayload {
    let cube: HyperCube
    let wavelengths: [Double]?
    let layout: CubeLayout
    let baseName: String
}
