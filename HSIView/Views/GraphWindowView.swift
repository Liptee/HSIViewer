import SwiftUI
import Charts
import UniformTypeIdentifiers

private enum GraphWindowDataset: String, CaseIterable, Identifiable {
    case points
    case roi
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .points: return L("graph.window.dataset.points")
        case .roi: return L("graph.window.dataset.roi")
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
        case .lines: return L("graph.window.style.lines")
        case .linesAndPoints: return L("graph.window.style.lines_points")
        case .area: return L("graph.window.style.area")
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
        case .default: return L("graph.window.palette.default")
        case .warm: return L("graph.window.palette.warm")
        case .cool: return L("graph.window.palette.cool")
        case .mono: return L("graph.window.palette.mono")
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
    case json
    
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .pdf: return "pdf"
        case .json: return "json"
        }
    }
    
    var title: String {
        switch self {
        case .png: return "PNG"
        case .pdf: return "PDF"
        case .json: return "JSON"
        }
    }
}

private struct GraphSeries: Identifiable, Equatable {
    let id: UUID
    let title: String
    let values: [Double]
    let wavelengths: [Double]?
    let defaultColor: Color
    let sourceName: String?
    
    init(id: UUID, title: String, values: [Double], wavelengths: [Double]?, defaultColor: Color, sourceName: String? = nil) {
        self.id = id
        self.title = title
        self.values = values
        self.wavelengths = wavelengths
        self.defaultColor = defaultColor
        self.sourceName = sourceName
    }
}

private struct GraphSeriesJSONPayload: Encodable {
    let wavelengths: [Double]
    let intensity: [Double]
}

struct GraphWindowView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var spectrumCache: LibrarySpectrumCache
    
    @State private var dataset: GraphWindowDataset = .points
    private var style: GraphWindowStyle {
        get { GraphWindowStyle(rawValue: state.graphWindowStyle) ?? .lines }
        nonmutating set { state.graphWindowStyle = newValue.rawValue }
    }
    
    private var palette: GraphPalette {
        get { GraphPalette(rawValue: state.graphWindowPalette) ?? .default }
        nonmutating set { state.graphWindowPalette = newValue.rawValue }
    }
    
    private var showLegend: Bool {
        get { state.graphWindowShowLegend }
        nonmutating set { state.graphWindowShowLegend = newValue }
    }
    
    private var showGrid: Bool {
        get { state.graphWindowShowGrid }
        nonmutating set { state.graphWindowShowGrid = newValue }
    }
    
    private var lineWidth: Double {
        get { state.graphWindowLineWidth }
        nonmutating set { state.graphWindowLineWidth = newValue }
    }
    
    private var pointSize: Double {
        get { state.graphWindowPointSize }
        nonmutating set { state.graphWindowPointSize = newValue }
    }
    
    private var autoScaleX: Bool {
        get { state.graphWindowAutoScaleX }
        nonmutating set { state.graphWindowAutoScaleX = newValue }
    }
    
    private var autoScaleY: Bool {
        get { state.graphWindowAutoScaleY }
        nonmutating set { state.graphWindowAutoScaleY = newValue }
    }
    
    private var xMin: Double {
        get { state.graphWindowXMin }
        nonmutating set { state.graphWindowXMin = newValue }
    }
    
    private var xMax: Double {
        get { state.graphWindowXMax }
        nonmutating set { state.graphWindowXMax = newValue }
    }
    
    private var yMin: Double {
        get { state.graphWindowYMin }
        nonmutating set { state.graphWindowYMin = newValue }
    }
    
    private var yMax: Double {
        get { state.graphWindowYMax }
        nonmutating set { state.graphWindowYMax = newValue }
    }
    
    private var styleBinding: Binding<GraphWindowStyle> {
        Binding(get: { style }, set: { style = $0 })
    }
    
    private var paletteBinding: Binding<GraphPalette> {
        Binding(get: { palette }, set: { palette = $0 })
    }
    
    private var showLegendBinding: Binding<Bool> {
        Binding(get: { showLegend }, set: { showLegend = $0 })
    }
    
    private var showGridBinding: Binding<Bool> {
        Binding(get: { showGrid }, set: { showGrid = $0 })
    }
    
    private var lineWidthBinding: Binding<Double> {
        Binding(get: { lineWidth }, set: { lineWidth = $0 })
    }
    
    private var pointSizeBinding: Binding<Double> {
        Binding(get: { pointSize }, set: { pointSize = $0 })
    }
    
    private var autoScaleXBinding: Binding<Bool> {
        Binding(get: { autoScaleX }, set: { autoScaleX = $0 })
    }
    
    private var autoScaleYBinding: Binding<Bool> {
        Binding(get: { autoScaleY }, set: { autoScaleY = $0 })
    }
    
    private var xMinBinding: Binding<Double> {
        Binding(get: { xMin }, set: { xMin = $0 })
    }
    
    private var xMaxBinding: Binding<Double> {
        Binding(get: { xMax }, set: { xMax = $0 })
    }
    
    private var yMinBinding: Binding<Double> {
        Binding(get: { yMin }, set: { yMin = $0 })
    }
    
    private var yMaxBinding: Binding<Double> {
        Binding(get: { yMax }, set: { yMax = $0 })
    }
    
    @State private var showLibraryPanel: Bool = true
    
    init(spectrumCache: LibrarySpectrumCache) {
        self._spectrumCache = ObservedObject(wrappedValue: spectrumCache)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if showLibraryPanel {
                GlassEffectContainerWrapper {
                    libraryPanel
                        .frame(width: 220)
                        .glassBackground(cornerRadius: 0)
                }
                
                Divider()
            }
            
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
        .frame(minWidth: showLibraryPanel ? 1100 : 900, minHeight: 560)
        .onAppear {
            pruneGraphSettings()
            applyPaletteForMissing()
            updateAxisBounds()
        }
        .onChange(of: palette) { _ in
            applyPaletteForMissing()
        }
        .onChange(of: series) { _ in
            pruneGraphSettings()
            applyPaletteForMissing()
            if autoScaleX || autoScaleY {
                updateAxisBounds()
            }
        }
        .onChange(of: state.libraryEntries) { _ in
            pruneVisibleEntries()
        }
    }
    
    private var libraryPanel: some View {
        GlassPanel(cornerRadius: 0, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(L("graph.window.sources"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button {
                        showLibraryPanel = false
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(L("graph.window.show_all")) {
                        showAllSources()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(L("graph.window.hide_all")) {
                        hideAllSources()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(state.libraryEntries) { entry in
                            libraryEntryRow(entry: entry)
                        }
                        
                        if state.libraryEntries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text(L("graph.window.empty.no_saved_spectra"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(L("graph.window.empty.add_points_roi"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
    
    private func libraryEntryRow(entry: CubeLibraryEntry) -> some View {
        let counts = sampleCounts(for: entry)
        let hasSamples = counts.spectrum > 0 || counts.roi > 0
        let isVisible = spectrumCache.visibleEntries.contains(entry.id)
        let isCurrentImage = entry.canonicalPath == state.cubeURL?.standardizedFileURL.path
        
        return HStack(spacing: 8) {
            Button {
                guard hasSamples else { return }
                spectrumCache.toggleVisibility(libraryID: entry.id)
            } label: {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isVisible ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!hasSamples)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.system(size: 11, weight: isCurrentImage ? .semibold : .regular))
                        .lineLimit(1)
                    
                    if isCurrentImage {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor)
                    }
                }
                
                HStack(spacing: 8) {
                    if counts.spectrum > 0 {
                        Label("\(counts.spectrum)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if counts.roi > 0 {
                        Label("\(counts.roi)", systemImage: "rectangle.dashed")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if !hasSamples {
                        Text(L("graph.window.no_data"))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isVisible && hasSamples ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
    
    private var settingsPanel: some View {
        GlassPanel(cornerRadius: 0, padding: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !showLibraryPanel {
                        Button {
                            showLibraryPanel = true
                        } label: {
                            Label(L("graph.window.show_library"), systemImage: "sidebar.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    settingsSection(L("graph.window.section.data")) {
                        Picker(L("graph.window.source"), selection: $dataset) {
                            ForEach(GraphWindowDataset.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    settingsSection(L("graph.window.section.display")) {
                        Picker(L("graph.window.line_style"), selection: styleBinding) {
                            ForEach(GraphWindowStyle.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        
                        Picker(L("graph.window.palette"), selection: paletteBinding) {
                            ForEach(GraphPalette.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        
                        HStack {
                            Text(L("graph.window.line_width"))
                            Spacer()
                            Text(String(format: "%.1f", lineWidth))
                                .foregroundColor(.secondary)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: lineWidthBinding, in: 0.5...4, step: 0.5)
                        
                        if style == .linesAndPoints {
                            HStack {
                                Text(L("graph.window.point_size"))
                                Spacer()
                                Text(String(format: "%.0f", pointSize))
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: pointSizeBinding, in: 8...48, step: 4)
                        }
                    }
                    
                    settingsSection(L("graph.window.section.axis_x")) {
                        Toggle(L("graph.window.auto_scale"), isOn: autoScaleXBinding)
                            .onChange(of: autoScaleX) { auto in
                                if auto { updateAxisBounds() }
                            }
                        
                        if !autoScaleX {
                            HStack {
                                Text(L("graph.window.min"))
                                TextField("", value: xMinBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text(L("graph.window.max"))
                                TextField("", value: xMaxBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            .font(.system(size: 11))
                        }
                    }
                    
                    settingsSection(L("graph.window.section.axis_y")) {
                        Toggle(L("graph.window.auto_scale"), isOn: autoScaleYBinding)
                            .onChange(of: autoScaleY) { auto in
                                if auto { updateAxisBounds() }
                            }
                        
                        if !autoScaleY {
                            HStack {
                                Text(L("graph.window.min"))
                                TextField("", value: yMinBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text(L("graph.window.max"))
                                TextField("", value: yMaxBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                            .font(.system(size: 11))
                        }
                    }
                    
                    settingsSection(L("graph.window.section.elements")) {
                        Toggle(L("graph.window.show_legend"), isOn: showLegendBinding)
                        Toggle(L("graph.window.show_grid"), isOn: showGridBinding)
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
                    
                    Text(L("graph.window.title"))
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    Text(LF("graph.window.header.series_count", series.count, visibleSourceCount))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    exportMenu
                }
            }
        }
    }
    
    private var exportMenu: some View {
        Menu {
            Button(L("graph.window.export.png_large")) { exportGraph(as: .png, scale: 2) }
            Button(L("graph.window.export.png_small")) { exportGraph(as: .png, scale: 1) }
            Divider()
            Button(L("graph.window.export.pdf")) { exportGraph(as: .pdf, scale: 2) }
            Button(L("graph.window.export.json")) { exportGraph(as: .json, scale: 1) }
        } label: {
            Label(L("graph.window.export"), systemImage: "square.and.arrow.up")
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
                    Text(L("graph.window.empty.no_data_to_display"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(L("graph.window.empty.save_points_or_regions"))
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
                        Text(L("graph.window.legend"))
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
                                        setCustomColor(newColor, for: item.id)
                                    }
                                )
                                HStack(spacing: 8) {
                                    ColorPicker("", selection: colorBinding, supportsOpacity: false)
                                        .labelsHidden()
                                        .frame(width: 28)
                                    Button(action: { toggleSeriesVisibility(id: item.id) }) {
                                        Image(systemName: state.graphSeriesHiddenIDs.contains(item.id) ? "eye.slash" : "eye")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(state.graphSeriesHiddenIDs.contains(item.id) ? .secondary : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    SeriesStyleButton(
                                        title: item.title,
                                        initialStyle: effectiveStyle(for: item),
                                        onSave: { newStyle in
                                            state.graphSeriesOverrides[item.id] = newStyle
                                        },
                                        onReset: {
                                            state.graphSeriesOverrides[item.id] = nil
                                        }
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            Text(LF("graph.window.points_count", item.values.count))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            if let source = item.sourceName {
                                                Text("•")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.secondary)
                                                Text(source)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
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
    
    private struct SeriesStyleButton: View {
        let title: String
        let initialStyle: SeriesStyleOverride
        let onSave: (SeriesStyleOverride) -> Void
        let onReset: () -> Void
        
        @State private var isPresented: Bool = false
        @State private var linePattern: SeriesLinePattern
        @State private var lineWidth: Double
        @State private var opacity: Double
        @State private var showPoints: Bool
        
        init(
            title: String,
            initialStyle: SeriesStyleOverride,
            onSave: @escaping (SeriesStyleOverride) -> Void,
            onReset: @escaping () -> Void
        ) {
            self.title = title
            self.initialStyle = initialStyle
            self.onSave = onSave
            self.onReset = onReset
            _linePattern = State(initialValue: initialStyle.linePattern)
            _lineWidth = State(initialValue: initialStyle.lineWidth)
            _opacity = State(initialValue: initialStyle.opacity)
            _showPoints = State(initialValue: initialStyle.showPoints)
        }
        
        var body: some View {
            Button(action: {
                resetFromInitial()
                isPresented = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("graph.window.line_shape"))
                            .font(.system(size: 10, weight: .medium))
                        Picker("", selection: $linePattern) {
                            ForEach(SeriesLinePattern.allCases) { pattern in
                                Text(pattern.title).tag(pattern)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("graph.window.thickness"))
                            Spacer()
                            Text(String(format: "%.1f", lineWidth))
                                .foregroundColor(.secondary)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: $lineWidth, in: 0.5...6, step: 0.5)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("graph.window.opacity"))
                            Spacer()
                            Text(String(format: "%.0f%%", opacity * 100))
                                .foregroundColor(.secondary)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
                    }
                    
                    Toggle(L("graph.window.show_points"), isOn: $showPoints)
                        .font(.system(size: 11))
                    
                    Divider()
                    
                    HStack {
                        Button(L("graph.window.reset")) {
                            onReset()
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button(L("graph.window.apply")) {
                            let updated = SeriesStyleOverride(
                                linePattern: linePattern,
                                lineWidth: lineWidth,
                                opacity: opacity,
                                showPoints: showPoints
                            )
                            onSave(updated)
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .frame(minWidth: 260, idealWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: initialStyle) { _ in
                resetFromInitial()
            }
        }
        
        private func resetFromInitial() {
            linePattern = initialStyle.linePattern
            lineWidth = initialStyle.lineWidth
            opacity = initialStyle.opacity
            showPoints = initialStyle.showPoints
        }
    }
    
    private var chartView: some View {
        Chart {
            ForEach(visibleSeries) { item in
                let seriesColor = color(for: item)
                let seriesID = item.id.uuidString
                let seriesStyle = effectiveStyle(for: item)
                
            if let wavelengths = item.wavelengths {
                ForEach(Array(wavelengths.enumerated()), id: \.offset) { idx, lambda in
                    let value = item.values[safe: idx] ?? 0
                        chartMarks(
                            x: lambda,
                            y: value,
                            seriesID: seriesID,
                            color: seriesColor,
                            style: seriesStyle
                        )
                }
            } else {
                ForEach(Array(item.values.enumerated()), id: \.offset) { idx, value in
                        chartMarks(
                            x: Double(idx),
                            y: value,
                            seriesID: seriesID,
                            color: seriesColor,
                            style: seriesStyle
                        )
                    }
                }
            }
        }
        .chartXAxisLabel(series.first?.wavelengths != nil ? L("graph.axis.wavelength_nm") : L("graph.axis.channel"))
        .chartYAxisLabel(L("graph.axis.intensity"))
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartForegroundStyleScale(
            domain: visibleSeries.map { $0.id.uuidString },
            range: visibleSeries.map { color(for: $0) }
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
    private func chartMarks(
        x: Double,
        y: Double,
        seriesID: String,
        color: Color,
        style: SeriesStyleOverride
    ) -> some ChartContent {
        switch self.style {
        case .lines:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(style.opacity))
            .lineStyle(style.linePattern.strokeStyle(lineWidth: style.lineWidth))
            
            if style.showPoints {
                PointMark(
                    x: .value("X", x),
                    y: .value("Y", y)
                )
                .foregroundStyle(color.opacity(style.opacity))
                .symbolSize(pointSize)
            }
            
        case .linesAndPoints:
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(style.opacity))
            .lineStyle(style.linePattern.strokeStyle(lineWidth: style.lineWidth))
            
            if style.showPoints {
                PointMark(
                    x: .value("X", x),
                    y: .value("Y", y)
                )
                .foregroundStyle(color.opacity(style.opacity))
                .symbolSize(pointSize)
            }
            
        case .area:
            AreaMark(
                x: .value("X", x),
                yStart: .value("YStart", areaBaseline),
                yEnd: .value("YEnd", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(style.opacity * 0.25))
            
            LineMark(
                x: .value("X", x),
                y: .value("Y", y),
                series: .value("Series", seriesID)
            )
            .foregroundStyle(color.opacity(style.opacity))
            .lineStyle(style.linePattern.strokeStyle(lineWidth: style.lineWidth))
            
            if style.showPoints {
                PointMark(
                    x: .value("X", x),
                    y: .value("Y", y)
                )
                .foregroundStyle(color.opacity(style.opacity))
                .symbolSize(pointSize)
            }
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
        let allX = visibleSeries.flatMap { s -> [Double] in
            if let w = s.wavelengths { return w }
            return (0..<s.values.count).map { Double($0) }
        }
        return allX.min() ?? 0
    }
    
    private var computedXMax: Double {
        let allX = visibleSeries.flatMap { s -> [Double] in
            if let w = s.wavelengths { return w }
            return (0..<s.values.count).map { Double($0) }
        }
        let m = allX.max() ?? 1
        return m == computedXMin ? m + 1 : m
    }
    
    private var computedYMin: Double {
        let allY = visibleSeries.flatMap { $0.values }
        return allY.min() ?? 0
    }
    
    private var computedYMax: Double {
        let allY = visibleSeries.flatMap { $0.values }
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
        var result: [GraphSeries] = []
        let currentImageID = state.cubeURL?.standardizedFileURL.path
        let visibleIDs = spectrumCache.visibleEntries
        
        for entry in state.libraryEntries where visibleIDs.contains(entry.id) {
            let isCurrent = entry.canonicalPath == currentImageID
            switch dataset {
            case .points:
                if isCurrent {
                    result += state.spectrumSamples.map {
                        GraphSeries(
                            id: $0.id,
                            title: $0.displayName ?? "(\($0.pixelX), \($0.pixelY))",
                            values: $0.values,
                            wavelengths: $0.wavelengths,
                            defaultColor: Color($0.nsColor),
                            sourceName: entry.displayName
                        )
                    }
                } else if let cached = spectrumCache.entries[entry.id]?.spectrumSamples {
                    result += cached.map { sample in
                        GraphSeries(
                            id: sample.id,
                            title: sample.effectiveName,
                            values: sample.values,
                            wavelengths: sample.wavelengths,
                            defaultColor: SpectrumColorPalette.colors[safe: sample.colorIndex % SpectrumColorPalette.colors.count].map { Color($0) } ?? .blue,
                            sourceName: entry.displayName
                        )
                    }
                }
            case .roi:
                if isCurrent {
                    result += state.roiSamples.map {
                        GraphSeries(
                            id: $0.id,
                            title: $0.displayName ?? "ROI (\($0.rect.minX), \($0.rect.minY))",
                            values: $0.values,
                            wavelengths: $0.wavelengths,
                            defaultColor: Color($0.nsColor),
                            sourceName: entry.displayName
                        )
                    }
                } else if let cached = spectrumCache.entries[entry.id]?.roiSamples {
                    result += cached.map { sample in
                        GraphSeries(
                            id: sample.id,
                            title: sample.effectiveName,
                            values: sample.values,
                            wavelengths: sample.wavelengths,
                            defaultColor: SpectrumColorPalette.colors[safe: sample.colorIndex % SpectrumColorPalette.colors.count].map { Color($0) } ?? .blue,
                            sourceName: entry.displayName
                        )
                    }
                }
            }
        }
        
        return result
    }

    private func sampleCounts(for entry: CubeLibraryEntry) -> (spectrum: Int, roi: Int) {
        let isCurrent = entry.canonicalPath == state.cubeURL?.standardizedFileURL.path
        if isCurrent {
            return (state.spectrumSamples.count, state.roiSamples.count)
        }
        if let cached = spectrumCache.entries[entry.id] {
            return (cached.spectrumSamples.count, cached.roiSamples.count)
        }
        return (0, 0)
    }
    
    private var visibleSourceCount: Int {
        let visible = spectrumCache.visibleEntries
        return state.libraryEntries.filter { entry in
            visible.contains(entry.id) && (sampleCounts(for: entry).spectrum > 0 || sampleCounts(for: entry).roi > 0)
        }.count
    }
    
    private func showAllSources() {
        let ids = state.libraryEntries.compactMap { entry -> String? in
            let counts = sampleCounts(for: entry)
            return (counts.spectrum > 0 || counts.roi > 0) ? entry.id : nil
        }
        spectrumCache.visibleEntries = Set(ids)
    }
    
    private func hideAllSources() {
        spectrumCache.visibleEntries.removeAll()
    }
    
    private func color(for series: GraphSeries) -> Color {
        if let custom = state.graphSeriesColors[series.id] {
            return Color(custom)
        }
        return series.defaultColor
    }
    
    private func applyPaletteForMissing() {
        guard !series.isEmpty else { return }
        let colors = palette.colors
        guard !colors.isEmpty else { return }
        var mapping = state.graphSeriesColors
        for (idx, item) in series.enumerated() {
            if mapping[item.id] == nil {
                mapping[item.id] = NSColor(colors[idx % colors.count])
            }
        }
        state.graphSeriesColors = mapping
    }
    
    private func pruneVisibleEntries() {
        let existingIDs = Set(state.libraryEntries.map(\.id))
        spectrumCache.visibleEntries = spectrumCache.visibleEntries.intersection(existingIDs)
    }

    private func toggleSeriesVisibility(id: UUID) {
        if state.graphSeriesHiddenIDs.contains(id) {
            state.graphSeriesHiddenIDs.remove(id)
        } else {
            state.graphSeriesHiddenIDs.insert(id)
        }
    }

    private func pruneGraphSettings() {
        let ids = knownSeriesIDs()
        guard !ids.isEmpty else {
            state.graphSeriesHiddenIDs.removeAll()
            state.graphSeriesOverrides.removeAll()
            state.graphSeriesColors.removeAll()
            return
        }
        state.graphSeriesHiddenIDs = state.graphSeriesHiddenIDs.intersection(ids)
        state.graphSeriesOverrides = state.graphSeriesOverrides.filter { ids.contains($0.key) }
        state.graphSeriesColors = state.graphSeriesColors.filter { ids.contains($0.key) }
    }

    private var visibleSeries: [GraphSeries] {
        series.filter { !state.graphSeriesHiddenIDs.contains($0.id) }
    }
    
    private func effectiveStyle(for series: GraphSeries) -> SeriesStyleOverride {
        if let override = state.graphSeriesOverrides[series.id] {
            return override
        }
        return SeriesStyleOverride(
            linePattern: .solid,
            lineWidth: lineWidth,
            opacity: 1.0,
            showPoints: style == .linesAndPoints
        )
    }

    private func knownSeriesIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        ids.formUnion(state.spectrumSamples.map(\.id))
        ids.formUnion(state.roiSamples.map(\.id))
        for entry in spectrumCache.entries.values {
            ids.formUnion(entry.spectrumSamples.map(\.id))
            ids.formUnion(entry.roiSamples.map(\.id))
        }
        return ids
    }
    
    private func setCustomColor(_ color: Color, for id: UUID) {
        state.graphSeriesColors[id] = NSColor(color)
    }
    
    private func exportGraph(as format: GraphExportFormat, scale: CGFloat) {
        let exportSeries = visibleSeries
        guard !exportSeries.isEmpty else { return }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        switch format {
        case .png:
            panel.allowedContentTypes = [UTType.png]
        case .pdf:
            panel.allowedContentTypes = [UTType.pdf]
        case .json:
            panel.allowedContentTypes = [UTType.json]
        }
        panel.nameFieldStringValue = "graph.\(format.fileExtension)"
        panel.title = L("graph.window.export.title")
        panel.message = LF("graph.window.export.message", format.title)
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        if format == .json {
            let payload = buildJSONPayload(from: exportSeries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(payload) {
                try? data.write(to: url)
            }
            return
        }
        
        let exportView = ExportableChartView(
            series: exportSeries,
            colors: exportSeries.map { color(for: $0) },
            style: style,
            lineWidth: lineWidth,
            pointSize: pointSize,
            showGrid: showGrid,
            xDomain: xDomain,
            yDomain: yDomain,
            xAxisLabel: exportSeries.first?.wavelengths != nil ? L("graph.axis.wavelength_nm") : L("graph.axis.channel")
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
        case .json:
            break
        }
    }
    
    private func buildJSONPayload(from seriesList: [GraphSeries]) -> [String: GraphSeriesJSONPayload] {
        var result: [String: GraphSeriesJSONPayload] = [:]
        var usedKeys: Set<String> = []
        
        for item in seriesList {
            let key = uniqueSeriesKey(base: item.title, used: &usedKeys)
            
            let pairs: [(Double, Double)]
            if let wavelengths = item.wavelengths {
                let count = min(wavelengths.count, item.values.count)
                pairs = (0..<count).compactMap { index in
                    let wavelength = wavelengths[index]
                    let intensity = item.values[index]
                    guard wavelength.isFinite, intensity.isFinite else { return nil }
                    return (wavelength, intensity)
                }
            } else {
                // Fallback: если длины волн отсутствуют, экспортируем индекс канала.
                pairs = item.values.enumerated().compactMap { index, intensity in
                    guard intensity.isFinite else { return nil }
                    return (Double(index), intensity)
                }
            }
            
            result[key] = GraphSeriesJSONPayload(
                wavelengths: pairs.map(\.0),
                intensity: pairs.map(\.1)
            )
        }
        
        return result
    }
    
    private func uniqueSeriesKey(base: String, used: inout Set<String>) -> String {
        let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseKey = normalized.isEmpty ? "series" : normalized
        if !used.contains(baseKey) {
            used.insert(baseKey)
            return baseKey
        }
        
        var suffix = 2
        while true {
            let candidate = "\(baseKey) (\(suffix))"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            suffix += 1
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
        .chartYAxisLabel(L("graph.axis.intensity"))
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
