import Foundation

class CubeWhitePointAutoDetector {
    private struct CandidateWindow {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let score: Double
        let brightnessScore: Double
        let flatnessScore: Double
        let dispersionScore: Double
        let homogeneityScore: Double
        let contrastScore: Double
        let glarePenalty: Double
    }

    private struct PresetTuning {
        let downsampleDivisor: Double
        let glarePercentile: Double
        let minBrightnessPercentile: Double
        let targetBrightnessPercentile: Double
        let highlightPercentile: Double
        let minNeutrality: Double
        let minAreaFraction: Double
        let areaScoreEdge0: Double
        let areaScoreEdge1: Double
        let windowFractions: [Double]
        let aspectRatios: [Double]
        let glareRatioWeight: Double
        let glareHintWeight: Double
        let glareGradientLow: Double
        let glareGradientHigh: Double
        let glareRejectThreshold: Double
        let shapeAspectNeutral: Double
        let shapeAspectSpread: Double
        let wBrightness: Double
        let wLocalHomogeneity: Double
        let wFlatness: Double
        let wDispersion: Double
        let wSpectralHomogeneity: Double
        let wContrast: Double
        let wNeutrality: Double
        let wArea: Double
        let wShape: Double
        let glarePenaltyWeight: Double
        let minDispersionScore: Double
    }

    private struct WindowSearchTuning {
        let fractionScale: Double
        let additionalFractions: [Double]
        let additionalAspectRatios: [Double]
        let stepDivisor: Double
        let minStep: Int
        let sizeSelectionStride: Int
    }

    static func findCandidates(
        cube: HyperCube,
        layout: CubeLayout,
        preset: WhitePointSearchPreset = .balanced,
        windowPreset: WhitePointWindowPreset = .balanced,
        factorWeights: WhitePointSearchFactorWeights = .identity,
        maxCandidates: Int = 8,
        progressCallback: ((WhitePointSearchProgressInfo) -> Void)? = nil
    ) -> WhitePointSearchResult? {
        guard let axes = cube.axes(for: layout) else { return nil }
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let width = dims[axes.width]
        let height = dims[axes.height]
        let channels = dims[axes.channel]
        guard width > 0, height > 0, channels > 0 else { return nil }
        let tuning = tuning(for: preset)

        let weightBrightness = tuning.wBrightness * max(0.0, factorWeights.brightness)
        let weightLocalHomogeneity = tuning.wLocalHomogeneity * max(0.0, factorWeights.localHomogeneity)
        let weightFlatness = tuning.wFlatness * max(0.0, factorWeights.spectralFlatness)
        let weightDispersion = tuning.wDispersion * max(0.0, factorWeights.spectralDispersion)
        let weightSpectralHomogeneity = tuning.wSpectralHomogeneity * max(0.0, factorWeights.spectralHomogeneity)
        let weightContrast = tuning.wContrast * max(0.0, factorWeights.contrast)
        let weightNeutrality = tuning.wNeutrality * max(0.0, factorWeights.neutrality)
        let weightArea = tuning.wArea * max(0.0, factorWeights.area)
        let weightShape = tuning.wShape * max(0.0, factorWeights.shape)
        let weightGlarePenalty = tuning.glarePenaltyWeight * max(0.0, factorWeights.glarePenalty)

        progressCallback?(
            WhitePointSearchProgressInfo(
                progress: 0.02,
                message: L("Подготовка данных сцены…"),
                evaluatedCandidates: 0,
                totalCandidates: 1,
                stage: "prepare"
            )
        )

        let sampledChannels = selectedChannels(totalChannels: channels, wavelengths: cube.wavelengths)
        guard !sampledChannels.isEmpty else { return nil }

        let downsampleFactor = max(1, Int(ceil(Double(max(width, height)) / max(tuning.downsampleDivisor, 1.0))))
        let downsampledWidth = max(1, width / downsampleFactor)
        let downsampledHeight = max(1, height / downsampleFactor)
        let totalPixels = downsampledWidth * downsampledHeight

        var channelSlices: [[Double]] = []
        channelSlices.reserveCapacity(sampledChannels.count)
        for channel in sampledChannels {
            let full = extractChannel(cube: cube, channel: channel, axes: axes)
            let sampled = downsampleMean(full, width: width, height: height, factor: downsampleFactor).data
            if sampled.count == totalPixels {
                channelSlices.append(sampled)
            }
        }
        guard channelSlices.count == sampledChannels.count else { return nil }

        let brightness = buildBrightnessMap(channelSlices: channelSlices)
        guard brightness.count == totalPixels else { return nil }
        let brightnessSquared = brightness.map { $0 * $0 }
        let gradientMap = sobelMagnitude(data: brightness, width: downsampledWidth, height: downsampledHeight)
        let glareThreshold = percentile(values: brightness, fraction: tuning.glarePercentile)
        let globalSampledSpectrum = channelSlices.map { slice in
            guard !slice.isEmpty else { return 0.0 }
            return slice.reduce(0.0, +) / Double(slice.count)
        }

        let neutralMap = buildNeutralityMap(
            channelSlices: channelSlices,
            wavelengths: cube.wavelengths,
            sampledChannels: sampledChannels
        )
        guard neutralMap.count == totalPixels else { return nil }

        let brightIntegral = integralImage(data: brightness, width: downsampledWidth, height: downsampledHeight)
        let brightSqIntegral = integralImage(data: brightnessSquared, width: downsampledWidth, height: downsampledHeight)
        let gradientIntegral = integralImage(data: gradientMap, width: downsampledWidth, height: downsampledHeight)
        let neutralIntegral = integralImage(data: neutralMap, width: downsampledWidth, height: downsampledHeight)
        let glareMask = brightness.map { $0 >= glareThreshold ? 1.0 : 0.0 }
        let glareIntegral = integralImage(data: glareMask, width: downsampledWidth, height: downsampledHeight)

        let pMin = percentile(values: brightness, fraction: tuning.minBrightnessPercentile)
        let pTarget = percentile(values: brightness, fraction: tuning.targetBrightnessPercentile)
        let pHighlight = percentile(values: brightness, fraction: tuning.highlightPercentile)
        let globalContrastScale = max(1e-9, pHighlight - pMin)
        let windowTuning = windowTuning(for: windowPreset)
        let windowSizes = generateWindowSizes(
            width: downsampledWidth,
            height: downsampledHeight,
            baseFractions: tuning.windowFractions,
            aspectRatios: tuning.aspectRatios,
            tuning: windowTuning
        )
        guard !windowSizes.isEmpty else { return nil }

        let estimatedCandidates = estimateWindowCount(
            width: downsampledWidth,
            height: downsampledHeight,
            sizes: windowSizes,
            stepDivisor: windowTuning.stepDivisor,
            minStep: windowTuning.minStep
        )
        guard estimatedCandidates > 0 else { return nil }

        var evaluated = 0
        var rejectedByGlare = 0
        var windows: [CandidateWindow] = []
        windows.reserveCapacity(min(estimatedCandidates, 512))
        let progressStride = max(1, estimatedCandidates / 180)

        for size in windowSizes {
            let w = size.width
            let h = size.height
            let stepX = windowStep(windowLength: w, stepDivisor: windowTuning.stepDivisor, minStep: windowTuning.minStep)
            let stepY = windowStep(windowLength: h, stepDivisor: windowTuning.stepDivisor, minStep: windowTuning.minStep)
            let xValues = steppedValues(min: 0, max: max(0, downsampledWidth - w), step: stepX)
            let yValues = steppedValues(min: 0, max: max(0, downsampledHeight - h), step: stepY)

            for y in yValues {
                for x in xValues {
                    evaluated += 1
                    let area = Double(w * h)
                    guard area > 0 else { continue }

                    let brightMean = sumRect(integral: brightIntegral, width: downsampledWidth, x: x, y: y, w: w, h: h) / area
                    guard brightMean >= pMin else { continue }

                    let brightSqMean = sumRect(integral: brightSqIntegral, width: downsampledWidth, x: x, y: y, w: w, h: h) / area
                    let brightVariance = max(0.0, brightSqMean - brightMean * brightMean)
                    let brightStd = sqrt(brightVariance)
                    let localHomogeneity = 1.0 - clamp(brightStd / max(globalContrastScale, 1e-9), min: 0.0, max: 1.0)

                    let spectral = evaluateSpectralConsistency(
                        channelSlices: channelSlices,
                        globalSpectrum: globalSampledSpectrum,
                        width: downsampledWidth,
                        height: downsampledHeight,
                        x: x,
                        y: y,
                        w: w,
                        h: h
                    )

                    let neutralMean = sumRect(
                        integral: neutralIntegral,
                        width: downsampledWidth,
                        x: x,
                        y: y,
                        w: w,
                        h: h
                    ) / area

                    let ringContrast = ringContrastScore(
                        brightIntegral: brightIntegral,
                        width: downsampledWidth,
                        height: downsampledHeight,
                        x: x,
                        y: y,
                        w: w,
                        h: h,
                        centerMean: brightMean,
                        scale: globalContrastScale
                    )

                    let glareRatio = sumRect(
                        integral: glareIntegral,
                        width: downsampledWidth,
                        x: x,
                        y: y,
                        w: w,
                        h: h
                    ) / area
                    let localGradient = sumRect(
                        integral: gradientIntegral,
                        width: downsampledWidth,
                        x: x,
                        y: y,
                        w: w,
                        h: h
                    ) / area

                    let brightnessScore = smoothstep(edge0: pMin, edge1: pTarget, value: brightMean)
                    let projectedSourceArea = Double(max(1, w * downsampleFactor) * max(1, h * downsampleFactor))
                    let areaFraction = projectedSourceArea / Double(max(1, width * height))
                    let areaScore = smoothstep(edge0: tuning.areaScoreEdge0, edge1: tuning.areaScoreEdge1, value: areaFraction)
                    let aspect = Double(w) / Double(max(h, 1))
                    let aspectFolded = max(aspect, 1.0 / max(aspect, 1e-9))
                    let shapeScore = 1.0 - clamp(
                        (aspectFolded - tuning.shapeAspectNeutral) / max(tuning.shapeAspectSpread, 1e-9),
                        min: 0.0,
                        max: 1.0
                    )
                    let glarePenalty = clamp(
                        glareRatio * tuning.glareRatioWeight
                        + spectral.glareHint * tuning.glareHintWeight
                        + smoothstep(edge0: pHighlight, edge1: glareThreshold, value: brightMean) * smoothstep(edge0: tuning.glareGradientLow, edge1: tuning.glareGradientHigh, value: localGradient),
                        min: 0.0,
                        max: 1.0
                    )
                    if glarePenalty > tuning.glareRejectThreshold {
                        rejectedByGlare += 1
                        continue
                    }

                    if neutralMean < tuning.minNeutrality
                        || areaFraction < tuning.minAreaFraction
                        || spectral.dispersion < tuning.minDispersionScore {
                        continue
                    }

                    let score =
                        weightBrightness * brightnessScore
                        + weightLocalHomogeneity * localHomogeneity
                        + weightFlatness * spectral.flatness
                        + weightDispersion * spectral.dispersion
                        + weightSpectralHomogeneity * spectral.homogeneity
                        + weightContrast * ringContrast
                        + weightNeutrality * neutralMean
                        + weightArea * areaScore
                        + weightShape * shapeScore
                        - weightGlarePenalty * glarePenalty

                    if score > 0.05 {
                        windows.append(
                            CandidateWindow(
                                x: x,
                                y: y,
                                width: w,
                                height: h,
                                score: score,
                                brightnessScore: brightnessScore,
                                flatnessScore: spectral.flatness,
                                dispersionScore: spectral.dispersion,
                                homogeneityScore: 0.5 * localHomogeneity + 0.5 * spectral.homogeneity,
                                contrastScore: ringContrast,
                                glarePenalty: glarePenalty
                            )
                        )
                    }

                    if evaluated % progressStride == 0 {
                        progressCallback?(
                            WhitePointSearchProgressInfo(
                                progress: min(0.9, 0.05 + 0.85 * Double(evaluated) / Double(estimatedCandidates)),
                                message: LF("pipeline.calibration.auto_white.progress_scan", evaluated, estimatedCandidates),
                                evaluatedCandidates: evaluated,
                                totalCandidates: estimatedCandidates,
                                stage: "scan"
                            )
                        )
                    }
                }
            }
        }

        guard !windows.isEmpty else {
            progressCallback?(
                WhitePointSearchProgressInfo(
                    progress: 1.0,
                    message: L("Подходящие области не найдены"),
                    evaluatedCandidates: evaluated,
                    totalCandidates: estimatedCandidates,
                    stage: "completed"
                )
            )
            return nil
        }

        let sorted = windows.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.width * lhs.height > rhs.width * rhs.height
            }
            return lhs.score > rhs.score
        }
        let filtered = nonMaximumSuppression(
            candidates: sorted,
            maxCount: max(1, maxCandidates),
            iouThreshold: 0.34
        )

        progressCallback?(
            WhitePointSearchProgressInfo(
                progress: 0.93,
                message: L("Формирование спектров кандидатов…"),
                evaluatedCandidates: evaluated,
                totalCandidates: estimatedCandidates,
                stage: "spectra"
            )
        )

        var resultCandidates: [WhitePointCandidate] = []
        resultCandidates.reserveCapacity(filtered.count)

        for window in filtered {
            let mapped = mapWindowToSource(
                x: window.x,
                y: window.y,
                w: window.width,
                h: window.height,
                downsampleFactor: downsampleFactor,
                sourceWidth: width,
                sourceHeight: height
            )
            let rect = SpectrumROIRect(minX: mapped.x, minY: mapped.y, width: mapped.width, height: mapped.height)
            let meanSpectrum = meanSpectrum(
                cube: cube,
                axes: axes,
                rect: rect,
                channels: channels
            )
            resultCandidates.append(
                WhitePointCandidate(
                    rect: rect,
                    score: window.score,
                    brightnessScore: window.brightnessScore,
                    spectralFlatnessScore: window.flatnessScore,
                    spectralDispersionScore: window.dispersionScore,
                    spectralHomogeneityScore: window.homogeneityScore,
                    contrastScore: window.contrastScore,
                    glarePenalty: window.glarePenalty,
                    meanSpectrum: meanSpectrum
                )
            )
        }

        progressCallback?(
            WhitePointSearchProgressInfo(
                progress: 1.0,
                message: LF("pipeline.calibration.auto_white.progress_done", resultCandidates.count),
                evaluatedCandidates: evaluated,
                totalCandidates: estimatedCandidates,
                stage: "completed"
            )
        )

        return WhitePointSearchResult(
            candidates: resultCandidates,
            evaluatedCandidates: evaluated,
            rejectedByGlare: rejectedByGlare
        )
    }

    private static func tuning(for preset: WhitePointSearchPreset) -> PresetTuning {
        switch preset {
        case .balanced:
            return PresetTuning(
                downsampleDivisor: 220,
                glarePercentile: 0.996,
                minBrightnessPercentile: 0.70,
                targetBrightnessPercentile: 0.92,
                highlightPercentile: 0.98,
                minNeutrality: 0.20,
                minAreaFraction: 0.0003,
                areaScoreEdge0: 0.0008,
                areaScoreEdge1: 0.009,
                windowFractions: [0.06, 0.08, 0.10, 0.13, 0.16, 0.20, 0.24, 0.28],
                aspectRatios: [1.0, 1.2, 0.83, 1.5, 0.67, 1.8, 0.56],
                glareRatioWeight: 2.2,
                glareHintWeight: 0.55,
                glareGradientLow: 0.08,
                glareGradientHigh: 0.22,
                glareRejectThreshold: 0.86,
                shapeAspectNeutral: 1.7,
                shapeAspectSpread: 1.4,
                wBrightness: 0.20,
                wLocalHomogeneity: 0.16,
                wFlatness: 0.22,
                wDispersion: 0.23,
                wSpectralHomogeneity: 0.18,
                wContrast: 0.10,
                wNeutrality: 0.16,
                wArea: 0.12,
                wShape: 0.08,
                glarePenaltyWeight: 0.30,
                minDispersionScore: 0.36
            )
        case .spectralonPriority:
            return PresetTuning(
                downsampleDivisor: 240,
                glarePercentile: 0.997,
                minBrightnessPercentile: 0.62,
                targetBrightnessPercentile: 0.90,
                highlightPercentile: 0.985,
                minNeutrality: 0.33,
                minAreaFraction: 0.0012,
                areaScoreEdge0: 0.0022,
                areaScoreEdge1: 0.018,
                windowFractions: [0.08, 0.10, 0.13, 0.16, 0.20, 0.24, 0.30, 0.36],
                aspectRatios: [1.0, 1.2, 0.83, 1.4, 0.71, 1.6, 0.62],
                glareRatioWeight: 2.4,
                glareHintWeight: 0.65,
                glareGradientLow: 0.08,
                glareGradientHigh: 0.20,
                glareRejectThreshold: 0.82,
                shapeAspectNeutral: 1.45,
                shapeAspectSpread: 0.95,
                wBrightness: 0.16,
                wLocalHomogeneity: 0.14,
                wFlatness: 0.24,
                wDispersion: 0.30,
                wSpectralHomogeneity: 0.19,
                wContrast: 0.06,
                wNeutrality: 0.24,
                wArea: 0.18,
                wShape: 0.10,
                glarePenaltyWeight: 0.34,
                minDispersionScore: 0.50
            )
        case .lowLight:
            return PresetTuning(
                downsampleDivisor: 180,
                glarePercentile: 0.9975,
                minBrightnessPercentile: 0.45,
                targetBrightnessPercentile: 0.78,
                highlightPercentile: 0.95,
                minNeutrality: 0.14,
                minAreaFraction: 0.0002,
                areaScoreEdge0: 0.0003,
                areaScoreEdge1: 0.006,
                windowFractions: [0.04, 0.06, 0.08, 0.10, 0.13, 0.16, 0.20, 0.24],
                aspectRatios: [1.0, 1.2, 0.83, 1.5, 0.67, 1.8, 0.56],
                glareRatioWeight: 1.8,
                glareHintWeight: 0.45,
                glareGradientLow: 0.10,
                glareGradientHigh: 0.28,
                glareRejectThreshold: 0.90,
                shapeAspectNeutral: 1.8,
                shapeAspectSpread: 1.6,
                wBrightness: 0.17,
                wLocalHomogeneity: 0.20,
                wFlatness: 0.20,
                wDispersion: 0.16,
                wSpectralHomogeneity: 0.20,
                wContrast: 0.10,
                wNeutrality: 0.15,
                wArea: 0.10,
                wShape: 0.06,
                glarePenaltyWeight: 0.24,
                minDispersionScore: 0.24
            )
        case .harshLight:
            return PresetTuning(
                downsampleDivisor: 230,
                glarePercentile: 0.992,
                minBrightnessPercentile: 0.65,
                targetBrightnessPercentile: 0.90,
                highlightPercentile: 0.97,
                minNeutrality: 0.24,
                minAreaFraction: 0.0005,
                areaScoreEdge0: 0.0012,
                areaScoreEdge1: 0.011,
                windowFractions: [0.06, 0.08, 0.10, 0.13, 0.16, 0.20, 0.24, 0.30],
                aspectRatios: [1.0, 1.2, 0.83, 1.4, 0.71, 1.6, 0.62],
                glareRatioWeight: 2.8,
                glareHintWeight: 0.75,
                glareGradientLow: 0.06,
                glareGradientHigh: 0.18,
                glareRejectThreshold: 0.72,
                shapeAspectNeutral: 1.6,
                shapeAspectSpread: 1.2,
                wBrightness: 0.18,
                wLocalHomogeneity: 0.17,
                wFlatness: 0.20,
                wDispersion: 0.24,
                wSpectralHomogeneity: 0.18,
                wContrast: 0.08,
                wNeutrality: 0.20,
                wArea: 0.11,
                wShape: 0.06,
                glarePenaltyWeight: 0.45,
                minDispersionScore: 0.38
            )
        }
    }

    private static func windowTuning(for preset: WhitePointWindowPreset) -> WindowSearchTuning {
        switch preset {
        case .balanced:
            return WindowSearchTuning(
                fractionScale: 1.0,
                additionalFractions: [],
                additionalAspectRatios: [],
                stepDivisor: 3.0,
                minStep: 2,
                sizeSelectionStride: 1
            )
        case .smallTargets:
            return WindowSearchTuning(
                fractionScale: 0.72,
                additionalFractions: [0.024, 0.032, 0.042, 0.054, 0.07, 0.09],
                additionalAspectRatios: [1.0, 1.25, 0.80],
                stepDivisor: 4.2,
                minStep: 1,
                sizeSelectionStride: 1
            )
        case .largePanels:
            return WindowSearchTuning(
                fractionScale: 1.33,
                additionalFractions: [0.20, 0.26, 0.34, 0.42, 0.50],
                additionalAspectRatios: [1.0, 1.15, 0.87, 1.4, 0.71],
                stepDivisor: 2.8,
                minStep: 3,
                sizeSelectionStride: 1
            )
        case .denseScan:
            return WindowSearchTuning(
                fractionScale: 1.0,
                additionalFractions: [0.05, 0.07, 0.09, 0.12, 0.15, 0.18, 0.22, 0.26, 0.32],
                additionalAspectRatios: [1.0, 1.33, 0.75],
                stepDivisor: 4.8,
                minStep: 1,
                sizeSelectionStride: 1
            )
        case .fastScan:
            return WindowSearchTuning(
                fractionScale: 1.0,
                additionalFractions: [],
                additionalAspectRatios: [],
                stepDivisor: 2.2,
                minStep: 3,
                sizeSelectionStride: 2
            )
        }
    }

    private static func selectedChannels(totalChannels: Int, wavelengths: [Double]?) -> [Int] {
        guard totalChannels > 0 else { return [] }
        if totalChannels <= 12 {
            return Array(0..<totalChannels)
        }

        if let wavelengths, wavelengths.count == totalChannels {
            let targets = [450.0, 500.0, 550.0, 610.0, 680.0, 760.0, 850.0]
            var used = Set<Int>()
            for lambda in targets {
                if let nearest = nearestChannel(to: lambda, wavelengths: wavelengths) {
                    used.insert(nearest)
                }
            }
            if !used.isEmpty {
                return used.sorted()
            }
        }

        let targetCount = min(24, totalChannels)
        if targetCount <= 1 {
            return [0]
        }
        var result: [Int] = []
        result.reserveCapacity(targetCount)
        let span = Double(totalChannels - 1)
        for i in 0..<targetCount {
            let idx = Int(round(Double(i) * span / Double(targetCount - 1)))
            result.append(min(max(idx, 0), totalChannels - 1))
        }
        return Array(Set(result)).sorted()
    }

    private static func nearestChannel(to wavelength: Double, wavelengths: [Double]) -> Int? {
        guard !wavelengths.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (idx, value) in wavelengths.enumerated() {
            let distance = abs(value - wavelength)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = idx
            }
        }
        return bestIndex
    }

    private static func buildBrightnessMap(channelSlices: [[Double]]) -> [Double] {
        guard let first = channelSlices.first else { return [] }
        let count = first.count
        guard count > 0 else { return [] }
        let channelCount = channelSlices.count
        var brightness = [Double](repeating: 0, count: count)

        if channelCount == 3 {
            let weights = [0.2126, 0.7152, 0.0722]
            for i in 0..<count {
                brightness[i] =
                    channelSlices[0][i] * weights[0]
                    + channelSlices[1][i] * weights[1]
                    + channelSlices[2][i] * weights[2]
            }
            return brightness
        }

        let weight = 1.0 / Double(max(channelCount, 1))
        for slice in channelSlices {
            guard slice.count == count else { continue }
            for i in 0..<count {
                brightness[i] += slice[i] * weight
            }
        }
        return brightness
    }

    private static func buildNeutralityMap(
        channelSlices: [[Double]],
        wavelengths: [Double]?,
        sampledChannels: [Int]
    ) -> [Double] {
        guard let first = channelSlices.first else { return [] }
        let count = first.count
        guard count > 0 else { return [] }
        let channelCount = channelSlices.count
        guard channelCount >= 3 else {
            return [Double](repeating: 1.0, count: count)
        }

        let anchors = representativeColorTriplet(sampledChannels: sampledChannels, wavelengths: wavelengths)
        let blueIndex = min(max(anchors.blue, 0), channelCount - 1)
        let greenIndex = min(max(anchors.green, 0), channelCount - 1)
        let redIndex = min(max(anchors.red, 0), channelCount - 1)

        let blue = channelSlices[blueIndex]
        let green = channelSlices[greenIndex]
        let red = channelSlices[redIndex]

        var neutrality = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let b = blue[i]
            let g = green[i]
            let r = red[i]
            let mean = (r + g + b) / 3.0
            let diff = abs(r - g) + abs(g - b) + abs(r - b)
            neutrality[i] = 1.0 - clamp(diff / max(3.0 * abs(mean), 1e-9), min: 0.0, max: 1.0)
        }
        return neutrality
    }

    private static func representativeColorTriplet(
        sampledChannels: [Int],
        wavelengths: [Double]?
    ) -> (blue: Int, green: Int, red: Int) {
        let count = sampledChannels.count
        guard count > 0 else { return (blue: 0, green: 0, red: 0) }
        guard let wavelengths, !wavelengths.isEmpty else {
            let mid = count / 2
            return (blue: 0, green: mid, red: max(0, count - 1))
        }

        func nearestIndex(to lambda: Double) -> Int {
            var best = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (localIndex, originalChannel) in sampledChannels.enumerated() {
                guard originalChannel >= 0, originalChannel < wavelengths.count else { continue }
                let distance = abs(wavelengths[originalChannel] - lambda)
                if distance < bestDistance {
                    bestDistance = distance
                    best = localIndex
                }
            }
            return best
        }

        return (
            blue: nearestIndex(to: 470),
            green: nearestIndex(to: 550),
            red: nearestIndex(to: 650)
        )
    }

    private static func generateWindowSizes(
        width: Int,
        height: Int,
        baseFractions: [Double],
        aspectRatios: [Double],
        tuning: WindowSearchTuning
    ) -> [(width: Int, height: Int)] {
        let minDim = max(4, min(width, height))
        var fractions = baseFractions.map { clamp($0 * tuning.fractionScale, min: 0.02, max: 0.95) }
        fractions.append(contentsOf: tuning.additionalFractions.map { clamp($0, min: 0.02, max: 0.95) })
        fractions = Array(Set(fractions.map { Int(round($0 * 10000.0)) }))
            .map { Double($0) / 10000.0 }
            .sorted()
        let ratios = Array(Set((aspectRatios + tuning.additionalAspectRatios).map { ratio in
            max(0.25, min(ratio, 4.0))
        })).sorted()

        var result: [(Int, Int)] = []
        for fraction in fractions {
            let base = max(4, Int(round(Double(minDim) * fraction)))
            for ratio in ratios {
                let w = max(4, min(width, Int(round(Double(base) * ratio))))
                let h = max(4, min(height, Int(round(Double(base) / ratio))))
                if w <= width && h <= height {
                    result.append((w, h))
                }
            }
        }
        return Array(Set(result.map { "\($0.0)x\($0.1)" }))
            .compactMap { token -> (Int, Int)? in
                let parts = token.split(separator: "x")
                guard parts.count == 2,
                      let w = Int(parts[0]),
                      let h = Int(parts[1]) else { return nil }
                return (w, h)
            }
            .sorted { lhs, rhs in
                let lhsArea = lhs.0 * lhs.1
                let rhsArea = rhs.0 * rhs.1
                if lhsArea == rhsArea {
                    return lhs.0 < rhs.0
                }
                return lhsArea < rhsArea
            }
            .map { (width: $0.0, height: $0.1) }
            .enumerated()
            .compactMap { index, size in
                if tuning.sizeSelectionStride <= 1 || index % tuning.sizeSelectionStride == 0 {
                    return size
                }
                return nil
            }
    }

    private static func estimateWindowCount(
        width: Int,
        height: Int,
        sizes: [(width: Int, height: Int)],
        stepDivisor: Double,
        minStep: Int
    ) -> Int {
        var total = 0
        for size in sizes {
            let stepX = windowStep(windowLength: size.width, stepDivisor: stepDivisor, minStep: minStep)
            let stepY = windowStep(windowLength: size.height, stepDivisor: stepDivisor, minStep: minStep)
            total += steppedValues(min: 0, max: max(0, width - size.width), step: stepX).count
                * steppedValues(min: 0, max: max(0, height - size.height), step: stepY).count
        }
        return total
    }

    private static func windowStep(windowLength: Int, stepDivisor: Double, minStep: Int) -> Int {
        guard stepDivisor.isFinite, stepDivisor > 0 else {
            return max(1, minStep)
        }
        let coarseStep = Int(round(Double(windowLength) / stepDivisor))
        return max(max(1, minStep), coarseStep)
    }

    private static func steppedValues(min: Int, max: Int, step: Int) -> [Int] {
        guard min <= max else { return [] }
        let safeStep = Swift.max(1, step)
        var values = Array(stride(from: min, through: max, by: safeStep))
        if values.last != max {
            values.append(max)
        }
        return values
    }

    private static func extractChannel(
        cube: HyperCube,
        channel: Int,
        axes: (channel: Int, height: Int, width: Int)
    ) -> [Double] {
        let dims = [cube.dims.0, cube.dims.1, cube.dims.2]
        let width = dims[axes.width]
        let height = dims[axes.height]
        var result = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var idx = [0, 0, 0]
                idx[axes.channel] = channel
                idx[axes.height] = y
                idx[axes.width] = x
                let linear = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                result[y * width + x] = cube.getValue(at: linear)
            }
        }
        return result
    }

    private static func downsampleMean(
        _ data: [Double],
        width: Int,
        height: Int,
        factor: Int
    ) -> (data: [Double], width: Int, height: Int) {
        let safeFactor = max(1, factor)
        guard safeFactor > 1 else { return (data, width, height) }
        let outWidth = max(1, width / safeFactor)
        let outHeight = max(1, height / safeFactor)
        var result = [Double](repeating: 0, count: outWidth * outHeight)
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                var sum = 0.0
                var count = 0.0
                let srcY0 = y * safeFactor
                let srcX0 = x * safeFactor
                for fy in 0..<safeFactor {
                    for fx in 0..<safeFactor {
                        let srcX = srcX0 + fx
                        let srcY = srcY0 + fy
                        if srcX < width && srcY < height {
                            sum += data[srcY * width + srcX]
                            count += 1.0
                        }
                    }
                }
                result[y * outWidth + x] = count > 0 ? sum / count : 0.0
            }
        }
        return (result, outWidth, outHeight)
    }

    private static func sobelMagnitude(data: [Double], width: Int, height: Int) -> [Double] {
        guard width > 1, height > 1, data.count == width * height else {
            return [Double](repeating: 0, count: max(0, width * height))
        }
        var output = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let tl = sample(data: data, width: width, height: height, x: x - 1, y: y - 1)
                let tc = sample(data: data, width: width, height: height, x: x, y: y - 1)
                let tr = sample(data: data, width: width, height: height, x: x + 1, y: y - 1)
                let ml = sample(data: data, width: width, height: height, x: x - 1, y: y)
                let mr = sample(data: data, width: width, height: height, x: x + 1, y: y)
                let bl = sample(data: data, width: width, height: height, x: x - 1, y: y + 1)
                let bc = sample(data: data, width: width, height: height, x: x, y: y + 1)
                let br = sample(data: data, width: width, height: height, x: x + 1, y: y + 1)

                let gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl)
                let gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr)
                output[y * width + x] = sqrt(gx * gx + gy * gy)
            }
        }
        return output
    }

    private static func sample(data: [Double], width: Int, height: Int, x: Int, y: Int) -> Double {
        let clampedX = max(0, min(x, max(0, width - 1)))
        let clampedY = max(0, min(y, max(0, height - 1)))
        return data[clampedY * width + clampedX]
    }

    private static func integralImage(data: [Double], width: Int, height: Int) -> [Double] {
        var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var rowSum = 0.0
            let integralRow = (y + 1) * (width + 1)
            let prevRow = y * (width + 1)
            let dataRow = y * width
            for x in 0..<width {
                rowSum += data[dataRow + x]
                integral[integralRow + x + 1] = integral[prevRow + x + 1] + rowSum
            }
        }
        return integral
    }

    private static func sumRect(
        integral: [Double],
        width: Int,
        x: Int,
        y: Int,
        w: Int,
        h: Int
    ) -> Double {
        let stride = width + 1
        let x0 = x
        let y0 = y
        let x1 = x + w
        let y1 = y + h
        return integral[y1 * stride + x1]
            - integral[y0 * stride + x1]
            - integral[y1 * stride + x0]
            + integral[y0 * stride + x0]
    }

    private static func evaluateSpectralConsistency(
        channelSlices: [[Double]],
        globalSpectrum: [Double],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        w: Int,
        h: Int
    ) -> (flatness: Double, dispersion: Double, homogeneity: Double, glareHint: Double) {
        let channels = channelSlices.count
        guard channels > 0 else {
            return (flatness: 0.0, dispersion: 0.0, homogeneity: 0.0, glareHint: 1.0)
        }

        let sampleCountX = max(2, min(6, w / 5))
        let sampleCountY = max(2, min(6, h / 5))
        let totalSamples = max(1, sampleCountX * sampleCountY)

        var spectra: [[Double]] = []
        spectra.reserveCapacity(totalSamples)

        for sy in 0..<sampleCountY {
            for sx in 0..<sampleCountX {
                let fx = (Double(sx) + 0.5) / Double(sampleCountX)
                let fy = (Double(sy) + 0.5) / Double(sampleCountY)
                let px = min(width - 1, max(0, x + Int(fx * Double(max(w - 1, 1)))))
                let py = min(height - 1, max(0, y + Int(fy * Double(max(h - 1, 1)))))
                let index = py * width + px
                var spectrum = [Double](repeating: 0, count: channels)
                for ch in 0..<channels {
                    spectrum[ch] = channelSlices[ch][index]
                }
                spectra.append(spectrum)
            }
        }

        guard !spectra.isEmpty else {
            return (flatness: 0.0, dispersion: 0.0, homogeneity: 0.0, glareHint: 1.0)
        }

        var meanSpectrum = [Double](repeating: 0, count: channels)
        for spectrum in spectra {
            for ch in 0..<channels {
                meanSpectrum[ch] += spectrum[ch]
            }
        }
        for ch in 0..<channels {
            meanSpectrum[ch] /= Double(spectra.count)
        }

        let meanValue = meanSpectrum.reduce(0.0, +) / Double(channels)
        let variance = meanSpectrum.reduce(0.0) { partial, value in
            let d = value - meanValue
            return partial + d * d
        } / Double(channels)
        let spectralStd = sqrt(max(0.0, variance))
        let cvRaw = spectralStd / max(abs(meanValue), 1e-9)

        var compensated = [Double](repeating: 0, count: channels)
        for ch in 0..<channels {
            let global = ch < globalSpectrum.count ? globalSpectrum[ch] : meanSpectrum[ch]
            compensated[ch] = meanSpectrum[ch] / max(global, 1e-9)
        }
        let compensatedMean = compensated.reduce(0.0, +) / Double(channels)
        let compensatedStd = sqrt(compensated.reduce(0.0) { partial, value in
            let d = value - compensatedMean
            return partial + d * d
        } / Double(channels))
        let cvCompensated = compensatedStd / max(abs(compensatedMean), 1e-9)

        var secondDerivativeSum = 0.0
        if channels >= 3 {
            for ch in 1..<(channels - 1) {
                let dd = compensated[ch + 1] - 2.0 * compensated[ch] + compensated[ch - 1]
                secondDerivativeSum += abs(dd)
            }
        }
        let smoothnessPenalty = secondDerivativeSum / Double(max(channels - 2, 1))
        let smoothnessScore = 1.0 - clamp((smoothnessPenalty - 0.01) / 0.22, min: 0.0, max: 1.0)

        let flatnessRaw = 1.0 - clamp((cvRaw - 0.02) / 0.30, min: 0.0, max: 1.0)
        let flatnessCompensated = 1.0 - clamp((cvCompensated - 0.015) / 0.25, min: 0.0, max: 1.0)
        let flatness = clamp(
            0.25 * flatnessRaw + 0.45 * flatnessCompensated + 0.30 * smoothnessScore,
            min: 0.0,
            max: 1.0
        )

        let cvDispersion = cvCompensated
        let p10 = percentile(values: compensated, fraction: 0.10)
        let p90 = percentile(values: compensated, fraction: 0.90)
        let iqrRelative = (p90 - p10) / max(abs(compensatedMean), 1e-9)
        let dispersionRaw = 0.55 * cvDispersion + 0.45 * iqrRelative
        let dispersion = 1.0 - clamp((dispersionRaw - 0.05) / 0.45, min: 0.0, max: 1.0)

        var meanAngle = 0.0
        for spectrum in spectra {
            meanAngle += spectralAngle(lhs: spectrum, rhs: meanSpectrum)
        }
        meanAngle /= Double(spectra.count)
        let homogeneity = 1.0 - clamp(meanAngle / 0.18, min: 0.0, max: 1.0)

        let maxV = compensated.max() ?? compensatedMean
        let minV = compensated.min() ?? compensatedMean
        let spikeRatio = (maxV - minV) / max(abs(compensatedMean), 1e-9)
        let glareHint = clamp((spikeRatio - 0.8) / 2.0, min: 0.0, max: 1.0)

        return (flatness: flatness, dispersion: dispersion, homogeneity: homogeneity, glareHint: glareHint)
    }

    private static func spectralAngle(lhs: [Double], rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .pi / 2.0 }
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        for i in 0..<lhs.count {
            dot += lhs[i] * rhs[i]
            lhsNorm += lhs[i] * lhs[i]
            rhsNorm += rhs[i] * rhs[i]
        }
        let denom = sqrt(max(lhsNorm, 1e-12)) * sqrt(max(rhsNorm, 1e-12))
        let cosValue = clamp(dot / max(denom, 1e-12), min: -1.0, max: 1.0)
        return acos(cosValue)
    }

    private static func ringContrastScore(
        brightIntegral: [Double],
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        w: Int,
        h: Int,
        centerMean: Double,
        scale: Double
    ) -> Double {
        let margin = max(1, min(w, h) / 4)
        let x0 = max(0, x - margin)
        let y0 = max(0, y - margin)
        let x1 = min(width, x + w + margin)
        let y1 = min(height, y + h + margin)
        let outerW = max(1, x1 - x0)
        let outerH = max(1, y1 - y0)
        let innerArea = max(1, w * h)
        let outerArea = max(1, outerW * outerH)
        guard outerArea > innerArea else { return 0.0 }

        let outerSum = sumRect(integral: brightIntegral, width: width, x: x0, y: y0, w: outerW, h: outerH)
        let innerSum = sumRect(integral: brightIntegral, width: width, x: x, y: y, w: w, h: h)
        let ringArea = Double(outerArea - innerArea)
        guard ringArea > 0 else { return 0.0 }
        let ringMean = (outerSum - innerSum) / ringArea
        let contrast = abs(centerMean - ringMean)
        return clamp(contrast / max(scale, 1e-9), min: 0.0, max: 1.0)
    }

    private static func nonMaximumSuppression(
        candidates: [CandidateWindow],
        maxCount: Int,
        iouThreshold: Double
    ) -> [CandidateWindow] {
        var selected: [CandidateWindow] = []
        selected.reserveCapacity(maxCount)
        for candidate in candidates {
            var keep = true
            for chosen in selected {
                if intersectionOverUnion(candidate, chosen) > iouThreshold {
                    keep = false
                    break
                }
            }
            if keep {
                selected.append(candidate)
                if selected.count >= maxCount {
                    break
                }
            }
        }
        return selected
    }

    private static func intersectionOverUnion(_ lhs: CandidateWindow, _ rhs: CandidateWindow) -> Double {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersectionW = max(0, right - left)
        let intersectionH = max(0, bottom - top)
        let intersection = intersectionW * intersectionH
        guard intersection > 0 else { return 0.0 }
        let lhsArea = lhs.width * lhs.height
        let rhsArea = rhs.width * rhs.height
        let union = lhsArea + rhsArea - intersection
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    private static func mapWindowToSource(
        x: Int,
        y: Int,
        w: Int,
        h: Int,
        downsampleFactor: Int,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let startX = min(max(0, x * downsampleFactor), max(0, sourceWidth - 1))
        let startY = min(max(0, y * downsampleFactor), max(0, sourceHeight - 1))
        let targetW = max(1, min(sourceWidth - startX, w * downsampleFactor))
        let targetH = max(1, min(sourceHeight - startY, h * downsampleFactor))
        return (x: startX, y: startY, width: targetW, height: targetH)
    }

    private static func meanSpectrum(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        rect: SpectrumROIRect,
        channels: Int
    ) -> [Double] {
        let area = max(1, rect.area)
        var result = [Double](repeating: 0, count: channels)
        for ch in 0..<channels {
            var sum = 0.0
            for py in rect.minY..<(rect.minY + rect.height) {
                for px in rect.minX..<(rect.minX + rect.width) {
                    var idx = [0, 0, 0]
                    idx[axes.channel] = ch
                    idx[axes.height] = py
                    idx[axes.width] = px
                    let linear = cube.linearIndex(i0: idx[0], i1: idx[1], i2: idx[2])
                    sum += cube.getValue(at: linear)
                }
            }
            result[ch] = sum / Double(area)
        }
        return result
    }

    private static func percentile(values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let clamped = clamp(fraction, min: 0.0, max: 1.0)
        let sorted = values.sorted()
        let rawIndex = Double(sorted.count - 1) * clamped
        let low = Int(floor(rawIndex))
        let high = Int(ceil(rawIndex))
        if low == high { return sorted[low] }
        let t = rawIndex - Double(low)
        return sorted[low] * (1.0 - t) + sorted[high] * t
    }

    private static func smoothstep(edge0: Double, edge1: Double, value: Double) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1.0 : 0.0 }
        let t = clamp((value - edge0) / (edge1 - edge0), min: 0.0, max: 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

