import SwiftUI
import Charts

struct GraphPanel: View {
    @EnvironmentObject var state: AppState
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
            
            if let spectrum = state.spectrumData {
                spectrumChart(spectrum)
            } else {
                emptyState
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
            
            if let spectrum = state.spectrumData {
                Text("(\(spectrum.pixelX), \(spectrum.pixelY))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
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
    private func spectrumChart(_ spectrum: SpectrumData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(Array(spectrum.values.enumerated()), id: \.offset) { index, value in
                    let xValue: Double = spectrum.wavelengths?[safe: index] ?? Double(index)
                    LineMark(
                        x: .value(spectrum.wavelengths != nil ? "λ (нм)" : "Канал", xValue),
                        y: .value("Интенсивность", value)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXAxisLabel(spectrum.wavelengths != nil ? "λ (нм)" : "Канал")
            .chartYAxisLabel("I")
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
            
            statisticsView(spectrum)
        }
        .padding(12)
    }
    
    private func statisticsView(_ spectrum: SpectrumData) -> some View {
        let values = spectrum.values
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 0
        let avgVal = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            
            HStack(spacing: 16) {
                StatItem(label: "Min", value: minVal)
                StatItem(label: "Max", value: maxVal)
                StatItem(label: "Avg", value: avgVal)
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

private struct StatItem: View {
    let label: String
    let value: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(formatValue(value))
                .font(.system(size: 10, design: .monospaced))
        }
    }
    
    private func formatValue(_ val: Double) -> String {
        if abs(val) < 0.001 || abs(val) >= 10000 {
            return String(format: "%.2e", val)
        }
        return String(format: "%.4f", val)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

