import SwiftUI

struct RangeWideColorControls: View {
    @EnvironmentObject var state: AppState
    let cube: HyperCube
    
    @State private var redStartWavelength: Double = 0
    @State private var redEndWavelength: Double = 0
    @State private var greenStartWavelength: Double = 0
    @State private var greenEndWavelength: Double = 0
    @State private var blueStartWavelength: Double = 0
    @State private var blueEndWavelength: Double = 0
    @State private var isSyncingInputs: Bool = false
    
    var body: some View {
        let mapping = state.colorSynthesisConfig.rangeMapping.clamped(maxChannelCount: max(state.channelCount, 0))
        let wavelengths = state.wavelengths
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.localized("rangewide.title"))
                        .font(.system(size: 11, weight: .medium))
                    rangeSummaryView(mapping: mapping, wavelengths: wavelengths)
                }
                Spacer()
            }
            
            ColorSynthesisRangeSliderView(
                channelCount: state.channelCount,
                cube: cube,
                layout: state.activeLayout,
                rangeMapping: mapping
            ) { newMapping in
                state.updateColorSynthesisRangeMapping(newMapping, userInitiated: true)
            }
            
            if let wavelengths, !wavelengths.isEmpty {
                wavelengthInputSection(mapping: mapping, wavelengths: wavelengths)
            } else {
                Text(state.localized("rangewide.wavelengths_unavailable"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            syncWavelengthInputs(mapping: mapping, wavelengths: wavelengths)
        }
        .onChange(of: state.colorSynthesisConfig.rangeMapping) { newValue in
            syncWavelengthInputs(mapping: newValue, wavelengths: wavelengths)
        }
        .onChange(of: state.wavelengths) { _ in
            syncWavelengthInputs(mapping: mapping, wavelengths: wavelengths)
        }
        .onChange(of: redStartWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
        .onChange(of: redEndWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
        .onChange(of: greenStartWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
        .onChange(of: greenEndWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
        .onChange(of: blueStartWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
        .onChange(of: blueEndWavelength) { _ in
            updateMappingFromWavelengthsIfNeeded(wavelengths)
        }
    }
    
    @ViewBuilder
    private func rangeSummaryView(mapping: RGBChannelRangeMapping, wavelengths: [Double]?) -> some View {
        let bounds = wavelengthBounds(wavelengths)
        VStack(alignment: .leading, spacing: 2) {
            if let bounds {
                Text(state.localizedFormat("rangewide.range_available", formatWavelength(bounds.min), formatWavelength(bounds.max)))
            } else {
                Text(state.localized("rangewide.range_no_data"))
            }
            Text(rangeInfoText(label: "R", range: mapping.red, wavelengths: wavelengths))
            Text(rangeInfoText(label: "G", range: mapping.green, wavelengths: wavelengths))
            Text(rangeInfoText(label: "B", range: mapping.blue, wavelengths: wavelengths))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private func wavelengthInputSection(mapping: RGBChannelRangeMapping, wavelengths: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            wavelengthRow(label: "R", color: .red, start: $redStartWavelength, end: $redEndWavelength, range: mapping.red, wavelengths: wavelengths)
            wavelengthRow(label: "G", color: .green, start: $greenStartWavelength, end: $greenEndWavelength, range: mapping.green, wavelengths: wavelengths)
            wavelengthRow(label: "B", color: .blue, start: $blueStartWavelength, end: $blueEndWavelength, range: mapping.blue, wavelengths: wavelengths)
        }
    }
    
    private func wavelengthRow(
        label: String,
        color: Color,
        start: Binding<Double>,
        end: Binding<Double>,
        range: RGBChannelRange,
        wavelengths: [Double]
    ) -> some View {
        let normalized = range.normalized
        let startLambda = wavelengthValue(for: normalized.start, wavelengths: wavelengths)
        let endLambda = wavelengthValue(for: normalized.end, wavelengths: wavelengths)
        let channelCount = max(normalized.end - normalized.start + 1, 1)
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 16, alignment: .leading)
                
                HStack(spacing: 6) {
                    TextField("", value: start, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text(state.localized("units.nm"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Text("—")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    TextField("", value: end, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text(state.localized("units.nm"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(
                state.localizedFormat(
                    "rangewide.channels_summary",
                    normalized.start,
                    normalized.end,
                    formatWavelength(startLambda),
                    formatWavelength(endLambda),
                    channelCount
                )
            )
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, 24)
        }
    }
    
    private func syncWavelengthInputs(mapping: RGBChannelRangeMapping, wavelengths: [Double]?) {
        guard let wavelengths, !wavelengths.isEmpty else { return }
        isSyncingInputs = true
        redStartWavelength = wavelengthValue(for: mapping.red.start, wavelengths: wavelengths)
        redEndWavelength = wavelengthValue(for: mapping.red.end, wavelengths: wavelengths)
        greenStartWavelength = wavelengthValue(for: mapping.green.start, wavelengths: wavelengths)
        greenEndWavelength = wavelengthValue(for: mapping.green.end, wavelengths: wavelengths)
        blueStartWavelength = wavelengthValue(for: mapping.blue.start, wavelengths: wavelengths)
        blueEndWavelength = wavelengthValue(for: mapping.blue.end, wavelengths: wavelengths)
        DispatchQueue.main.async {
            isSyncingInputs = false
        }
    }
    
    private func updateMappingFromWavelengthsIfNeeded(_ wavelengths: [Double]?) {
        guard !isSyncingInputs, let wavelengths, !wavelengths.isEmpty else { return }
        let redRange = rangeFromWavelengths(start: redStartWavelength, end: redEndWavelength, wavelengths: wavelengths)
        let greenRange = rangeFromWavelengths(start: greenStartWavelength, end: greenEndWavelength, wavelengths: wavelengths)
        let blueRange = rangeFromWavelengths(start: blueStartWavelength, end: blueEndWavelength, wavelengths: wavelengths)
        
        let newMapping = RGBChannelRangeMapping(red: redRange, green: greenRange, blue: blueRange)
        state.updateColorSynthesisRangeMapping(newMapping, userInitiated: true)
    }
    
    private func rangeFromWavelengths(start: Double, end: Double, wavelengths: [Double]) -> RGBChannelRange {
        let startIndex = nearestChannelIndex(to: start, wavelengths: wavelengths)
        let endIndex = nearestChannelIndex(to: end, wavelengths: wavelengths)
        let normalized = RGBChannelRange(start: startIndex, end: endIndex).normalized
        return normalized
    }
    
    private func nearestChannelIndex(to target: Double, wavelengths: [Double]) -> Int {
        guard !wavelengths.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDiff = abs(wavelengths[0] - target)
        
        for (index, wavelength) in wavelengths.enumerated() {
            let diff = abs(wavelength - target)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = index
            }
        }
        return bestIndex
    }
    
    private func wavelengthValue(for channel: Int, wavelengths: [Double]) -> Double {
        guard wavelengths.indices.contains(channel) else { return wavelengths.last ?? 0 }
        return wavelengths[channel]
    }
    
    private func wavelengthBounds(_ wavelengths: [Double]?) -> (min: Double, max: Double)? {
        guard let wavelengths, let minValue = wavelengths.min(), let maxValue = wavelengths.max() else {
            return nil
        }
        return (min: minValue, max: maxValue)
    }
    
    private func rangeInfoText(label: String, range: RGBChannelRange, wavelengths: [Double]?) -> String {
        let normalized = range.normalized
        let channelCount = max(normalized.end - normalized.start + 1, 1)
        if let wavelengths, wavelengths.indices.contains(normalized.start), wavelengths.indices.contains(normalized.end) {
            return state.localizedFormat(
                "rangewide.range_info_with_wavelength",
                label,
                normalized.start,
                normalized.end,
                formatWavelength(wavelengths[normalized.start]),
                formatWavelength(wavelengths[normalized.end]),
                channelCount
            )
        }
        return state.localizedFormat(
            "rangewide.range_info_channels_only",
            label,
            normalized.start,
            normalized.end,
            channelCount
        )
    }
    
    private func formatWavelength(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
