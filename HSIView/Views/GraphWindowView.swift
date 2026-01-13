import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum GraphWindowDataset: String, CaseIterable, Identifiable {
    case points
    case roi
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .points: return "Точки"
        case .roi: return "ROI"
        }
    }
}

private enum GraphWindowStyle: String, CaseIterable, Identifiable {
    case lines
    case linesAndPoints
    case area
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .lines: return "Линии"
        case .linesAndPoints: return "Линии + точки"
        case .area: return "Площадь"
        }
    }
}

private enum GraphPalette: String, CaseIterable, Identifiable {
    case `default`
    case warm
    case cool
    case mono
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .default: return "Стандартная"
        case .warm: return "Тёплая"
        case .cool: return "Холодная"
        case .mono: return "Монохром"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .default:
            return SpectrumColorPalette.colors.map { Color($0) }
        case .warm:
            return [.orange, .red, .yellow, .pink, .brown]
        case .cool:
            return [.blue, .mint, .teal, .purple, .cyan]
        case .mono:
            return [.gray, .black, .secondary, .primary]
        }
    }
}

private enum GraphExportFormat {
    case png
    case pdf
    
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .pdf: return "pdf"
        }
    }
    
    var title: String {
        switch self {
        case .png: return "PNG"
        case .pdf: return "PDF"
        }
    }
}

private struct GraphSeries: Identifiable, Equatable {
    let id: UUID
    let title: String
    let values: [Double]
    let wavelengths: [Double]?
    let defaultColor: Color
}

struct GraphWindowView: View {
    @EnvironmentObject var state: AppState
    
    @State private var dataset: GraphWindowDataset = .points
    @State private var style: GraphWindowStyle = .linesAndPoints
    @State private var palette: GraphPalette = .default
    @State private var customColors: [UUID: Color] = [:]
    @State private var showLegend: Bool = true
    @State private var showGrid: Bool = true
    @State private var lineWidth: Double = 1.5
    @State private var pointSize: Double = 24
    
    @State private var autoScaleX: Bool = true
    @State private var autoScaleY: Bool = true
    @State private var xMin: Double = 0
    @State private var xMax: Double = 1000
    @State private var yMin: Double = 0
    @State private var yMax: Double = 1
    
    var body: some View {
        HStack(spacing: 0) {
            GlassEffectContainerWrapper {
                settingsPanel
                    .frame(width: 240)
                    .glassBackground(cornerRadius: 0)
            }
            
            Divider()
            
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                Divider()
                
            content
                    .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear {
            applyPalette()
            updateAxisBounds()
        }
        .onChange(of: palette) { _ in
            applyPalette()
        }
        .onChange(of: series) { _ in
            pruneColors()
            applyPaletteIfNeeded()
            if autoScaleX || autoScaleY {
                updateAxisBounds()
            }
        }
    }
    
    private var settingsPanel: some View {
        GlassPanel(cornerRadius: 0, padding: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Данные") {
                        Picker("Источник", selection: $dataset) {
                            ForEach(GraphWindowDataset.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    settingsSection("Отображение") {
                        Picker("Стиль линий", selection: $style) {
                            ForEach(GraphWindowStyle.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        
                        Picker("Палитра", selection: $palette) {
                            ForEach(GraphPalette.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        
                        HStack {
                            Text("Толщина линии")
                            Spacer()
                            Text(String(format: "%.1f", lineWidth))
                                .foregroundColor(.secondary)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: $lineWidth, in: 0.5...4, step: 0.5)
                        
                        if style == .linesAndPoints {
                            HStack {
                                Text("Размер точек")
                                Spacer()
                                Text(String(format: "%.0f", pointSize))
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: $pointSize, in: 8...48, step: 4)
                        }
                    }
                    
                    settingsSection("Ось X") {
                        Toggle("Авто масштаб", isOn: $autoScaleX)
                            .onChange(of: autoScaleX) { auto in
                                if auto { updateAxisBounds() }
                            }
                        
                        if !autoScaleX {
                            HStack {
                                Text("Мин")
                                TextField("", value: $xMin, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("Макс")
                                TextField("", value: $xMax, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            .font(.system(size: 11))
                        }
                    }
                    
                    settingsSection("Ось Y") {
                        Toggle("Авто масштаб", isOn: $autoScaleY)
                            .onChange(of: autoScaleY) { auto in
                                if auto { updateAxisBounds() }
                            }
                        
                        if !autoScaleY {
                            HStack {
                                Text("Мин")
                                TextField("", value: $yMin, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("Макс")
                                TextField("", value: $yMax, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            .font(.system(size: 11))
                        }
                    }
                    
                    settingsSection("Элементы") {
                        Toggle("Показать легенду", isOn: $showLegend)
                        Toggle("Показать сетку", isOn: $showGrid)
                    }
                    
                    Spacer()
                }
                .padding(12)
            }
        }
    }
    
    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
    
    private var header: some View {
        GlassEffectContainerWrapper {
            GlassPanel(cornerRadius: 12, padding: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                    
                    Text("График спектров")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    Text("\(series.count) серий")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    exportMenu
                }
            }
        }
    }
    
    private var exportMenu: some View {
        Menu {
            Button("Экспорт PNG (1800×1200)") { exportGraph(as: .png, scale: 2) }
            Button("Экспорт PNG (900×600)") { exportGraph(as: .png, scale: 1) }
            Divider()
            Button("Экспорт PDF") { exportGraph(as: .pdf, scale: 2) }
        } label: {
            Label("Экспорт", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
        }
    }
    
    private var content: some View {
        HStack(spacing: 16) {
            chartContainer
            if showLegend {
                legend
                    .frame(width: 220)
            }
        }
    }
    
    private var chartContainer: some View {
        Group {
            if series.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Нет данных для отображения")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Сохраните точки или области в панели графика")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chartView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            }
        }
    }
    
    private var legend: some View {
        GlassEffectContainerWrapper {
            GlassPanel(cornerRadius: 12, padding: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Легенда")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(series) { item in
                                let colorBinding = Binding<Color>(
                                    get: { color(for: item) },
                                    set: { newColor in
                                        customColors[item.id] = newColor
                                    }
                                )
                                HStack(spacing: 8) {
                                    ColorPicker("", selection: colorBinding, supportsOpacity: false)
                                        .labelsHidden()
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        Text("\(item.values.count) точек")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var chartView: some View {
        Chart {
            ForEach(series) { item in
                let seriesColor = color(for: item)
                let seriesID = item.id.uuidString
                
            if let wavelengths = item.wavelengths {
                ForEach(Array(wavelengths.enumerated()), id: \.offset) { idx, lambda in
                    let value = item.values[safe: idx] ?? 0
                        chartMarks(x: lambda, y: value, seriesID: seriesID, color: seriesColor)
                }
            } else {
                ForEach(Array(item.values.enumerated()), id: \.offset) { idx, value in
                        chartMarks(x: Double(idx), y: value, seriesID: seriesID, color: seriesColor)
                    }
                }
            }
        }
        .chartXAxisLabel(series.first?.wavelengths != nil ? "λ (нм)" : "Канал")
        .chartYAxisLabel("Интенсивность")
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartForegroundStyleScale(
            domain: series.map { $0.id.uuidString },
            range: series.map { color(for: $0) }
        )
        .padding(16)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: showGrid ? 8 : 5)) { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
                AxisTick()
                AxisValueLabel()
                    .font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: showGrid ? 6 : 4)) { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
                AxisTick()
                AxisValueLabel()
                    .font(.system(size: 10))
            }
        }
    }
    
    @ChartContentBuilder
    private func chartMarks(x: Double, y: Double, seriesID: String, color: Color) -> some ChartContent {
        switch style {
        case .lines:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
            
        case .linesAndPoints:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
            
            PointMark(
                x: .value("X", x),
                y: .value("Y", y)
            )
            .foregroundStyle(color)
            .symbolSize(pointSize)
            
        case .area:
            AreaMark(
                x: .value("X", x),
                yStart: .value("YStart", areaBaseline),
                yEnd: .value("YEnd", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(0.25))
            
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
    }
    
    private var xDomain: ClosedRange<Double> {
        if autoScaleX {
            return computedXMin...computedXMax
        }
        return xMin...max(xMin + 1, xMax)
    }
    
    private var yDomain: ClosedRange<Double> {
        if autoScaleY {
            return computedYMin...computedYMax
        }
        return yMin...max(yMin + 0.001, yMax)
    }
    
    private var areaBaseline: Double {
        let domain = yDomain
        return domain.contains(0) ? 0 : domain.lowerBound
    }
    
    private var computedXMin: Double {
        let allX = series.flatMap { s -> [Double] in
            if let w = s.wavelengths { return w }
            return (0..<s.values.count).map { Double($0) }
        }
        return allX.min() ?? 0
    }
    
    private var computedXMax: Double {
        let allX = series.flatMap { s -> [Double] in
            if let w = s.wavelengths { return w }
            return (0..<s.values.count).map { Double($0) }
        }
        let m = allX.max() ?? 1
        return m == computedXMin ? m + 1 : m
    }
    
    private var computedYMin: Double {
        let allY = series.flatMap { $0.values }
        return allY.min() ?? 0
    }
    
    private var computedYMax: Double {
        let allY = series.flatMap { $0.values }
        let m = allY.max() ?? 1
        return m == computedYMin ? m + 0.001 : m
    }
    
    private func updateAxisBounds() {
        if autoScaleX {
            xMin = computedXMin
            xMax = computedXMax
        }
        if autoScaleY {
            yMin = computedYMin
            yMax = computedYMax
        }
    }
    
    private var series: [GraphSeries] {
        switch dataset {
        case .points:
            return state.spectrumSamples.map {
                GraphSeries(
                    id: $0.id,
                    title: $0.displayName ?? "(\($0.pixelX), \($0.pixelY))",
                    values: $0.values,
                    wavelengths: $0.wavelengths,
                    defaultColor: Color($0.nsColor)
                )
            }
        case .roi:
            return state.roiSamples.map {
                GraphSeries(
                    id: $0.id,
                    title: $0.displayName ?? "ROI (\($0.rect.minX), \($0.rect.minY))",
                    values: $0.values,
                    wavelengths: $0.wavelengths,
                    defaultColor: Color($0.nsColor)
                )
            }
        }
    }
    
    private func color(for series: GraphSeries) -> Color {
        if let custom = customColors[series.id] {
            return custom
        }
        return series.defaultColor
    }
    
    private func applyPalette() {
        guard !series.isEmpty else { return }
        let colors = palette.colors
        guard !colors.isEmpty else { return }
        var mapping: [UUID: Color] = [:]
        for (idx, item) in series.enumerated() {
            mapping[item.id] = colors[idx % colors.count]
        }
        customColors = mapping
    }
    
    private func applyPaletteIfNeeded() {
        if customColors.isEmpty {
            applyPalette()
        }
    }
    
    private func pruneColors() {
        let ids = Set(series.map(\.id))
        customColors = customColors.filter { ids.contains($0.key) }
    }
    
    private func exportGraph(as format: GraphExportFormat, scale: CGFloat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = format == .png ? [UTType.png] : [UTType.pdf]
        panel.nameFieldStringValue = "graph.\(format.fileExtension)"
        panel.title = "Экспорт графика"
        panel.message = "Выберите место для сохранения \(format.title)"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        let exportView = ExportableChartView(
            series: series,
            colors: series.map { color(for: $0) },
            style: style,
            lineWidth: lineWidth,
            pointSize: pointSize,
            showGrid: showGrid,
            xDomain: xDomain,
            yDomain: yDomain,
            xAxisLabel: series.first?.wavelengths != nil ? "λ (нм)" : "Канал"
        )
        .frame(width: 900 * scale, height: 600 * scale)
        .background(Color.white)
        
        let hosting = NSHostingView(rootView: exportView)
        let size = NSSize(width: 900 * scale, height: 600 * scale)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        
        switch format {
        case .png:
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        case .pdf:
            let pdfData = hosting.dataWithPDF(inside: hosting.bounds)
            try? pdfData.write(to: url)
        }
    }
    
}

private struct ExportableChartView: View {
    let series: [GraphSeries]
    let colors: [Color]
    let style: GraphWindowStyle
    let lineWidth: Double
    let pointSize: Double
    let showGrid: Bool
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    let xAxisLabel: String
    
    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.element.id) { idx, item in
                let seriesColor = colors[safe: idx] ?? .blue
                let seriesID = item.id.uuidString
                
                if let wavelengths = item.wavelengths {
                    ForEach(Array(wavelengths.enumerated()), id: \.offset) { i, lambda in
                        let value = item.values[safe: i] ?? 0
                        chartMarks(x: lambda, y: value, seriesID: seriesID, color: seriesColor)
                    }
                } else {
                    ForEach(Array(item.values.enumerated()), id: \.offset) { i, value in
                        chartMarks(x: Double(i), y: value, seriesID: seriesID, color: seriesColor)
                    }
                }
            }
        }
        .chartXAxisLabel(xAxisLabel)
        .chartYAxisLabel("Интенсивность")
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartForegroundStyleScale(
            domain: series.map { $0.id.uuidString },
            range: colors
        )
        .padding(24)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 8)) { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                }
                AxisTick()
                AxisValueLabel()
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                }
                AxisTick()
                AxisValueLabel()
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black)
            }
        }
    }
    
    @ChartContentBuilder
    private func chartMarks(x: Double, y: Double, seriesID: String, color: Color) -> some ChartContent {
        switch style {
        case .lines:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
            
        case .linesAndPoints:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
            
            PointMark(
                x: .value("X", x),
                y: .value("Y", y)
            )
            .foregroundStyle(color)
            .symbolSize(pointSize)
            
        case .area:
            AreaMark(
                x: .value("X", x),
                yStart: .value("YStart", areaBaseline),
                yEnd: .value("YEnd", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(0.25))
            
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: lineWidth))
        }
    }
    
    private var areaBaseline: Double {
        yDomain.contains(0) ? 0 : yDomain.lowerBound
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
