import SwiftUI
import Charts

struct GraphPanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedSampleID: UUID?
    @FocusState private var hasFocus: Bool
    let panelWidth: CGFloat = 400
    
    var body: some View {
        ZStack(alignment: .leading) {
            if state.isGraphPanelExpanded {
                expandedPanel
                    .transition(.move(edge: .trailing))
            }
            
            toggleButton
        }
        .animation(.easeInOut(duration: 0.25), value: state.isGraphPanelExpanded)
    }
    
    private var expandedPanel: some View {
        VStack(spacing: 0) {
            panelHeader
            
            Divider()
            
            if state.displayedSpectrumSamples.isEmpty {
                emptyState
            } else {
                spectrumChart(state.displayedSpectrumSamples)
            }
        }
        .frame(width: panelWidth)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: -4, y: 0)
    }
    
    private var panelHeader: some View {
        HStack {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            
            Text("График спектра")
                .font(.system(size: 12, weight: .semibold))
            
            Spacer()
            
            Text(state.spectrumSamples.isEmpty ? "Нет сохранённых точек" : "Сохранено: \(state.spectrumSamples.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            
            Text("Кликните на изображение")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("чтобы увидеть спектр пикселя")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    @ViewBuilder
    private func spectrumChart(_ samples: [SpectrumSample]) -> some View {
        let usesWavelengths = samples.contains { $0.wavelengths != nil }
        let axisLabel = usesWavelengths ? "λ (нм)" : "Канал"
        let xAllValues: [Double] = samples.flatMap { sample in
            let xs = sample.wavelengths ?? (0..<sample.values.count).map { Double($0) }
            return xs
        }
        let minX = xAllValues.min() ?? 0
        let maxXRaw = xAllValues.max() ?? minX
        let adjustedMaxX = maxXRaw == minX ? minX + 1 : maxXRaw
        let domain = minX...adjustedMaxX
        
        let seriesMapping = samples.map { ($0.id.uuidString, $0.displayColor) }
        
        let cubeName = state.cubeURL?.lastPathComponent ?? "Куб"
        
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(samples) { sample in
                    let seriesID = sample.id.uuidString
                    ForEach(Array(sample.values.enumerated()), id: \.offset) { index, value in
                        let xValue: Double = sample.wavelengths?[safe: index] ?? Double(index)
                        LineMark(
                            x: .value(axisLabel, xValue),
                            y: .value("Интенсивность", value),
                            series: .value("Точка", seriesID)
                        )
                        .foregroundStyle(by: .value("Точка", seriesID))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartXAxisLabel(axisLabel)
            .chartYAxisLabel("I")
            .chartXScale(domain: domain)
            .chartForegroundStyleScale(
                domain: seriesMapping.map { $0.0 },
                range: seriesMapping.map { $0.1 }
            )
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick()
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisTick()
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .frame(height: 280)
            .padding(.horizontal, 4)
            
            samplesLegend(samples, cubeName: cubeName)
            
            VStack(alignment: .leading, spacing: 6) {
                if let pending = state.pendingSpectrumSample {
                    Text("Выбрана точка: \(cubeName): (\(pending.pixelX), \(pending.pixelY)) — не сохранена")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button(action: { state.savePendingSpectrumSample() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                        Text("Сохранить точку")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.pendingSpectrumSample == nil)
                
                if let selectedID = selectedSampleID,
                   let sample = samples.first(where: { $0.id == selectedID }) {
                    Button(role: .destructive) {
                        deleteSamples([sample])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Удалить точку")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onAppear { hasFocus = true }
        .onDeleteCommand(perform: deleteSelectedSamples)
        .onChange(of: state.displayedSpectrumSamples) { samples in
            guard let selectedID = selectedSampleID else { return }
            if !samples.contains(where: { $0.id == selectedID }) {
                selectedSampleID = nil
            }
        }
    }
    
    private func samplesLegend(_ samples: [SpectrumSample], cubeName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            
            ForEach(samples) { sample in
                SampleRow(
                    sample: sample,
                    isSelected: selectedSampleID == sample.id,
                    title: "\(cubeName): (\(sample.pixelX), \(sample.pixelY))",
                    onSelect: {
                        selectedSampleID = (selectedSampleID == sample.id) ? nil : sample.id
                        hasFocus = true
                    }
                )
            }
            .padding(.top, 4)
        }
    }
    
    private var toggleButton: some View {
        Button(action: {
            state.toggleGraphPanel()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 16, height: 48)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: -2, y: 0)
                
                Image(systemName: state.isGraphPanelExpanded ? "chevron.right" : "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .offset(x: state.isGraphPanelExpanded ? -8 : 0)
        .help(state.isGraphPanelExpanded ? "Свернуть панель" : "Развернуть панель")
    }
}

extension GraphPanel {
    private func deleteSelectedSamples() {
        guard let selectedID = selectedSampleID else { return }
        deleteSamples(samplesMatching(ids: [selectedID]))
    }
    
    private func deleteSamples(_ samples: [SpectrumSample]) {
        for sample in samples {
            if state.pendingSpectrumSample?.id == sample.id {
                state.pendingSpectrumSample = nil
            } else {
                state.removeSpectrumSample(with: sample.id)
            }
            if selectedSampleID == sample.id {
                selectedSampleID = nil
            }
        }
    }
    
    private func samplesMatching(ids: [UUID]) -> [SpectrumSample] {
        state.displayedSpectrumSamples.filter { ids.contains($0.id) }
    }
}

private struct SampleRow: View {
    let sample: SpectrumSample
    let isSelected: Bool
    let title: String
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sample.displayColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                )
            Text(title)
                .font(.system(size: 10))
            Spacer()
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
