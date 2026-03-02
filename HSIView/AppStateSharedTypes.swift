import Foundation
import AppKit

enum FastImportDevice: String, CaseIterable, Identifiable {
    case specimIQ

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .specimIQ:
            return L("fast_import.device.specim_iq")
        }
    }
}

enum FastImportDataMode: String, CaseIterable, Identifiable {
    case radiance
    case reflectance

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .radiance:
            return L("fast_import.mode.rad")
        case .reflectance:
            return L("fast_import.mode.ref")
        }
    }
}

enum CubeMetricsPSNRPeakMode: String, CaseIterable, Identifiable {
    case dataRange
    case custom

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dataRange:
            return L("cube.metrics.psnr.peak.data_range")
        case .custom:
            return L("cube.metrics.psnr.peak.custom")
        }
    }
}

enum CubeMetricsSSIMRangeMode: String, CaseIterable, Identifiable {
    case dataRange
    case custom

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dataRange:
            return L("cube.metrics.ssim.range.data_range")
        case .custom:
            return L("cube.metrics.ssim.range.custom")
        }
    }
}

struct CubeMetricsSettings {
    var rmsePerChannelEnabled: Bool = false
    var psnrPeakMode: CubeMetricsPSNRPeakMode = .dataRange
    var psnrCustomPeak: Double = 1.0
    var psnrPerChannelEnabled: Bool = false
    var ssimRangeMode: CubeMetricsSSIMRangeMode = .dataRange
    var ssimCustomRange: Double = 1.0
    var ssimK1: Double = 0.01
    var ssimK2: Double = 0.03
    var ssimPerChannelEnabled: Bool = false
    var samEpsilon: Double = 1e-12
    var samPerChannelEnabled: Bool = false
}

struct CubeMetricsSpatialSignature: Equatable {
    let width: Int
    let height: Int
    let channels: Int
}

struct CubeMetricsPreparedCube {
    let entryID: CubeLibraryEntry.ID
    let displayName: String
    let cube: HyperCube
    let layout: CubeLayout
    let signature: CubeMetricsSpatialSignature
}

struct CubeMetricsRequest: Identifiable {
    let id = UUID()
    let reference: CubeMetricsPreparedCube
    let target: CubeMetricsPreparedCube
}

struct CubeMetricsResult {
    let rmse: Double
    let rmsePerChannel: [Double]?
    let psnr: Double
    let psnrPeak: Double
    let psnrPerChannel: [Double]?
    let ssim: Double
    let ssimPerChannel: [Double]?
    let samDegrees: Double
    let samPerChannelDegrees: [Double]?
    let voxelCount: Int
}

struct CubeMetricsPreparationContext {
    let entryID: CubeLibraryEntry.ID
    let displayName: String
    let canonicalURL: URL
    let snapshot: CubeSessionSnapshot
    let currentRawCube: HyperCube?
}

enum CubeMetricsComputationError: LocalizedError {
    case emptyData
    case invalidPSNRPeak
    case invalidSSIMRange
    case invalidSSIMConstant
    case invalidSAMEpsilon

    var errorDescription: String? {
        switch self {
        case .emptyData:
            return L("cube.metrics.error.empty")
        case .invalidPSNRPeak:
            return L("cube.metrics.error.invalid_psnr_peak")
        case .invalidSSIMRange:
            return L("cube.metrics.error.invalid_ssim_range")
        case .invalidSSIMConstant:
            return L("cube.metrics.error.invalid_ssim_constant")
        case .invalidSAMEpsilon:
            return L("cube.metrics.error.invalid_sam_epsilon")
        }
    }
}

enum CubeMetricsEngine {
    static func calculate(
        reference: CubeMetricsPreparedCube,
        target: CubeMetricsPreparedCube,
        settings: CubeMetricsSettings
    ) throws -> CubeMetricsResult {
        guard reference.signature == target.signature else {
            throw CubeMetricsComputationError.emptyData
        }

        let signature = reference.signature
        guard signature.width > 0, signature.height > 0, signature.channels > 0 else {
            throw CubeMetricsComputationError.emptyData
        }

        guard let refAxes = reference.cube.axes(for: reference.layout),
              let targetAxes = target.cube.axes(for: target.layout) else {
            throw CubeMetricsComputationError.emptyData
        }

        guard settings.samEpsilon.isFinite, settings.samEpsilon > 0 else {
            throw CubeMetricsComputationError.invalidSAMEpsilon
        }

        struct ChannelStats {
            var count: Int = 0
            var sumSquaredDiff: Double = 0
            var minValue: Double = Double.infinity
            var maxValue: Double = -Double.infinity
            var sumX: Double = 0
            var sumY: Double = 0
            var sumXX: Double = 0
            var sumYY: Double = 0
            var sumXY: Double = 0
            var samDot: Double = 0
            var samNormX: Double = 0
            var samNormY: Double = 0
        }

        var validVoxelCount = 0
        var sumSquaredDiff = 0.0

        var minValue = Double.infinity
        var maxValue = -Double.infinity

        var sumX = 0.0
        var sumY = 0.0
        var sumXX = 0.0
        var sumYY = 0.0
        var sumXY = 0.0

        var samSum = 0.0
        var samCount = 0
        var channelStats = Array(repeating: ChannelStats(), count: signature.channels)

        for y in 0..<signature.height {
            for x in 0..<signature.width {
                var dot = 0.0
                var normX = 0.0
                var normY = 0.0

                for channel in 0..<signature.channels {
                    let left = sampleValue(
                        cube: reference.cube,
                        axes: refAxes,
                        x: x,
                        y: y,
                        channel: channel
                    )
                    let right = sampleValue(
                        cube: target.cube,
                        axes: targetAxes,
                        x: x,
                        y: y,
                        channel: channel
                    )

                    guard left.isFinite, right.isFinite else { continue }

                    validVoxelCount += 1
                    let diff = left - right
                    sumSquaredDiff += diff * diff

                    minValue = min(minValue, left, right)
                    maxValue = max(maxValue, left, right)

                    sumX += left
                    sumY += right
                    sumXX += left * left
                    sumYY += right * right
                    sumXY += left * right

                    channelStats[channel].count += 1
                    channelStats[channel].sumSquaredDiff += diff * diff
                    channelStats[channel].minValue = min(channelStats[channel].minValue, left, right)
                    channelStats[channel].maxValue = max(channelStats[channel].maxValue, left, right)
                    channelStats[channel].sumX += left
                    channelStats[channel].sumY += right
                    channelStats[channel].sumXX += left * left
                    channelStats[channel].sumYY += right * right
                    channelStats[channel].sumXY += left * right
                    channelStats[channel].samDot += left * right
                    channelStats[channel].samNormX += left * left
                    channelStats[channel].samNormY += right * right

                    dot += left * right
                    normX += left * left
                    normY += right * right
                }

                let samDenominator = sqrt(normX) * sqrt(normY)
                if samDenominator > settings.samEpsilon {
                    let cosine = max(-1.0, min(1.0, dot / samDenominator))
                    samSum += acos(cosine)
                    samCount += 1
                }
            }
        }

        guard validVoxelCount > 0 else {
            throw CubeMetricsComputationError.emptyData
        }

        let mseGlobal = sumSquaredDiff / Double(validVoxelCount)
        let rmseGlobal = sqrt(mseGlobal)

        let psnrPeakGlobal = try resolvePSNRPeak(
            minValue: minValue,
            maxValue: maxValue,
            settings: settings
        )
        let psnrGlobal: Double
        if rmseGlobal == 0 {
            psnrGlobal = .infinity
        } else {
            psnrGlobal = 20.0 * log10(psnrPeakGlobal / rmseGlobal)
        }

        let ssimRangeGlobal = try resolveSSIMRange(
            minValue: minValue,
            maxValue: maxValue,
            settings: settings
        )
        guard settings.ssimK1.isFinite, settings.ssimK2.isFinite,
              settings.ssimK1 > 0, settings.ssimK2 > 0 else {
            throw CubeMetricsComputationError.invalidSSIMConstant
        }
        let ssimGlobal = computeSSIM(
            sumX: sumX,
            sumY: sumY,
            sumXX: sumXX,
            sumYY: sumYY,
            sumXY: sumXY,
            count: validVoxelCount,
            dynamicRange: ssimRangeGlobal,
            k1: settings.ssimK1,
            k2: settings.ssimK2
        )

        let samRadiansGlobal: Double
        if samCount > 0 {
            samRadiansGlobal = samSum / Double(samCount)
        } else {
            samRadiansGlobal = .nan
        }
        let samDegreesGlobal = samRadiansGlobal * 180.0 / .pi

        var rmsePerChannel: [Double]?
        if settings.rmsePerChannelEnabled {
            let values = channelStats.map { stats -> Double in
                guard stats.count > 0 else { return .nan }
                return sqrt(stats.sumSquaredDiff / Double(stats.count))
            }
            guard let _ = meanIgnoringNaN(values) else {
                throw CubeMetricsComputationError.emptyData
            }
            rmsePerChannel = values
        }

        var psnrPerChannel: [Double]?
        var psnrPeaksPerChannel: [Double]?
        if settings.psnrPerChannelEnabled {
            var values: [Double] = []
            var peaks: [Double] = []
            values.reserveCapacity(signature.channels)
            peaks.reserveCapacity(signature.channels)
            for stats in channelStats {
                guard stats.count > 0 else {
                    values.append(.nan)
                    peaks.append(.nan)
                    continue
                }
                let rmse = sqrt(stats.sumSquaredDiff / Double(stats.count))
                let peak = try resolvePSNRPeak(
                    minValue: stats.minValue,
                    maxValue: stats.maxValue,
                    settings: settings
                )
                peaks.append(peak)
                if rmse == 0 {
                    values.append(.infinity)
                } else {
                    values.append(20.0 * log10(peak / rmse))
                }
            }
            guard let _ = meanIgnoringNaN(values) else {
                throw CubeMetricsComputationError.emptyData
            }
            psnrPerChannel = values
            psnrPeaksPerChannel = peaks
        }

        var ssimPerChannel: [Double]?
        if settings.ssimPerChannelEnabled {
            var values: [Double] = []
            values.reserveCapacity(signature.channels)
            for stats in channelStats {
                guard stats.count > 0 else {
                    values.append(.nan)
                    continue
                }
                let range = try resolveSSIMRange(
                    minValue: stats.minValue,
                    maxValue: stats.maxValue,
                    settings: settings
                )
                let value = computeSSIM(
                    sumX: stats.sumX,
                    sumY: stats.sumY,
                    sumXX: stats.sumXX,
                    sumYY: stats.sumYY,
                    sumXY: stats.sumXY,
                    count: stats.count,
                    dynamicRange: range,
                    k1: settings.ssimK1,
                    k2: settings.ssimK2
                )
                values.append(value)
            }
            guard let _ = meanIgnoringNaN(values) else {
                throw CubeMetricsComputationError.emptyData
            }
            ssimPerChannel = values
        }

        var samPerChannelDegrees: [Double]?
        if settings.samPerChannelEnabled {
            let values = channelStats.map { stats -> Double in
                let denominator = sqrt(stats.samNormX) * sqrt(stats.samNormY)
                guard denominator > settings.samEpsilon else { return .nan }
                let cosine = max(-1.0, min(1.0, stats.samDot / denominator))
                return acos(cosine) * 180.0 / .pi
            }
            guard let _ = meanIgnoringNaN(values) else {
                throw CubeMetricsComputationError.emptyData
            }
            samPerChannelDegrees = values
        }

        let rmseSummary = settings.rmsePerChannelEnabled
            ? (meanIgnoringNaN(rmsePerChannel ?? []) ?? rmseGlobal)
            : rmseGlobal
        let psnrSummary = settings.psnrPerChannelEnabled
            ? (meanIgnoringNaN(psnrPerChannel ?? []) ?? psnrGlobal)
            : psnrGlobal
        let psnrPeakSummary = settings.psnrPerChannelEnabled
            ? (meanIgnoringNaN(psnrPeaksPerChannel ?? []) ?? psnrPeakGlobal)
            : psnrPeakGlobal
        let ssimSummary = settings.ssimPerChannelEnabled
            ? (meanIgnoringNaN(ssimPerChannel ?? []) ?? ssimGlobal)
            : ssimGlobal
        let samSummary = settings.samPerChannelEnabled
            ? (meanIgnoringNaN(samPerChannelDegrees ?? []) ?? samDegreesGlobal)
            : samDegreesGlobal

        return CubeMetricsResult(
            rmse: rmseSummary,
            rmsePerChannel: rmsePerChannel,
            psnr: psnrSummary,
            psnrPeak: psnrPeakSummary,
            psnrPerChannel: psnrPerChannel,
            ssim: ssimSummary,
            ssimPerChannel: ssimPerChannel,
            samDegrees: samSummary,
            samPerChannelDegrees: samPerChannelDegrees,
            voxelCount: validVoxelCount
        )
    }

    private static func sampleValue(
        cube: HyperCube,
        axes: (channel: Int, height: Int, width: Int),
        x: Int,
        y: Int,
        channel: Int
    ) -> Double {
        let i0 = axes.channel == 0 ? channel : (axes.height == 0 ? y : x)
        let i1 = axes.channel == 1 ? channel : (axes.height == 1 ? y : x)
        let i2 = axes.channel == 2 ? channel : (axes.height == 2 ? y : x)
        return cube.getValue(i0: i0, i1: i1, i2: i2)
    }

    private static func resolvePSNRPeak(
        minValue: Double,
        maxValue: Double,
        settings: CubeMetricsSettings
    ) throws -> Double {
        switch settings.psnrPeakMode {
        case .dataRange:
            let range = maxValue - minValue
            if range > 0 {
                return range
            }
            let absMax = max(abs(maxValue), abs(minValue))
            return absMax > 0 ? absMax : 1.0
        case .custom:
            guard settings.psnrCustomPeak.isFinite, settings.psnrCustomPeak > 0 else {
                throw CubeMetricsComputationError.invalidPSNRPeak
            }
            return settings.psnrCustomPeak
        }
    }

    private static func resolveSSIMRange(
        minValue: Double,
        maxValue: Double,
        settings: CubeMetricsSettings
    ) throws -> Double {
        switch settings.ssimRangeMode {
        case .dataRange:
            let range = maxValue - minValue
            if range > 0 {
                return range
            }
            let absMax = max(abs(maxValue), abs(minValue))
            return absMax > 0 ? absMax : 1.0
        case .custom:
            guard settings.ssimCustomRange.isFinite, settings.ssimCustomRange > 0 else {
                throw CubeMetricsComputationError.invalidSSIMRange
            }
            return settings.ssimCustomRange
        }
    }

    private static func computeSSIM(
        sumX: Double,
        sumY: Double,
        sumXX: Double,
        sumYY: Double,
        sumXY: Double,
        count: Int,
        dynamicRange: Double,
        k1: Double,
        k2: Double
    ) -> Double {
        let n = Double(count)
        let meanX = sumX / n
        let meanY = sumY / n

        let varianceX = max(0.0, (sumXX / n) - meanX * meanX)
        let varianceY = max(0.0, (sumYY / n) - meanY * meanY)
        let covariance = (sumXY / n) - meanX * meanY

        let c1 = pow(k1 * dynamicRange, 2)
        let c2 = pow(k2 * dynamicRange, 2)

        let numerator = (2.0 * meanX * meanY + c1) * (2.0 * covariance + c2)
        let denominator = (meanX * meanX + meanY * meanY + c1) * (varianceX + varianceY + c2)
        guard denominator != 0 else { return 1.0 }
        return numerator / denominator
    }

    private static func meanIgnoringNaN(_ values: [Double]) -> Double? {
        let filtered = values.filter { !$0.isNaN }
        guard !filtered.isEmpty else { return nil }
        return filtered.reduce(0.0, +) / Double(filtered.count)
    }
}

