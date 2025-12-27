import SwiftUI
import Charts

struct GraphPanel: View {
    @EnvironmentObject var state: AppState
    @State private var selectedSampleID: UUID?
    @State private var editingSampleID: UUID?
    @FocusState private var hasFocus: Bool
    let panelWidth: CGFloat = 400
    
    private enum GraphMode {
        case inactive
        case points
        case roi
    }
    
    private var graphMode: GraphMode {
        switch state.activeAnalysisTool {
        case .spectrumGraph:
            return .points
        case .spectrumGraphROI:
            return .roi
        default:
            return .inactive
        }
    }
    
    private var panelTitle: String {
        switch graphMode {
        case .points:
            return "График спектра"
        case .roi:
            return "График спектра ROI"
        case .inactive:
            return "График спектра"
        }
    }
    
    private var panelIconName: String {
        switch graphMode {
        case .points:
            return "chart.xyaxis.line"
        case .roi:
            return "square.dashed.inset.filled"
        case .inactive:
            return "chart.xyaxis.line"
        }
    }
    
    private var panelStatusText: String {
        switch graphMode {
        case .points:
            return state.spectrumSamples.isEmpty ? "Нет сохранённых точек" : "Сохранено: \(state.spectrumSamples.count)"
        case .roi:
            return state.roiSamples.isEmpty ? "Нет сохранённых областей" : "Областей: \(state.roiSamples.count)"
        case .inactive:
            return "Инструмент не выбран"
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            toggleButton
            
            if state.isGraphPanelExpanded {
                expandedPanel
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.isGraphPanelExpanded)
    }
    
    private var expandedPanel: some View {
        VStack(spacing: 0) {
            panelHeader
            
            Divider()
            
            switch graphMode {
            case .inactive:
                inactiveState
            case .points:
                if state.displayedSpectrumSamples.isEmpty {
                    emptyState(
                        icon: "cursorarrow.click",
                        title: "Кликните на изображение",
                        subtitle: "чтобы увидеть спектр пикселя"
                    )
                } else {
                    pointChartSection(state.displayedSpectrumSamples)
                }
            case .roi:
                if state.displayedROISamples.isEmpty {
                    emptyState(
                        icon: "lasso.and.sparkles",
                        title: "Нарисуйте область на изображении",
                        subtitle: "чтобы увидеть спектр ROI"
                    )
                } else {
                    roiChartSection(state.displayedROISamples)
                }
            }
        }
        .frame(width: panelWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: -4, y: 0)
        .focusable()
        .focusEffectDisabled()
        .focused($hasFocus)
        .onAppear { hasFocus = true }
        .onDeleteCommand(perform: deleteSelectedSamples)
        .onChange(of: state.displayedSpectrumSamples) { samples in
            guard selectedSampleID != nil, graphMode == .points else { return }
            if !samples.contains(where: { $0.id == selectedSampleID }) {
                selectedSampleID = nil
            }
        }
        .onChange(of: state.displayedROISamples) { samples in
            guard selectedSampleID != nil, graphMode == .roi else { return }
            if !samples.contains(where: { $0.id == selectedSampleID }) {
                selectedSampleID = nil
            }
        }
        .onChange(of: state.activeAnalysisTool) { _ in
            selectedSampleID = nil
        }
    }
    
    private var panelHeader: some View {
        HStack {
            Image(systemName: panelIconName)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            
            Text(panelTitle)
                .font(.system(size: 12, weight: .semibold))
            
            Spacer()
            
            Text(panelStatusText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    private var inactiveState: some View {
        emptyState(
            icon: "slider.horizontal.3",
            title: "Выберите инструмент",
            subtitle: "Активируйте анализ в доке справа"
        )
    }
    
    
    private func samplesLegend(_ samples: [SpectrumSample], cubeName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            
            ForEach(samples) { sample in
                SampleRow(
                    sample: sample,
                    isSelected: selectedSampleID == sample.id,
                    title: sample.displayName ?? "\(cubeName): (\(sample.pixelX), \(sample.pixelY))",
                    onSelect: {
                        selectedSampleID = (selectedSampleID == sample.id) ? nil : sample.id
                        hasFocus = true
                    },
                    onRename: { newName in
                        state.renameSpectrumSample(id: sample.id, to: newName)
                    },
                    editingSampleID: $editingSampleID
                )
            }
            .padding(.top, 4)
        }
    }
    
    private func roiSamplesLegend(_ samples: [SpectrumROISample], cubeName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            
            ForEach(samples) { sample in
                ROISampleRow(
                    sample: sample,
                    isSelected: selectedSampleID == sample.id,
                    title: sample.displayName ?? "\(cubeName): (\(sample.rect.minX), \(sample.rect.minY)) – (\(sample.rect.maxX), \(sample.rect.maxY))",
                    onSelect: {
                        selectedSampleID = (selectedSampleID == sample.id) ? nil : sample.id
                        hasFocus = true
                    },
                    onRename: { newName in
                        state.renameROISample(id: sample.id, to: newName)
                    },
                    editingSampleID: $editingSampleID
                )
            }
            .padding(.top, 4)
        }
    }
    
    private var toggleButton: some View {
        Button(action: {
            state.toggleGraphPanel()
        }) {
            Image(systemName: state.isGraphPanelExpanded ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 56)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.isGraphPanelExpanded ? "Свернуть панель" : "Развернуть панель")
    }
}

extension GraphPanel {
    private func deleteSelectedSamples() {
        guard let selectedID = selectedSampleID else { return }
        switch graphMode {
        case .points:
            deletePointSamples(samplesMatching(ids: [selectedID]))
        case .roi:
            deleteROISamples(roiSamplesMatching(ids: [selectedID]))
        case .inactive:
            break
        }
    }
    
    private func deletePointSamples(_ samples: [SpectrumSample]) {
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
    
    private func deleteROISamples(_ samples: [SpectrumROISample]) {
        for sample in samples {
            if state.pendingROISample?.id == sample.id {
                state.pendingROISample = nil
            } else {
                state.removeROISample(with: sample.id)
            }
            if selectedSampleID == sample.id {
                selectedSampleID = nil
            }
        }
    }
    
    private func roiSamplesMatching(ids: [UUID]) -> [SpectrumROISample] {
        state.displayedROISamples.filter { ids.contains($0.id) }
    }
}

private struct SpectrumChartSeries: Identifiable {
    let id: UUID
    let values: [Double]
    let wavelengths: [Double]?
    let color: Color
}

private struct SampleRow: View {
    let sample: SpectrumSample
    let isSelected: Bool
    let title: String
    let onSelect: () -> Void
    let onRename: (String?) -> Void
    @Binding var editingSampleID: UUID?
    
    @State private var isEditing: Bool = false
    @State private var nameText: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sample.displayColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                )
            if isEditing {
                TextField("Имя", text: $nameText, onCommit: commitName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: 180)
            } else {
                Text(title)
                    .font(.system(size: 10))
            }
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
        .onLongPressGesture {
            startEditing()
        }
        .onAppear {
            nameText = sample.displayName ?? ""
        }
        .onChange(of: editingSampleID) { newValue in
            guard newValue == sample.id else { return }
            startEditing()
            editingSampleID = nil
        }
    }
    
    private func startEditing() {
        nameText = sample.displayName ?? ""
        isEditing = true
    }
    
    private func commitName() {
        isEditing = false
        onRename(nameText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct ROISampleRow: View {
    let sample: SpectrumROISample
    let isSelected: Bool
    let title: String
    let onSelect: () -> Void
    let onRename: (String?) -> Void
    @Binding var editingSampleID: UUID?
    
    @State private var isEditing: Bool = false
    @State private var nameText: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sample.displayColor)
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                )
            if isEditing {
                TextField("Имя", text: $nameText, onCommit: commitName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: 180)
            } else {
                Text(title)
                    .font(.system(size: 10))
            }
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
        .onLongPressGesture {
            startEditing()
        }
        .onAppear {
            nameText = sample.displayName ?? ""
        }
        .onChange(of: editingSampleID) { newValue in
            guard newValue == sample.id else { return }
            startEditing()
            editingSampleID = nil
        }
    }
    
    private func startEditing() {
        nameText = sample.displayName ?? ""
        isEditing = true
    }
    
    private func commitName() {
        isEditing = false
        onRename(nameText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension GraphPanel {
    @ViewBuilder
    private func pointChartSection(_ samples: [SpectrumSample]) -> some View {
        let usesWavelengths = samples.contains { $0.wavelengths != nil }
        let axisLabel = usesWavelengths ? "λ (нм)" : "Канал"
        let cubeName = state.cubeURL?.lastPathComponent ?? "Куб"
        let series = samples.map {
            SpectrumChartSeries(
                id: $0.id,
                values: $0.values,
                wavelengths: $0.wavelengths,
                color: $0.displayColor
            )
        }
        
        VStack(alignment: .leading, spacing: 8) {
            chartView(series: series, axisLabel: axisLabel)
            
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
                    HStack(spacing: 8) {
                        Button {
                            editingSampleID = sample.id
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Переименовать")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(role: .destructive) {
                            deletePointSamples([sample])
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
        }
        .padding(12)
    }
    
    @ViewBuilder
    private func roiChartSection(_ samples: [SpectrumROISample]) -> some View {
        let usesWavelengths = samples.contains { $0.wavelengths != nil }
        let axisLabel = usesWavelengths ? "λ (нм)" : "Канал"
        let cubeName = state.cubeURL?.lastPathComponent ?? "Куб"
        let series = samples.map {
            SpectrumChartSeries(
                id: $0.id,
                values: $0.values,
                wavelengths: $0.wavelengths,
                color: $0.displayColor
            )
        }
        
        VStack(alignment: .leading, spacing: 8) {
            chartView(series: series, axisLabel: axisLabel)
            
            roiSamplesLegend(samples, cubeName: cubeName)
            
            Picker("Метод", selection: $state.roiAggregationMode) {
                ForEach(SpectrumROIAggregationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 6) {
                if let pending = state.pendingROISample {
                    let rect = pending.rect
                    Text("Выбрана область: \(cubeName): (\(rect.minX), \(rect.minY)) – (\(rect.maxX), \(rect.maxY)) — не сохранена")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button(action: { state.savePendingROISample() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.square.fill")
                        Text("Сохранить область")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.pendingROISample == nil)
                
                if let selectedID = selectedSampleID,
                   let sample = samples.first(where: { $0.id == selectedID }) {
                    HStack(spacing: 8) {
                        Button {
                            editingSampleID = sample.id
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Переименовать")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(role: .destructive) {
                            deleteROISamples([sample])
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Удалить область")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
    }
    
    private func chartView(series: [SpectrumChartSeries], axisLabel: String) -> some View {
        let xValues: [Double] = series.flatMap { entry in
            entry.wavelengths ?? (0..<entry.values.count).map { Double($0) }
        }
        let minX = xValues.min() ?? 0
        let maxXRaw = xValues.max() ?? minX
        let adjustedMaxX = maxXRaw == minX ? minX + 1 : maxXRaw
        let domain = minX...adjustedMaxX
        
        return Chart {
            ForEach(series) { entry in
                let seriesID = entry.id.uuidString
                ForEach(Array(entry.values.enumerated()), id: \.offset) { index, value in
                    let xValue = entry.wavelengths?[safe: index] ?? Double(index)
                    LineMark(
                        x: .value(axisLabel, xValue),
                        y: .value("Интенсивность", value),
                        series: .value("Серия", seriesID)
                    )
                    .foregroundStyle(by: .value("Серия", seriesID))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartXAxisLabel(axisLabel)
        .chartYAxisLabel("I")
        .chartXScale(domain: domain)
        .chartForegroundStyleScale(
            domain: series.map { $0.id.uuidString },
            range: series.map { $0.color }
        )
        .chartLegend(.hidden)
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
    }
}
