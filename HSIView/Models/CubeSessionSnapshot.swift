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
    var maskLayerSamples: [SpectrumMaskLayerSampleDescriptor]
    var rulerPoints: [RulerPointDescriptor]
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
    var maskEditorSnapshot: MaskEditorSnapshotDescriptor?
    
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
        maskLayerSamples: [],
        rulerPoints: [],
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
        ndThreshold: 0.3,
        maskEditorSnapshot: nil
    )
}

struct MaskEditorSnapshotDescriptor: Equatable {
    var width: Int
    var height: Int
    var referenceVisible: Bool
    var activeClassValue: UInt8?
    var layers: [MaskLayerSnapshotDescriptor]
}

struct MaskLayerSnapshotDescriptor: Equatable {
    var name: String
    var classValue: UInt8
    var colorR: Double
    var colorG: Double
    var colorB: Double
    var opacity: Double
    var visible: Bool
    var locked: Bool
    var activeForDrawing: Bool
    var data: [UInt8]
}

struct SpectrumSampleDescriptor: Equatable {
    var id: UUID
    var pixelX: Int
    var pixelY: Int
    var colorIndex: Int
    var displayName: String?
    var values: [Double]
    var wavelengths: [Double]?
    
    init(id: UUID, pixelX: Int, pixelY: Int, colorIndex: Int, displayName: String? = nil, values: [Double] = [], wavelengths: [Double]? = nil) {
        self.id = id
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.colorIndex = colorIndex
        self.displayName = displayName
        self.values = values
        self.wavelengths = wavelengths
    }
}

struct SpectrumROISampleDescriptor: Equatable {
    var id: UUID
    var minX: Int
    var minY: Int
    var width: Int
    var height: Int
    var colorIndex: Int
    var displayName: String?
    var values: [Double]
    var wavelengths: [Double]?
    
    var rect: SpectrumROIRect {
        SpectrumROIRect(minX: minX, minY: minY, width: width, height: height)
    }
    
    init(id: UUID, minX: Int, minY: Int, width: Int, height: Int, colorIndex: Int, displayName: String? = nil, values: [Double] = [], wavelengths: [Double]? = nil) {
        self.id = id
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
        self.colorIndex = colorIndex
        self.displayName = displayName
        self.values = values
        self.wavelengths = wavelengths
    }
}

struct SpectrumMaskLayerSampleDescriptor: Equatable {
    var id: UUID
    var layerID: UUID
    var classValue: UInt8
    var colorIndex: Int
    var displayName: String?
    var values: [Double]
    var wavelengths: [Double]?

    init(
        id: UUID,
        layerID: UUID,
        classValue: UInt8,
        colorIndex: Int,
        displayName: String? = nil,
        values: [Double] = [],
        wavelengths: [Double]? = nil
    ) {
        self.id = id
        self.layerID = layerID
        self.classValue = classValue
        self.colorIndex = colorIndex
        self.displayName = displayName
        self.values = values
        self.wavelengths = wavelengths
    }
}

struct RulerPointDescriptor: Equatable {
    var id: UUID
    var pixelX: Int
    var pixelY: Int

    init(id: UUID, pixelX: Int, pixelY: Int) {
        self.id = id
        self.pixelX = pixelX
        self.pixelY = pixelY
    }
}
