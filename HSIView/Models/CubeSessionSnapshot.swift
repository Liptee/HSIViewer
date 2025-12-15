import Foundation
import CoreGraphics

struct CubeSessionSnapshot {
    var pipelineOperations: [PipelineOperation]
    var pipelineAutoApply: Bool
    var wavelengths: [Double]?
    var lambdaStart: String
    var lambdaEnd: String
    var lambdaStep: String
    var trimStart: Double
    var trimEnd: Double
    var spectralTrimRange: ClosedRange<Int>?
    var normalizationType: CubeNormalizationType
    var normalizationParams: CubeNormalizationParameters
    var autoScaleOnTypeConversion: Bool
    var layout: CubeLayout
    var viewMode: ViewMode
    var currentChannel: Double
    var zoomScale: CGFloat
    var imageOffset: CGSize
}
