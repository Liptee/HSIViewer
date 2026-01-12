import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var showWavelengthPopover: Bool = false
    @State private var currentImageSize: CGSize = .zero
    @State private var currentGeoSize: CGSize = .zero
    @State private var roiDragStartPixel: PixelCoordinate?
    @State private var roiPreviewRect: SpectrumROIRect?
    @State private var showWDVIAutoSheet: Bool = false
    @State private var wdviAutoConfig = WDVIAutoEstimationConfig(
        selectedROIIDs: [],
        lowerPercentile: 0.02,
        upperPercentile: 0.98,
        zScoreThreshold: 3.0,
        method: .ols
    )
    @FocusState private var isImageFocused: Bool
    
    private let imageCoordinateSpaceName = "image-canvas"
    
    var body: some View {
        GeometryReader { proxy in
            GlassEffectContainerWrapper {
                ZStack {
                    mainContent
                        .disabled(state.isBusy)
                    
                    if state.isBusy {
                        ZStack {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                            BusyOverlayView(message: state.busyMessage ?? "Выполнение…")
                        }
                        .transition(.opacity)
                    }
                    
                    if let exportInfo = state.libraryExportProgressState {
                        VStack {
                            HStack {
                                Spacer()
                                LibraryExportToastView(state: exportInfo)
                                    .frame(maxWidth: 280)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: $showWDVIAutoSheet) {
            wdviAutoSheet
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar
            
            HStack(spacing: 0) {
                if state.cube != nil && state.viewMode != .mask {
                    PipelinePanel()
                        .environmentObject(state)
                        .padding(.leading, 12)
                    
                    Divider()
                }
                
                if state.viewMode == .mask && state.cube != nil {
                    MaskEditorView(maskState: state.maskEditorState)
                        .environmentObject(state)
                } else {
                GeometryReader { geo in
                        ZStack {
                            if let cube = state.cube {
                                cubeView(cube: cube, geoSize: geo.size)
                                .scaleEffect(state.zoomScale * tempZoomScale)
                                .offset(
                                    x: state.imageOffset.width + dragOffset.width,
                                    y: state.imageOffset.height + dragOffset.height
                                )
                        } else {
                            VStack(spacing: 8) {
                                Text("Открой гиперспектральный куб")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Поддерживаются форматы: .mat, .tiff, .npy")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("2D и 3D изображения")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                tempZoomScale = value
                                            }
                                            .onEnded { value in
                                                state.zoomScale *= value
                                                state.zoomScale = max(0.5, min(state.zoomScale, 10.0))
                                                tempZoomScale = 1.0
                                            }
                                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDrag(value: value, geoSize: geo.size)
                        } else {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if state.activeAnalysisTool == .spectrumGraphROI {
                                    handleROIDragEnd(value: value, geoSize: geo.size)
                                } else {
                                    state.imageOffset.width += value.translation.width
                                    state.imageOffset.height += value.translation.height
                                }
                                dragOffset = .zero
                            }
                    )
                    .onTapGesture { location in
                        if state.activeAnalysisTool == .spectrumGraph {
                            handleImageClick(at: location, geoSize: geo.size)
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isImageFocused)
                    .onAppear {
                        isImageFocused = true
                    }
                    .onKeyPress(.leftArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: -20, height: 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: 20))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard state.activeAnalysisTool != .spectrumGraphROI else { return .ignored }
                        state.moveImage(by: CGSize(width: 0, height: -20))
                        return .handled
                    }
                    .onChange(of: geo.size) { newSize in
                        currentGeoSize = newSize
                    }
                    .onHover { isHovering in
                        if (state.activeAnalysisTool == .spectrumGraph || state.activeAnalysisTool == .spectrumGraphROI),
                           state.cube != nil {
                            if isHovering {
                                NSCursor.crosshair.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .onChange(of: state.activeAnalysisTool) { _ in
                        NSCursor.pop()
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                    }
                    .onChange(of: state.cubeURL) { _ in
                        roiPreviewRect = nil
                        roiDragStartPixel = nil
                    }
                }
                .coordinateSpace(name: imageCoordinateSpaceName)
                
                if let cube = state.cube {
                    Divider()
                    
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            VStack(spacing: 12) {
                                ImageInfoPanel(cube: cube, layout: state.activeLayout)
                                    .id(cube.id)
                                
                                LibraryPanel()
                            }
                            .padding(12)
                        }
                        .frame(width: 260)
                        
                        GraphPanel()
                            .environmentObject(state)
                    }
                    .padding(.trailing, 12)
                }
            } // end else for mask mode check
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            if let cube = state.cube {
                GlassPanel(cornerRadius: 0, padding: 8) {
                    if state.viewMode == .mask {
                        maskModeBottomControls(cube: cube)
                    } else {
                        bottomControls(cube: cube)
                    }
                }
            }
        }
        .frame(minWidth: 960, minHeight: 500)
        .onChange(of: state.viewMode) { newMode in
            if newMode == .mask {
                state.initializeMaskEditor()
            }
        }
        .sheet(item: $state.pendingMatSelection) { request in
            MatVariableSelectionView(request: request)
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showExportView) {
            ExportView()
                .environmentObject(state)
        }
        .onChange(of: state.pendingExport) { newValue in
            if let exportInfo = newValue {
                performActualExport(
                    format: exportInfo.format,
                    wavelengths: exportInfo.wavelengths,
                    matVariableName: exportInfo.matVariableName,
                    matWavelengthsAsVariable: exportInfo.matWavelengthsAsVariable,
                    colorSynthesisConfig: exportInfo.colorSynthesisConfig
                )
                state.pendingExport = nil
            }
        }
    }
    
    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    if let cube = state.cube {
                        ImageInfoPanel(cube: cube, layout: state.activeLayout)
                            .id(cube.id)
                    }
                    
                    LibraryPanel()
                }
                .padding(12)
            }
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
    }
    
    private func performActualExport(format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisConfig: ColorSynthesisConfig?) {
        if state.exportEntireLibrary {
            guard !state.libraryEntries.isEmpty else { return }
            
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Выбрать папку"
            panel.message = "Выберите папку для сохранения экспортированных файлов библиотеки"
            
            let response = panel.runModal()
            guard response == .OK, let folderURL = panel.url else {
                return
            }
            
            exportLibraryEntries(
                to: folderURL,
                format: format,
                wavelengths: wavelengths,
                matVariableName: matVariableName,
                matWavelengthsAsVariable: matWavelengthsAsVariable,
                colorSynthesisConfig: colorSynthesisConfig
            )
            return
        }
        
        guard let cube = state.cube else { return }
        
        let defaultBaseName = state.defaultExportBaseName
        
        // PNG Channels требует выбора директории, так как создаётся много файлов
        if format == .pngChannels {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = true
            openPanel.canChooseFiles = false
            openPanel.canCreateDirectories = true
            openPanel.allowsMultipleSelection = false
            openPanel.prompt = "Выбрать папку"
            openPanel.message = "Выберите папку для сохранения PNG каналов (\(defaultBaseName)_channel_XXX.png)"
            
            openPanel.begin { response in
                print("ContentView: Open panel response: \(response == .OK ? "OK" : "Cancel")")
                guard response == .OK, let folderURL = openPanel.url else {
                    print("ContentView: Export cancelled or no URL")
                    return
                }
                
                print("ContentView: Exporting PNG Channels to folder: \(folderURL.path)")
                
                let wavelengthsToExport = wavelengths ? self.state.wavelengths : nil
                let currentLayout = self.state.activeLayout
                // Создаём URL с базовым именем внутри выбранной папки
                let baseURL = folderURL.appendingPathComponent(defaultBaseName)
                
                DispatchQueue.global(qos: .userInitiated).async {
                    print("ContentView: Calling TiffExporter with layout: \(currentLayout)")
                    let result = PngChannelsExporter.export(cube: cube, to: baseURL, wavelengths: wavelengthsToExport, layout: currentLayout)
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            print("ContentView: PNG Channels export successful")
                        case .failure(let error):
                            print("ContentView: PNG Channels export error: \(error.localizedDescription)")
                        }
                    }
                }
            }
            return
        }
        
        // Для остальных форматов используем NSSavePanel
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        
        switch format {
        case .pngChannels:
            break // Обработано выше
        case .quickPNG:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType.png]
            panel.message = "Выберите путь для сохранения PNG изображения"
        case .npy:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "npy") ?? .data]
            panel.message = "Выберите путь для сохранения"
        case .mat:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType(filenameExtension: "mat") ?? .data]
            panel.message = "Выберите путь для сохранения"
        case .tiff:
            panel.nameFieldStringValue = "\(defaultBaseName).\(format.fileExtension)"
            panel.allowedContentTypes = [UTType.tiff]
            panel.message = "Выберите путь для сохранения TIFF"
        case .maskPNG, .maskNpy, .maskMat:
            return // Маска экспортируется через ExportView
        }
        
        panel.begin { response in
            print("ContentView: Save panel response: \(response == .OK ? "OK" : "Cancel")")
            guard response == .OK, let saveURL = panel.url else {
                print("ContentView: Export cancelled or no URL")
                return
            }
            
            print("ContentView: Exporting to: \(saveURL.path)")
            print("ContentView: Format: \(format.rawValue)")
            
            let wavelengthsToExport = wavelengths ? self.state.wavelengths : nil
            let currentLayout = self.state.activeLayout
            let currentWavelengths = self.state.wavelengths
            
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error>
                
                switch format {
                case .npy:
                    result = NpyExporter.export(cube: cube, to: saveURL, wavelengths: wavelengthsToExport)
                case .mat:
                    result = MatExporter.export(
                        cube: cube,
                        to: saveURL,
                        variableName: matVariableName ?? "hypercube",
                        wavelengths: wavelengthsToExport,
                        wavelengthsAsVariable: matWavelengthsAsVariable
                    )
                case .tiff:
                    result = TiffExporter.export(cube: cube, to: saveURL, wavelengths: wavelengthsToExport, layout: currentLayout)
                case .quickPNG:
                    result = QuickPNGExporter.export(
                        cube: cube,
                        to: saveURL,
                        layout: currentLayout,
                        wavelengths: currentWavelengths,
                        config: colorSynthesisConfig ?? state.colorSynthesisConfig
                    )
                case .pngChannels:
                    result = .failure(ExportError.writeError("PNG channels export handled elsewhere"))
                case .maskPNG, .maskNpy, .maskMat:
                    result = .failure(ExportError.writeError("Mask export handled elsewhere"))
                }
                
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("ContentView: Export successful")
                    case .failure(let error):
                        print("ContentView: Export error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func exportLibraryEntries(to destinationFolder: URL, format: ExportFormat, wavelengths: Bool, matVariableName: String?, matWavelengthsAsVariable: Bool, colorSynthesisConfig: ColorSynthesisConfig?) {
        let entries = state.libraryEntries
        guard !entries.isEmpty else { return }
        let includeWavelengths = wavelengths
        state.beginLibraryExportProgress(total: entries.count)
        
        DispatchQueue.global(qos: .userInitiated).async {
            var completed = 0
            var allSuccess = true
            
            for entry in entries {
                autoreleasepool {
                    guard let payload = state.exportPayload(for: entry) else {
                        allSuccess = false
                        completed += 1
                        state.updateLibraryExportProgress(completed: completed, total: entries.count)
                        print("Пропуск \(entry.fileName) — нет данных для экспорта")
                        return
                    }
                    
                    let baseName = payload.baseName
                    let wavelengthsToExport = includeWavelengths ? payload.wavelengths : nil
                    let result: Result<Void, Error>
                    
                    switch format {
                    case .npy:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("npy")
                        result = NpyExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport)
                    case .mat:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("mat")
                        let varName = (matVariableName?.isEmpty == false ? matVariableName! : "hypercube")
                        result = MatExporter.export(
                            cube: payload.cube,
                            to: target,
                            variableName: varName,
                            wavelengths: wavelengthsToExport,
                            wavelengthsAsVariable: matWavelengthsAsVariable && includeWavelengths
                        )
                    case .tiff:
                        let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("tiff")
                        result = TiffExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport, layout: payload.layout)
                    case .pngChannels:
                        let target = destinationFolder.appendingPathComponent(baseName)
                        result = PngChannelsExporter.export(cube: payload.cube, to: target, wavelengths: wavelengthsToExport, layout: payload.layout)
                    case .quickPNG:
                            let target = destinationFolder.appendingPathComponent(baseName).appendingPathExtension("png")
                        let config = colorSynthesisConfig ?? payload.colorSynthesisConfig
                            result = QuickPNGExporter.export(
                                cube: payload.cube,
                                to: target,
                                layout: payload.layout,
                                wavelengths: payload.wavelengths,
                            config: config
                            )
                    case .maskPNG, .maskNpy, .maskMat:
                        result = .success(())
                    }
                    
                    switch result {
                    case .success:
                        print("Экспортирован \(entry.fileName)")
                    case .failure(let error):
                        print("Ошибка экспорта \(entry.fileName): \(error.localizedDescription)")
                        allSuccess = false
                    }
                    
                    completed += 1
                    state.updateLibraryExportProgress(completed: completed, total: entries.count)
                }
            }
            
            let message = allSuccess
                ? "Экспорт библиотеки завершён"
                : "Экспорт выполнен с ошибками"
            state.finishLibraryExportProgress(success: allSuccess, total: entries.count, message: message)
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
    
    private var topBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                if let url = state.cubeURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Файл не выбран")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                if let error = state.loadError {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            
            Spacer()
            
            if state.cube != nil {
                ToolbarDockView()
                    .environmentObject(state)
            }
            
            Spacer()
            
            Text(appVersion)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: 300, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Color(NSColor.windowBackgroundColor)
                .opacity(0.9)
        )
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
    
    private func cubeView(cube: HyperCube, geoSize: CGSize) -> some View {
        let view: AnyView
        switch state.viewMode {
        case .gray:
            let chIdx = Int(state.currentChannel)
            if let nsImage = ImageRenderer.renderGrayscale(
                cube: cube,
                layout: state.activeLayout,
                channelIndex: chIdx
            ) {
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                view = AnyView(
                    Text("Не удалось построить изображение")
                        .foregroundColor(.red)
                )
            }
            
        case .rgb:
            let config = state.colorSynthesisConfig
            let image: NSImage?
            switch config.mode {
            case .trueColorRGB:
                image = ImageRenderer.renderRGB(
                    cube: cube,
                    layout: state.activeLayout,
                    wavelengths: state.wavelengths,
                    mapping: config.mapping
                )
            case .pcaVisualization:
                image = state.pcaRenderedImage
            }
            
            if let nsImage = image {
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                view = AnyView(
                    Text(config.mode == .pcaVisualization ? "Нажмите «Применить PCA»" : "Не удалось построить RGB изображение")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                )
            }
            
        case .nd:
            if let indices = state.ndChannelIndices(),
               let nsImage = ImageRenderer.renderND(
                cube: cube,
                layout: state.activeLayout,
                positiveIndex: indices.positive,
                negativeIndex: indices.negative,
                palette: state.ndPalette,
                threshold: state.ndThreshold,
                preset: state.ndPreset,
                wdviSlope: Double(state.wdviSlope.replacingOccurrences(of: ",", with: ".")) ?? 1.0,
                wdviIntercept: Double(state.wdviIntercept.replacingOccurrences(of: ",", with: ".")) ?? 0.0
               ) {
                view = AnyView(spectrumImageView(nsImage: nsImage, geoSize: geoSize))
            } else {
                view = AnyView(
                    Text("Не удалось построить ND")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                )
            }
            
        case .mask:
            view = AnyView(EmptyView())
        }
        
        return view
    }
    
    private func spectrumImageView(nsImage: NSImage, geoSize: CGSize) -> some View {
                    let fittedSize = fittingSize(imageSize: nsImage.size, in: geoSize)
                    
        return ZStack(alignment: .topLeading) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedSize.width,
                               height: fittedSize.height,
                               alignment: .center)
            
            if state.activeAnalysisTool == .spectrumGraph {
                SpectrumPointsOverlay(
                    samples: state.activeSpectrumSamples,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                )
            } else if state.activeAnalysisTool == .spectrumGraphROI {
                SpectrumROIsOverlay(
                    samples: state.activeROISamples,
                    temporaryRect: roiPreviewRect,
                    originalSize: nsImage.size,
                    displaySize: fittedSize
                )
            }
        }
        .frame(width: fittedSize.width,
               height: fittedSize.height,
               alignment: .center)
        .background(Color.black.opacity(0.02))
        .onAppear {
            currentImageSize = nsImage.size
            currentGeoSize = geoSize
        }
        .onChange(of: nsImage.size) { newSize in
            currentImageSize = newSize
        }
    }
    
    private func bottomControls(cube: HyperCube) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if cube.is2D {
                    Text("Режим: 2D изображение")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("Layout:")
                        .font(.system(size: 11))
                    Picker("", selection: $state.layout) {
                        ForEach(CubeLayout.allCases) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    
                    Divider()
                        .frame(height: 18)
                    
                    Text("Mode:")
                        .font(.system(size: 11))
                    
                    Picker("", selection: $state.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 160)
                    
                    if state.viewMode == .rgb {
                        Divider()
                            .frame(height: 18)
                        
                        Text("Цветосинтез:")
                            .font(.system(size: 11))
                        
                        Picker("", selection: Binding(
                            get: { state.colorSynthesisConfig.mode },
                            set: { state.setColorSynthesisMode($0) }
                        )) {
                            ForEach(ColorSynthesisMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 170)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        state.resetZoom()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Центрировать")
                                .font(.system(size: 11))
                        }
                    }
                    .disabled(state.zoomScale == 1.0 && state.imageOffset == .zero)
                    
                    Text("Zoom: \(String(format: "%.1f", state.zoomScale))x")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if cube.is2D, let dims2D = cube.dims2D {
                        Divider()
                            .frame(height: 18)
                        Text("размер: \(dims2D.width) × \(dims2D.height)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Divider()
                            .frame(height: 18)
                        Text("dims: \(cube.dims.0) × \(cube.dims.1) × \(cube.dims.2)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if !cube.is2D {
                if state.viewMode == .gray {
                    grayscaleChannelControls(cube: cube)
                } else if state.viewMode == .rgb {
                    colorSynthesisControls(cube: cube)
                } else if state.viewMode == .nd {
                    ndControls()
                }
                
                HStack(spacing: 12) {
                    Button {
                        showWavelengthPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wave.3.right")
                                .font(.system(size: 10))
                            Text("Длины волн")
                                .font(.system(size: 11))
                        }
                    }
                    .popover(isPresented: $showWavelengthPopover, arrowEdge: .top) {
                        wavelengthPopoverContent
                    }
                    
                    if let lambda = state.wavelengths {
                        Text("λ: \(lambda.count) каналов")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if let first = lambda.first, let last = lambda.last {
                            Text("(\(String(format: "%.0f", first)) – \(String(format: "%.0f", last)) нм)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("λ не заданы")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            state.updateChannelCount()
        }
        .onChange(of: state.cube?.dims.0) { _ in
            state.updateChannelCount()
        }
    }
    
    private func maskModeBottomControls(cube: HyperCube) -> some View {
        HStack {
            Text("Layout:")
                .font(.system(size: 11))
            Picker("", selection: $state.layout) {
                ForEach(CubeLayout.allCases) { layout in
                    Text(layout.rawValue).tag(layout)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            
            Divider()
                .frame(height: 18)
            
            Text("Mode:")
                .font(.system(size: 11))
            
            Picker("", selection: $state.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    state.resetZoom()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Центрировать")
                            .font(.system(size: 11))
                    }
                }
                .disabled(state.zoomScale == 1.0 && state.imageOffset == .zero)
                
                Text("Zoom: \(String(format: "%.1f", state.zoomScale))x")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Divider()
                    .frame(height: 18)
                
                if let firstMask = state.maskEditorState.maskLayers.first {
                    Text("Маска: \(firstMask.width) × \(firstMask.height)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func grayscaleChannelControls(cube: HyperCube) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    let channelIdx = Int(state.currentChannel)
                    let wavelengthText: String = {
                        if let wavelengths = state.wavelengths,
                           channelIdx < wavelengths.count {
                            return String(format: " (%.2f нм)", wavelengths[channelIdx])
                        }
                        return ""
                    }()
                    
                    HStack {
                        Text("Канал: \(channelIdx) / \(max(state.channelCount - 1, 0))\(wavelengthText)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                        
                        Spacer()
                        
                        if state.isTrimMode {
                            trimInfoView
                        }
                    }
                    
                    HStack(spacing: 8) {
                        ChannelSliderView(
                            currentChannel: $state.currentChannel,
                            channelCount: state.channelCount,
                            cube: cube,
                            layout: state.activeLayout,
                            isTrimMode: state.isTrimMode,
                            trimStart: $state.trimStart,
                            trimEnd: $state.trimEnd
                        )
                        
                        trimControlButtons
                    }
                }
    }
    
    @ViewBuilder
    private func colorSynthesisControls(cube: HyperCube) -> some View {
        switch state.colorSynthesisConfig.mode {
        case .trueColorRGB:
            let mapping = state.colorSynthesisConfig.mapping.clamped(maxChannelCount: max(state.channelCount, 0))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Каналы цветосинтеза")
                            .font(.system(size: 11, weight: .medium))
                        Text(colorMappingDescription(mapping: mapping))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                ColorSynthesisSliderView(
                    channelCount: state.channelCount,
                    cube: cube,
                    layout: state.activeLayout,
                    mapping: mapping
                ) { newMapping in
                    state.updateColorSynthesisMapping(newMapping, userInitiated: true)
                }
            }
            
        case .pcaVisualization:
            pcaColorControls(cube: cube)
        }
    }
    
    private func colorMappingDescription(mapping: RGBChannelMapping) -> String {
        func channelInfo(label: String, index: Int) -> String {
            if let wavelengths = state.wavelengths, index < wavelengths.count {
                return "\(label): ch \(index) (\(String(format: "%.1f", wavelengths[index])) нм)"
            }
            return "\(label): ch \(index)"
        }
        
        let red = channelInfo(label: "R", index: mapping.red)
        let green = channelInfo(label: "G", index: mapping.green)
        let blue = channelInfo(label: "B", index: mapping.blue)
        return "\(red) • \(green) • \(blue)"
    }
    
    private func ndControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ND индексы")
                .font(.system(size: 11, weight: .medium))
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Пресет")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $state.ndPreset) {
                        ForEach(NDIndexPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                switch state.ndPreset {
                case .ndvi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Red (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("660", text: $state.ndviRedTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NIR (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("840", text: $state.ndviNIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                case .ndsi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Green (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("555", text: $state.ndsiGreenTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SWIR (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("1610", text: $state.ndsiSWIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                case .wdvi:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Red (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("660", text: $state.ndviRedTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NIR (нм)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("840", text: $state.ndviNIRTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("a (slope)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("1.0", text: $state.wdviSlope)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("b (intercept)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("0.0", text: $state.wdviIntercept)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ")
                            .font(.system(size: 10))
                        Button {
                            let roiIDs = Set(state.roiSamples.map { $0.id })
                            wdviAutoConfig = WDVIAutoEstimationConfig(
                                selectedROIIDs: roiIDs,
                                lowerPercentile: wdviAutoConfig.lowerPercentile,
                                upperPercentile: wdviAutoConfig.upperPercentile,
                                zScoreThreshold: wdviAutoConfig.zScoreThreshold,
                                method: wdviAutoConfig.method
                            )
                            showWDVIAutoSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text("Автооценка почвы…")
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Палитра")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Picker("", selection: $state.ndPalette) {
                        ForEach(NDPalette.allCases) { palette in
                            Text(palette.rawValue).tag(palette)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                if state.ndPalette == .binaryVegetation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Порог ND")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack {
                            Slider(value: $state.ndThreshold, in: -1...1, step: 0.01)
                                .frame(width: 180)
                            Text(String(format: "%.2f", state.ndThreshold))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 50, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    
    private var wdviAutoSheet: some View {
        let rois = state.roiSamples
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Автооценка линии почвы (WDVI)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            
            if rois.isEmpty {
                Text("Сохранённых ROI нет — добавьте области на изображении и повторите.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ROI для оценки")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button("Выбрать все") {
                            wdviAutoConfig.selectedROIIDs = Set(rois.map { $0.id })
                        }
                        Button("Очистить") {
                            wdviAutoConfig.selectedROIIDs.removeAll()
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(rois) { roi in
                                Toggle(isOn: Binding(
                                    get: { wdviAutoConfig.selectedROIIDs.contains(roi.id) },
                                    set: { isOn in
                                        if isOn {
                                            wdviAutoConfig.selectedROIIDs.insert(roi.id)
                                        } else {
                                            wdviAutoConfig.selectedROIIDs.remove(roi.id)
                                        }
                                    }
                                )) {
                                    Text(roi.displayName ?? "ROI \(roi.id.uuidString.prefix(4))")
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .frame(maxHeight: 180)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Фильтрация и регрессия")
                    .font(.system(size: 11, weight: .medium))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Обрезка по перцентилям")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Text("Нижний")
                            .font(.system(size: 10))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { wdviAutoConfig.lowerPercentile * 100 },
                            set: { v in wdviAutoConfig.lowerPercentile = min(v / 100, wdviAutoConfig.upperPercentile - 0.01) }
                        ), in: 0...20, step: 0.5)
                        Text(String(format: "%.1f%%", wdviAutoConfig.lowerPercentile * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                    HStack(spacing: 12) {
                        Text("Верхний")
                            .font(.system(size: 10))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: Binding(
                            get: { wdviAutoConfig.upperPercentile * 100 },
                            set: { v in wdviAutoConfig.upperPercentile = max(v / 100, wdviAutoConfig.lowerPercentile + 0.01) }
                        ), in: 80...100, step: 0.5)
                        Text(String(format: "%.1f%%", wdviAutoConfig.upperPercentile * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Отсечение по z-score")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Slider(value: $wdviAutoConfig.zScoreThreshold, in: 0...5, step: 0.1)
                                .frame(width: 220)
                            Text(String(format: "%.1f", wdviAutoConfig.zScoreThreshold))
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Метод регрессии")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Picker("", selection: $wdviAutoConfig.method) {
                            ForEach(WDVIAutoRegressionMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Отмена") {
                    showWDVIAutoSheet = false
                }
                Button("Рассчитать") {
                    var normalizedConfig = wdviAutoConfig
                    normalizedConfig.lowerPercentile = max(0, min(0.5, normalizedConfig.lowerPercentile))
                    normalizedConfig.upperPercentile = min(1, max(normalizedConfig.lowerPercentile + 0.01, normalizedConfig.upperPercentile))
                    state.runWDVIAutoEstimation(config: normalizedConfig)
                    showWDVIAutoSheet = false
                }
                .disabled(rois.isEmpty || wdviAutoConfig.selectedROIIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
    
    @ViewBuilder
    private func pcaColorControls(cube: HyperCube) -> some View {
        let config = state.pcaPendingConfig ?? state.colorSynthesisConfig.pcaConfig
        let maxComponents = max(1, min(state.channelCount, 3))
        let componentOptions = Array(0..<maxComponents) // рассчитываем первые 3 компоненты
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Область расчёта PCA")
                        .font(.system(size: 10, weight: .medium))
                    Picker("", selection: Binding(
                        get: { config.computeScope },
                        set: { newValue in
                            state.updatePCAConfig { $0.computeScope = newValue }
                        })) {
                        ForEach(PCAComputeScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preprocess")
                        .font(.system(size: 10, weight: .medium))
                    Picker("", selection: Binding(
                        get: { config.preprocess },
                        set: { newValue in
                            state.updatePCAConfig {
                                $0.preprocess = newValue
                                $0.basis = nil
                                $0.clipUpper = nil
                                $0.explainedVariance = nil
                            }
                        })) {
                        ForEach(PCAPreprocess.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Маппинг компонентов → RGB")
                        .font(.system(size: 10, weight: .medium))
                    HStack(spacing: 8) {
                        pcaComponentPicker(label: "R", value: config.mapping.red, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.red = newVal }
                        }
                        pcaComponentPicker(label: "G", value: config.mapping.green, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.green = newVal }
                        }
                        pcaComponentPicker(label: "B", value: config.mapping.blue, options: componentOptions) { newVal in
                            state.updatePCAConfig { $0.mapping.blue = newVal }
                        }
                    }
                }
                
                Toggle("Lock basis", isOn: Binding(
                    get: { config.lockBasis },
                    set: { newValue in
                        state.updatePCAConfig { $0.lockBasis = newValue }
                    })
                )
                .font(.system(size: 10))
                .toggleStyle(.switch)
                .frame(width: 140, alignment: .leading)
            }
            
            if config.computeScope == .roi {
                HStack(spacing: 10) {
                    Text("ROI для PCA")
                        .font(.system(size: 10, weight: .medium))
                    Picker("ROI", selection: Binding(
                        get: { config.selectedROI ?? state.displayedROISamples.first?.id },
                        set: { newID in
                            state.updatePCAConfig { $0.selectedROI = newID }
                        })) {
                        if state.displayedROISamples.isEmpty {
                            Text("Нет сохранённых ROI").tag(Optional<UUID>.none)
                        } else {
                            ForEach(state.displayedROISamples) { sample in
                                Text(sample.displayName ?? "ROI \(sample.id.uuidString.prefix(6))")
                                    .tag(Optional(sample.id))
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            
            HStack(spacing: 10) {
                Text("Отрезать верхние выбросы")
                    .font(.system(size: 10, weight: .medium))
                Slider(
                    value: Binding(
                        get: { config.clipTopPercent },
                        set: { newValue in
                            state.updatePCAConfig {
                                $0.clipTopPercent = newValue
                                $0.basis = nil
                                $0.clipUpper = nil
                            }
                        }
                    ),
                    in: 0...5,
                    step: 0.1
                )
                Text(String(format: "%.1f %%", config.clipTopPercent))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
            }
            
            if let ev = config.explainedVariance, !ev.isEmpty {
                let total = ev.reduce(0, +)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(ev.enumerated()), id: \.0) { item in
                        let value = total > 0 ? item.element / total : 0
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.accentColor.opacity(item.offset == 0 ? 0.9 : 0.6))
                                .frame(width: 18, height: CGFloat(max(4.0, value * 70.0)))
                            Text("PC\(item.offset + 1)")
                                .font(.system(size: 9, weight: .medium))
                            Text(String(format: "%.1f%%", value * 100))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    state.applyPCAVisualization()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Применить PCA")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    state.isPCAApplying
                    || state.cube == nil
                    || (config.computeScope == .roi && (config.selectedROI == nil && state.displayedROISamples.isEmpty))
                )
                
                if state.isPCAApplying {
                    ProgressView(state.pcaProgressMessage ?? "Обработка…")
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                } else if state.pcaRenderedImage == nil {
                    Text("Настройте параметры и нажмите «Применить»")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("PCA: спектры пикселей; lock basis сохраняет базис до смены параметров.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if config.computeScope == .roi,
               config.selectedROI == nil,
               let first = state.displayedROISamples.first?.id {
                state.updatePCAConfig { $0.selectedROI = first }
            }
        }
        .onChange(of: config.computeScope) { scope in
            if scope == .roi,
               config.selectedROI == nil,
               let first = state.displayedROISamples.first?.id {
                state.updatePCAConfig { $0.selectedROI = first }
            }
        }
    }
    
    private func pcaComponentPicker(label: String, value: Int, options: [Int], onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
            Picker("", selection: Binding(
                get: { value },
                set: { onChange($0) }
            )) {
                ForEach(options, id: \.self) { idx in
                    Text("PC\(idx + 1)").tag(idx)
                }
            }
            .frame(width: 80)
            .pickerStyle(.menu)
        }
    }
    
    private var trimControlButtons: some View {
        VStack(spacing: 4) {
            if state.isTrimMode {
                TrimActionButton(
                    icon: "checkmark",
                    color: .green,
                    tooltip: "Применить обрезку"
                ) {
                    state.applyTrim()
                }
                
                TrimActionButton(
                    icon: "xmark",
                    color: .red,
                    tooltip: "Отменить"
                ) {
                    state.exitTrimMode()
                }
            } else {
                Button {
                    state.enterTrimMode()
                } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .help("Обрезать каналы")
            }
        }
    }
    
    private var trimInfoView: some View {
        HStack(spacing: 4) {
            let startCh = Int(state.trimStart)
            let endCh = Int(state.trimEnd)
            let trimCount = endCh - startCh + 1
            
            if let wavelengths = state.wavelengths,
               startCh < wavelengths.count,
               endCh < wavelengths.count {
                Text("Обрезка: \(String(format: "%.0f", wavelengths[startCh])) – \(String(format: "%.0f", wavelengths[endCh])) нм")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("(\(trimCount) кан.)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Обрезка: канал \(startCh) – \(endCh)")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("(\(trimCount) кан.)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var wavelengthPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройка длин волн")
                .font(.system(size: 12, weight: .semibold))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Диапазон (нм):")
                    .font(.system(size: 11))
                
                HStack(spacing: 8) {
                    Text("от")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("400", text: $state.lambdaStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    
                    Text("до")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("1000", text: $state.lambdaEnd)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                
                if state.channelCount > 1 {
                    let step = calculateDisplayStep()
                    Text("Шаг: \(String(format: "%.2f", step)) нм")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Button("Применить диапазон") {
                    state.generateWavelengthsFromParams()
                    showWavelengthPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Или загрузить из файла:")
                    .font(.system(size: 11))
                
                Button("Выбрать .txt файл…") {
                    openWavelengthTXT()
                    showWavelengthPopover = false
                }
                .controlSize(.small)
            }
            
            if let lambda = state.wavelengths {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Текущие значения:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(lambda.count) каналов")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let first = lambda.first, let last = lambda.last {
                        Text("\(String(format: "%.1f", first)) – \(String(format: "%.1f", last)) нм")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }
    
    private func calculateDisplayStep() -> Double {
        guard let start = Double(state.lambdaStart.replacingOccurrences(of: ",", with: ".")),
              let end = Double(state.lambdaEnd.replacingOccurrences(of: ",", with: ".")),
              state.channelCount > 1 else {
            return 0
        }
        return (end - start) / Double(state.channelCount - 1)
    }
    
    private func openWavelengthTXT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать txt"
        panel.allowedContentTypes = [.plainText]
        
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        
        state.loadWavelengthsFromTXT(url: url)
    }
    
    private func fittingSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return containerSize
        }
        
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)
        
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
    
    private func handleImageClick(at location: CGPoint, geoSize: CGSize) {
        guard state.activeAnalysisTool == .spectrumGraph else { return }
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.extractSpectrum(at: pixel.x, pixelY: pixel.y)
    }
    
    private func pixelCoordinate(for location: CGPoint, geoSize: CGSize) -> PixelCoordinate? {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else { return nil }
        
        let fittedSize = fittingSize(imageSize: currentImageSize, in: geoSize)
        let totalZoom = state.zoomScale * tempZoomScale
        let scaledImageSize = CGSize(
            width: fittedSize.width * totalZoom,
            height: fittedSize.height * totalZoom
        )
        
        let centerX = geoSize.width / 2
        let centerY = geoSize.height / 2
        
        let imageOriginX = centerX - scaledImageSize.width / 2 + state.imageOffset.width + dragOffset.width
        let imageOriginY = centerY - scaledImageSize.height / 2 + state.imageOffset.height + dragOffset.height
        
        let relativeX = location.x - imageOriginX
        let relativeY = location.y - imageOriginY
        
        guard relativeX >= 0, relativeX < scaledImageSize.width,
              relativeY >= 0, relativeY < scaledImageSize.height else {
            return nil
        }
        
        let maxX = max(Int(currentImageSize.width) - 1, 0)
        let maxY = max(Int(currentImageSize.height) - 1, 0)
        let rawX = Int((relativeX / scaledImageSize.width) * currentImageSize.width)
        let rawY = Int((relativeY / scaledImageSize.height) * currentImageSize.height)
        let pixelX = max(0, min(rawX, maxX))
        let pixelY = max(0, min(rawY, maxY))
        
        return PixelCoordinate(x: pixelX, y: pixelY)
    }
    
    private func roiRect(from start: PixelCoordinate, to end: PixelCoordinate) -> SpectrumROIRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x) + 1
        let height = abs(end.y - start.y) + 1
        return SpectrumROIRect(minX: minX, minY: minY, width: width, height: height)
    }
    
    private func handleROIDrag(value: DragGesture.Value, geoSize: CGSize) {
        guard let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize) else { return }
        guard let currentPixel = pixelCoordinate(for: value.location, geoSize: geoSize) else { return }
        roiDragStartPixel = startPixel
        roiPreviewRect = roiRect(from: startPixel, to: currentPixel)
    }
    
    private func handleROIDragEnd(value: DragGesture.Value, geoSize: CGSize) {
        defer {
            roiDragStartPixel = nil
            roiPreviewRect = nil
        }
        guard
            let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize),
            let endPixel = pixelCoordinate(for: value.location, geoSize: geoSize)
        else { return }
        let rect = roiRect(from: startPixel, to: endPixel)
        state.extractROISpectrum(for: rect)
    }
    
    private func roiSelectionGesture(in geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(imageCoordinateSpaceName))
            .onChanged { value in
                guard state.activeAnalysisTool == .spectrumGraphROI else { return }
                handleROIDrag(value: value, geoSize: geoSize)
            }
            .onEnded { value in
                guard state.activeAnalysisTool == .spectrumGraphROI else { return }
                handleROIDragEnd(value: value, geoSize: geoSize)
            }
    }


private struct LibraryExportToastView: View {
    let state: LibraryExportProgressState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(titleText)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            
            switch state.phase {
            case .running:
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                Text("\(state.completed) / \(state.total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            case .success, .failure:
                Text(state.message ?? defaultMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
    
    private var titleText: String {
        switch state.phase {
        case .running:
            return "Экспорт библиотеки"
        case .success:
            return "Готово"
        case .failure:
            return "Ошибка экспорта"
        }
    }
    
    private var iconName: String {
        switch state.phase {
        case .running:
            return "tray.full"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch state.phase {
        case .running:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
    
    private var defaultMessage: String {
        switch state.phase {
        case .success:
            return "Все файлы успешно экспортированы"
        case .failure:
            return "При экспорте возникли ошибки"
        case .running:
            return ""
        }
    }
}

private struct SpectrumPointsOverlay: View {
    let samples: [SpectrumSample]
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                let position = position(for: sample)
                Circle()
                    .fill(sample.displayColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .frame(width: 10, height: 10)
                    .position(x: position.x, y: position.y)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func position(for sample: SpectrumSample) -> CGPoint {
        let width = max(originalSize.width - 1, 1)
        let height = max(originalSize.height - 1, 1)
        let xRatio = CGFloat(sample.pixelX) / width
        let yRatio = CGFloat(sample.pixelY) / height
        let x = xRatio * displaySize.width
        let y = yRatio * displaySize.height
        return CGPoint(x: x, y: y)
    }
}

private struct SpectrumROIsOverlay: View {
    let samples: [SpectrumROISample]
    let temporaryRect: SpectrumROIRect?
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                roiPath(for: sample.rect)
                    .stroke(sample.displayColor, lineWidth: 1.5)
                    .background(
                        roiPath(for: sample.rect)
                            .fill(sample.displayColor.opacity(0.08))
                    )
            }
            
            if let temp = temporaryRect {
                roiPath(for: temp)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(
                        roiPath(for: temp)
                            .fill(Color.accentColor.opacity(0.05))
                    )
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func roiPath(for rect: SpectrumROIRect) -> Path {
        Path { path in
            path.addRoundedRect(in: frame(for: rect), cornerSize: CGSize(width: 4, height: 4))
        }
    }
    
    private func frame(for rect: SpectrumROIRect) -> CGRect {
        guard originalSize.width > 0, originalSize.height > 0 else { return .zero }
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        let x = CGFloat(rect.minX) * scaleX
        let y = CGFloat(rect.minY) * scaleY
        let width = CGFloat(rect.width) * scaleX
        let height = CGFloat(rect.height) * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct PixelCoordinate: Equatable {
    let x: Int
    let y: Int
}

struct TrimActionButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .shadow(color: isHovered ? color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(isHovered ? 0.8 : 0.4), lineWidth: isHovered ? 2 : 1)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isHovered ? .white : color)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 30, height: 30)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .help(tooltip)
    }
    
    private var backgroundColor: Color {
        if isPressed {
            return color.opacity(0.9)
        } else if isHovered {
            return color.opacity(0.75)
        } else {
            return color.opacity(0.15)
        }
    }
}

struct BusyOverlayView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.1)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
        )
    }
}

}
