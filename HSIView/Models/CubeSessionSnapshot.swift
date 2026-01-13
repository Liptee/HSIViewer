import Foundation
import CoreGraphics

struct CubeSessionSnapshot {
    var pipelineOperations: [PipelineOperation]
    var pipelineAutoApply: Bool
    var wavelengths: [Double]?
    var baseWavelengths: [Double]?
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
    var spectrumSamples: [SpectrumSampleDescriptor]
    var roiSamples: [SpectrumROISampleDescriptor]
    var roiAggregationMode: SpectrumROIAggregationMode
    var colorSynthesisConfig: ColorSynthesisConfig
    var ndPreset: NDIndexPreset
    var ndviRedTarget: String
    var ndviNIRTarget: String
    var ndsiGreenTarget: String
    var ndsiSWIRTarget: String
    var wdviSlope: String
    var wdviIntercept: String
    var ndPaletteRaw: String
    var ndThreshold: Double
    
    static let empty = CubeSessionSnapshot(
        pipelineOperations: [],
        pipelineAutoApply: true,
        wavelengths: nil,
        baseWavelengths: nil,
        lambdaStart: "400",
        lambdaEnd: "1000",
        lambdaStep: "",
        trimStart: 0,
        trimEnd: 0,
        spectralTrimRange: nil,
        normalizationType: .none,
        normalizationParams: .default,
        autoScaleOnTypeConversion: true,
        layout: .auto,
        viewMode: .gray,
        currentChannel: 0,
        zoomScale: 1.0,
        imageOffset: .zero,
        spectrumSamples: [],
        roiSamples: [],
        roiAggregationMode: .mean,
        colorSynthesisConfig: .default(channelCount: 0, wavelengths: nil),
        ndPreset: .ndvi,
        ndviRedTarget: "660",
        ndviNIRTarget: "840",
        ndsiGreenTarget: "555",
        ndsiSWIRTarget: "1610",
        wdviSlope: "1.0",
        wdviIntercept: "0.0",
        ndPaletteRaw: NDPalette.classic.rawValue,
        ndThreshold: 0.3
    )
}

struct SpectrumSampleDescriptor: Equatable {
    var id: UUID
    var pixelX: Int
    var pixelY: Int
    var colorIndex: Int
    var displayName: String?
}

struct SpectrumROISampleDescriptor: Equatable {
    var id: UUID
    var minX: Int
    var minY: Int
    var width: Int
    var height: Int
    var colorIndex: Int
    var displayName: String?
    
    var rect: SpectrumROIRect {
        SpectrumROIRect(minX: minX, minY: minY, width: width, height: height)
    }
}
