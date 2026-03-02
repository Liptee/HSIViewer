import Foundation

class CubeCalibrator {
    static func calibrate(cube: HyperCube, parameters: CalibrationParameters, layout: CubeLayout) -> HyperCube? {
        let dims = cube.dims
        let dimsArray = [dims.0, dims.1, dims.2]
        
        guard let axes = cube.axes(for: layout) else { return cube }
        
        let channels = dimsArray[axes.channel]
        let height = dimsArray[axes.height]
        let width = dimsArray[axes.width]
        
        guard channels > 0, height > 0, width > 0 else { return cube }
        
        let whiteSpectrum = parameters.whiteSpectrum?.values
        let blackSpectrum = parameters.blackSpectrum?.values
        let whiteRef = parameters.whiteRef
        let blackRef = parameters.blackRef
        let hasWhite = whiteSpectrum != nil || whiteRef != nil
        let hasBlack = blackSpectrum != nil || blackRef != nil
        
        guard hasWhite || hasBlack else { return cube }
        
        if let white = whiteSpectrum, white.count != channels { return cube }
        if let black = blackSpectrum, black.count != channels { return cube }
        
        let scanAxisSize = width
        let canUseWhiteRef = whiteRef?.channels == channels && whiteRef?.scanLength == scanAxisSize
        let canUseBlackRef = blackRef?.channels == channels && blackRef?.scanLength == scanAxisSize
        
        let targetMin = parameters.targetMin
        let targetMax = parameters.targetMax
        
        let swapSpatial = parameters.useScanDirection && (parameters.scanDirection == .leftToRight || parameters.scanDirection == .rightToLeft)
        var newDims = [dims.0, dims.1, dims.2]
        if swapSpatial {
            newDims[axes.height] = width
            newDims[axes.width] = height
        }
        
        let totalElements = newDims[0] * newDims[1] * newDims[2]
        var resultData = [Double](repeating: 0, count: totalElements)
        
        for h in 0..<height {
            for w in 0..<width {
                let destH: Int
                let destW: Int
                if parameters.useScanDirection {
                    switch parameters.scanDirection {
                    case .topToBottom:
                        destH = h
                        destW = w
                    case .bottomToTop:
                        destH = height - 1 - h
                        destW = w
                    case .leftToRight:
                        destH = w
                        destW = h
                    case .rightToLeft:
                        destH = w
                        destW = height - 1 - h
                    }
                } else {
                    destH = h
                    destW = w
                }
                
                for ch in 0..<channels {
                    let blackVal: Double
                    if canUseBlackRef, let ref = blackRef {
                        blackVal = ref.value(channel: ch, scanIndex: w)
                    } else {
                        blackVal = blackSpectrum?[ch] ?? 0.0
                    }
                    
                    var indices = [0, 0, 0]
                    indices[axes.channel] = ch
                    indices[axes.height] = h
                    indices[axes.width] = w
                    
                    let srcIndex = cube.linearIndex(i0: indices[0], i1: indices[1], i2: indices[2])
                    let value = cube.getValue(at: srcIndex)
                    
                    let clamped: Double
                    if hasWhite {
                        let whiteVal: Double
                        if canUseWhiteRef, let ref = whiteRef {
                            whiteVal = ref.value(channel: ch, scanIndex: w)
                        } else {
                            whiteVal = whiteSpectrum?[ch] ?? 1.0
                        }
                        
                        let range = whiteVal - blackVal
                        let normalized: Double
                        if range > 0 {
                            normalized = (value - blackVal) / range
                        } else {
                            normalized = 0.0
                        }
                        
                        let scaled = targetMin + normalized * (targetMax - targetMin)
                        if parameters.clampOutput {
                            clamped = max(targetMin, min(targetMax, scaled))
                        } else {
                            clamped = scaled
                        }
                    } else {
                        let adjusted = value - blackVal
                        if parameters.clampOutput {
                            clamped = max(targetMin, min(targetMax, adjusted))
                        } else {
                            clamped = adjusted
                        }
                    }
                    
                    var dstIndices = [0, 0, 0]
                    dstIndices[axes.channel] = ch
                    dstIndices[axes.height] = destH
                    dstIndices[axes.width] = destW
                    
                    let dstIndex = linearIndex(
                        i0: dstIndices[0],
                        i1: dstIndices[1],
                        i2: dstIndices[2],
                        dims: (newDims[0], newDims[1], newDims[2]),
                        fortran: cube.isFortranOrder
                    )
                    resultData[dstIndex] = clamped
                }
            }
        }
        
        return HyperCube(
            dims: (newDims[0], newDims[1], newDims[2]),
            storage: .float64(resultData),
            sourceFormat: cube.sourceFormat,
            isFortranOrder: cube.isFortranOrder,
            wavelengths: cube.wavelengths,
            geoReference: cube.geoReference
        )
    }
    
    private static func linearIndex(
        i0: Int,
        i1: Int,
        i2: Int,
        dims: (Int, Int, Int),
        fortran: Bool
    ) -> Int {
        if fortran {
            return i0 + dims.0 * (i1 + dims.1 * i2)
        } else {
            return i2 + dims.2 * (i1 + dims.1 * i0)
        }
    }
}

